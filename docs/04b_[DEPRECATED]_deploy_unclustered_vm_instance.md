# Deploy an Unclustered Looker Instance

> **Warning: The clustered VM reference implementation is deprecated**. Running VM-based Looker instances is not advisable for production workloads. The use of Kubernetes is strongly recommended. For that reason we have deprecated support for the VM-based clustered instance and will be removing it from the repo in a future release. Please use the [kubernetes reference implementation](./03a_deploy_kubernetes_instance) instead.

For your first Looker deployment, you will deploy a simple single node instance with a HyperSQL backend. We’ll be leveraging the VM Image we created [with Packer](/builders/packer).

> Warning: This deployment type is extremely bare-bones. This makes it simple and fast to spin up but it offers no automatic backups, no ability to scale out, and is difficult to maintain. It is therefore not suitable for serious development let alone production workloads. It is best used as a temporary sandbox and playground.

## Prerequisites

You will need to have completed all steps in [part 1](./01_gcp_project_setup.md) and [part 2](./02a_build_vm_image.md).

## Step 1: Create your `terraform.tfvars` file

1. Navigate to "looker_unclustered_instance" module in [the examples directory](/terraform/looker_unclustered_instance).
2. Create a file called `terraform.tfvars`.
3. Edit your `terraform.tfvars` file to set your definitions for the required variables. It should look something like this:

```
project = "your-gcp-project"
region = "us-central1"
zone = "us-central1-c"
terraform_sa_email = "your_serviceaccount_email@gserviceaccount.com"
image_family = "looker-ubuntu"
machine_type = "e2-standard-4"
startup_script = "startup.sh"
hosted_zone = "my-hosted-zone"
env = "sandbox"
gcm_key_secret_name = "your_gcm_key_secret_name"
```

Variable definitions are as follows:

| Name                | Description                                                                                                                                                     |
|---------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| project             | Your GCP Project ID                                                                                                                                             |
| dns_project         | (Optional) A separate Project ID in case your DNS config lives in a different GCP project                                                                       |
| region              | The GCP region to use                                                                                                                                           |
| zone                | The GCP zone to use                                                                                                                                             |
| terraform_sa_email  | The email address of your service account                                                                                                                       |
| image_family        | The name of the image family for your VM image. Unless you changed something this is going to be something like “looker-ubuntu".                                |
| machine_type        | The Compute Engine [machine type](https://cloud.google.com/compute/docs/machine-types) to use for your Looker. To be safe use at least 4 cores and 16GB of RAM. |
| startup_script      | Path to the startup script to use. Stick with the default provided in the module.                                                                               |
| hosted_zone         | The name of your GCP Project’s Cloud DNS hosted zone                                                                                                            |
| env                 | A unique name for this looker instance, e.g. “dev”, “sandbox”, “test”, etc.                                                                                     |
| gcm_key_secret_name | The GCP Secret containing your GCM encryption key                                                                                                               |
| subnet_ip_range     | (Optional) The IP range for the primary Looker subnet - the default value is 10.0.0.0/16 which is very generous (~65k IP addresses)                             |
| user_provisioning_secret_name | (Optional) the name of a GCP secret that conforms to [Looker's user provisioning format](https://docs.looker.com/setup-and-management/on-prem-install/auto-provision-user). If present, this will auto-provision the user specified in the secret. |

## Step 2: Initialize the Looker Terraform Module

Before you can run the Looker Terraform module you will need to initialize it. You will only need to do this once. This is done by executing the following command:

```
$ terraform init
```

Once initialization is complete we’ll confirm the module is ready to go by executing a plan:

```
$ terraform plan
```

## Step 3: Run Terraform

We're ready to kick off a Terraform run. Execute the following command:

```
$ terraform apply
```

When prompted, type “yes” to confirm you want to execute, then press return. The Terraform build will execute.

This script will take about 2-3 minutes to complete.

## Step 4: Check GCP Console

Explore the GCP console to confirm the new instance:

**Compute Engine -> VM Instances**
You’ll see a new “looker” VM (it also includes the env name you chose for easy filtering).

**Network Services -> Cloud DNS**
You should see an entry like `<env>.looker.domain.com` when you click into your hosted zone.

**Network Services -> Load Balancing**
There should be one there called `looker-loadbalancer-<env>`. Click on it and you should see a bunch of details about your load balancer.

If a few minutes have passed since you deployed you should see that the Backend Services are reporting as “Healthy”. This means your instance is ready for traffic.

For VM instances we make use of GCP-managed SSL certificates. These often take some time to provision. You can check the status of the certificate by clicking on its link.

## Step 5: Log into Looker Instance

Open a new browser tab and enter the web URL from your DNS. You should be presented with a Looker registration page.

Use your Looker license key to register an initial user.

## Step 6: Cleaning Up

In general, you don’t want to leave sandbox instances littered around as it’s a waste of resources.

Utilize Terraform's `destroy` command for this:

```
$ terraform destroy
```

When prompted for confirmation, type “yes” and press return.
