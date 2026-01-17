---
title: Running Kubernetes on AppVeyor with minikube
author: Petr Ruzicka
date: 2018-04-20
description: Running Kubernetes on AppVeyor with minikube
categories: [Kubernetes]
tags: [.appveyor.yml, appveyor, ci, minikube, travis]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2018/04/running-kubernetes-on-appveyor-with.html)
{: .prompt-info }

When I was playing with Kubernetes I made a lot of [notes](https://multinode-kubernetes-cluster.readthedocs.io)
on how to do things. Then I realized it may be handy to put those notes to
Github and let them go through some CI to be sure they are correct.

I was looking for a way to run Kubernetes via [minikube](https://github.com/kubernetes/minikube)
in [Travis CI](https://travis-ci.org/) and there are "some" ways:
[Running Kubernetes on Travis CI with minikube](https://web.archive.org/web/20171213061419/https://blog.travis-ci.com/2017-10-26-running-kubernetes-on-travis-ci-with-minikube)

Unfortunately I didn't have much luck with the latest minikube (0.26) and the
latest Kubernetes (1.10) when I tried to make it work on Travis. It looks like
there are some problems with running the latest stuff on Travis and people are
using older Kubernetes/minikube versions (like here: [https://github.com/LiliC/travis-minikube/blob/master/.travis.yml](https://github.com/LiliC/travis-minikube/blob/master/.travis.yml)).

Instead of troubleshooting Travis CI - I decided to use [AppVeyor](https://www.appveyor.com/).

![AppVeyor Kubernetes build screenshot](/assets/img/posts/2018/2018-04-20-running-kubernetes-on-appveyor-with-minikube/appveyor_kubernetes.avif)

It's another free service like Travis doing basically the same, but it has some
advantages:

- Your build environment is running in VM with 2 x CPU and 8GB of RAM and it can
  be running for 1 hour (can be extended to 1:30).
- It supports [Ubuntu Xenial 16.04](https://www.appveyor.com/docs/getting-started-with-appveyor-for-linux/#running-your-build-on-linux)
  and [Windows](https://www.appveyor.com/docs/build-environment/#build-worker-images)
  images (both with a lot of software preinstalled).
- You can access the Linux VM via SSH: [https://www.appveyor.com/docs/getting-started-with-appveyor-for-linux/#accessing-build-vm-via-ssh](https://www.appveyor.com/docs/getting-started-with-appveyor-for-linux/#accessing-build-vm-via-ssh).
  You can also [access Windows build](https://www.appveyor.com/docs/how-to/rdp-to-build-worker/)
  (via RDP).

AppVeyor was mainly focused on Windows builds, but recently they announced the
Linux build support (which is now in [beta](https://www.appveyor.com/docs/getting-started-with-appveyor-for-linux/#running-your-build-on-linux)
phase). Anyway, the possibility of using Ubuntu Xenial 16.04 (compared to old
Ubuntu Trusty 14.04 in Travis) and SSH access to the VM makes it really
interesting for CI.

I decided to try to use minikube with AppVeyor - so here is `.appveyor.yml`
sample:

```yaml
image: ubuntu

build_script:
  # Download and install minikube
  # Download kubectl, which is a requirement for using minikube
  - curl -sL https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl -o kubectl
  - chmod +x kubectl
  - sudo mv kubectl /usr/local/bin/
  # Download minikube
  - curl -sL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o minikube
  - chmod +x minikube
  - sudo mv minikube /usr/local/bin/
  - sudo CHANGE_MINIKUBE_NONE_USER=true minikube start --vm-driver=none --memory=4096
  # Wait for Kubernetes to be up and ready (https://web.archive.org/web/20171213061419/https://blog.travis-ci.com/2017-10-26-running-kubernetes-on-travis-ci-with-minikube)
  - JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
  # Run commands
  - kubectl get nodes
  - kubectl get pods --all-namespaces
```

Real example:

- Github repository: [https://github.com/ruzickap/multinode_kubernetes_cluster](https://github.com/ruzickap/multinode_kubernetes_cluster)
- AppVeyor pipeline: [https://ci.appveyor.com/project/ruzickap/multinode-kubernetes-cluster](https://ci.appveyor.com/project/ruzickap/multinode-kubernetes-cluster)

Maybe if you need to test some Kubernetes commands / scripts / etc... you can
use minikube and AppVeyor...

Enjoy :-)
