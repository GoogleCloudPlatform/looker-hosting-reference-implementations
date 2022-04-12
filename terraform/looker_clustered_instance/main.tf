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

locals {
  hosted_zone_domain   = trim(data.google_dns_managed_zone.looker_zone.dns_name, ".")
  hosted_zone_dns_name = data.google_dns_managed_zone.looker_zone.dns_name

  # This allows us to pass in the Private IP range as a cidr block, like every other
  # ip range variable.
  private_ip_start = split("/", var.private_ip_range)[0]
  private_ip_block = tonumber(split("/", var.private_ip_range)[1])

  # We set our default database flags here - these will be combined with the user defined flags from the variables
  default_db_flags = [
    {
      name = "local_infile"
      value = "off"
    }
  ]
}

##############
# Networking #
##############

# We define a custom VPC for this instance:
module "looker_vpc" {
  source       = "terraform-google-modules/network/google"
  version      = "4.1.0"
  project_id   = var.project
  network_name = "looker-network"
  subnets = [
    {
      subnet_name   = "looker-subnet"
      subnet_ip     = var.subnet_ip_range
      subnet_region = var.region
    }
  ]
}

# Set up Private Services access. Private Services are used to securely connect
# to Cloud SQL, Filestore, and Memorystore
module "private_service_access" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/private_service_access"
  version = "9.0.0"

  project_id    = var.project
  vpc_network   = element(split("/", module.looker_vpc.network_self_link), length(split("/", module.looker_vpc.network_self_link)) - 1) # https://github.com/terraform-google-modules/terraform-google-sql-db/issues/176
  address       = local.private_ip_start
  ip_version    = "IPV4"
  prefix_length = local.private_ip_block
}

module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "1.3.0"

  project = var.project
  name    = "looker-router"
  network = module.looker_vpc.network_name
  region  = var.region

  nats = [{
    name = "looker-nat"
  }]
}

# We define a the vm firewall rules:
module "vm-looker-firewall_rules" {
  source  = "terraform-google-modules/network/google//modules/firewall-rules"
  version = "4.1.0"

  project_id   = var.project
  network_name = module.looker_vpc.network_name

