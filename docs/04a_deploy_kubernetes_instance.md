# Deploying a Kubernetes-Based Instance

Deploying Looker in Kubernetes (K8s) is the recommended approach for production environments. Unlike VM-based deployments we will need to handle the Looker deployment in two parts. First we will deploy the required infrastructure with Terraform and then we will deploy the application itself using Kubernetes-native tools. This adds a small amount of complexity but K8s makes it easy to enable advanced features such as redis-based caching and rolling updates.

## Prerequisites

- You will need to have completed all steps in [part 1](./01_gcp_project_setup.md)
- You will need to have built a Looker container image - see [part 2](./02_build_vm_image_and_container.md)

## Deploy the infrastructure

### Step 1: Create your `.tfvars` file

1. Navigate to the [looker_kubernetes](/terraform/looker_kubernetes) directory.
2. Create a file called `terraform.tfvars` You will define your variables in this file. It will look something like this:

```
project_id            = "your-gcp-project-id"
region                = "us-central1"
zone                  = "us-central1-a"
terraform_sa_email    = "your_serviceaccount_email@gserviceaccount"
prefix                = "test"
subnet_ip_range       = "10.0.0.0/16"
private_ip_range      = "192.168.0.0/20"
dns_managed_zone_name = "your-managed-zone"
envs = {
  dev = {
    gcm_key_secret_name                  = "looker-dev-gcm-encryption-key"
    db_tier                              = "db-custom-2-7680"
    db_high_availability                 = false
    db_read_replicas                     = []
    db_deletion_protection               = false
    db_secret_name                       = "looker-dev-db-password"
    filestore_tier                       = "STANDARD"
    redis_memory_size_gb                 = 4
    redis_high_availability              = false
    gke_regional_cluster                 = false
    gke_use_application_layer_encryption = false
    gke_node_zones                       = ["us-west1-a"]
    gke_node_count_min                   = 3
    gke_node_count_max                   = 3
    gke_node_tier                        = "e2-standard-16"
    gke_private_endpoint                 = false
    gke_release_channel                  = "REGULAR"
    gke_subnet_pod_range = {
      ip_cidr_range = "172.16.16.0/20",
      range_name    = "pod-range-dev"
    }
    gke_subnet_service_range = {
      ip_cidr_range = "172.16.64.0/20",
      range_name    = "service-range-dev"
    }
    gke_controller_range = "172.16.0.0/28"
    cert_admin_email     = "colinpistell@google.com"
    acme_server          = "https://acme-v02.api.letsencrypt.org/directory"
  }
}
```

Variable definitions are as follows:

| Name | Description |
|------|-------------|
| project_id | Your GCP Project ID |
| kms_project_id | (Optional) If you want to use [Application Layer Encryption](https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets) the best practice is to set up Cloud KMS in a separate project. However, this can certainly be the same as your main project. Omit to use your main project for KMS as well. |
| dns_project_id | (Optional) A separate project ID in case your DNS config lives in a different GCP project |
| region | The GCP region to use |
| zone | The GCP zone to use |
| terraform_sa_email | The email address of your deployment service account |
| prefix | Since this module gives us the ability to deploy multiple "environments" in a single project we need a separate unique prefix to use for resource names. |
| subnet_ip_range | The IP range of the cluster's subnet in CIDR notation |
| private_ip_range | The IP range made available for Private Service Connections |
| dns_managed_zone_name | The name of your GCP Cloud DNS managed zone |
| envs | New to this module is the ability to deploy multiple "environments" in a single project. In most circumstances different environments should be isolated in their own project, but in some cases it may be desirable to deploy multiple environments in a single project. The details of the map are explained below. |

The envs variable is a map that contains environment-specific variables for your deployment. Each key of the map is the name of an environment and each value is an object that contains the required variables for the given environment name. The definitions are as follows:

