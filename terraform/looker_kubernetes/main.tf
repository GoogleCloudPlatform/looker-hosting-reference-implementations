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
  parsed_secondary_ranges = flatten(
    [
      for i in values(var.envs) : [
        i.gke_subnet_pod_range,
        i.gke_subnet_service_range
      ]
    ]
  )

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

  # We need to figure out which environments require gke application-layer kms encryption. This is to avoid unnecessary kms keyring creation
  parsed_kms_envs = toset([
    for k, v in var.envs :
    k if v.gke_use_application_layer_encryption
  ])

  # We set our default database flags here - these will be combined with the user defined flags from the variables
  default_db_flags = [
    {
      name = "local_infile"
      value = "off"
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
  version = "4.1.0"

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
  version = "9.0.0"

  project_id    = var.project_id
  vpc_network   = element(split("/", module.looker_vpc.network_self_link), length(split("/", module.looker_vpc.network_self_link)) - 1) # https://github.com/terraform-google-modules/terraform-google-sql-db/issues/176
  address       = local.private_ip_start
  ip_version    = "IPV4"
  prefix_length = local.private_ip_block
}

# Create a router and NAT to allow egress traffic to reach the internet
module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "1.3.0"

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
  version = "9.0.0"

  for_each = var.envs

  project_id                      = var.project_id
  name                            = "${var.prefix}-looker-${each.key}"
  random_instance_name            = true
  database_version                = each.value.db_version
  region                          = var.region
  zone                            = var.zone
  deletion_protection             = each.value.db_deletion_protection
  tier                            = each.value.db_tier
  enable_default_db               = false
  enable_default_user             = false
  maintenance_window_day          = 6
  maintenance_window_hour         = 20
  maintenance_window_update_track = "stable"
  availability_type               = each.value.db_high_availability ? "REGIONAL" : "ZONAL"

  database_flags = distinct(concat(local.default_db_flags, each.value.db_flags))

  ip_configuration = {
    authorized_networks = []
    ipv4_enabled        = false
    private_network     = module.looker_vpc.network_self_link
    require_ssl         = true
  }

  additional_databases = [
    {
      name      = "looker"
      charset   = "utf8mb4"
      collation = "utf8mb4_general_ci"
    }
  ]

  additional_users = [
    {
      name     = "looker"
      password = data.google_secret_manager_secret_version.db_pass[each.key].secret_data
      host     = "cloudsqlproxy~%"
    }
  ]

  backup_configuration = {
    enabled                        = true
    binary_log_enabled             = true
    start_time                     = "03:00"
    location                       = "us"
    transaction_log_retention_days = 3
    retained_backups               = 3
    retention_unit                 = "COUNT"
  }

  read_replicas = each.value.db_read_replicas

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
  version = "4.2.0"

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
  version = "4.1.0"

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
  for_each    = local.parsed_kms_envs
  byte_length = 4
}

module "looker_kms" {
  source  = "terraform-google-modules/kms/google"
  version = "2.1.0"

  for_each = local.parsed_kms_envs

  project_id      = var.kms_project_id
  location        = var.region
  keyring         = "looker-gke-secrets-${each.key}-${random_id.keyring_suffix[each.key].hex}"
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
  version = "19.0.0"

  for_each = var.envs

  project_id                        = var.project_id
  name                              = "${var.prefix}-looker-gke-${each.key}"
  region                            = var.region
  zones                             = each.value.gke_node_zones
  regional                          = each.value.gke_regional_cluster
  network                           = module.looker_vpc.network_name
  subnetwork                        = module.looker_vpc.subnets_names[0]
  ip_range_pods                     = each.value.gke_subnet_pod_range.range_name
  ip_range_services                 = each.value.gke_subnet_service_range.range_name
  create_service_account            = false
  service_account                   = module.gke_service_account.email
  enable_private_endpoint           = each.value.gke_private_endpoint
  enable_private_nodes              = true
  remove_default_node_pool          = true
  initial_node_count                = 1
  master_ipv4_cidr_block            = each.value.gke_controller_range
  add_master_webhook_firewall_rules = true
  firewall_inbound_ports            = ["8443"]
  release_channel                   = each.value.gke_release_channel
  database_encryption               = each.value.gke_use_application_layer_encryption ? [{ state = "ENCRYPTED", key_name = module.looker_kms[each.key].keys["key-encryption-key"] }] : [{ state = "DECRYPTED", key_name = "" }]

