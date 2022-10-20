/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

##########
# Locals #
##########

# We use local variables to translate from the cleaner interface of the tfvars file
# to the required structure for some of the modules.

locals {

  # This finds all secondary ranges among all envs and flattens them into a single list
  parsed_secondary_ranges = [
    var.gke_subnet_pod_range,
    var.gke_subnet_service_range
  ]

  # This allows us to pass in the Private IP range as a cidr block, like every other
  # ip range variable.
  private_ip_start = split("/", var.private_ip_range)[0]
  private_ip_block = tonumber(split("/", var.private_ip_range)[1])

  # This allows us to reference a pre-parsed subnet name in the secondary ranges block below
  parsed_subnet_name = "${var.prefix}-looker-subnet"

  # This pre-parses the managed zone domain name to remove the period
  parsed_hosted_zone_domain = trim(data.google_dns_managed_zone.dns_zone.dns_name, ".")

  # This pre-parses the main GKE servcie account
  parsed_main_gke_service_account = "serviceAccount:service-${data.google_project.gke_project.number}@container-engine-robot.iam.gserviceaccount.com"

  # This parses the correct project ID if the user has specified separate projects for DNS and KMS
  parsed_dns_project_id = coalesce(var.dns_project_id, var.project_id)
  parsed_kms_project_id = coalesce(var.kms_project_id, var.project_id)

  # We set our default database flags here - these will be combined with the user defined flags from the variables
  default_db_flags = [
    {
      name  = "local_infile"
      value = "off"
    }
  ]

  # We need to create entries for the databases and database users for each instance being deployed in this environment
  parsed_db_databases = [
    for k in keys(var.envs) : {
      name      = "looker-${k}"
      charset   = "utf8mb4"
      collation = "utf8mb4_general_ci"
    }
  ]

  parsed_db_users = [
    for k in keys(var.envs) : {
      name     = "looker-${k}"
      host     = "cloudsqlproxy~%"
      password = data.google_secret_manager_secret_version.db_pass[k].secret_data
    }
  ]
}

# We must grab the project number to correctly reference the main GKE service account
data "google_project" "gke_project" {
  project_id = var.project_id
}

##############
# Networking #
##############

# Create the VPC along with subnets and secondary ranges. Secondary ranges
# are needed because our GKE cluster will be VPC-native
module "looker_vpc" {
  source  = "terraform-google-modules/network/google"
  version = "5.2.0"

  project_id   = var.project_id
  network_name = "${var.prefix}-network"
  subnets = [
    {
      subnet_name   = local.parsed_subnet_name
      subnet_ip     = var.subnet_ip_range
      subnet_region = var.region
    }
  ]
  secondary_ranges = {
    (local.parsed_subnet_name) = local.parsed_secondary_ranges
  }
}

# Set up Private Services access. Private Services are used to securely connect
# to Cloud SQL, Filestore, and Memorystore
module "private_service_access" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version = "12.0.0"

  project_id    = var.project_id
  vpc_network   = element(split("/", module.looker_vpc.network_self_link), length(split("/", module.looker_vpc.network_self_link)) - 1) # https://github.com/terraform-google-modules/terraform-google-sql-db/issues/176
  address       = local.private_ip_start
  ip_version    = "IPV4"
  prefix_length = local.private_ip_block
}

# Create a router and NAT to allow egress traffic to reach the internet
module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "3.0.0"

  project = var.project_id
  name    = "${var.prefix}-looker-router"
  network = module.looker_vpc.network_name
  region  = var.region

  nats = [{
    name = "${var.prefix}-looker-nat"
  }]
}

############
# Database #
############

# We need to pull in the secret that has been previously created
data "google_secret_manager_secret_version" "db_pass" {
  for_each = var.envs
  secret   = each.value.db_secret_name
}

module "looker_db" {
  depends_on = [module.private_service_access] # We need to make sure private services is ready first

  source  = "GoogleCloudPlatform/sql-db/google//modules/mysql"
  version = "12.0.0"

  project_id                      = var.project_id
  name                            = "${var.prefix}-looker-db-instance"
  random_instance_name            = true
  database_version                = var.db_version
  region                          = var.region
  zone                            = var.zone
  deletion_protection             = var.db_deletion_protection
  tier                            = var.db_tier
  enable_default_db               = false
  enable_default_user             = false
  maintenance_window_day          = 6
  maintenance_window_hour         = 20
  maintenance_window_update_track = "stable"
  availability_type               = var.db_high_availability ? "REGIONAL" : "ZONAL"

  database_flags = distinct(concat(local.default_db_flags, var.db_flags))

  ip_configuration = {
    authorized_networks = []
    ipv4_enabled        = false
    private_network     = module.looker_vpc.network_self_link
    require_ssl         = true
    allocated_ip_range  = module.private_service_access.google_compute_global_address_name
  }

  additional_databases = local.parsed_db_databases

  additional_users = local.parsed_db_users

  backup_configuration = {
    enabled                        = true
    binary_log_enabled             = true
    start_time                     = "03:00"
    location                       = "us"
    transaction_log_retention_days = 3
    retained_backups               = 3
    retention_unit                 = "COUNT"
  }

  read_replicas = var.db_read_replicas

}


#######
# NFS #
#######

# There's no published module for filestore, but it's a pretty simple resource so a module wouldn't add anything
resource "google_filestore_instance" "looker_filestore" {
  depends_on = [module.private_service_access] # We need to make sure private services is ready first
  provider   = google-beta

  for_each = var.envs

  project  = var.project_id
  name     = "${var.prefix}-looker-fs-${each.key}"
  location = var.zone
  tier     = each.value.filestore_tier

  file_shares {
    capacity_gb = 1024
    name        = "lookerfiles"
  }

  networks {
    network      = module.looker_vpc.network_name
    modes        = ["MODE_IPV4"]
    connect_mode = "PRIVATE_SERVICE_ACCESS"
  }

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

###############
# Redis Cache #
###############

module "looker_cache" {
  depends_on = [module.private_service_access]

  source  = "terraform-google-modules/memorystore/google"
  version = "5.1.0"

  for_each = var.envs

  project                 = var.project_id
  name                    = "${var.prefix}-looker-cache-${each.key}"
  auth_enabled            = false
  transit_encryption_mode = "DISABLED"
  redis_configs = {
    "maxmemory-policy" = "volatile-lru"
  }
  memory_size_gb     = each.value.redis_memory_size_gb
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  redis_version      = "REDIS_5_0"
  region             = var.region
  tier               = each.value.redis_high_availability ? "STANDARD_HA" : "BASIC"
  authorized_network = module.looker_vpc.network_name
}


###############
# GKE Cluster #
###############

# We need to create a custom service account for the GKE nodes
module "gke_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.1.1"

  project_id   = var.project_id
  prefix       = var.prefix
  names        = ["looker-gke-account"]
  display_name = "Looker GKE Node Service Account"
  description  = "Service account for Looker GKE nodes"
  project_roles = [
    "${var.project_id}=>roles/monitoring.metricWriter",
    "${var.project_id}=>roles/stackdriver.resourceMetadata.writer",
    "${var.project_id}=>roles/logging.logWriter",
    "${var.project_id}=>roles/artifactregistry.reader",
    "${var.project_id}=>roles/storage.objectViewer",
  ]
}


# If enabled, we need a KMS key to set up application-layer secret encryption

resource "random_id" "keyring_suffix" {
  byte_length = 4
}

module "looker_kms" {
  source  = "terraform-google-modules/kms/google"
  version = "2.2.1"
  count   = var.gke_use_application_layer_encryption ? 1 : 0

  project_id      = local.parsed_kms_project_id
  location        = var.region
  keyring         = "${var.prefix}-looker-gke-secrets-${random_id.keyring_suffix.hex}"
  keys            = ["key-encryption-key"]
  prevent_destroy = false

  set_encrypters_for = ["key-encryption-key"]
  encrypters         = [local.parsed_main_gke_service_account]

