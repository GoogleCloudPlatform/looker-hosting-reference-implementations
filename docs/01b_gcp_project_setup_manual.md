# GCP Project Setup

In order to deploy Looker you will first need a GCP project. This guide will walk you through how to create a basic project suitable for testing.

> Note: This is not a recommended setup for your production environment. Your production projects will likely need to be configured a bit differently - especially if you are separating various duties into distinct GCP projects and leveraging best practices such as Shared VPC and VPC-SC.

> Note: Project creation can (and should!) be fully automated with Terraform as well, please refer to [01a_gcp_project_setup_as_code](./01a_gcp_project_setup_as_code.md) to learn more.

## Prerequisites

You will need:
- The Project Creator GCP role and a suitable Billing Account.
- A valid Looker License Key - please work with your GCP account team if you do not have one.
- The [gcloud command line tool](https://cloud.google.com/sdk/docs/install) installed.

## Step 1: Create a Project

Follow the [documentation](https://cloud.google.com/resource-manager/docs/creating-managing-projects#console) to create a new GCP project.
It's a good idea to create a new project for Looker testing to make sure we keep resources and permissions isolated for this particular use case.

## Step 2: Configure gcloud

Once your project is created you will want to configure your `gcloud` command line utility to use it.

1. First, authorize the Cloud SDK by running `gcloud auth login` and following the prompts.
2. Next, [configure gcloud](https://cloud.google.com/sdk/gcloud/reference/config/set) to reference your new project.
   Run `gcloud config set project <project id>`.
3. Finally, [configure your application default credentials](https://cloud.google.com/sdk/gcloud/reference/auth/application-default/login).
   Run `gcloud auth application-default login` and follow the prompts.

## Step 3: Enable the APIs

GCP's APIs must be enabled before they can be used. We'll use `gcloud` to enable the required APIs in batches. We will need to run the command in two parts since only a certain number of APIs can be enabled per call.

Execute the following commands:

```
$ gcloud services enable \
bigquery.googleapis.com \
bigquerystorage.googleapis.com \
cloudresourcemanager.googleapis.com \
compute.googleapis.com \
cloudbuild.googleapis.com \
container.googleapis.com \
artifactregistry.googleapis.com \
domains.googleapis.com \
dns.googleapis.com \
file.googleapis.com \
iap.googleapis.com
```

```
$ gcloud services enable \
iam.googleapis.com \
iamcredentials.googleapis.com \
monitoring.googleapis.com \
oslogin.googleapis.com \
pubsub.googleapis.com \
servicenetworking.googleapis.com \
sql-component.googleapis.com \
sqladmin.googleapis.com \
storage-api.googleapis.com \
secretmanager.googleapis.com \
redis.googleapis.com \
cloudkms.googleapis.com
```

## Step 4: Configure a Development Domain and DNS Zone

We will make use of [Managed DNS Zones](https://cloud.google.com/dns/docs/zones) to handle DNS for these examples. If you do not currently have a suitable development domain you can use [Cloud Domains](https://cloud.google.com/domains/docs/overview) to acquire one.

Once you have secured a domain, create a [public managed zone](https://cloud.google.com/dns/docs/zones#create-pub-zone).
Make a note of the name.

## Step 5: Create Artifact Registry

[Artifact Registry](https://cloud.google.com/artifact-registry/docs/repositories/create-repos#create) will be used to store container images and Helm charts. Create a new docker repository called "looker".

## Step 6: Create Secrets

Secrets management is a vital element of security. We want to avoid storing potentially sensitive information in configuration files whenever possible and streamline the process of securely injecting secrets where they need to go. We will use GCP's [Secret Manager](https://cloud.google.com/secret-manager/docs/creating-and-accessing-secrets) for this.

Following the directions in the link above, create four secrets:

1. A strong password (to be used as a password for Looker's MySQL account). This password should include only alphanumeric characters - no special characters!
2. Your Looker License Key (this will be stored as the secret value)
3. A GCM Encryption Key - this can be generated by running the command `openssl rand -base64 32`. See Looker's [encryption documentation](https://docs.looker.com/setup-and-management/on-prem-mgmt/migrating-encryption#generating_a_cmk) for more details.

## Step 7: Create a Terraform Service Account (optional but strongly recommended)

While you can leverage your application default credentials to authorize Terraform to your GCP project it is considered a best practice to create a dedicated [service account](https://cloud.google.com/iam/docs/service-accounts) for the job. This will be increasingly important as you move towards production use cases and using CI/CD pipelines.

[Follow the instructions](https://cloud.google.com/iam/docs/creating-managing-service-accounts#creating) to create a service account. Assign it the following permissions:

```
Compute Network Admin
Compute Admin
Cloud SQL Admin
Cloud Filestore Editor
Cloud Memorystore Redis Admin
Service Networking Admin
DNS Administrator
Kubernetes Engine Admin
Service Account Admin
Service Account User
Project IAM Admin
IAM Workload Identity Pool Admin
Storage Admin
Storage Object Viewer
Secret Manager Secret Accessor
Secret Manager Viewer
Cloud KMS Admin
IAP Secure Tunnel User
```

Once your service account is created you will need to grant your account the ability to [impersonate it](https://cloud.google.com/iam/docs/impersonating-service-accounts#impersonate-sa-level). Navigate to Service Account's Permissions, add your principal email address, and grant it the `Service Account Token Creator` role.

We need to make one more IAM-related change. Navigate to IAM & Admin -> IAM and locate your Cloud Build service account - it will have been automatically created when you enabled the Cloud Build API. It will have the format of `<project number>@cloudbuild.gserviceaccount.com`.

Edit the permissions and add `Secret Manager Secret Accessor`.


## Step 8: Install Required Software

Let's get the rest of the software stack installed in your development environment. See below for links to installation instructions for each tool.

1. [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli). Ensure version is >= 1.3.0
2. [Kubectl](https://kubernetes.io/docs/tasks/tools/)
3. [Helm](https://helm.sh/docs/intro/install/). Ensure version is >= 3.8.0

If you want to make use of VM-based Looker instances (Not Recommended) then you will need to also install the following tools:

1. [Packer](https://learn.hashicorp.com/tutorials/packer/get-started-install-cli)
2. [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) (Note that Ansible requires Python)