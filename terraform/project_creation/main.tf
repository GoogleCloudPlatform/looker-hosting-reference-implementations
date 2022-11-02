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

locals {
  activate_apis = [
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "domains.googleapis.com",
    "dns.googleapis.com",
    "file.googleapis.com",
    "iap.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "oslogin.googleapis.com",
    "pubsub.googleapis.com",
    "servicenetworking.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "storage-api.googleapis.com",
    "secretmanager.googleapis.com",
    "redis.googleapis.com",
    "cloudkms.googleapis.com",
    "serviceusage.googleapis.com"
  ]
  roles = [
    "roles/file.editor",
    "roles/cloudkms.admin",
    "roles/redis.admin",
    "roles/cloudsql.admin",
    "roles/compute.admin",
    "roles/compute.networkAdmin",
    "roles/dns.admin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/secretmanager.viewer",
    "roles/container.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/secretmanager.secretAccessor",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/servicenetworking.networksAdmin",
    "roles/storage.admin",
    "roles/storage.objectViewer",
    "roles/logging.logWriter"
  ]
}

module "project" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/modules/project"

  name            = var.project_id
  services        = local.activate_apis
  billing_account = var.billing_account
  parent          = var.parent
}

module "secret_manager" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/modules/secret-manager"

  project_id = module.project.project_id
  secrets = {
    looker_license_key = null
    looker_db_pw       = null
    gcm_key            = null
  }
}

module "artifact_registry" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/modules/artifact-registry"

  project_id = module.project.project_id
  location   = var.location
  format     = "DOCKER"
  id         = var.repository_id
}

module "service_account" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/modules/iam-service-account"

  project_id = module.project.project_id
  name       = var.sa_name
  iam_project_roles = {
    "${module.project.project_id}" = local.roles
  }
  #impersonification of SA enabling
  iam = {
    "roles/iam.serviceAccountTokenCreator" = ["user:${var.email_address}"]
  }
}

resource "google_project_iam_member" "cloudbuild" {
  project = module.project.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${module.project.number}@cloudbuild.gserviceaccount.com"
}

module "dns" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric/modules/dns"

  project_id = module.project.project_id
  type       = "public"
  name       = var.dns_zone
  domain     = var.dns_domain
}
