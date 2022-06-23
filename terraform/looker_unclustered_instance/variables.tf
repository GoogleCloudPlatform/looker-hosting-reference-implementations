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

variable "image_family" {
  type        = string
  description = "The name of the image family for your VM image"
  default     = "looker-ubuntu"
}

variable "machine_type" {
  type        = string
  description = "The Compute Engine machine type to use for your Looker instance"
}

variable "startup_script" {
  type        = string
  description = "Path to the startup script to use."
}

variable "hosted_zone" {
  type        = string
  description = "The name of your GCP Project’s Cloud DNS hosted zone."
}

variable "env" {
  type        = string
  description = "A unique name for this Looker instance"
}

variable "subnet_ip_range" {
  type        = string
  description = "The IP range of the primary Looker subnet"
  default     = "10.0.0.0/16"
}

variable "gcm_key_secret_name" {
  type        = string
  description = "The name of the GCM key secret in secret manager"
}

# This last optional variable is only needed if you wish to trigger automatic user provisioning
variable "user_provisioning_secret_name" {
  type        = string
  description = "The name of the user provisioner secret in secret manager"
  default = ""
}