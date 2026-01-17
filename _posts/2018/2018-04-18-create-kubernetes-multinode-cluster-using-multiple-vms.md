---
title: Create Kubernetes Multinode Cluster using multiple VMs
author: Petr Ruzicka
date: 2018-04-18
description: Create Kubernetes Multinode Cluster using multiple VMs
categories: [Kubernetes]
tags: [multinode, cluster, installation, kubespray, kubeadm]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2018/04/create-kubernetes-multinode-cluster.html)
{: .prompt-info }

If you need to run a single-node Kubernetes cluster for testing then
[minikube][minikube] is your choice.

[minikube]: https://kubernetes.io/docs/getting-started-guides/minikube/

But sometimes you need to run tests on a multinode cluster running on
multiple VMs.

There are many ways to install a Kubernetes Multinode Cluster but I chose
these projects [kubeadm](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/)
and [kubespray](https://kubespray.io/).

![Kubernetes logo](https://github.com/kubernetes/kubernetes/raw/master/logo/logo.png)

- Kubespray is handy for enterprise installations where HA is a must, but it
  can be used for standard testing if you have [Ansible](https://www.ansible.com/)
  installed.

- Kubeadm is the official tool for Kubernetes installation, but it needs more
  love when you want to use it in enterprise to configure HA.

Let's look at these two projects to see how "easy" it is to install Kubernetes
to multiple nodes (VMs):

## Kubeadm

Here are the steps:

```bash
### Master node installation

# SSH to the first VM which will be your Master node:
ssh root@node1

# Set the Kubernetes version which will be installed:
KUBERNETES_VERSION="1.10.0"

# Set the proper CNI URL:
CNI_URL="https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml"

# For Flannel installation you need to use proper "pod-network-cidr":
POD_NETWORK_CIDR="10.244.0.0/16"

# Add the Kubernetes repository (details):
apt-get update -qq && apt-get install -y -qq apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
tee /etc/apt/sources.list.d/kubernetes.list << EOF2
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF2

# Install necessary packages:
apt-get update -qq
apt-get install -y -qq docker.io kubelet=${KUBERNETES_VERSION}-00 kubeadm=${KUBERNETES_VERSION}-00 kubectl=${KUBERNETES_VERSION}-00

# Install Kubernetes Master:
kubeadm init --pod-network-cidr=$POD_NETWORK_CIDR --kubernetes-version v${KUBERNETES_VERSION}

# Copy the "kubectl" config files to the home directory:
test -d "$HOME/.kube" || mkdir "$HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown -R "$USER:$USER" "$HOME/.kube"

# Install CNI:
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f $CNI_URL

# Your Kuberenets Master node should be ready now. You can check it using this command:
kubectl get nodes

### Worker nodes installation

# Let's connect the worker nodes now

# SSH to the worker nodes and repeat these commands on all of them in parallel:

ssh root@node2
ssh root@node3
ssh root@node4

# Set the Kubernetes version which will be installed:
KUBERNETES_VERSION="1.10.0"

# Add the Kubernetes repository (details):
apt-get update -qq && apt-get install -y -qq apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
tee /etc/apt/sources.list.d/kubernetes.list << EOF2
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF2

# Install necessary packages:
apt-get update -qq
apt-get install -y -qq docker.io kubelet=${KUBERNETES_VERSION}-00 kubeadm=${KUBERNETES_VERSION}-00 kubectl=${KUBERNETES_VERSION}-00
exit

# All the worker nodes are prepared now - let's connect them to master node.
# SSH to the master node again and generate the "joining" command:

ssh root@node1 "kubeadm token create --print-join-command"

# You should see something like:
# -> kubeadm join <master-ip>:<master-port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Execute the generated command on all worker nodes...
ssh -t root@node2 "kubeadm join --token ... ... ... ... ... ..."
ssh -t root@node3 "kubeadm join --token ... ... ... ... ... ..."
ssh -t root@node4 "kubeadm join --token ... ... ... ... ... ..."

# SSH back to the master nodes and check the cluster status - all the nodes should appear there in "Ready" status after while.
ssh root@node1
# Check nodes
kubectl get nodes
```

[![asciicast](https://asciinema.org/a/176954.svg)](https://asciinema.org/a/176954)

If you want to do it quickly with creating the VMs in Linux you can use this
script:

[https://github.com/ruzickap/multinode_kubernetes_cluster/blob/master/run-kubeadm.sh](https://github.com/ruzickap/multinode_kubernetes_cluster/blob/master/run-kubeadm.sh)

It will create 4 VMs using Vagrant (you should have these vagrant plugins
installed: vagrant-libvirt + vagrant-hostmanager) and install Kubernetes using
kubeadm.

[![asciicast](https://asciinema.org/a/176939.svg)](https://asciinema.org/a/176939)

## Kubespray

Kubernetes installation with Kubespray is little bit more complicated. Instead
of writing it here I'll point you to another script which you can use for it's
automation:

[https://github.com/ruzickap/multinode_kubernetes_cluster/blob/master/run-kubespray.sh](https://github.com/ruzickap/multinode_kubernetes_cluster/blob/master/run-kubespray.sh)

It will create 4 VMs using Vagrant (you should have these vagrant plugins
installed: vagrant-libvirt + vagrant-hostmanager) and install Kubernetes using
kubespray+ansible.

[![asciicast](https://asciinema.org/a/176949.svg)](https://asciinema.org/a/176949)

Enjoy... :-)
