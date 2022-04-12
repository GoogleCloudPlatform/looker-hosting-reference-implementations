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

apiVersion: batch/v1
kind: Job
metadata:
  name: schema-migration
spec:
  backoffLimit: 10
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 60
  template:
    spec:
      serviceAccountName: ${k8s_service_account_name}
      restartPolicy: Never
      containers:
        - name: cloud-sql-proxy-migrate
          image: gcr.io/cloudsql-docker/gce-proxy:1.17-buster
          imagePullPolicy: "Always"
          command: ["bin/bash", "-c"]
          args:
            - |
              /cloud_sql_proxy -instances=${looker_project}:${region}:${db_name}=tcp:3306 &
              PID=$!
              while true
                do
                  if [[ -f "/lifecycle/main-terminated" ]]
                  then
                    echo "detected terminate file - attempting to kill process"
                    kill $PID
                    exit 0
                  fi
                  sleep 1
                done
          securityContext:
            runAsNonRoot: true
            capabilities:
              add:
                - SYS_PTRACE
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
          volumeMounts:
            - name: lifecycle
              mountPath: lifecycle
        - name: looker-migrator
          image: gcr.io/gcp-project/looker:21.20
          imagePullPolicy: "Always"
          command: ["/bin/bash", "/app/bin/migrator.sh"]
          securityContext:
            runAsUser: 9999
            runAsGroup: 9999
          resources:
            requests:
              cpu: "1000m"
              memory: "8Gi"
          env:
            - name: DESIRED_LOOKER_VERSION
              value: "21.20"
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          volumeMounts:
            - name: looker-startup
              mountPath: /app/lookerstart.cfg
              subPath: lookerstart.cfg
            - name: lookerfiles
              mountPath: /mnt/lookerfiles
            - name: lifecycle
              mountPath: /lifecycle
      volumes:
        - name: looker-startup
          configMap:
            defaultMode: 420
            name: looker-startup-options
            items:
              - key: lookerstart.cfg
                path: lookerstart.cfg
        - name: lookerfiles
          persistentVolumeClaim:
            claimName: fileserver-claim-${env_label}
            readOnly: false
        - name: lifecycle
          emptyDir:
