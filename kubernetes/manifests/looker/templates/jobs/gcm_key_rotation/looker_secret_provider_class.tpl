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

apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: looker-rotator-secrets
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/${project_id}/secrets/${gcm_key_secret_name}/versions/latest"
        fileName: looker_gcm_key_new
      - resourceName: "projects/${project_id}/secrets/${gcm_key_secret_name}/versions/1"
        fileName: looker_gcm_key_old
  secretObjects:
    - data:
        - key: gcm-key-old
          objectName: looker_gcm_key_old
        - key: gcm-key-new
          objectName: looker_gcm_key_new
      secretName: gcm-rotation-secrets
      type: Opaque
