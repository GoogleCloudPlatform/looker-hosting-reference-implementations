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

output "project" {
  value = var.project_id
}

output "dns_project" {
  value = local.parsed_dns_project_id
}

output "region" {
  value = var.region
}

output "zone" {
  value = var.zone
}

output "env_data" {
  value = {
    for env in keys(var.envs) : env => {
      db_name                    = module.looker_db[env].instance_name
      db_secret_name             = var.envs[env].db_secret_name
      gcm_key_secret_name        = var.envs[env].gcm_key_secret_name
      nfs_ip                     = google_filestore_instance.looker_filestore[env].networks.0.ip_addresses.0
      redis_host                 = module.looker_cache[env].host
      redis_port                 = module.looker_cache[env].port
      looker_ip                  = module.looker_dns[env].addresses[0]
      hostname                   = module.looker_dns[env].dns_fqdns[0]
      looker_k8s_namespace       = "${var.looker_k8s_namespace}-${env}"
      looker_k8s_service_account = "${var.looker_k8s_service_account}-${env}"
      cert_admin_email           = var.envs[env].cert_admin_email
      acme_server                = var.envs[env].acme_server
      user_provisioning_secret_name = var.envs[env].user_provisioning_secret_name
    }
  }
}

output "cloud_sql_sa_email" {
  value = module.workload_id_sql_service_account.email
}

output "dns_sa_email" {
  value = module.workload_id_dns_service_account.email
}
