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
  description = "The id of the KMS GCP Project to use. This can be the same as the project_id, but for production use cases it should be different."
}

variable "dns_project_id" {
  type        = string
  description = "the id of the GCP Project used for DNS. This can be the same as the project_id if your DNS zone is in the same project"
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

variable "envs" {
  type = map(object({
    gcm_key_secret_name    = string
    db_version             = string
    db_tier                = string
    db_high_availability   = bool
    db_deletion_protection = bool
    db_secret_name         = string
    db_flags               = list(object({
      name = string
      value = string
    }))
    db_read_replicas = list(object({
      name            = string
      tier            = string
      zone            = string
      disk_type       = string
      disk_autoresize = string
      disk_size       = string
      user_labels     = map(string)
      database_flags = list(object({
        name  = string
        value = string
      }))
      ip_configuration = object({
        authorized_networks = list(map(string))
        ipv4_enabled        = bool
        private_network     = string
        require_ssl         = bool
      })
      encryption_key_name = string
    }))
    filestore_tier                       = string
    redis_memory_size_gb                 = number
    redis_high_availability              = bool
    gke_regional_cluster                 = bool
    gke_use_application_layer_encryption = bool
    gke_node_zones                       = list(string)
    gke_node_count_min                   = number
    gke_node_count_max                   = number
    gke_node_tier                        = string
    gke_private_endpoint                 = bool
    gke_release_channel                  = string
    gke_subnet_pod_range                 = map(string)
    gke_subnet_service_range             = map(string)
    gke_controller_range                 = string
    cert_admin_email                     = string
    acme_server                          = string
    user_provisioning_secret_name        = string
  }))
  description = "A set of required options for each Looker environment"
  validation {
    condition     = toset(sort(flatten([for i in values(var.envs) : keys(i.gke_subnet_pod_range)]))) == toset(["ip_cidr_range", "range_name"])
    error_message = "The gke_subnet_pod_range map must include the keys \"ip_cidr_range\" and \"range_name\"."
  }
  validation {
    condition     = toset(sort(flatten([for i in values(var.envs) : keys(i.gke_subnet_service_range)]))) == toset(["ip_cidr_range", "range_name"])
    error_message = "The gke_subnet_service_range map must include the keys \"ip_cidr_range\" and \"range_name\"."
  }
  validation {
    condition     = length(setsubtract(toset(sort(flatten([for i in values(var.envs) : i.db_version]))), ["MYSQL_5_7", "MYSQL_8_0"])) == 0
    error_message = "The db_version variable must be one of \"MYSQL_5_7\" or \"MYSQL_8_0\"."
  }
}

variable "looker_k8s_namespace" {
  type        = string
  description = "The k8s looker namespace - will be appended by the relevant environment name"
  default     = "looker"
}

variable "looker_k8s_service_account" {
  type        = string
  description = "The k8s service account associated with the looker namespace - will be appended by the relevant environment name"
  default     = "looker-service-account"
}

variable "certmanager_k8s_namespace" {
  type        = string
  description = "The k8s cert-manager namespace"
  default     = "cert-manager"
}

variable "certmanager_k8s_service_account" {
  type        = string
  description = "The k8s service account associated with the cert-manager namespace"
  default     = "cert-manager"
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
