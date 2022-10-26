# Deploying a Kubernetes-Based Instance

Deploying Looker in Kubernetes (K8s) is the recommended approach for production environments. We leverage Helm and the official Terraform Helm provider to manage the entire rollout with Terraform.

## Prerequisites

- You will need to have completed all steps in [part 1](./01_gcp_project_setup.md)
- You will need to have built a Looker container image - see [part 2a](./02a_build_container_image.md)
- You will need to have built a Looker helm chart - see [part 2b](./02b_build_helm_chart.md)

## Deploy the infrastructure

### Step 1: Create your `.tfvars` file

1. Navigate to the [looker_kubernetes](/terraform/looker_kubernetes) directory.
2. Create a file called `terraform.tfvars` You will define your variables in this file. A minimal example might look something like this:

```
project_id            = "my-gcp-project-id"
region                = "us-central1"
zone                  = "us-central1-a"
terraform_sa_email    = "my_serviceaccount_email@gserviceaccount"
prefix                = "test"
dns_managed_zone_name = "my-managed-zone"

db_tier               = "db-custom-2-7680"

gke_node_zones        = ["us-central1-a"]
gke_node_tier         = "e2-standard-16"
gke_node_min          = 3
gke_node_max          = 5

looker_k8s_repository = "us-central1-docker.pkg.dev/my-gcp-project/looker/looker"
looker_helm_repository = "oci://us-central1-docker.pkg.dev/my-gcp-project/looker/looker-helm"

envs = {
  dev = {
    db_secret_name                = "looker-dev-db-password"
    gcm_secret_name               = "looker-dev-gcm-encryption-key"
    looker_node_count             = 1
    looker_version                = "22.16"
    looker_k8s_issuer_admin_email = "me@example.com"
  }
}
```
> Note: for full details of how to use each variable please refer to the [variables file](../terraform/looker_kubernetes/variables.tf)

Variable definitions are as follows:

