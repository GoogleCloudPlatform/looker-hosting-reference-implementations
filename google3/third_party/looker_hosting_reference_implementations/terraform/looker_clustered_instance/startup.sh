#!/bin/bash
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

# Looker startup script for Ubuntu 18.04 Bionic Beaver on GCP
# This makes use of terraform templating to inject relevant sections based on the variables provided in the .tfvars file

# Define standard variables all variables should default to "" if not present in the tfvars file
LOOKER_FIRSTNAME=${looker_firstname}
LOOKER_LASTNAME=${looker_lastname}
LOOKER_TECHNICAL_CONTACT_EMAIL=${looker_technical_contact_email}
LOOKER_CLIENT_ID=${looker_client_id}
LOOKER_CLIENT_SECRET=${looker_client_secret}
DOMAIN=${domain}
ENV=${env}

cd /home/looker/looker

# create the GCM key environment variable for proper AES-256 encryption initialization
gcloud secrets versions access latest --secret ${gcm_key_secret_name} > /home/looker/looker/gcm_key
sudo chown looker:looker gcm_key
sudo chmod 400 gcm_key

# set license key from secret
%{ if looker_license_key_secret != "" }
LOOKER_LICENSE_KEY=$(gcloud secrets versions access latest --secret ${looker_license_key_secret})
%{ endif }

# set database info including password from secret
%{ if db_password_secret != "" }
DB_SERVER=${db_server}
DB_USER=${db_user}
DB_PASSWORD=$(gcloud secrets versions access latest --secret ${db_password_secret})
cat <<EOT | sudo tee -a /etc/systemd/system/cloud_sql_proxy.service
[Install]
WantedBy=multi-user.target
[Unit]
Description=Google Cloud SQL Proxy
Requires=network.target
After=network.target
[Service]
Type=simple
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/cloud_sql_proxy -instances=$DB_SERVER=tcp:3306
Restart=always
StandardOutput=journal
User=root
EOT

cat <<EOT > /home/looker/looker/looker-db.yml
host: 127.0.0.1
username: $DB_USER
password: $DB_PASSWORD
database: $DB_USER
dialect: mysql
port: 3306
EOT

sudo chown looker:looker looker-db.yml
%{ endif }

# Set up User-based Looker provisioner
%{ if looker_password_secret != "" }
LOOKER_PASSWORD=$(gcloud secrets versions access latest --secret ${looker_password_secret})

cat <<EOT > /home/looker/looker/provision.yml
license_key: "$LOOKER_LICENSE_KEY"
host_url: "https://$ENV.looker.$DOMAIN"
user:
  first_name: "$LOOKER_FIRSTNAME"
  last_name: "$LOOKER_LASTNAME"
  email: "$LOOKER_TECHNICAL_CONTACT_EMAIL"
  password: "$LOOKER_PASSWORD"
EOT

sudo chown looker:looker provision.yml
%{ endif }

# Set up API-based Looker provisioner (if a password has been provided default to user-based above)"
# API keys probably shouldn't be persistent secrets since they expire
%{ if looker_client_secret != "" && looker_password_secret == ""}
cat << EOT > /home/looker/looker/provision.yml
license_key: "$LOOKER_LICENSE_KEY"
host_url: "https://$ENV.looker.$DOMAIN"
EOT

cat << EOT > /home/looker/looker/api-provision.yml
user:
  first_name: "$LOOKER_FIRSTNAME"
  last_name: "$LOOKER_LASTNAME"
  client_id: "$LOOKER_CLIENT_ID"
  client_secret: "$LOOKER_CLIENT_SECRET"
EOT

sudo chown looker:looker api-provision.yml provision.yml
sudo chmod 600 api-provision.yml
%{ endif }

# Set up NFS system
%{ if shared_storage_server != "" }
SHARED_STORAGE_SERVER=${shared_storage_server}
SHARED_STORAGE_FS=${shared_storage_fs}

# Set up NFS
sudo mkdir -p /mnt/lookerfiles
echo "$SHARED_STORAGE_SERVER:/$SHARED_STORAGE_FS /mnt/lookerfiles nfs defaults 0 0" | sudo tee -a /etc/fstab
sudo mount -a
sudo chown looker:looker /mnt/lookerfiles
cat /proc/mounts | grep looker
%{ endif }

# Set up google-fluentd logging
cat << EOT | sudo tee -a /etc/google-fluentd/config.d/looker-log.conf
<source>
    @type tail
    format json
    path /home/looker/looker/log/looker.log
    pos_file /var/lib/google-fluentd/pos/looker.pos
    read_from_head true
    tag looker-$ENV
</source>
<filter>
    @type parser
    key_name s
    reserve_data true
    <parse>
        @type regexp
        expression /^(?<severity>.*)/
    </parse>
</filter>
EOT

# Modify LookerArgs appropriately
export IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

echo "LOOKERARGS=\"
%{~ if db_server != ""}-d /home/looker/looker/looker-db.yml %{endif ~}
%{~ if shared_storage_server != ""}--shared-storage-dir /mnt/lookerfiles %{endif ~}
%{~ for flag in startup_flags ~}
%{~ if flag != ""}${flag} %{else}%{endif ~}
%{~ if flag == "--clustered"}-H $IP %{endif ~}
%{~ endfor ~}
%{ for  config_key, config_value in startup_params ~}
%{if config_value != ""}${config_key} ${config_value} %{else}%{endif}
%{~ endfor ~}
--force-gcm-encryption --log-format json\"" | sudo tee -a /home/looker/looker/lookerstart.cfg

# e.g. with flags of ["--clustered"] and params of {"--per-user-query-limit"=30} the above should parse to:
# echo "LOOKERARGS=\"-d /home/looker/looker/looker-db.yml --shared-storage-dir /mnt/lookerfiles --clustered -H $IP --per-user-query-limit 30 --log-format json\"" | sudo tee -a /home/looker/looker/lookerstart.cfg

# Start Looker
sudo systemctl daemon-reload
%{ if db_password_secret != "" }
sudo systemctl enable cloud_sql_proxy.service
sudo systemctl start cloud_sql_proxy
while true; do
  if [ $(systemctl is-active cloud_sql_proxy) == "active" ]; then
    sleep 1
    break
  fi
  sleep 1
done
%{ endif }
sudo systemctl enable looker.service
sudo systemctl start looker
while true; do
  if [ $(systemctl is-active looker) == "active" ]; then
    sleep 1
    break
  fi
  sleep 1
done
sudo systemctl restart google-fluentd
sudo systemctl restart stackdriver-agent