  # This is an optional component to enable workload monitoring, which can be used to export Looker
  # metrics to Cloud Monitoring. If you do not care for Cloud Monitoring support you can leave this
  # disabled.
  # Temporarily commenting this out to avoid https://github.com/hashicorp/terraform-provider-google/issues/10361.
  # After the initial run the below line can be commented back in and then the Terraform can be re-applied (i.e. `terraform apply`)
  # to safely enable workload monitoring.
  # monitoring_enabled_components     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  node_pools = [
    {
      name         = "${var.prefix}-looker-node-${each.key}"
      machine_type = each.value.gke_node_tier
      min_count    = each.value.gke_node_count_min
      max_count    = each.value.gke_node_count_max
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

# Finally we need two more service accounts for workload identity

# This first set takes care of Cloud SQL connectivity from inside the GKE cluster
module "workload_id_sql_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.1.0"

  project_id   = var.project_id
  prefix       = var.prefix
  display_name = "GKE Workload ID BQ and Cloud SQL"
  names        = ["looker-sql-workload-id"]
  description  = "Service account for GKE BigQuery and CloudSQL workload identity"
  project_roles = [
    "${var.project_id}=>roles/cloudsql.client",
    "${var.project_id}=>roles/bigquery.dataEditor",
    "${var.project_id}=>roles/bigquery.jobUser",
    "${var.project_id}=>roles/secretmanager.secretAccessor",
  ]
}

module "workload_id_sql_member" {
  depends_on = [module.looker_gke]

  source  = "terraform-google-modules/iam/google//modules/service_accounts_iam"
  version = "7.4.0"

  project          = var.project_id
  service_accounts = [module.workload_id_sql_service_account.email]
  mode             = "authoritative"
  bindings = {
    "roles/iam.workloadIdentityUser" = [
      for env in keys(var.envs) : "serviceAccount:${module.looker_gke[env].identity_namespace}[${var.looker_k8s_namespace}-${env}/${var.looker_k8s_service_account}-${env}]"
    ]
  }
}

# This next set takes care of appropriate DNS permissions to allow cert-manager to create SSL certificates
module "workload_id_dns_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.1.0"

  project_id   = var.dns_project_id
  prefix       = var.prefix
  display_name = "GKE Workload ID DNS"
  names        = ["looker-dns-workload-id"]
  description  = "Service account for GKE DNS workload identity"
  project_roles = [
    "${var.dns_project_id}=>roles/dns.admin",
  ]
}

module "workload_id_dns_member" {
  depends_on = [module.looker_gke]

  source  = "terraform-google-modules/iam/google//modules/service_accounts_iam"
  version = "7.4.0"

  project          = var.dns_project_id
  service_accounts = [module.workload_id_dns_service_account.email]
  mode             = "authoritative"
  bindings = {
    "roles/iam.workloadIdentityUser" = [
      for env in keys(var.envs) : "serviceAccount:${module.looker_gke[env].identity_namespace}[${var.certmanager_k8s_namespace}/${var.certmanager_k8s_service_account}]"
    ]
  }
}


#######
# DNS #
#######

# In most cases DNS will already be in place, so this may be a common point of customization. Here
# we're assuming a domain and GCP Managed DNS Zone already exist.

data "google_dns_managed_zone" "dns_zone" {
  name = var.dns_managed_zone_name
  project = var.dns_project_id
}

module "looker_dns" {
  source  = "terraform-google-modules/address/google"
  version = "3.1.1"

  for_each = var.envs

  project_id   = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  names        = ["looker-ip-${each.key}"]

  enable_cloud_dns = true
  dns_managed_zone = data.google_dns_managed_zone.dns_zone.name
  dns_project      = var.dns_project_id
  dns_domain       = local.parsed_hosted_zone_domain
  dns_short_names  = [var.looker_subdomain == "" ? each.key : "${each.key}.${var.looker_subdomain}"]
}
