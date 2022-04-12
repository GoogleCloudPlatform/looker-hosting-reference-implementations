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

trap "touch /lifecycle/main-terminated" EXIT

[ -z $LOOKERARGS ] && LOOKERARGS=""

if [ -r ./lookerstart.cfg ]; then
  . ./lookerstart.cfg
fi

java \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+PrintFlagsFinal \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:InitialRAMPercentage=75.0 \
  -XshowSettings:vm \
  -XX:+AlwaysPreTouch \
  -XX:+ExitOnOutOfMemoryError \
  -XX:MaxMetaspaceSize=800m \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=1000 \
  -XX:+UseStringDeduplication \
  -jar /app/looker.jar \
  migrate_db_to_looker_version ${DESIRED_LOOKER_VERSION} ${LOOKERARGS} \
  --no-daemonize \
  --no-log-to-file \
  --log-format=json

EXIT_CODE=$?
echo "migrator completed with exit code $EXIT_CODE"

exit $EXIT_CODE
