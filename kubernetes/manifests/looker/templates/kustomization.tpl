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

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${namespace}

resources:
  - looker_namespace.yaml
  - looker_cloudsql_service_account.yaml
  - looker_secret_provider_class.yaml
%{ if user_provisioning_secret_name != "" ~}
  - looker_user_provisioner_secret_provider_class.yaml
%{ endif ~}
  # - looker_pod_monitor.yaml
  - config
  - ../../base

images:
  - name: gcr.io/gcp-project/looker
    newName: gcr.io/${project_id}/looker
    newTag: "latest"

replicas:
  - name: looker-clustered
    count: 1

commonLabels:
  app: looker-clustered-${env_label}

patchesStrategicMerge:
  - patch_ingress_annotations.yaml
  - patch_deployment_cloud_sql_sidecar.yaml
  - patch_deployment_secret_store_csi.yaml
  - patch_deployment_redis_env_variables.yaml
  - patch_deployment_monitoring_ports.yaml
  - patch_deployment_looker_resources.yaml
%{ if user_provisioning_secret_name != "" ~}
  - patch_deployment_user_provisioner_secret_store_csi.yaml
%{ endif ~}

patchesJson6902:
  - path: patch_hostname.yaml
    target:
      group: networking.k8s.io
      kind: Ingress
      version: v1
      name: looker-ingress
  - path: patch_persistent_volume.yaml
    target:
      kind: PersistentVolume
      version: v1
      name: fileserver
  - path: patch_persistent_volume_claim.yaml
    target:
      kind: PersistentVolumeClaim
      version: v1
      name: fileserver-claim
