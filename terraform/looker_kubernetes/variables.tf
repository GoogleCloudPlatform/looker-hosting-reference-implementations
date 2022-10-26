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

variable "project_id" {
  type        = string
  description = "The id of the main GCP Project to use"
}

variable "kms_project_id" {
  type        = string
  description = "The id of the KMS GCP Project to use. This can be the same as the project_id, but for production use cases it should be different. Omit to use project_id."
  default     = ""
}

variable "dns_project_id" {
  type        = string
  description = "the id of the GCP Project used for DNS. This can be the same as the project_id if your DNS zone is in the same project. Omit to use project_id"
  default     = ""
}

variable "region" {
  type        = string
  description = "The GCP region to use"
}

variable "zone" {
  type        = string
  description = "The GCP zone to use"
}

variable "terraform_sa_email" {
  type        = string
  description = "The Service Account to use for running Terraform"
}

variable "prefix" {
  type        = string
  description = "A unique prefix for resources deployed in this module"
}

variable "subnet_ip_range" {
  type        = string
  description = "The IP range of the primary Looker subnet"
  default     = "10.0.0.0/16"
}

variable "private_ip_range" {
  type        = string
  description = "The IP range to use with Private Service Connection"
  default     = "192.168.0.0/16"
}

variable "db_version" {
  type        = string
  description = "The MySQL version to use - must be either MYSQL_5_7 or MYSQL_8_0"
  default     = "MYSQL_8_0"
}

variable "db_deletion_protection" {
  type        = bool
  description = "Should the database instance be protected from deletion. Useful for prod environments"
  default     = false
}

variable "db_tier" {
  type        = string
  description = "The tier to use for the database instance. Supports custom tiers."
}

variable "db_high_availability" {
  type        = bool
  description = "Should the database instance be configured for high availability"
  default     = false
}

variable "db_flags" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "a list of database flags to include in addition to the default flags"
  default     = []
}

variable "db_read_replicas" {
  type = list(object({
    name                  = string
    tier                  = string
    zone                  = string
    availability_type     = string
    disk_type             = string
    disk_autoresize       = string
    disk_autoresize_limit = number
    disk_size             = string
    user_labels           = map(string)
    database_flags = list(object({
      name  = string
      value = string
    }))
    ip_configuration = object({
      authorized_networks = list(map(string))
      ipv4_enabled        = bool
      private_network     = string
      require_ssl         = bool
      allocated_ip_range  = string
    })
    encryption_key_name = string
  }))
  description = "A list of read replicas to create for this instance"
  default     = []
}

variable "gke_node_zones" {
  type        = list(string)
  description = "A list of zones for zonal node replication"
}

variable "gke_regional_cluster" {
  type        = bool
  description = "Should the GKE cluster be regionally replicated. More expensive but higher availability"
  default     = false
}

variable "gke_subnet_pod_range" {
  type = object({
    ip_cidr_range = string
    range_name    = string
  })
  description = "The secondary subnet range for GKE pods"
  default = {
    ip_cidr_range = "172.16.16.0/20"
    range_name    = "looker-pod-range"
  }
}

variable "gke_subnet_service_range" {
  type = object({
    ip_cidr_range = string
    range_name    = string
  })
  description = "The secondary subnet range for GKE services"
  default = {
    ip_cidr_range = "172.16.64.0/20"
    range_name    = "looker-service-range"
  }
}

variable "gke_controller_range" {
  type        = string
  description = "The CIDR block range for the GKE controller. Must be a /28 block."
  default     = "172.16.0.0/28"
}

variable "gke_private_endpoint" {
  type        = bool
  description = "Should the GKE endpoint be private. Note this has significant access implications."
  default     = false
}

variable "gke_master_global_access_enabled" {
  type        = bool
  description = "If enabled, access to GKE endpoint can occur outside of its region"
  default     = false
}

variable "gke_master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "A list of networks authorized to access the GKE endpoint"
  default     = []
}

variable "gke_release_channel" {
  type        = string
  description = "The name of the release channel to use for the GKE cluster"
  default     = "REGULAR"
}

