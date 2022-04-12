# Kubernetes Operations Runbook

Kubernetes deployments offer some advanced features that allow for improved operations. Let's take a look at some common procedures

## Scale Out A Cluster

Scaling out a cluster is as simple as adding a new replica to your `looker-clustered` K8s deployment. This can be accomplished both imperatively and declaratively.

### Imperative Scaling

> Note: We will assume your looker namespace is called `looker-dev`

Imperative scaling is accomplished with a simple `kubectl` command - execute the following:

```
$ kubectl scale deployment/looker-clustered --replicas=2 -n looker-dev
```

In this example your deployment will be scaled to 2 looker nodes. You can track the progress of this rollout by executing the following command:

```
$ kubectl get pods -n looker-dev -w
```

> Note: the `-w` flag sets kubectl to watch mode which will automatically update as your deployment rolls out. You can exit watch mode by pressing `crl-c`

### Declarative Scaling

While imperative commands are quick and easy they will be undone the next time an apply command is executed against the deployment manifest. For this reason we recommend scaling declaratively. Let's do that now.

> Note: We will assume you have deployed one environment called `dev`.

1. Navigate to the correct Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
2. Edit your `kustomization.yaml` file: change the `replicas:count` value to your desired number of Looker nodes.
3. Save your changes, then execute the following command:
```
$ kubectl apply -k .
```

You can track the progress of this rollout by executing the following command:

```
$ kubectl get pods -n looker-dev
```

## Scale Up Looker Nodes

In addition to scaling your Looker cluster out you can also commit more CPU and RAM to each individual Looker node.

1. Navigate to the correct Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
2. Edit your `patch_deployment_looker_resources.yaml` file: change the resource requests and limits to suit your requirements.
3. Save your changes, then execute the following command:
```
$ kubectl apply -k .
```

You can track the progress of this rollout by executing the following command:

```
$ kubectl get pods -n looker-dev
```

> Note: Your ability to scale up your Looker nodes is constrained by the size of your GKE nodes. You can't create a 32Gb Looker node if your GKE node only has 16Gb available!

## Upgrading Looker

With K8s deployments most Looker upgrades can be deployed in a rolling fashion, meaning no downtime is required. This applies to patch upgrades (e.g. `21.18.32 -> 21.18.33`) and minor version upgrades (e.g. `21.18 -> 21.20`). Major version upgrades (e.g. `21.20 -> 22.0`) will still require some downtime.

### Patch version upgrades

Patch upgrades are the simplest since they require no schema migrations.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Input the same version number you are currently using - the script automatically pulls the latest patch version.
2. Navigate to the correct Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
3. If necessary, edit your `kustomization.yaml` file to update your version tag in the `images:newTag` field. This should only be necessary if you are using SHA values for tags.
4. Execute the following command:
```
$ kubectl apply -k .
```

The new image will be pulled into your cluster and deployed.

### Minor version upgrades

Minor version upgrades are the most common type of upgrade you will perform. This largely follows the same procedure as above, but in order to perform the upgrade with zero downtime you will need to execute a schema migration job prior to rolling out the new image in your cluster.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Make sure you specify the new version number.
2. Navigate to the correct Looker environment job directory (e.g. `/kubernetes/manifests/looker/envs/dev/jobs/rolling_updates`)
3. Edit the `kustomization.yaml` file - set `images:newTag` and `patchesJson6902:patch:value` to your images new version tag.
4. Execute the schema migration job - execute the following command:
```
$ kubectl apply -k .
```
5. Wait for the job to complete. You can track its progress by executing the following command:
```
$ kubectl get jobs -n looker-dev
```
   You can also make use of Cloud Logging to track the progress of the migration job. It should successfully complete in a couple of minutes.

6. Once the migration job has successfully completed you can navigate back to the Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
7. Edit your `kustomization.yaml` file to update your version tag in the `images:newTag` field. Set it to your new version tag.
8. Execute the following command:
```
$ kubectl apply -k .
```

The new image will be rolled out. You can track the progress of the rollout by executing the following command:
```
$ kubectl get pods -n looker-dev
```

> Note: We recommend applying the schema migration job only in single version increments (e.g. 21.18 -> 21.20 rather than 21.16 -> 21.20). If you are jumping up multiple versions then apply the schema migrations one step at a time.

### Minor version rollbacks

If you determine you need to perform a rollback you can use the same schema migration job process to execute your rollback with zero downtime. The steps are almost identical to the upgrade steps listed above with the following exceptions:

- For step 3, make sure that the `images:newTag` value **is still set to the most recent tagged version** (e.g. 21.20) while the `patchesJson6902:patch:value` field **is set to the prior version** (e.g. 21.18).
- For step 7, make sure you set `images:newTag` **to the prior version**.

> Note: As stated above we recommend only performing schema migrations in single-version increments.


### Major version upgrades

Major version upgrades (e.g. 21.20 -> 22.0) require downtime and therefore you do not need to run the schema migration job applying the upgrade.

1. Follow [the steps](./02b_build_container_image.md) to build a new container image. Make sure you specify the new version number.
2. Navigate to the correct Looker environment directory (e.g. `/kubernetes/manifests/looker/envs/dev`)
3. Scale your looker deployment to 0 replicas. This can be accomplished imperatively with the following command:
```
$ kubectl scale deployment looker-clustered --replicas=0 -n looker-dev
```
   Wait for the deployment to spin down to 0 replicas

4. (Optional but recommended) [Create a backup](https://cloud.google.com/sql/docs/mysql/backup-recovery/backing-up#on-demand) of your MySQL database. Backups are automatically created on a regular basis so this is only necessary if you desire a different RPO than these backups can provide.
5. Edit your `kustomization.yaml` file to update your version tag in the `images:newTag` field.
6. Execute the following command:
```
$ kubectl apply -k .
```

The new image will be rolled out. You can track its progress by executing the following command:

```
$ kubectl get pods -n looker-dev
```

### Major version rollbacks

Rolling back a major version follows a similar pattern to the steps outlined above, but rather than creating a database backup you will restore a database backup:

1. Scale your deployment to 0 replicas
2. Once your replicas have spun down [restore an appropriate backup](https://cloud.google.com/sql/docs/mysql/backup-recovery/restoring#restorebackups) of your database that was taken from the prior version.
3. Edit your `kustomization.yaml` file to update your version tag in the `images:newTag` field to the prior version.
4. Execute the following command:
```
$ kubectl apply -k .
```

> Note: It should go without saying that this major version rollback operation will require downtime.

## Update Your GCM Encryption Key

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
