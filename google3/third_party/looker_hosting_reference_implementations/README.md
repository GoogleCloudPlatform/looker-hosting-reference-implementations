# Looker Infrastructure as Code Reference Implementations

## Introduction

Looker Hosting Reference Implementations (codename "OpsBae") is a set of Infrastructure-as-Code (IaC) tools and Kubernetes manifests to help jump-start Looker customers who
choose to self-host on GCP. We have designed it to be highly modular - we want to offer some opinionated solutions and best
practices while making it easy to adapt the solution for a client's particular needs. These modules should be taken as a
starting point and an accelerator, not as a production-ready solution out of the box.

### Status and Support

These reference implementations are not an official Google product. We will respond to any opened issues on a best-effort basis. Our official documentation for setting up a self-hosted Looker instance can be found [here](https://docs.looker.com/setup-and-management/on-prem-install) and further help center articles can be found [here](https://help.looker.com/hc/en-us/articles/4404416923283-Customer-hosted-Architecture-solutions-Component-Walkthroughs-).

## Hosting Decision

For the significant majority of customers, Looker's hosted option is the correct choice for how to deploy Looker. If you are working through your
hosting decision please reach out to your GCP account team for help. Self-hosting Looker should not be entered into lightly.

## Requirements

- Packer >= 1.7.0
- Terraform >= 1.0.0
- Kubernetes >= 1.21

You will also require Project Creator permissions for your GCP Organization.

## Getting Started

We have provided some tutorials to help get you started - they can be found in the [docs](/docs) directory.