variable "gke_use_application_layer_encryption" {
  type        = bool
  description = "Should GKE leverage Cloud KMS to provide additional envelope encryption for its internal storage database"
  default     = false
}

variable "gke_use_managed_prometheus" {
  type        = bool
  description = "Should the GKE cluster be enabled to use Google Managed Prometheus for monitoring"
  default     = true
}

variable "gke_node_tier" {
  type        = string
  description = "The tier to use for the Looker GKE node pool"
}

variable "gke_node_count_min" {
  type        = number
  description = "The min node count for the GKE cluster. Needed for autoscaling"
}

variable "gke_node_count_max" {
  type        = number
  description = "The max node count for the GKE cluster. Needed for autoscaling"
}

variable "dns_managed_zone_name" {
  type        = string
  description = "The name of the GCP DNS Managed Zone to use for DNS"
}

variable "looker_subdomain" {
  type        = string
  description = "An optional subdomain to include in Looker URLs"
  default     = "looker"
}

variable "looker_k8s_repository" {
  type        = string
  description = "The repository where the Looker container image is stored"
}

variable "looker_k8s_image_pull_policy" {
  type        = string
  description = "The image pull policy for Looker k8s images"
  default     = "Always"
}

variable "envs" {
  type = map(object({
    looker_node_count             = number
    looker_version                = string
    looker_startup_flags          = optional(string, "")
    gcm_key_secret_name           = string
    db_secret_name                = string
    user_provisioning_secret_name = optional(string, "")
    user_provisioning_enabled     = optional(bool, false)
    filestore_tier                = optional(string, "STANDARD")
    redis_enabled                 = optional(bool, true)
    redis_memory_size_gb          = optional(number, 4)
    redis_high_availability       = optional(bool, false)
    looker_k8s_issuer_admin_email = string
    looker_k8s_issuer_acme_server = optional(string, "https://acme-v02.api.letsencrypt.org/directory")
    looker_k8s_namespace          = optional(string, "looker")
    looker_k8s_update_config = optional(map(number), {
      maxSurge       = 1
      maxUnavailable = 0
    })
    looker_k8s_node_resources = optional(map(map(string)), {
      requests = {
        cpu    = "4000m"
        memory = "16Gi"
      },
      limits = {
        cpu    = "6000m"
        memory = "18Gi"
      }
    })
    looker_scheduler_node_enabled        = optional(bool, false)
    looker_scheduler_node_count          = optional(number, 2)
    looker_scheduler_threads             = optional(number, 10)
    looker_scheduler_unlimited_threads   = optional(number, 3)
    looker_scheduler_alert_threads       = optional(number, 3)
    looker_scheduler_render_caching_jobs = optional(number, 3)
    looker_scheduler_render_jobs         = optional(number, 2)
    looker_scheduler_resources = optional(map(map(string)), {
      requests = {
        cpu    = "4000m"
        memory = "16Gi"
      },
      limits = {
        cpu    = "6000m"
        memory = "18Gi"
      }
    })
  }))
  description = "A set of required options for each Looker environment"
}

variable "certmanager_helm_version" {
  type        = string
  description = "The helm chart version of cert-manager to install"
  default     = "v1.9.1"
}

variable "ingress_nginx_helm_version" {
  type        = string
  description = "The helm chart version of ingress-nginx to install"
  default     = "4.2.5"
}

variable "secrets_store_csi_driver_helm_version" {
  type        = string
  description = "The helm chart version of secrets-store-csi-driver to install"
  default     = "1.2.4"
}

variable "looker_helm_repository" {
  type        = string
  description = "The repository where the Looker helm chart is stored. For GCP Artifact Registry, this must begin with: oci:// "
}

variable "looker_helm_version" {
  type        = string
  description = "The version of the Looker Helm chart to deploy"
  default     = "0.1.0"
}

variable "disable_hooks" {
  type        = bool
  description = "Should helm hooks be disabled for the looker rollout - this will skip the schema migration job"
  default     = false
}
