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
  description = "Project Name"
  type        = string
}

variable "parent" {
  description = "Parent folder or organization in 'folders/folder_id' or 'organizations/org_id' format"
  type        = string
  default     = null
}

variable "location" {
  description = "GCP Location"
  type        = string
}

variable "billing_account" {
  description = "Billing Account ID"
  type        = string
}

variable "repository_id" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "looker"
}

variable "sa_name" {
  description = "Service Account Name"
  type        = string
}

variable "email_address" {
  description = "Your own user credentials"
  type        = string
}

variable "dns_zone" {
  description = "DNS Zone Name"
  type        = string
}

variable "dns_domain" {
  description = "DNS Domain Name  - this NEEDS to end with a period"
  type        = string

  validation {
    condition     = endswith(var.dns_domain, ".")
    error_message = "The DNS domain must end with a period (.)"
  }
}