| Name | Description | Default |
|------|-------------|---------|
| project_id | Your GCP Project ID |  |
| kms_project_id | If you want to use [Application Layer Encryption](https://cloud.google.com/kubernetes-engine/docs/how-to/encrypting-secrets) the best practice is to set up Cloud KMS in a separate project. However, this can certainly be the same as your main project. Omit to use your main project for KMS as well. | |
| dns_project_id | A separate project ID in case your DNS config lives in a different GCP project. Omit to use your main project for DNS as well | |
| region | The GCP region to use | |
| zone | The GCP zone to use | |
| terraform_sa_email | The email address of your deployment service account | |
| prefix | An identifier added as a prefix to many resources to aid in organization | |
| subnet_ip_range | The IP range of the cluster's subnet in CIDR notation | "10.0.0.0/16" |
| private_ip_range | The IP range made available for Private Service Connections | "192.168.0.0/16" |
| dns_managed_zone_name | The name of your GCP Cloud DNS managed zone | |
| db_version | The MYSQL version to use for Looker's internal database. Must be either "MYSQL_5_7" or "MYSQL_8_0" | "MYSQL_8_0" |
| db_deletion_protection | Should the database instance be protected from deletion. Useful for production environments | false |
| db_tier | The tier to use for the database instance. Supports custom tiers. | |
| db_high_availability | Should the database instance be configured for high availability. Improves availability but costs more. | false |
| db_flags | A list of optional database flags to include in addition to the default flags | [] |
| db_read_replicas | a list of read replica configurations for the database instance. More information can be found [here](https://registry.terraform.io/modules/GoogleCloudPlatform/sql-db/google/latest/submodules/mysql) | [] |
| gke_node_zones | a list of zones to use for GKE zonal replication | |
| gke_regional_cluster | Should the GKE cluster be regionally replicated. Improves availability but costs more | false |
| gke_subnet_pod_range | The secondary IP range to use for GKE pods | {ip_cidr_range = "172.16.16.0/20", range_name = "looker_pod_range"} |
| gke_subnet_service range | The secondary IP range to use for GKE services | {ip_cidr_range = "172.16.64.0/20", range_name = "looker_service_range"} |
| gke_controller_range | The secondary range to use for the GKE controller. Must be a /28 block. | 172.16.0.0/28 |
| gke_private_endpoint | Should the GKE endpoint be private. This has significant access implications. Note that the cluster already uses private nodes.  | false |
| gke_master_global_access_enabled | If a private endpoint is enabled, should access be allowed outside the cluster's region | false |
| gke_master_authorized_networks | A list of IP ranges that are allowed to access the GKE endpoint. Note that including ranges will disable access for any other range. | [] |
| gke_release_channel | Which release channel to use for GKE updates | "REGULAR" |
| gke_use_application_layer_encryption | Should GKE leverage Cloud KMS to provide an additional layer of envelope encryption for its internal database | false |
| gke_use_managed_prometheus | Should the GKE cluster be enabled to use Google Managed Prometheus for monitoring | true |
| gke_node_tier | The compute tier to use for GKE nodes | |
| gke_node_count_min | The minimal number of GKE nodes in the cluster. Used for node autoscaling | |
| gke_node_count_max | The maximum number of GKE nodes in the cluster. Used for node autoscaling | |
| dns_managed_zone_name | The name of the GCP Managed DNS zone to use for DNS entries | |
| looker_subdomain | An optional subdomain to use for Looker URLs | "looker" |
| looker_k8s_repository | The Artifact Registry repository where the Looker container image is stored | |
| looker_k8s_image_pull_policy | The image pull policy for Looker K8s images | "Always" |
| certmanager_helm_version | The Helm chart version to use for certmanager | "v1.9.1" |
| ingress_nginx_helm_version | The Helm chart version to use for ingress_nginx | "4.2.5" |
| secrets_store_csi_driver_helm_version | The Helm chart version to use for secrets_store_csi_driver | "1.2.4" |
| looker_helm_repository | The Artifact Registry repository where the Looker Helm chart is stored. For GCP Artifact Registry, this must begin with "oci://" | |
| looker_helm_version | The Helm chart version to use for Looker | "0.1.0" |
| disable_hooks | Should the Helm hooks be disable for the Looker Helm rollout. Essentially used to skip the schema migration job - useful if your rollout does not include a version upgrade and you want it to deploy faster. | false |
| envs | Instance-specific details for each deployed Looker instance. The details of the object map are explained below. | |

The envs variable is a map that contains environment-specific variables for your deployment. Each key of the map is the name of an environment and each value is an object that contains the required variables for the given environment name. The definitions are as follows:

| Name                                 | Description | Default |
|--------------------------------------|-------------|---------|
| looker_node_count | The number of Looker nodes to deploy | |
| looker_version | The version of Looker to deploy. This must align with a tag of a Looker image you built in [step 2a](./02a_build_container_image) | |
| looker_startup_flags | A string of additional [startup flags](https://cloud.google.com/looker/docs/startup-options) you may want to include. You should not include `shared-storage-dir`, `clustered`, or `host` as these are automatically included for you | |
| gcm_key_secret_name | The name of the GCM key secret you created in Secret Manager while setting up your GCP Project | |
| db_secret_name | The name of your database password secret you created in Secret Manager while setting up your GCP Project | |
| user_provisioning_enabled | Should Looker provision a starting user - you must have created a Secrets Manager secret in the [correct yaml format](https://cloud.google.com/looker/docs/auto-provisioning-new-looker-instance). | false |
| user_provisioning_secret_name | The name of the Secrets Manager secret to use for user provisioning. This secret must in the correct yaml format - refer to [the docs](https://cloud.google.com/looker/docs/auto-provisioning-new-looker-instance) for details | |
| filestore_tier | The [service tier](https://cloud.google.com/filestore/docs/service-tiers) to use for Filestore | "STANDARD" |
| redis_enabled | Should Looker use Redis for its cache - improves performance but adds cost | true |
| redis_memory_size_gb | How much memory to use for the Redis cache. The rule of thumb is to have 2GB per node - so a 3-node Looker cluster should have 6 GB of cache memory. | 4 |
| redis_high_availability | Should Redis be configured with a failover backup. This adds cost. Note that this is not the same as running Redis in clustered mode, which Looker [does not support](https://docs.looker.com/setup-and-management/on-prem-mgmt/redis-cache). | false |
| looker_k8s_issuer_admin_email | The email address to register as the Let's Encrypt admin for generated TLS certificates. In practice, this is the person who will receive reminder emails if certs are about to expire. | |
| looker_k8s_issuer_acme_server | The server to use for provisioning Let's Encrypt TLS certificates. If you plan on creating and tearing down many Looker instances to test things out you may want to use the [staging server]() to avoid API limits. Defaults to the production server | "https://acme-v02.api.letsencrypt.org/directory" |
| looker_k8s_namespace | The K8s namespace to use for the Looker instance | "looker" |
| looker_k8s_update_config | How should Looker's rolling updates be configured | {maxSurge = 1, maxUnavailable = 0} |
| looker_k8s_node_resources | Set the Kubernetes requests and limits for CPU and memory for a Looker deployment | {requests = {cpu = "4000m", memory = "16Gi"}, limits = {cpu = "6000m", memory = "18Gi"}} |
| looker_scheduler_node_enabled | This option toggles specialized scheduler nodes - this will create a new Deployment with nodes that are dedicated to performing schedule and render tasks. This can be a good option for instance that experience heavy scheduler/render activity that slows down UI navigation | false |
| looker_scheduler_node_count | If scheduler nodes are enabled, how many should be deployed | 2 |
| looker_scheduler_threads | How many scheduler threads should be run on the scheduler nodes. Leave at default unless you fully understand what you are doing | 10 |
| looker_scheduler_unlimited_threads | How many unlimited scheduler thread should be run on the scheduler nodes. Leave at default unless you fully understand what you are doing | 3 |
| looker_scheduler_alert_threads | How many alert threads should be run on the scheduler nodes. Leave at default unless you fully understand what you are doing | 3 | 
| looker_scheduler_render_caching_jobs | How many render caching jobs should be allowed on the scheduler nodes. Leave at default unless you fully understand what you are doing | 3 |
| looker_scheduler_render_jobs | How many render jobs should be allowed on the scheduler nodes. Leave at default unless you fully understand what you are doing | 2 |
| looker_scheduler_resources | Set the the Kubernetes request and limits for CPU and memory for the scheduler node deployment | {requests = {cpu = "4000m", memory = "16Gi"}, limits = {cpu = "6000m", memory = "18Gi"}} |

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

All Kubernetes workloads should be deployed at the end of the Terraform rollout. You can confirm this either by visiting your GKE console and selecting "Workloads" on the left-hand menu, or with `kubectl`. If you want to use `kubectl` you will need to authenticate to your GKE cluster with the following command:

```
$ gcloud container clusters get-credentials <cluster name> --zone <zone>
```

The Looker deployment will take a few minutes to complete rollout. Once it is ready you can navigate to the URL defined in your DNS - it should be `<env name>.<subdomain>.<domain>` - something like `dev.looker.example.com`