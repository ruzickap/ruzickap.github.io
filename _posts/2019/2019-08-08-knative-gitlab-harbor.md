---
title: Kubernetes with Knative, GitLab, and Harbor
author: Petr Ruzicka
date: 2019-08-08
description: Guide for building and deploying container images with Knative and Tekton
categories: [Kubernetes, Cloud, DevOps]
tags: [kubernetes, aws, kops, knative, tekton, gitlab, harbor, istio, cert-manager, kaniko]
image: https://opengraph.githubassets.com/ec2a45f6584cea1cbd22d105f58a481d1e7dc8e7/ruzickap/k8s-knative-gitlab-harbor
---

This guide builds a [kops](https://kops.sigs.k8s.io/)
[Kubernetes](https://kubernetes.io/) platform on AWS for cloud-native
application delivery.

![Amazon EKS services animation](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/3-service-animated.gif){:width="500"}

- Installs [Istio](https://istio.io/), [cert-manager](https://cert-manager.io/),
  [Harbor](https://goharbor.io/), [GitLab](https://about.gitlab.com/), and
  [Knative](https://knative.dev/)
- Builds and runs container images with [Knative](https://knative.dev/) and
  [Tekton](https://tekton.dev/)
- Automates deployment pipelines and covers [Knative](https://knative.dev/)
  operations

Read the complete guide at [Kubernetes with Knative, GitLab, and Harbor](https://ruzickap.github.io/k8s-knative-gitlab-harbor/).

View the source at [ruzickap/k8s-knative-gitlab-harbor](https://github.com/ruzickap/k8s-knative-gitlab-harbor).
