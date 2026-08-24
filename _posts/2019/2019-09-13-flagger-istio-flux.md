---
title: AKS with Flagger, Flux, and Istio
author: Petr Ruzicka
date: 2019-09-13
description: Guide for GitOps-driven canary deployments on Azure Kubernetes Service
categories: [Kubernetes, Cloud, DevOps]
tags: [azure-aks, kubernetes, flux, flagger, istio, tekton, canary-deployment, gitops, terraform, kubectl]
image: https://opengraph.githubassets.com/20487f7178d1b43eaafb7c66c4160ef985884299/ruzickap/k8s-flagger-istio-flux
---

This guide builds an [Azure Kubernetes Service](https://azure.microsoft.com/products/kubernetes-service/)
environment for [GitOps](https://opengitops.dev/) and progressive delivery.

- Creates an AKS cluster with [Terraform](https://developer.hashicorp.com/terraform)
- Installs [Flux](https://fluxcd.io/), [Tekton](https://tekton.dev/) pipelines,
  [Flagger](https://flagger.app/), and [Istio](https://istio.io/)
- Demonstrates a [Flagger](https://flagger.app/)-managed canary deployment

Read the complete guide at [AKS with Flagger, Flux, and Istio](https://ruzickap.github.io/k8s-flagger-istio-flux/).
