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
  - looker_upgrade_job.yaml
  - ../../config

images:
  - name: gcr.io/gcp-project/looker
    newName: gcr.io/${project_id}/looker
    # This changes the container version you are using. Typically this
    # should be the most recent build.
    newTag: "21.20"

patchesStrategicMerge:
  - patch_job_secret_store_csi.yaml

patchesJson6902:
  - target:
      group: batch
      version: v1
      kind: Job
      name: schema-migration
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/2/value
        # This sets the schema you want to migrate to. Typically this
        # is the same as the version you set above. (for standard upgrades)
        # For rollbacks this can be one version below the container
        # version you are running above.
        value: "21.20"