  rules = [
    {
      name                    = "looker-firewall-allow-node-internal"
      description             = null
      direction               = "INGRESS"
      priority                = null
      ranges                  = [element(module.looker_vpc.subnets_ips, 0)]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["looker-node"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["1551", "61616", "1552", "8983", "9090"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name                    = "looker-firewall-allow-nfs-internal"
      description             = null
      direction               = "INGRESS"
      priority                = null
      ranges                  = [element(module.looker_vpc.subnets_ips, 0)]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["looker"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["2049", "4045", "111", "2046"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name                    = "looker-firewall-gfe"
      description             = null
      direction               = "INGRESS"
      priority                = null
      ranges                  = ["130.211.0.0/22", "35.191.0.0/16"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = ["looker-node"]
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["9999", "19999"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    },
    {
      name                    = "looker-firewall-iap"
      description             = null
      direction               = "INGRESS"
      priority                = null
      ranges                  = ["35.235.240.0/20"]
      source_tags             = null
      source_service_accounts = null
      target_tags             = null
      target_service_accounts = null
      allow = [{
        protocol = "tcp"
        ports    = ["22"]
      }]
      deny = []
      log_config = {
        metadata = "INCLUDE_ALL_METADATA"
      }
    }
  ]
}

############
# Database #
############

data "google_secret_manager_secret_version" "db_pass" {
  secret = var.db_secret_name
}

module "looker_db" {
  depends_on = [module.private_service_access] # We need to make sure private services is ready first

  source  = "GoogleCloudPlatform/sql-db/google//modules/mysql"
  version = "9.0.0"

  project_id                      = var.project
  name                            = "looker-${var.env}"
  random_instance_name            = true
  database_version                = var.db_version
  region                          = var.region
  zone                            = var.zone
  deletion_protection             = var.db_deletion_protection
  tier                            = var.db_type
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
      password = data.google_secret_manager_secret_version.db_pass.secret_data
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

  read_replicas = var.db_read_replicas
}

#######
# NFS #
#######

# There's no published module for filestore, but it's a pretty simple resource so a module wouldn't add anything
resource "google_filestore_instance" "looker_filestore" {
  depends_on = [module.private_service_access] # We need to make sure private services is ready first
  provider   = google-beta


  project  = var.project
  name     = "${var.env}-looker-fs"
  location = var.zone
  tier     = "STANDARD"

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

##################
# Compute Engine #
##################

# We define the vm service account and accompanying IAM role permissions
module "vm_service_account" {
  source       = "terraform-google-modules/service-accounts/google"
  version      = "4.1.0"
  project_id   = var.project
  prefix       = var.env
  names        = ["looker-vm"]
  display_name = "Default compute engine service account for Looker instancese"
  project_roles = ["${var.project}=>roles/cloudsql.editor",
    "${var.project}=>roles/monitoring.metricWriter",
    "${var.project}=>roles/logging.logWriter",
    "${var.project}=>roles/secretmanager.secretAccessor"
  ]
}

# We pull in information about the Packer-build compute image. We leverage
# image families to ensure the latest build gets deployed.
data "google_compute_image" "looker_image" {
  family = var.image_family
}

# We define the vm instance group with startup script flags
module "vm_instance_template" {
  source       = "terraform-google-modules/vm/google//modules/instance_template"
  version      = "7.5.0"
  name_prefix  = "looker-template-${var.env}"
  machine_type = var.machine_type
  region       = var.region
  source_image = data.google_compute_image.looker_image.self_link
  subnetwork   = element(module.looker_vpc.subnets_names, 0)
  labels = {
    app         = "looker"
    environment = var.env
    type        = "node"
  }
  tags = ["looker", "looker-node"]

  startup_script = templatefile(
    "${path.module}/${var.startup_script}",
    {
      db_server                      = module.looker_db.instance_connection_name,
      db_user                        = module.looker_db.additional_users[0].name,
      db_password_secret             = var.db_secret_name,
      gcm_key_secret_name            = var.gcm_key_secret_name
      shared_storage_server          = google_filestore_instance.looker_filestore.networks.0.ip_addresses.0,
      shared_storage_fs              = google_filestore_instance.looker_filestore.file_shares[0].name,
      looker_license_key_secret      = var.looker_license_key_secret_name,
      looker_password_secret         = var.looker_password_secret_name,
      looker_firstname               = var.first_name,
      looker_lastname                = var.last_name,
      looker_technical_contact_email = var.technical_contact_email,
      looker_client_id               = "",
      looker_client_secret           = "",
      env                            = var.env,
      domain                         = local.hosted_zone_domain,
      startup_flags                  = var.startup_flags,
      startup_params                 = var.startup_params
    }
  )
  service_account = {
    email  = module.vm_service_account.email
    scopes = ["cloud-platform"]
  }
}

# We define the vm managed instance group and health checks
module "vm_mig" {
  source            = "terraform-google-modules/vm/google//modules/mig"
  version           = "7.5.0"
  mig_name          = "looker-${var.env}-group"
  hostname          = "looker-${var.env}"
  region            = var.region
  instance_template = module.vm_instance_template.self_link
  target_size       = var.node_count
  named_ports = [
    {
      name = "https"
      port = 9999
    },
    {
      name = "https-api"
      port = 19999
    }
  ]
  health_check_name = "looker-https-health-check-${var.env}"
  health_check = {
    "check_interval_sec" : 10,
    "healthy_threshold" : 1,
    "host" : "",
    "initial_delay_sec" : 30,
    "port" : 9999,
    "proxy_header" : "NONE",
    "request" : "",
    "request_path" : "/alive",
    "response" : "",
    "timeout_sec" : 3,
    "type" : "",
    "unhealthy_threshold" : 3
  }
}

##################
# Load Balancing #
##################

# We define the url map path rules
resource "google_compute_url_map" "looker_loadbalancer" {
  name            = "looker-loadbalancer-${var.env}"
  default_service = module.looker-lb-https.backend_services["web"].self_link

  host_rule {
    hosts        = ["${var.env}.looker.${local.hosted_zone_domain}"]
    path_matcher = "web"
  }

  path_matcher {
    name            = "web"
    default_service = module.looker-lb-https.backend_services["web"].self_link

    path_rule {
      paths   = ["/*", "/api/internal/*"]
      service = module.looker-lb-https.backend_services["web"].self_link
    }
    path_rule {
      paths   = ["/api/*", "/api-docs/*", "/versions"]
      service = module.looker-lb-https.backend_services["api"].self_link
    }
  }
}

# Finally we need to wire up the instance group to a load balancer:
module "looker-lb-https" {
  source  = "GoogleCloudPlatform/lb-http/google"
  version = "6.2.0"

  project                         = var.project
  address                         = module.looker_dns.addresses[0]
  create_address                  = false
  name                            = "looker-${var.env}"
  target_tags                     = []
  ssl                             = true
  use_ssl_certificates            = false
  url_map                         = google_compute_url_map.looker_loadbalancer.self_link
  create_url_map                  = false
  https_redirect                  = true
  managed_ssl_certificate_domains = ["${var.env}.looker.${local.hosted_zone_domain}"]
  backends = {
    web = {
      description                     = null
      protocol                        = "HTTPS"
      port                            = null
      port_name                       = "https"
      timeout_sec                     = 10
      enable_cdn                      = false
      custom_request_headers          = null
      custom_response_headers         = null
      security_policy                 = null
      connection_draining_timeout_sec = null
      session_affinity                = null
      affinity_cookie_ttl_sec         = null
      health_check = {
        check_interval_sec  = 10
        timeout_sec         = 3
        healthy_threshold   = 1
        unhealthy_threshold = 3
        request_path        = "/alive"
        port                = 9999
        host                = ""
        logging             = null
      }

      log_config = {
        enable      = false
        sample_rate = null
      }

      groups = [
        {
          group                        = module.vm_mig.instance_group
          balancing_mode               = null
          capacity_scaler              = null
          description                  = null
          max_connections              = null
          max_connections_per_instance = null
          max_connections_per_endpoint = null
          max_rate                     = null
          max_rate_per_instance        = null
          max_rate_per_endpoint        = null
          max_utilization              = null
        }
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = null
        oauth2_client_secret = null
      }
    },
    api = {
      description             = null
      protocol                = "HTTPS"
      port                    = null
      port_name               = "https-api"
      timeout_sec             = 10
      enable_cdn              = false
      custom_request_headers  = null
      custom_response_headers = null
      security_policy         = null

      connection_draining_timeout_sec = null
      session_affinity                = null
      affinity_cookie_ttl_sec         = null
      health_check = {
        check_interval_sec  = 10
        timeout_sec         = 3
        healthy_threshold   = 1
        unhealthy_threshold = 3
        request_path        = "/alive"
        port                = 19999
        host                = ""
        logging             = null
      }

      log_config = {
        enable      = false
        sample_rate = null
      }

      groups = [
        {
          group                        = module.vm_mig.instance_group
          balancing_mode               = null
          capacity_scaler              = null
          description                  = null
          max_connections              = null
          max_connections_per_instance = null
          max_connections_per_endpoint = null
          max_rate                     = null
          max_rate_per_instance        = null
          max_rate_per_endpoint        = null
          max_utilization              = null
        }
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = null
        oauth2_client_secret = null
      }
    }
  }
}


#######
# DNS #
#######

# Pulling in the pre-defined hosted zone:
data "google_dns_managed_zone" "looker_zone" {
  name = var.hosted_zone
}

module "looker_dns" {
  source  = "terraform-google-modules/address/google"
  version = "3.1.1"


  project_id   = var.project
  region       = var.region
  global       = true
  address_type = "EXTERNAL"
  names        = ["looker-ip-${var.env}"]

  enable_cloud_dns = true
  dns_managed_zone = data.google_dns_managed_zone.looker_zone.name
  dns_project      = var.project
  dns_domain       = local.hosted_zone_domain
  dns_short_names  = ["${var.env}.looker"]
}
