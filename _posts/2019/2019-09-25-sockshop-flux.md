---
title: AKS with Flagger, Flux, and Sock Shop
author: Petr Ruzicka
date: 2019-09-25
description: Guide for deploying Sock Shop to Azure Kubernetes Service with Flux and Flagger
categories: [Kubernetes, Cloud, DevOps]
tags: [azure-aks, kubernetes, flux, flagger, sock-shop, gitops, terraform, kubectl]
image: https://opengraph.githubassets.com/f046993ddf1105ab54489a944e2c04a055cc0d3b/ruzickap/k8s-sockshop
---

This guide deploys the [Sock Shop](https://github.com/microservices-demo/microservices-demo)
application to [Azure Kubernetes Service](https://azure.microsoft.com/products/kubernetes-service/)
using [GitOps](https://opengitops.dev/) tooling.

- Creates an AKS cluster with [Terraform](https://developer.hashicorp.com/terraform)
- Installs [Flux](https://fluxcd.io/) for GitOps reconciliation
- Deploys Sock Shop with [Flagger](https://flagger.app/) and
  [Istio](https://istio.io/)

Read the complete guide at [AKS with Flagger, Flux, and Sock Shop](https://ruzickap.github.io/k8s-sockshop/).
