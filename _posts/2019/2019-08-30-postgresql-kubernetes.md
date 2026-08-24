---
title: PostgreSQL on Kubernetes
author: Petr Ruzicka
date: 2019-08-30
description: Guide for evaluating PostgreSQL high-availability solutions on Kubernetes
categories: [Cloud, Data, Kubernetes]
tags: [azure-aks, crunchy-data, kubernetes, patroni, postgresql, terraform, zalando-postgres-operator]
image: https://opengraph.githubassets.com/bef741679bba32163f5db319e2e96d1c6fa8506b/ruzickap/k8s-postgresql
---

This guide compares approaches to running [PostgreSQL](https://www.postgresql.org/)
on [Kubernetes](https://kubernetes.io/).

- Creates a [Kubernetes](https://kubernetes.io/) cluster for the examples
- Deploys a [Patroni](https://github.com/patroni/patroni)-based PostgreSQL setup
- Evaluates the [Zalando Postgres Operator](https://github.com/zalando/postgres-operator)
  and [Crunchy Data PostgreSQL Operator](https://github.com/CrunchyData/postgres-operator)

Read the complete guide at [PostgreSQL on Kubernetes](https://ruzickap.github.io/k8s-postgresql/).