  set_decrypters_for = ["key-encryption-key"]
  decrypters         = [local.parsed_main_gke_service_account]
}

# This builds the GKE cluster and the separately mananaged node pool (this is important
# since it allows you to modify the node pool without rebuilding the entire cluster)
module "looker_gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  version = "23.1.0"

  project_id                           = var.project_id
  name                                 = "${var.prefix}-looker-cluster"
  region                               = var.region
  zones                                = var.gke_node_zones
  regional                             = var.gke_regional_cluster
  network                              = module.looker_vpc.network_name
  subnetwork                           = module.looker_vpc.subnets_names[0]
  ip_range_pods                        = var.gke_subnet_pod_range.range_name
  ip_range_services                    = var.gke_subnet_service_range.range_name
  create_service_account               = false
  service_account                      = module.gke_service_account.email
  enable_private_endpoint              = var.gke_private_endpoint
  master_global_access_enabled         = var.gke_master_global_access_enabled
  enable_private_nodes                 = true
  master_authorized_networks           = var.gke_master_authorized_networks
  remove_default_node_pool             = true
  initial_node_count                   = 1
  master_ipv4_cidr_block               = var.gke_controller_range
  add_master_webhook_firewall_rules    = true
  firewall_inbound_ports               = ["8443"]
  release_channel                      = var.gke_release_channel
  database_encryption                  = var.gke_use_application_layer_encryption ? [{ state = "ENCRYPTED", key_name = module.looker_kms.keys["key-encryption-key"] }] : [{ state = "DECRYPTED", key_name = "" }]
  monitoring_enable_managed_prometheus = var.gke_use_managed_prometheus

  node_pools = [
    {
      name         = "${var.prefix}-looker-nodepool"
      machine_type = var.gke_node_tier
      min_count    = var.gke_node_count_min
      max_count    = var.gke_node_count_max
      image_type   = "COS_CONTAINERD"
    }
  ]

  node_pools_oauth_scopes = {
    all = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

###############
# Workload ID #
###############

# This takes care of GCP connectivity from inside the GKE cluster
module "workload_id_looker_k8s_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.1.1"

  project_id   = var.project_id
  prefix       = var.prefix
  display_name = "Looker GKE Workload ID"
  names        = ["looker-k8s-workload-id"]
  description  = "Service account for Looker GKE workload identity"
  project_roles = [
    "${var.project_id}=>roles/cloudsql.client",
    "${var.project_id}=>roles/bigquery.dataEditor",
    "${var.project_id}=>roles/bigquery.jobUser",
    "${var.project_id}=>roles/secretmanager.secretAccessor",
  ]
}

module "workload_id_looker_k8s_member" {
  depends_on = [module.looker_gke]

  source  = "terraform-google-modules/iam/google//modules/service_accounts_iam"
  version = "7.4.1"

  project          = var.project_id
  service_accounts = [module.workload_id_looker_k8s_service_account.email]
  mode             = "authoritative"
  bindings = {
    "roles/iam.workloadIdentityUser" = [
      for k, v in var.envs : "serviceAccount:${module.looker_gke.identity_namespace}[${v.looker_k8s_namespace}/looker-service-account-${k}]"
    ]
  }
}

#######
# DNS #
#######

# In most cases DNS will already be in place, so this may be a common point of customization. Here
# we're assuming a domain and GCP Managed DNS Zone already exist.

data "google_dns_managed_zone" "dns_zone" {
  name    = var.dns_managed_zone_name
  project = local.parsed_dns_project_id
}

resource "google_compute_address" "looker_ip" {
  name        = "${var.prefix}-looker-ip"
  region      = var.region
  description = "IP address for Looker instance(s) load balancer"
}

resource "google_dns_record_set" "looker_dns_record" {
  for_each     = var.envs
  project      = local.parsed_dns_project_id
  managed_zone = data.google_dns_managed_zone.dns_zone.name
  type         = "A"
  name         = "${each.key}.${var.looker_subdomain}.${data.google_dns_managed_zone.dns_zone.dns_name}"
  rrdatas      = [google_compute_address.looker_ip.address]
  ttl          = 300
}

