# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "os_distribution" {
  type    = string
  default = "ubuntu"

  validation {
    condition = contains(["ubuntu", "debian", "rhel", "centos"], lower(var.os_distribution))
    error_message = "Distribution must be one of \"ubuntu\", \"debian\", \"rhel\", or \"centos\"."
  }
}

variable "packer_sa_email" {
  type    = string
}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "jmx_pass_secret_name" {
  type    = string
}

variable "license_key_secret_name" {
  type    = string
}

variable "project_id" {
  type    = string
}

variable "technical_contact" {
  type    = string
}

variable "looker_version" {
  type    = string
  default = "22.0"
}

variable "looker_playbook" {
  type    = string
  default = "./ansible/image.yml"
}

variable "image_network" {
  type    = string
  default = "default"
}

variable "image_subnet" {
  type = string
  default = ""
}

variable "private_ip_mode" {
  type = bool
  default = false
}
