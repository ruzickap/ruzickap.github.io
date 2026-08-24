---
title: Kubernetes with Flux, Istio, GitLab, and Harbor
author: Petr Ruzicka
date: 2019-08-21
description: Guide for a kops Kubernetes cluster with GitOps, service mesh, and registry services
categories: [Kubernetes, Cloud, DevOps]
tags: [kubernetes, kops, aws, flux, gitops, istio, gitlab, harbor, cert-manager, helm]
image: https://opengraph.githubassets.com/a85ea78b88494b393a4aba484ffc386dbd1ac581/ruzickap/k8s-flux-istio-gitlab-harbor
---

This guide documents a [kops](https://kops.sigs.k8s.io/)
[Kubernetes](https://kubernetes.io/) cluster on AWS with a GitOps platform
stack.

- Creates the cluster and installs [Helm](https://helm.sh/) and
  [Flux](https://fluxcd.io/)
- Deploys [cert-manager](https://cert-manager.io/),
  [kubed](https://github.com/appscode/kubed), [Istio](https://istio.io/), and
  [Harbor](https://goharbor.io/) through Flux
- Manages container images and Helm charts with [GitOps](https://opengitops.dev/)
  workflows

Read the complete guide at [Kubernetes with Flux, Istio, GitLab, and Harbor](https://ruzickap.github.io/k8s-flux-istio-gitlab-harbor/).

View the source at [ruzickap/k8s-flux-istio-gitlab-harbor](https://github.com/ruzickap/k8s-flux-istio-gitlab-harbor).