########
# Helm #
########

# We now deploy kubernetes workloads via Helm.

resource "helm_release" "cert_manager" {
  depends_on       = [module.looker_gke]
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.certmanager_helm_version
  namespace        = "cert-manager"
  create_namespace = true
  values = [
    file("${path.module}/helm_values/cert_manager_values.yaml")
  ]
}

resource "helm_release" "ingress_nginx" {
  depends_on       = [module.looker_gke]
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_helm_version
  namespace        = "ingress-nginx"
  create_namespace = true
  values = [
    templatefile(
      "${path.module}/helm_values/ingress_nginx_values.yaml",
      {
        ip_address = google_compute_address.looker_ip.address
      }
    )
  ]
}

resource "helm_release" "secrets_store_csi_driver" {
  depends_on = [module.looker_gke]
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_helm_version
  namespace  = "kube-system"
  values = [
    file("${path.module}/helm_values/secrets_store_csi_values.yaml")
  ]
}

resource "helm_release" "looker" {
  depends_on = [helm_release.cert_manager, helm_release.ingress_nginx, helm_release.secrets_store_csi_driver, module.workload_id_looker_k8s_member]
  for_each   = var.envs

  name             = each.key
  chart            = var.looker_helm_repository
  version          = var.looker_helm_version
  namespace        = each.value.looker_k8s_namespace
  create_namespace = true
  disable_webhooks = var.disable_hooks
  timeout          = 600
  values = [
    templatefile(
      "${path.module}/helm_values/looker_values.yaml",
      {
        looker_k8s_repository                = var.looker_k8s_repository
        looker_k8s_image_pull_policy         = var.looker_k8s_image_pull_policy
        looker_version                       = each.value.looker_version
        looker_gcp_service_account_email     = module.workload_id_looker_k8s_service_account.email
        filestore_ip                         = google_filestore_instance.looker_filestore[each.key].networks.0.ip_addresses.0
        looker_db_name                       = "looker-${each.key}"
        looker_db_user                       = "looker-${each.key}"
        looker_db_connection_name            = module.looker_db.instance_connection_name
        looker_host_url                      = "${each.key}.${var.looker_subdomain}.${local.parsed_hosted_zone_domain}"
        secrets_project                      = var.project_id
        db_pass_secret_name                  = each.value.db_secret_name
        gcm_key_secret_name                  = each.value.gcm_key_secret_name
        cert_admin_email                     = each.value.looker_k8s_issuer_admin_email
        cert_server                          = each.value.looker_k8s_issuer_acme_server
        looker_node_count                    = each.value.looker_node_count
        looker_version                       = each.value.looker_version
        looker_startup_flags                 = each.value.looker_startup_flags
        looker_update_config                 = indent(2, yamlencode(each.value.looker_k8s_update_config))
        looker_node_resources                = indent(4, yamlencode(each.value.looker_k8s_node_resources))
        looker_scheduler_node_enabled        = each.value.looker_scheduler_node_enabled
        looker_scheduler_node_count          = each.value.looker_scheduler_node_count
        looker_scheduler_node_resources      = indent(6, yamlencode(each.value.looker_scheduler_resources))
        looker_scheduler_threads             = each.value.looker_scheduler_threads
        looker_scheduler_unlimited_threads   = each.value.looker_scheduler_unlimited_threads
        looker_scheduler_alert_threads       = each.value.looker_scheduler_alert_threads
        looker_scheduler_render_caching      = each.value.looker_scheduler_render_caching_jobs
        looker_scheduler_render_jobs         = each.value.looker_scheduler_render_jobs
        looker_redis_enabled                 = each.value.redis_enabled
        looker_redis_ip                      = each.value.redis_enabled ? module.looker_cache[each.key].host : ""
        looker_redis_port                    = each.value.redis_enabled ? module.looker_cache[each.key].port : 0
        looker_user_provisioning_enabled     = each.value.user_provisioning_enabled
        looker_user_provisioning_secret_name = each.value.user_provisioning_secret_name
      }
    )
  ]
}
