---
title: Amazon EKS with Bottlerocket and Fargate
author: Petr Ruzicka
date: 2020-10-17
description: Guide for building Amazon EKS with Bottlerocket and AWS Fargate
categories: [Kubernetes, Cloud]
tags: [amazon-eks, kubernetes, bottlerocket, fargate, eksctl, helm, gitops, harbor, velero]
image: https://opengraph.githubassets.com/917f7c6e6def2aea61e230cc152f60359147dff3/ruzickap/k8s-eks-bottlerocket-fargate
---

This guide explores [Amazon EKS](https://aws.amazon.com/eks/) with
[Bottlerocket](https://bottlerocket.dev/) worker nodes and
[AWS Fargate](https://aws.amazon.com/fargate/).

- Creates the EKS cluster and supporting AWS resources
- Configures monitoring, logging, DNS, ingress, certificates, and authentication
- Deploys workloads, [Drupal](https://www.drupal.org/),
  [Harbor](https://goharbor.io/), [Velero](https://velero.io/), and GitOps tools

Read the complete guide at [Amazon EKS with Bottlerocket and Fargate](https://ruzickap.github.io/k8s-eks-bottlerocket-fargate/).

View the source at [ruzickap/k8s-eks-bottlerocket-fargate](https://github.com/ruzickap/k8s-eks-bottlerocket-fargate).
