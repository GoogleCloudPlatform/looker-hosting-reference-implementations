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

location=$(echo $REGISTRY_PATH | cut -d "." -f1 | sed 's/-docker//')
repository=$(echo $REGISTRY_PATH | cut -d "/" -f3)

# find all existing valid tags (numeric or latest) and sort by descending order
tags=$(gcloud artifacts tags list --location=$location --repository=$repository --package=$IMAGE_NAME --filter="name~.*tags/latest|.*tags/\d{1,2}\.\d{1,2}" --format=json | jq -r '.[].name' | awk -F/ '{print $NF}'| sort -r)

# if we don't have a latest tag then this is the first ever run and we'll need one
if [[ $(echo $tags | head -n1 | cut -d " " -f1) != "latest" ]]
then
  echo "no latest tag found - this will be the first!"
  echo 1 > latest_tag.txt
  exit 0
fi

# if we do have a latest tag then we need to check to see if the new version
# is greater than the latest old version
echo "found existing latest tag - checking to see if we need a new one"
candidate_version=$(cat minor_version.txt)
current_max_version=$(echo $tags | head -n1 | cut -d " " -f2)
echo "candidate version is $candidate_version and current max version is $current_max_version"
if [[ $(printf '%s\n' $candidate_version $current_max_version | sort -rV | head -n1) == $candidate_version  ]]
then
  echo "new latest version detected"
  echo 1 > latest_tag.txt
else
  echo "not  latest version"
  echo 0 > latest_tag.txt
fi