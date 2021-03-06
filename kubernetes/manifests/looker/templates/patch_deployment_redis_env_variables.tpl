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

apiVersion: apps/v1
kind: Deployment
metadata:
  name: looker-clustered
spec:
  template:
    spec:
      containers:
        - name: looker-clustered-instance
          env:
            - name: LOOKER_REDIS_CACHE_DISCOVERY
              value: redis://${redis_host}:${redis_port}
            - name: LOOKER_REDIS_OPERATIONAL_DISCOVERY
              value: redis://${redis_host}:${redis_port}
