---
title: Amazon EKS with Terraform and GitOps
author: Petr Ruzicka
date: 2022-01-19
description: Guide for a multitenant, multicluster Amazon EKS platform managed with Terraform and GitOps
categories: [Cloud, DevOps, Kubernetes]
tags: [amazon-eks, argocd, cert-manager, cilium, external-dns, flux, github-actions, gitops, grafana, ingress-nginx, kubernetes, multicluster, multitenant, prometheus, rancher, renovate, sops, terraform]
image: https://opengraph.githubassets.com/db2ec04ad980eb4b833f883296334260e9699225/ruzickap/k8s-tf-eks-gitops
---

This guide describes a multitenant, multicluster
[Amazon EKS](https://aws.amazon.com/eks/) platform managed with
[Terraform](https://developer.hashicorp.com/terraform),
[GitHub Actions](https://github.com/features/actions), and
[GitOps](https://opengitops.dev/).

- Provisions EKS infrastructure with [Terraform](https://developer.hashicorp.com/terraform)
- Uses [Flux](https://fluxcd.io/) or [Argo CD](https://argo-cd.readthedocs.io/)
  to reconcile cluster configuration
- Adds [Cilium](https://cilium.io/), ingress, DNS, certificates, monitoring,
  secret encryption, and SSO

Read the complete guide at [Amazon EKS with Terraform and GitOps](https://ruzickap.github.io/k8s-tf-eks-gitops/).
