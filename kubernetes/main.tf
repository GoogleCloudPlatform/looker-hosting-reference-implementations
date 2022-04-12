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

# Generally speaking, we want to try to avoid templating in declarative kubernetes manifests - hence our choice
# of favoring Kustomize over options like Helm. However, we need a way to fill the outputs from Terraform (e.g.
# the IP address of the NFS & Redis servers) into our manifests. This module provides an easy way to accomplish
# this, but is by no means the only solution.


locals {
  k8s_base_path = "${path.module}/manifests"
  k8s_looker_path = "${local.k8s_base_path}/looker"
  k8s_nginx_path = "${local.k8s_base_path}/ingress-nginx"
  k8s_certmanager_path = "${local.k8s_base_path}/cert-manager"
  k8s_secret_store_path = "${local.k8s_base_path}/secret-store"
}

# Note that this is currently configured to read local state for development work. For production cases you will
# certainly want to modify this to read the appropriate remote state.
# (https://www.terraform.io/docs/language/settings/backends/gcs.html)
data "terraform_remote_state" "looker" {
  backend = "local"

  config = {
    path = "../terraform/looker_kubernetes/terraform.tfstate"
  }
}

#################
# Ingress NGINX #
#################

# This patches the IP address we created in TF into the GFE L4 loadbalancer
# created by the ingress-nginx deployment
resource "local_file" "looker-ip" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_nginx_path}/templates/patch_nginx_ip_address.tpl",
    {
      ip_address = each.value.looker_ip
    }
  )
  filename = "${local.k8s_nginx_path}/envs/${each.key}/patch_nginx_ip_address.yaml"
  file_permission = "0640"
}

resource "local_file" "nginx-kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_nginx_path}/templates/kustomization.yaml")
  filename = "${local.k8s_nginx_path}/envs/${each.key}/kustomization.yaml"
  file_permission = "0640"
}

resource "local_file" "service_monitoring" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_nginx_path}/templates/patch_service_monitoring_port.yaml")
  filename = "${local.k8s_nginx_path}/envs/${each.key}/patch_service_monitoring_port.yaml"
  file_permission = "0640"
}

resource "local_file" "deployment_monitoring" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_nginx_path}/templates/patch_deployment_monitoring_port.yaml")
  filename = "${local.k8s_nginx_path}/envs/${each.key}/patch_deployment_monitoring_port.yaml"
  file_permission = "0640"
}

resource "local_file" "ingress_pod_monitor" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_nginx_path}/templates/ingress_pod_monitor.yaml")
  filename = "${local.k8s_nginx_path}/envs/${each.key}/ingress_pod_monitor.yaml"
  file_permission = "0640"
}

################
# Cert Manager #
################

# We rely on workload identity and a GCP service account to allow cert-manager's
# DNS challenges to authenticate correctly. This patches in the appropriate GCP
# Service Account to the K8s service account annotation - required for workload
# identity setup.
# (https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
resource "local_file" "looker_certmanager_service_account" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_certmanager_path}/templates/certmanager_service_account.tpl",
    {
      dns_sa_email = data.terraform_remote_state.looker.outputs.dns_sa_email
    }
  )
  filename = "${local.k8s_certmanager_path}/envs/${each.key}/certmanager_service_account.yaml"
  file_permission = "0640"
}

# We default to use ACME/LetsEncrypt with cert-manager. The elements here configure
# which ACME server to use for cert provisioning. The staging server can be used for
# testing while the production server can be used for valid production certificates
# (https://letsencrypt.org/docs/staging-environment/)
resource "local_file" "looker_certmanager_clusterissuer" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_certmanager_path}/templates/cluster_issuer.tpl",
    {
      cert_admin_email = each.value.cert_admin_email,
      acme_server = each.value.acme_server,
      dns_project = data.terraform_remote_state.looker.outputs.project
    }
  )
  filename = "${local.k8s_certmanager_path}/envs/${each.key}/cluster_issuer.yaml"
  file_permission = "0640"
}

resource "local_file" "cert-manager-kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_certmanager_path}/templates/kustomization.yaml")
  filename = "${local.k8s_certmanager_path}/envs/${each.key}/kustomization.yaml"
  file_permission = "0640"
}

##########
# Looker #
##########

