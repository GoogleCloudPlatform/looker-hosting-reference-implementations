# Build VM Images

> **Warning: The clustered VM reference implementation is deprecated**. Running VM-based Looker instances is not advisable for production workloads. The use of Kubernetes is strongly recommended. For that reason we have deprecated support for the VM-based clustered instance and will be removing it from the repo in a future release. Please use the [kubernetes reference implementation](./03a_deploy_kubernetes_instance) instead.

Next up we will create some Looker images that we can use in our deployments. In this section we will cover building VM images. VM images are required for VM-based deployments. We will utilize Packer and Ansible to create the image for us.

## Prerequisites

- You will need to have completed all steps in [part 1](./01_gcp_project_setup.md).
- You will need to have accepted the [Looker EULA](https://download.looker.com/validate). You'll need your Looker license key handy. Note that you do not need to actually download the JARs after accepting the EULA. You will only need to do this once per license key/email combination.

## Step 1: Create your `vars.auto.pkrvars.hcl` file

1. Navigate to [the packer directory](/builders/packer)
2. Create a file called `vars.auto.pkrvars.hcl`
> Note: the `auto` in the filename will tell Packer to automatically apply this variables file when we deploy. If you'd rather manually specify the variables file then remove `auto` from the filename.

3. Edit your `pkrvars` file to set your definitions for the required variables. It should look something like this:

```
project_id = "your-gcp-project"
os_distribution = "ubuntu"
zone = "us-central1-c"
packer_sa_email = "your_serviceaccount_email@gserviceaccount.com"
technical_contact = "you@example.com"
license_key_secret_name = "looker-license-key"
jmx_pass_secret_name = "looker-jmx-pass"
looker_version = "22.2"
looker_playbook = "./ansible/image.yml"
image_network = "default"
private_ip_mode = false
```

Variable definitions are as follows:

| Name                    | Description                                                                                                                                                                                         |
|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| project_id              | Your GCP Project ID                                                                                                                                                                                 |
| os_distribution         | The underlying OS of the VM image. Valid options are "ubuntu", "debian", "rhel", or "centos".                                                                                                       |
| zone                    | The GCP zone to use                                                                                                                                                                                 |
| packer_sa_email         | The email address of your deployment service account                                                                                                                                                |
| technical_contact       | The email address you used to sign the Looker EULA referenced above                                                                                                                                 |
| looker_version          | The version of Looker you want to install. Generally this should be the [latest available version](https://docs.looker.com/relnotes).                                                               |
| looker_playbook         | The ansible playbook to use for provisioning. Stick with the default `ansible/image.yml` for the moment.                                                                                            |
| image_network           | The VPC to use for building the image                                                                                                                                                               |
| image_subnet            | The subnet to use for building the image. If using the default network this can be omitted.                                                                                                         |
| private_ip_mode         | This forces the use of internal IP addresses, disables external IP, and handles the SSH connection over IAP. This is useful for environments with restrictions on the use of external IP addresses. |
| jmx_pass_secret_name    | The name of the JMX password secret you created in Secret Manager                                                                                                                                   |
| license_key_secret_name | The name of the Looker license key secret you created in Secret Manager                                                                                                                             |

> Note: If you need to enable private IP mode you will need to ensure you have [configured your VPC to make use of IAP TCP forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding) and [set up a route to the internet](https://cloud.google.com/architecture/building-internet-connectivity-for-private-vms#deploying_cloud_nat_for_fetching) for private instances.


## Step 2: Initialize the GCP Plugin

In order to use the GCP Packer plugin we must initialize it. This is done by executing the following command:

```
$ packer init .
```
> Note: You only need to do this the first time you use Packer. You can skip this step for subsequent builds.

## Step 3: Build the VM Image

We're ready to build the VM image. Execute the following command:

```
$ packer build .
```

> Note: If you removed `auto` from the pkrvars file name then make sure to include a `-var-file` flag, i.e., `-var-file=variables.pkrvars.hcl`

The build will take approximately 5 minutes to complete.

For more details you can run `packer build --help` or refer to the [full documentation](https://www.packer.io/plugins/builders/googlecompute).

You can now see the Looker image in the GCP Console by visiting **Compute Engine -> Images**.
