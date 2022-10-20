# Kubernetes Operations Runbook

> Note: You should make sure to [authenticate to your cluster](https://cloud.google.com/kubernetes-engine/docs/how-to/api-server-authentication#authenticating_using_oauth) so you can execute all the following commands.

Kubernetes deployments offer some advanced features that allow for improved operations. Let's take a look at some common procedures.

## Scale Out A Cluster

Scaling out a cluster is as simple as adding a new replica to your looker K8s deployment. This can be accomplished either imperatively or declaratively.

### Imperative Scaling

> Note: We will assume your looker namespace is called `looker`

First, we determine the name of your deployment. Execute the following command:

```
$ kubectl get deployments -n looker
```

Let's assume your deployment is called `looker-dev` Imperative scaling is accomplished with a simple `kubectl` command - execute the following:

```
$ kubectl scale deployment/looker-dev --replicas=2 -n looker
```

In this example your deployment will be scaled to 2 looker nodes. You can track the progress of this rollout by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

### Declarative Scaling

While imperative commands are quick and easy they will be undone the next time an apply command is executed. For this reason we recommend scaling declaratively. Let's do that now.

> Note: We will assume you have deployed one environment called `dev`.

1. Navigate to the correct Terraform directory: `terraform/looker_kubernetes`
2. Edit your `terraform.tfvars` file: change the `looker_node_count` variable in the correct env object to your desired level.
3. Save your changes, then execute the following command:

```
$ terraform apply -var="disable_hooks=true"
```
> The use of the `disable_hooks` variable is optional - since we are not upgrading Looker versions as a part of this rollout we do not need to run the schema migration job, so setting this variable will save us some time.

You can track the progress of this rollout by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

## Scale Up Looker Nodes

In addition to scaling your Looker cluster out you can also commit more CPU and RAM to each individual Looker node.

1. Navigate to the correct Terraform directory: `terraform/looker_kubernetes`
2. Edit your `terraform.tfvars` file: add or change the `looker_k8s_node_resources` in the correct env object to your desired state. It might look something like this:

```
looker_k8s_node_resources = {
   requests = {
      cpu = "8000m"
      memory = "20Gi"
   },
   limits = {
      cpu = "10000m"
      memory = "24Gi"
   }
}
```

3. Save your changes, then execute the following command:

```
$ terraform apply -var="disable_hooks=true"
```

> The use of the `disable_hooks` variable is optional - since we are not upgrading Looker versions as a part of this rollout we do not need to run the schema migration job, so setting this variable will save us some time.
> Note: Your ability to scale up your Looker nodes is constrained by the size of your GKE nodes. You can't create a 32Gb Looker node if your GKE node only has 16Gb available!

You can track the progress of this rollout by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

## Upgrading Looker

With K8s deployments most Looker upgrades can be deployed in a rolling fashion, meaning no downtime is required. This applies to patch upgrades (e.g. `21.18.32 -> 21.18.33`) and minor version upgrades (e.g. `21.18 -> 21.20`). Major version upgrades (e.g. `21.20 -> 22.0`) will still require some downtime.

### Patch version upgrades

Patch upgrades are the fastest since they require no schema migrations.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Input the same version number you are currently using - the script automatically pulls the latest patch version.
2. Navigate to the correct Terraform directory: `terraform/looker_kubernetes`
3. Execute the following command:

```
$ terraform apply -var="disable_hooks=true"
```

> The use of the `disable_hooks` variable is optional - since we are performing only a patch version upgrade as a part of this rollout we do not need to run the schema migration job, so setting this variable will save us some time.

The new image will be pulled into your cluster and deployed.

You can track the progress of this rollout by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

### Minor version upgrades

Minor version upgrades are the most common type of upgrade you will perform.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Make sure you specify the new version number. Confirm your new image has the major:minor version tag.
2. Navigate to the correct Terraform directory: `terraform/looker_kubernetes`
3. Edit the `terraform.tfvars` file - set the `looker_version` variable in the correct env object to the desired major:minor version e.g. "22.14"
4. Execute the following command:

```
$ terraform apply
```

> Note: In this case we **must** run the Helm hooks because that triggers the required schema migration job. 

The pre-upgrade hook will run which will execute the schema migration job. You can track the job's progress with the following command:

```
$ kubectl get jobs -n looker
```

Kubernetes will clean up the job as soon as it completes so don't be surprised if no results come back! The job should take about 1-3 minutes to complete. With the job complete, the updated deployment will be rolled out. You can track the progress of the rollout by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

> Note: We recommend applying the schema migration job only in single version increments (e.g. 22.12 -> 22.14 rather than 22.10 -> 21.14).

### Minor version rollbacks

> Note: "Rollbacks" is a bit of a misnomer here due to the schema migration requirement. What you are technically doing is rolling out a new update, but one that migrates the schema back to an older version of Looker and then deploys an older container image.

If you determine you need to perform a "rollback" you can use the same process as above. The steps are almost identical to the upgrade steps listed above with the following exceptions:

- You obviously don't need to build a new container image.
- Ensure you have set your `looker_version` variable back to your desired prior version of Looker

> Note: As stated above we recommend only performing schema migrations in single-version increments.


### Major version upgrades

Major version upgrades (e.g. 21.20 -> 22.0) require downtime and therefore you do not need to run the schema migration job applying the upgrade.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Make sure you specify the new version number.
2. Scale your looker deployment to 0 replicas. This can be accomplished imperatively with the following command:

```
$ kubectl scale deployment looker-dev --replicas=0 -n looker
```

Wait for the deployment to spin down to 0 replicas

3. (Optional but recommended) [Create a backup](https://cloud.google.com/sql/docs/mysql/backup-recovery/backing-up#on-demand) of your MySQL database. Backups are automatically created on a regular basis so this is only necessary if you desire a different RPO than these backups can provide.
4. Edit your `terraform.tfvars` file - set the `looker_version` field in the appropriate envs object to the new major version.
5. Execute the following command:

```
$ terraform apply -var="disable_hooks=true"
```

The new image will be rolled out. You can track its progress by executing the following command:

```
$ kubectl rollout status deployment/looker-dev -n looker
```

### Major version rollbacks

Rolling back a major version follows a similar pattern to the steps outlined above, but rather than creating a database backup you will restore a database backup:

1. Scale your deployment to 0 replicas
2. Once your replicas have spun down [restore an appropriate backup](https://cloud.google.com/sql/docs/mysql/backup-recovery/restoring#restorebackups) of your database that was taken from the prior version.
3. Edit your `terraform.tfvars` file - set the `looker_version` variable back to the desired version.
4. Execute the following command:

```
$ terraform apply -var="disable_hooks=true"
```

> Note: It should go without saying that this major version rollback operation will require downtime.

## Updating Your GCM Encryption Key

Looker's [AES-256 encryption](https://docs.looker.com/setup-and-management/on-prem-mgmt/changing-encryption-keys) requires that you provide a GCM encryption key. You set this up in a Secret Manager secret back in [part 1](./01_gcp_project_setup.md). Depending on your organization's key rotation policy you may need to cycle this key every so often.

> Note: This operation requires downtime.

1. Generate a new key. In a terminal execute the following command:

```
$ openssl rand -base64 32
```

2. Copy the output and use it to [create a new version](https://cloud.google.com/secret-manager/docs/creating-and-accessing-secrets#add-secret-version) for the appropriate Secret Manager secret. Take note of what your secret version numbers are.
3. Navigate to the correct Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
4. Scale your looker deployment to 0 replicas. This can be accomplished imperatively with the following command:
```
$ kubectl scale deployment looker-clustered --replicas=0 -n looker-dev
```

   Wait for the deployment to spin down to 0 replicas

5. Navigate to the key rotation job directory (e.g. `/kubernetes/manifests/looker/envs/dev/jobs/gcm_key_rotation`)
6. Edit the `kustomization.yaml` file - make sure the value of `images:newTag` is set to your currently deployed image tag.
7. Edit the `looker_secret_provider_class.yaml` file - Under `spec:parameters:secrets` you want the `resourceName` associated with `looker_gcm_key_old` to point to the secret version **of your currently used secret** (not the new one you just made).

Example - if this is your first GCM key rotation then the new secret you generated will be version 2. Your old version would look something like `projects/<project id>/secrets/<gcm key secret name>/versions/1`

8. Execute the gcm key rotation job. Execute the following command:
```
$ kubectl apply -k .
```

9. Wait for the job to complete. This should take a couple of minutes. You can track the job's progress by examining the logs in Cloud Logging or by running the following command:
```
$ kubectl get jobs -n looker-dev -w
```

10. Once the job has completed return to the Looker environment directory (e.g. `kubernetes/manifests/looker/envs/dev`)
11. Redeploy your Looker deployment. Execute the following command:
```
$ kubectl apply -k .
```
