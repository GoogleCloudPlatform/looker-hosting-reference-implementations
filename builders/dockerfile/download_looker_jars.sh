#!/usr/bin/env bash

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

set -e

# Set these variables. For LOOKER_VERSION include a major and minor version only, no patch version - e.g. "21.0" or "21.4"
PARSED_VERSION=looker-${LOOKER_VERSION}-latest.jar
echo $PARSED_VERSION

curl -i -X POST -H 'Content-Type:application/json' -d "{\"lic\": \"$LOOKER_LICENSE_KEY\", \"email\": \"$LOOKER_TECHNICAL_CONTACT_EMAIL\", \"latest\":\"specific\", \"specific\":\"$PARSED_VERSION\"}" https://apidownload.looker.com/download -o response.txt
sed -i 1,9d response.txt
chmod 644 response.txt
eula=$(cat response.txt | jq -r '.eulaMessage')
if [[ "$eula" =~ .*EULA.* ]]; then echo "Error! This script was unable to download the latest Looker JAR file because you have not accepted the EULA. Please go to https://download.looker.com/validate and fill in the form."; fi;

url=$(cat response.txt | jq -r '.url')
curl $url -o looker.jar

url=$(cat response.txt | jq -r '.depUrl')
curl $url -o looker-dependencies.jar

echo "Checking SHA values..."
sha=$(cat response.txt | jq -r '.sha256' | tr -d '\n')
depsha=$(cat response.txt | jq -r '.depSha256' | tr -d '\n')

echo "$sha looker.jar" | sha256sum --check
echo "$depsha looker-dependencies.jar" | sha256sum --check

cat response.txt| jq -r '.version_text' | sed 's/\.jar//' | sed 's/looker-//' > minor_version.txt