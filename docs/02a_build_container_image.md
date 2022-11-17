# Build Container Images

Next up we will create some Looker images that we can use in our deployments. In this section we will cover building container images for use with Kubernetes. We will use [Cloud Build](https://cloud.google.com/build/docs/quickstart-build) to build an image and push it to [Google Artifact Registry](https://cloud.google.com/artifact-registry/docs/docker).

## Prerequisites

- You will need to have completed all steps in [part 1](./01a_gcp_project_setup_as_code.md).
- You will need to have accepted the [Looker EULA](https://download.looker.com/validate). You'll need your Looker license key handy. Note that you do not need to actually download the JARs after accepting the EULA. You will only need to do this once per license key/email combination.

## Step 1: Trigger Cloud Build

Building a container image is very straightforward. Simply navigate to [the container directory](/builders/dockerfile) and execute the following command:

```
$ gcloud builds submit --config cloudbuild.yaml --substitutions=_LOOKER_LICENSE_KEY_SECRET="<your license key secret name>,_LOOKER_TECHNICAL_CONTACT_EMAIL="<your technical contact email>",_LOOKER_VERSION="<the Looker version you want>",_REGISTRY_PATH="<your Artifact Registry repository>
```

The definitions for the substitution values are as follows:

| Name                            | Description | Default |
|---------------------------------|-------------|---------|
| _LOOKER_LICENSE_KEY_SECRET      | The name of the Secret Manager secret you created for your Looker license key | `looker_license_key` |
| _LOOKER_TECHNICAL_CONTACT_EMAIL | A valid email address - Looker uses this as a point of contact for things like patch notifications, etc. | |
| _LOOKER_VERSION                 | The Looker version you want to use. This should be in the format of `<major version>.<minor version>` - e.g. `22.14` | |
| _REGISTRY_PATH                  | The URI of your Looker Artifact Registry. This should be in the format of `<location>-docker.pkg.dev/<project id>/<registry name>` | |
| _IMAGE_NAME                     | The name for the Looker image. `looker` is a pretty safe bet. | `looker` |

The build process will take about 5 minutes to complete. You should now be able to see your container image in your Project's artifact registry.