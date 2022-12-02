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


[ -z $LOOKERARGS ] && LOOKERARGS=""

set -euo pipefail

echo "Memory: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
JMXARGS="-Dcom.sun.management.jmxremote=true
 -Dcom.sun.management.jmxremote.local.only=true
 -Dcom.sun.management.jmxremote.port=9910
 -Dcom.sun.management.jmxremote.ssl=false
 -Dcom.sun.management.jmxremote.authenticate=false"

echo "JMXARGS: $JMXARGS"
# startup flags docs https://docs.looker.com/setup-and-management/on-prem-install/looker-startup-options

# check for a lookerstart.cfg file to set JAVAARGS and LOOKERARGS
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
  -XX:MaxMetaspaceSize=1100m \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=500 \
  -XX:+UseStringDeduplication \
  $JMXARGS \
  -javaagent:./jmx_prometheus_javaagent-0.15.0.jar=9920:jmx-prom-config.yaml \
  -jar /app/looker.jar \
  start ${LOOKERARGS} \
  --no-daemonize \
  --no-log-to-file \
  --log-format=json
