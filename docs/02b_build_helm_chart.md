# Build Helm Charts

Now we'll need to build and push the Looker Helm chart to [Artifact Registry](https://cloud.google.com/artifact-registry/docs/helm) - this will ensure anyone deploying Looker is using the same chart/k8s manifests.

## Prerequisites

- You will need to have [authenticated Helm to Artifact Registry](https://cloud.google.com/artifact-registry/docs/helm/authentication). We recommend making use of [Docker configuration with a gcloud credentials helper](https://cloud.google.com/artifact-registry/docs/docker/authentication#gcloud-helper).

## Step 1: Package the Helm Chart

Packaging a Helm chart is very straightforward. Simply navigate to [the Helm directory](/builders/helm) and execute the following command:

```
$ helm package .
```

This will create a `.tgz` file in the directory. You will now push this to Artifact Registry.

## Step 2: Push the Helm package to Artifact Registry

Once you have your `.tgz` file you can push it to Artifact Registry with the following command:

```
$ helm push looker-helm-0.1.0.tgz oci://<your artifact registry repo>
```

An example might look like this:

```
$ helm push looker-helm-0.1.0.tgz oci://us-central1-docker.pkg.dev/my-cool-project/looker
```

> Note: This assumes you are deploying Helm chart version 0.1.0. As you customize the chart to suit your own requirements you can and should update the version number - make sure you're deploying the correct version!

You can confirm the push was successful by visiting Artifact Registry and looking for your helm chart - by default it is called `looker-helm`.

## Alternate Approach: Cloud Build

For convenience we've also provided a Cloud Build template to automate this process. Navigate to [the Helm directory](/builders/helm) and execute the following command:

```
$ gcloud builds submit --config cloudbuild.yaml --substitutions=_REGISTRY_LOCATION="<the region of your Artifact Registry>"
```

For example, if your artifact registry was in us-central1, the command would look like this:

```
$ gcloud builds submit --config cloudbuild.yaml --substitutions=_REGISTRY_LOCATION="us-central1"
```

> Note: In the examples above we're using the default value for `_REGISTRY_REPO_NAME` which is `looker`

Definitions for the possible substitute variables are:

| Name | Description | Default |
|------|-------------|---------|
| _REGISTRY_LOCATION | The location of your Artifact Registry repo - typically a region like `us-central1` | `us-central1` |
| _REGISTRY_REPO_NAME | The name of the Looker Artifact Registry repo | `looker` |