# This patches the approprate values into the kustomization yaml
resource "local_file" "looker_kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/kustomization.tpl",
    {
      namespace = each.value.looker_k8s_namespace,
      project_id = data.terraform_remote_state.looker.outputs.project
      env_label = each.key
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/kustomization.yaml"
  file_permission = "0640"
}

# This patches the appropriate namespace into the namespace's definition yaml
resource "local_file" "looker_namespace" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/looker_namespace.tpl",
    {
      namespace = each.value.looker_k8s_namespace
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/looker_namespace.yaml"
  file_permission = "0640"
}

# We rely on workload identity and a GCP service account to allow Looker
# to communicate with Cloud SQL and BigQuery (using ADCs) This patches in the
# appropriate GCP Service Account to the K8s service account annotation - required
# for workload identity setup.
# (https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
resource "local_file" "looker_cloudsql_service_account" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/looker_cloudsql_service_account.tpl",
    {
      k8s_service_account_name = each.value.looker_k8s_service_account
      cloud_sql_sa_email = data.terraform_remote_state.looker.outputs.cloud_sql_sa_email
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/looker_cloudsql_service_account.yaml"
  file_permission = "0640"
}

# We communicate with Cloud SQL via Cloud SQL Auth Proxy running in a sidecar.
# This patches the appropriate values into the Looker deployment to configure
# the sidecar.
# (https://cloud.google.com/sql/docs/mysql/connect-kubernetes-engine)
resource "local_file" "patch_deployment_cloud_sql_sidecar" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_deployment_cloud_sql_sidecar.tpl",
    {
      k8s_service_account_name = each.value.looker_k8s_service_account,
      looker_project = data.terraform_remote_state.looker.outputs.project
      region = data.terraform_remote_state.looker.outputs.region,
      db_name = each.value.db_name,
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_deployment_cloud_sql_sidecar.yaml"
  file_permission = "0640"
}

# This patches the appropriate URL in to the ingress controller's hostname
resource "local_file" "patch_hostname" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_hostname.tpl",
    {
      dns_entry = each.value.hostname
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_hostname.yaml"
  file_permission = "0640"
}

# Ingress NGINX uses annotations to configure the relevant ingress controllers.
# This patches the appropriate value into this annotation.
resource "local_file" "patch_ingress_annotations" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_ingress_annotations.tpl",
    {
      dns_entry = each.value.hostname
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_ingress_annotations.yaml"
  file_permission = "0640"
}

# This patches the appropriate NFS IP into the persistent volume manifest
resource "local_file" "patch_persistent_volume" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_persistent_volume.tpl",
    {
      nfs_ip = each.value.nfs_ip,
      env_label = each.key
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_persistent_volume.yaml"
  file_permission = "0640"
}

# This patches the appropriate filestore name into the volume claim
resource "local_file" "patch_persistent_volume_claim" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_persistent_volume_claim.tpl",
    {
      env_label = each.key
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_persistent_volume_claim.yaml"
  file_permission = "0640"
}

# This patches the appropriate values for Redis into the Looker deployment
resource "local_file" "patch_deployment_redis_env_variables" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/patch_deployment_redis_env_variables.tpl",
    {
      redis_host = each.value.redis_host,
      redis_port = each.value.redis_port
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_deployment_redis_env_variables.yaml"
  file_permission = "0640"
}

resource "local_file" "monitoring_ports" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/patch_deployment_monitoring_ports.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_deployment_monitoring_ports.yaml"
  file_permission = "0640"
}

resource "local_file" "looker_container_resources" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/patch_deployment_looker_resources.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_deployment_looker_resources.yaml"
  file_permission = "0640"
}

resource "local_file" "looker_pod_monitor" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/looker_pod_monitor.tpl",
    {
      env_label = each.key
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/looker_pod_monitor.yaml"
  file_permission = "0640"
}

###############
# Config Maps #
###############


resource "local_file" "jmx_config" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/config/jmx-prom-config.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/config/jmx-prom-config.yaml"
  file_permission = "0640"
}

resource "local_file" "lookerstart_cfg" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/config/lookerstart.cfg")
  filename = "${local.k8s_looker_path}/envs/${each.key}/config/lookerstart.cfg"
  file_permission = "0640"
}

resource "local_file" "config_kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/config/kustomization.tpl",
    {
      namespace = each.value.looker_k8s_namespace
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/config/kustomization.yaml"
  file_permission = "0640"
}

