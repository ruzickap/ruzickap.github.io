---
title: Harbor on Kubernetes
author: Petr Ruzicka
date: 2019-04-12
description: Guide for installing and operating the Harbor container registry on Amazon EKS
categories: [Kubernetes, Cloud, Security]
tags: [amazon-eks, kubernetes, harbor, container-registry, vulnerability-scanning, helm, cert-manager]
image: https://raw.githubusercontent.com/ruzickap/k8s-harbor/f9caf0b921824c0281f01f7f1772c91444069644/docs/part-04/harbor_login_page.png
---

This guide deploys the [Harbor](https://goharbor.io/) cloud-native container
registry on [Amazon EKS](https://aws.amazon.com/eks/).

- Creates an EKS cluster and installs [Helm](https://helm.sh/)
- Configures [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) and
  [cert-manager](https://cert-manager.io/)
- Installs [Harbor](https://goharbor.io/) and covers projects, images, and Helm
  charts

Read the complete guide at [Harbor on Kubernetes](https://ruzickap.github.io/k8s-harbor/).

View the source at [ruzickap/k8s-harbor](https://github.com/ruzickap/k8s-harbor).
