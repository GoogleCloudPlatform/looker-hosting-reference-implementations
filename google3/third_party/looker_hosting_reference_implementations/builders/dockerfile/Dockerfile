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

FROM ubuntu:focal

ARG WHICH_CHROMIUM="97.0.4692.71-1"

RUN addgroup --gid 9999 looker && adduser --system --disabled-password --disabled-login --uid 9999 --gid 9999 --shell /bin/bash --home /app looker

RUN apt-get update && apt-get install -y \
  curl \
  fontconfig \
  fonts-freefont-otf \
  tzdata \
  openjdk-11-jre-headless \
  gnupg2 \
&& curl --silent -o /chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${WHICH_CHROMIUM}_amd64.deb \
&& apt-get install -y /chrome.deb \
&& ln -s /usr/bin/google-chrome /usr/local/bin/chromium \
&& rm -f /chrome.deb \
&& rm -rf /var/lib/apt/lists/*

# install dumb-init, is good to have signal handling
RUN curl -L -s -o /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.1/dumb-init_1.2.1_amd64 \
&& chmod +x /usr/bin/dumb-init

ENV DEPENDENCY_JAR_DIRECTORY /app/

COPY --chown=9999:9999 looker.jar looker-dependencies.ja[r] /app/
COPY --chown=9999:9999 bin/* /app/bin/
COPY --chown=9999:9999 jmx_prometheus_javaagent-0.15.0.jar /app/

USER 9999

ENV PORT 9999
EXPOSE 9999

ENV API_PORT 19999
EXPOSE 19999

ENV JMX_PORT 9920
EXPOSE 9920

ENV MONITORING_PORT 1552
EXPOSE 1552

WORKDIR /app

ENV HOME /app

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/bin/bash", "/app/bin/looker.sh"]