###########
# Secrets #
###########

# There are many solutions for dealing with secrets. Here we follow one popular option: integrating
# with an enterprise-grade secret manager - in this case GCP's secret manager. Another popular option
# is Hashicorp Vault. This approach makes use of the Secret Store CSI to mount the secrets directly
# from the secret manager into the pod's file system. We can then create environment variables from
# the linked secrets. This solution is fully integrated with workload identity and IAM.
# (https://cloud.google.com/secret-manager/docs/quickstart)
# (https://cloud.google.com/secret-manager/docs/using-other-products#google-kubernetes-engine)
# (https://secrets-store-csi-driver.sigs.k8s.io/introduction.html)

# This creates the secret store kustomization file
resource "local_file" "secret-store-kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_secret_store_path}/templates/kustomization.yaml")
  filename = "${local.k8s_secret_store_path}/envs/${each.key}/kustomization.yaml"
  file_permission = "0640"
}

# This creates the secret provider class
resource "local_file" "secret_provider_class" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/looker_secret_provider_class.tpl",
    {
      project_id = data.terraform_remote_state.looker.outputs.project
      db_secret_name = each.value.db_secret_name
      gcm_key_secret_name = each.value.gcm_key_secret_name
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/looker_secret_provider_class.yaml"
  file_permission = "0640"
}


# This creates the deployment patch that mounts the secret volume and creates the relevant env variables
resource "local_file" "secret_store_csi" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/patch_deployment_secret_store_csi.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/patch_deployment_secret_store_csi.yaml"
  file_permission = "0640"
}

#################
# Migration Job #
#################

resource "local_file" "migrage_looker_kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/jobs/rolling_update/kustomization.tpl",
    {
      namespace = each.value.looker_k8s_namespace,
      project_id = data.terraform_remote_state.looker.outputs.project
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/rolling_update/kustomization.yaml"
  file_permission = "0640"
}

resource "local_file" "migrage_looker_job" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/jobs/rolling_update/looker_upgrade_job.tpl",
    {
      k8s_service_account_name = each.value.looker_k8s_service_account,
      looker_project = data.terraform_remote_state.looker.outputs.project,
      region = data.terraform_remote_state.looker.outputs.region,
      db_name = each.value.db_name,
      env_label = each.key
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/rolling_update/looker_upgrade_job.yaml"
  file_permission = "0640"
}

resource "local_file" "job_secret_store_csi" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/jobs/rolling_update/patch_job_secret_store_csi.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/rolling_update/patch_job_secret_store_csi.yaml"
  file_permission = "0640"
}

####################
# Key Rotation Job #
####################

resource "local_file" "rotate_looker_kustomize" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/jobs/gcm_key_rotation/kustomization.tpl",
    {
      namespace = each.value.looker_k8s_namespace,
      project_id = data.terraform_remote_state.looker.outputs.project
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/gcm_key_rotation/kustomization.yaml"
  file_permission = "0640"
}

resource "local_file" "rotate_secret_provider" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/jobs/gcm_key_rotation/looker_secret_provider_class.tpl",
    {
      gcm_key_secret_name = each.value.gcm_key_secret_name,
      project_id = data.terraform_remote_state.looker.outputs.project,
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/gcm_key_rotation/looker_secret_provider_class.yaml"
  file_permission = "0640"
}

resource "local_file" "rotate_looker_job" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = templatefile(
    "${local.k8s_looker_path}/templates/jobs/gcm_key_rotation/looker_key_rotation_job.tpl",
    {
      k8s_service_account_name = each.value.looker_k8s_service_account
      project_id = data.terraform_remote_state.looker.outputs.project,
      region = data.terraform_remote_state.looker.outputs.region,
      db_name = each.value.db_name,
    }
  )
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/gcm_key_rotation/looker_key_rotation_job.yaml"
  file_permission = "0640"
}

resource "local_file" "patch_rotate_job_env_variables" {
  for_each = data.terraform_remote_state.looker.outputs.env_data
  content = file("${local.k8s_looker_path}/templates/jobs/gcm_key_rotation/patch_job_env_variables.yaml")
  filename = "${local.k8s_looker_path}/envs/${each.key}/jobs/gcm_key_rotation/patch_job_env_variables.yaml"
  file_permission = "0640"
}
