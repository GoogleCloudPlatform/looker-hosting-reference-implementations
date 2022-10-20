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

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    google-beta = {
      source = "hashicorp/google-beta"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "google" {
  impersonate_service_account = var.terraform_sa_email
  project                     = var.project_id
  region                      = var.region
  zone                        = var.zone
}

provider "google-beta" {
  impersonate_service_account = var.terraform_sa_email
  project                     = var.project_id
  region                      = var.region
  zone                        = var.zone
}

data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${module.looker_gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.looker_gke.ca_certificate)
  }
}

provider "kubernetes" {
  host                   = "https://${module.looker_gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.looker_gke.ca_certificate)
}

provider "random" {}

provider "local" {}

provider "http" {}
