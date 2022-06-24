# Deploy a Clustered Looker Instance

A production-capable Looker environment typically requires more than a single node instance, namely the ability to cluster. This requires that we implement a MySQL backend database and a shared file system.

## Prerequisites

At this point you should be comfortable with spinning up and tearing down a simple unclustered Looker instance. See [part 3a](./03a_deploy_unclustered_vm_instance.md).

## Deploying a Clustered Instance

### Step 1: Create your `terraform.tfvars` file

1. Navigate to [the looker_clustered_instance directory](/terraform/looker_clustered_instance)
2. Create a file called `terraform.tfvars`
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
env = "clustered"
gcm_key_secret_name = "your_gcm_key_secret_name"
node_count = 1
db_type = "db-n1-standard-4"
db_deletion_protection = false
db_secret_name = "looker-dev-db-password"
db_high_availability = false
db_read_replicas = false
startup_flags = ["--clustered"]
startup_params = {}
```

Variable definitions are as follows:

| Name | Description |
|------|-------------|
| project | Your GCP Project ID |
| dns_project | (Optional) A separate project ID in case your DNS config lives in different GCP project |
| region | The GCP region to use |
| zone | The GCP zone to use |
| terraform_sa_email | The email address of your service account |
| image_family | The name of the image family for your VM image. Unless you changed something this is going to be “looker-ubuntu”. |
| machine_type | The Compute Engine [machine type](https://cloud.google.com/compute/docs/machine-types) to use for your Looker. To be safe use at least 4 cores and 16GB of RAM. |
| startup_script | Path to the startup script to use. Stick with the default provided in the module. |
| hosted_zone | The name of your GCP Project’s Cloud DNS hosted zone |
| env | A unique name for this looker instance, e.g. “dev”, “sandbox”, “test”, "clustered", etc. |
| gcm_key_secret_name | The GCP Secret containing your GCM encryption key |
| node_count | How many initial nodes to create. For the moment this should **always** be set to 1. (Looker doesn’t like when you boot up multiple nodes at once) |
| db_type | The core and memory configuration of your MySQL database. Learn more [here](https://cloud.google.com/sql/docs/mysql/instance-settings#machine-type-2ndgen). |
| db_deletion_protection | When enabled, this will prevent your instance from being deleted. For the moment, set this to “false”. |
| db_secret_name | The name of the database password secret you defined during GCP Project creation. |
| db_high_availability | When enabled, this will configure the database for high availability. This is more expensive, but more robust, so this should be reserved for production instances. |
| db_read_replicas | This creates one or more read replicas of the backend database. This may be a good option if a client is planning on offloading data from the backend database to a warehouse, a la “Elite System Activity” or otherwise planning on making heavy use of System Activity queries. The underlying object is a bit complex so refer to the variable definition in the code and the [documentation](https://registry.terraform.io/modules/GoogleCloudPlatform/sql-db/google/latest/submodules/mysql) for details. |
| db_version | The MySQL version to  use. Must be either "MYSQL_5_7" or "MYSQL_8_0". Defaults to "MYSQL_5_7". |
| db_flags | An optional set of flags to further configure the backend database |
| subnet_ip_range | (Optional) The IP range for the primary Looker subnet - the default value is 10.0.0.0/16 which is very generous (~65k IP addresses) |
| startup_flags | A list of flag-style [startup options](https://docs.looker.com/setup-and-management/on-prem-install/looker-startup-options). “Flag” means they don’t require an associated value. **You should make sure to include "[\-\-clustered]" in there.**
| startup_params | A map of key/value pairs for [startup options](https://docs.looker.com/setup-and-management/on-prem-install/looker-startup-options) that take a value. E.g. {"\-\-per-user-query-limit" = 50} |
| user_provisioning_secret_name | (Optional) the name of a GCP secret that conforms to [Looker's user provisioning format](https://docs.looker.com/setup-and-management/on-prem-install/auto-provision-user). If present, this will auto-provision the user specified in the secret. |

### Step 2: Initialize the Looker Terraform Module

Before you can run the Looker Terraform module you will need to initialize it. You will only need to do this once. This is done by executing the following command:

```
$ terraform init
```

Once initialization is complete we’ll confirm the module is ready to go by executing a plan:

```
$ terraform plan
```

### Step 3: Run Terraform

We're ready to kick off a Terraform run. Execute the following command:

```
$ terraform apply
```

When prompted, type “yes” to confirm you want to execute, then press return. The Terraform build will execute.

This script will take about 8-10 minutes to complete.

### Step 4: Check GCP Console

Explore the GCP console:

**CloudSQL**: Once the provisioning is completed you'll have a MySQL instance. You can find it by searching for "SQL". Click into the relevant instance and you'll see information about your database.

**Filestore**: There is also a Filestore instance. Search for "Filestore" and click into your instance.

**Compute Engine -> VM Instances**: You’ll see a new “looker” VM (it also includes the env name you chose for easy filtering).

**Network Services -> Cloud DNS**: You should see an entry like `<env>.looker.domain.com` when you click into your hosted zone.

**Network Services -> Load Balancing**: There should be one there called `looker-loadbalancer-<env>`. Click on it and you should see a bunch of details about your load balancer. If a few minutes have passed since you deployed you should see that the Backend Services are reporting as “Healthy”. This means your instance is ready for traffic.

For VM instances we make use of GCP-managed SSL certificates. These often take some time to provision. You can check the status of the certificate by clicking on its link.

### Step 5: Log into Looker Instance

Open a new browser tab and enter the web URL from your DNS. You should be presented with a Looker registration page. Use your Looker license key to register an initial user.

### Step 6: Cleaning Up

In general, you don’t want to leave sandbox instances littered around as it’s a waste of resources.

Utilize Terraform's `destroy` command for this:
```
$ terraform destroy
```
When prompted for confirmation, type “yes” and press return. You can use `terraform state list` to ensure you haven’t left an instance out there. If nothing is returned you’re good to go.
