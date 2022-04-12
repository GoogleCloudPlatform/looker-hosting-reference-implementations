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

# "timestamp" template function replacement
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  image_version = replace(var.looker_version, ".", "-")
  distro_image_map = {
    "ubuntu" = "ubuntu-1804-lts",
    "debian" = "debian-10",
    "rhel"   = "rhel-7",
    "centos" = "centos-7"
  }
  source_image_family = lookup(local.distro_image_map, lower(var.os_distribution), "ubuntu-1804-lts")
}

# A source can be referenced in
# build blocks. A build block runs provisioner and post-processors onto a
# source. Read the documentation for source blocks here:
# https://www.packer.io/docs/from-1.5/blocks/source
source "googlecompute" "gcp_build" {
  impersonate_service_account = var.packer_sa_email
  image_family = "looker-${var.os_distribution}"
  image_name   = "looker-${lower(var.os_distribution)}-${local.image_version}-${local.timestamp}"
  project_id   = var.project_id
  source_image_family = local.source_image_family
  ssh_username = "packer"
  zone         = var.zone
  network      = var.image_network
  subnetwork   = var.image_subnet
  tags         = ["packer-builder"]
  use_iap      = var.private_ip_mode
  omit_external_ip = var.private_ip_mode
  use_internal_ip = var.private_ip_mode
  service_account_email = var.packer_sa_email
  scopes       = ["https://www.googleapis.com/auth/cloud-platform"]
}

# a build block invokes sources and runs provisionning steps on them. The
# documentation for build blocks can be found here:
# https://www.packer.io/docs/from-1.5/blocks/build
build {
  name = "ansible"
  sources = ["source.googlecompute.gcp_build"]

  provisioner "shell" {
    inline = ["sleep 5"]
  }

  provisioner "ansible" {
    user = "packer"
    extra_arguments = ["--extra-vars", "LICENSE_KEY_SECRET=${var.license_key_secret_name} TECHNICAL_CONTACT=${var.technical_contact} JMX_PASS_SECRET=${var.jmx_pass_secret_name} LOOKER_VERSION=${var.looker_version}"]
    playbook_file   = var.looker_playbook
  }
}
