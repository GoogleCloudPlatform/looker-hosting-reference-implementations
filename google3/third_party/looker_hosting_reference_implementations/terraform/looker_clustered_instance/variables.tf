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

variable "project" {
  type        = string
  description = "The GCP Project to use"
}

variable "terraform_sa_email" {
  type        = string
  description = "The Service Account to use for running Terraform"
}

variable "region" {
  type        = string
  description = "The GCP region to use"
}

variable "zone" {
  type        = string
  description = "The GCP zone to use"
}

variable "technical_contact_email" {
  type        = string
  description = "Your Looker license key"
}

variable "image_family" {
  type        = string
  description = "The name of the image family for your VM image"
  default     = "looker"
}

variable "machine_type" {
  type        = string
  description = "The Compute Engine machine type to use for your Looker instance"
}

variable "node_count" {
  type        = string
  description = "How many initial nodes to create"
  default     = 1
}

variable "startup_script" {
  type        = string
  description = "Path to the startup script to use."
}

variable "gcm_key_secret_name" {
  type        = string
  description = "The name of the GCM key secret in secret manager"
}

variable "db_secret_name" {
  type        = string
  description = "Name of the looker database password secret"
}

variable "db_version" {
  type = string
  description = "The mysql version to use"
  default = "MYSQL_5_7"
  validation {
    condition = contains(["MYSQL_5_7", "MYSQL_8_0"], var.db_version)
    error_message = "The db_version must be either \"MYSQL_5_7\" or \"MYSQL_8_0\"."
  }
}

variable "db_type" {
  type        = string
  description = "The core and memory configuration of your mysql database"
  default     = "db-n1-standard-1"
}

variable "db_deletion_protection" {
  type        = string
  description = "When enabled, this will prevent your instance from being deleted"
  default     = "false"
}

variable "db_high_availability" {
  type        = bool
  description = "When enabled, this will configure the database for high availability. This is more expensive, but more robust, so this should be reserved for production instances."
  default     = false
}

variable "db_flags" {
  type = list(object({
    name = string
    value = string
  }))
}

variable "db_read_replicas" {
  type = list(object({
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
  description = "This creates read replica(s) of the backend database. This may be a good option if a client is planning on offloading data from the backend database to a warehouse, a la “Elite System Activity” or otherwise planning on making heavy use of System Activity queries."
  default     = []
}

variable "hosted_zone" {
  type        = string
  description = "The name of your GCP Project’s Cloud DNS hosted zone."
}

variable "env" {
  type        = string
  description = "A unique name for this Looker instance"
}

variable "first_name" {
  type        = string
  description = "Your first name. Used for user registration."
}

variable "last_name" {
  type        = string
  description = "Your last name. Used for user registration."
}

variable "subnet_ip_range" {
  type        = string
  description = "The IP range of the primary Looker subnet"
  default     = "10.0.0.0/16"
}

variable "startup_flags" {
  type        = list(any)
  description = "A list of flag-style startup options. `Flag` means they don’t require an associated value."
}

variable "startup_params" {
  type        = map(any)
  description = "A map of key/value pairs for startup options that take a value"
}

variable "private_ip_range" {
  type        = string
  description = "The IP range to use with Private Service Connection"
  default     = "192.168.0.0/16"
}

# These last two optional variables are only needed if you wish to trigger automatic user provisioning
variable "looker_password_secret_name" {
  type        = string
  description = "The name of the looker password secret"
  default     = ""
}

variable "looker_license_key_secret_name" {
  type        = string
  description = "Your looker license key secret name"
  default     = ""
}