| Name                                 | Description                                                                                                                                                                                                                                  |
|--------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| gcm_key_secret_name                  | The name of the GCM key secret you created in Secret Manager while setting up your GCP Project |
| db_secret_name                       | The name of your database password secret you created in Secret Manager while setting up your GCP Project |
| db_tier                              | The machine type to use for the Cloud SQL database. Learn more [here](https://cloud.google.com/sql/docs/postgres/create-instance#machine-types)                                                                                              |
| db_high_availability                 | Should the database be configured for high availablity? This adds significant cost.                                                                                                                                                            |
| db_read_replicas                     | This creates one or more read replicas of the backend database. The underlying object is a bit complex so refer the variable definition and the [documentation]() for details.                                                               |
| db_deletion_protection               | Should GCP prevent the database from being deleted? For transient dev instances this should be set to false, but you may want to enable it for production instances.                                                                         |
| filestore_tier                       | The [service tier]() to use for Filestore.                                                                                                                                                                                                   |
| redis_memory_size_gb                 | How much memory to use for the Redis cache. The rule of thumb is to have 2GB per node - so a 3-node Looker cluster should have 6 GB of cache memory.                                                                                        |
| redis_high_availability              | Should Redis be configured with a failover backup. This adds cost. Note that this is not the same as running Redis in clustered mode, which Looker [does not support](https://docs.looker.com/setup-and-management/on-prem-mgmt/redis-cache). |
| gke_regional_cluster                 | Should GKE be configured for regional high availability? This increases cost.                                                                                                                                                                |
| gke_node_zones                       | A list of zones within your region where you want GKE to create K8s nodes. Note that you can still be multi-zonal without setting up regional clusters.                                                                                      |
| gke_node_count (min/max)             | How many GKE nodes there should be. GKE can automatically add new K8s nodes as needed. Note this is nodes per zone.                                                                                                                          |
| gke_node_tier                        | What machine type to use. At least an e2-standard-8 is recommended.                                                                                                                                                                          |
| gke_private_endpoint                 | Should the GKE control plane be private, i.e. not accessible over the internet? Note that authentication is still required if set to false.                                                                                                  |
| gke_release_channel                  | The [release channel](https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels) to be used. This affects what version of K8s is running in GKE and how often it gets upgraded. "REGULAR" is a safe bet.               |
| gke_subnet_pod_range                 | A map that defines the subnet alias range to use for GKE pods. See [VPC-native clusters](https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips#cluster_sizing) for more information. Details are below.                         |
| gke_subnet_service_range             | A map that defines the subnet alias range to use for GKE services. Details are below.                                                                                                                                                        |
| gke_use_application_layer_encryption | You can add another layer of encryption on GKE's data store via envelope encryption.                                                                                                                                                         |
| gke_controller_range                 | For Private GKE clusteres you must specify a /28 CIDR block within your VPC's address space.                                                                                                                                                 |
| cert_admin_email                     | By default we use cert-manager and LetsEncrypt to generate SSL certificates. This is the email address that will be used when registering an account to create certificates with LetsEncrypt.                                                |
| acme_server                          | The ACME server to use with LetsEncrypt. For valid certificates this should always be `https://acme-v02.api.letsencrypt.org/directory`.                                                                                                      |

The alias range maps have the following structure:

| Name          | Description                        |
|---------------|------------------------------------|
| ip_cidr_range | The CIDR block for the given range |
| range_name    | The name of the given range        |


### Step 2: Deploy the infrastructure

1. You will need to initialize Terraform before applying - you will only need to do this once. Execute the following command:

```
$ terraform init
```

2. Next, run the plan to make sure your configuration is valid. Execute the following command:

```
$ terraform plan
```

3. If your plan comes back successfully it is time to deploy! Execute the following command:

```
$ terraform apply
```

The deployment will take around 8-10 minutes.

When the deployment completes it will generate a bunch of output. You will use this next to configure your Kubernetes manifests.

### Step 3: Configure the Kubernetes manifests

We use [Kustomize](https://kustomize.io/) to declaratively configure our Kubernetes deployments. There are some elements that we can only fill in after we have deployed the infrastructure - for example database connection strings, NFS IP addresses, etc. To simplify this final configuration you can run a provided script.

1. Navigate to the [kubernetes](/kubernetes) directory.
2. Initialize the Terraform module - you will only need to do this once. Execute the following command:

```
$ terraform init
```

3. Plan and apply. Execute the following commands:

```
$ terraform plan
```

If all is well move on to the apply:

```
$ terraform apply
```

For each of the provided K8s manifests this module will create an `envs` directory for each environment you specified in your Terraform variable definition. This will be populated with configured Kustomize manifests ready for deployment.


### Step 4: Authenticate to your GKE cluster

Before you can deploy anything to GKE you will need to authenticate to the appropriate cluster. Execute the following command:

```
$ gcloud container clusters get-credentials <cluster name> --zone <zone>
```

> Note: For the following steps we will assume your environment name is `dev`.

### Step 5: Deploy NGINX

The first Kubernetes workload we will be deploying is ingress-nginx, which we use as our preferred load balancer.

1. Navigate to the correct ingress-nginx environment directory (e.g. `/kubernetes/manifests/ingress-nginx/envs/dev`)
2. Execute the following command:
```
$ kubectl apply -k .
```

### Step 6: Deploy Secrets-Store-CSI

In order to securely pass the secrets contained in Secret Manager into GKE we will use the [Secret Store CSI](https://secrets-store-csi-driver.sigs.k8s.io/introduction.html).

1. Navigate to the correct secret-store environment directory (e.g. `/kubernetes/manifests/secret-store/envs/dev`)
2. Execute the following command:
```
$ kubectl apply -k .
```

### Step 7: Deploy Cert-manager

We use cert-manager to deploy free LetsEncrypt TLS/SSL certificates - cert-manager will handle all renewals automatically.

1. Navigate to the correct cert-manager environment directory (e.g. `/kubernetes/manifests/cert-manager/envs/dev`)
2. Execute the following command: `kubectl apply -k .`
3. We also need to deploy the cluster issuer, which is responsible for actually requesting and issuing the certificates. This must be deployed after the rest of the cert-manager bundle to allow time for the custom resource definitions to fully deploy. Execute the following command:
```
$ kubectl apply -k .
```

### Step 8: Deploy Looker

With all of our required workloads in place we can now deploy Looker.

1. Navigate to the correct Looker directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
2. Open your `kustomization.yaml` file and ensure you have the correct version tag set in the `images:newTag` field. Save and exit.
3. Navigate to the `config` directory and examine the `lookerstart.cfg` file. Add any additional [Looker startup options](https://docs.looker.com/setup-and-management/on-prem-install/looker-startup-options) you require.
4. Return to the `kubernetes/manifests/looker/envs/dev` directory. Execute the following command:
```
$ kubectl apply -k .
```

### Step 9: Confirming the deployment

> Note: We'll assume your looker namespace is `looker-dev`

You can track the status of your deployment by executing the following command:

```
kubectl get pods -n looker-dev
```

You should see that after about 3 minutes the Looker pod shows 2/2 ready. You should now be able to access your Looker environment at your specified URL.
