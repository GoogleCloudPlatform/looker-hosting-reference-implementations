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