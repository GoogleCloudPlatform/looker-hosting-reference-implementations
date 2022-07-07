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
  parsed_dns_project   = coalesce(var.dns_project, var.project)
}

##############
# Networking #
##############

# Create the VPC and subnet. We also need a cloud router and NAT to allow traffic
# from the private nodes out to the internet.
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

# We also define a the required VM firewall rules:
module "vm-looker-firewall_rules" {
  source       = "terraform-google-modules/network/google//modules/firewall-rules"
  version      = "4.1.0"

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

##################
# Compute Engine #
##################

# We define the VM service account and accompanying IAM role permissions
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
    "${var.project}=>roles/secretmanager.secretAccessor",
  ]
}

# We pull in information about the Packer-build compute image. We leverage
# image families to ensure the latest build gets deployed.
data "google_compute_image" "looker_image" {
  family = var.image_family
}

# We define the vm instance template with startup script flags
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
      db_server                      = ""
      db_user                        = ""
      db_password_secret             = ""
      gcm_key_secret_name            = var.gcm_key_secret_name
      shared_storage_server          = ""
      shared_storage_fs              = ""
      user_provisioning_secret_name  = var.user_provisioning_secret_name
      env                            = var.env
      domain                         = local.hosted_zone_domain
      startup_flags                  = []
      startup_params                 = {}
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
  target_size       = 1
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
  source                          = "GoogleCloudPlatform/lb-http/google"
  version                         = "6.2.0"
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
  firewall_projects               = []
  firewall_networks               = []
  backends = {
    web = {
      description                     = null
      protocol                        = "HTTPS"
      port                            = null
      port_name                       = "https"
      timeout_sec                     = 60
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
  project = local.parsed_dns_project
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
  dns_project      = local.parsed_dns_project
  dns_domain       = local.hosted_zone_domain
  dns_short_names  = ["${var.env}.looker"]
}
