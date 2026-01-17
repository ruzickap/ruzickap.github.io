---
title: Setup production ready Kubernetes cluster using Kubespray and Vagrant running on the libvirt KVMs
author: Petr Ruzicka
date: 2017-11-02
description: Setup production ready Kubernetes cluster using Kubespray and Vagrant running on the libvirt KVMs
categories: [Virtualization, Vagrant]
tags: [kubespray, minikube, pods, etcd, master]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2017/11/setup-production-ready-kubernetes.html)
{: .prompt-info }

If you are creating some Docker containers - sooner or later you will work with
Kubernetes to automate deploying, scaling, and operating application containers.
If you need to simply run Kubernetes, there is a project called
[Minikube](https://github.com/kubernetes/minikube) which can help you set up a
single VM with Kubernetes. This is probably the best way to start with it.

Sometimes it's handy to have "production ready" Kubernetes cluster running on
your laptop containing multiple VMs (like in a real production environment) -
that's
where you need to look around and search for another solution.

After trying a few tools I decided to use
[Kubespray](https://github.com/kubernetes-incubator/kubespray). It's a tool for
deploying a production ready Kubernetes cluster on AWS, GCE, Azure, OpenStack or
Baremetal.

I'm fine to create a few virtual machines (using
[Vagrant](https://www.vagrantup.com/)) on my laptop and install Kubernetes
there.

![image](https://github.com/kubernetes/kubernetes/raw/master/logo/logo.png)

I'll use 3 VMs, all 3 have etcd installed, all 3 are nodes (running pods), 2 of
them run master components:

![image](https://s32.postimg.org/8q7gns8ut/3nodes.png)

(you can use more VMs with more advanced setup:
<https://github.com/kubespray/kubespray-cli>)

Let's see how you can do it in Fedora 26 using Vagrant + libvirt + Kubespray +
Kubespray-cli.

- Install Vagrant VMs + libvirt and the Vagrantfile template for building the

VMs

```bash
# Install Vagrant libvirt plugin (with all the dependencies like qemu, libvirt, vagrant, ...)
dnf install -y -q ansible git libvirt-client libvirt-nss python-netaddr python-virtualenv vagrant-libvirt
vagrant plugin install vagrant-libvirt

# Enable dns resolution of VMs taken from libvirt (https://lukas.zapletalovi.com/2017/10/definitive-solution-to-libvirt-guest-naming.html)
sed -i.orig 's/files dns myhostname/files libvirt libvirt_guest dns myhostname/' /etc/nsswitch.conf

# Start the libvirt daemon
service libvirtd start

# Create ssh key if it doesn't exist
test -f ~/.ssh/id_rsa.pub || ssh-keygen -f $HOME/.ssh/id_rsa -N ''

# Create directory structure
mkdir /var/tmp/kubernetes_cluster
cd /var/tmp/kubernetes_cluster

# Create Vagrantfile
cat > Vagrantfile << EOF
box_image = "peru/my_ubuntu-16.04-server-amd64"
node_count = 4
ssh_pub_key = File.readlines("#{Dir.home}/.ssh/id_rsa.pub").first.strip

Vagrant.configure(2) do |config|
  config.vm.synced_folder ".", "/vagrant", :disabled => true
  config.vm.box = box_image

  config.vm.provider :libvirt do |domain|
    domain.cpus = 2
    domain.memory = 2048
    domain.default_prefix = ''
  end

  (1..node_count).each do |i|
    config.vm.define "kube0#{i}" do |config|
      config.vm.hostname = "kube0#{i}"
    end
  end

  config.vm.provision 'shell', inline: "install -m 0700 -d /root/.ssh/; echo #{ssh_pub_key} >> /root/.ssh/authorized_keys; chmod 0600 /root/.ssh/authorized_keys"
  config.vm.provision 'shell', inline: "echo #{ssh_pub_key} >> /home/vagrant/.ssh/authorized_keys", privileged: false
end
EOF

# Create and start virtual machines
vagrant up
```

- Create Python's Virtualenv for kubespray and start the Kubernetes cluster
provisioning

```bash
# Create Virtual env for Kubespray and make it active
virtualenv --system-site-packages kubespray_virtenv
source kubespray_virtenv/bin/activate

# Install Ansible and Kubespray to virtualenv
pip install kubespray

# Create kubespray config file
cat > ~/.kubespray.yml << EOF
kubespray_git_repo: "https://github.com/kubespray/kubespray.git"
kubespray_path: "$PWD/kubespray"
loglevel: "info"
EOF

# Prepare kubespray for deployment
kubespray prepare --assumeyes --path $PWD/kubespray --nodes kubernetes_cluster_kube01 kubernetes_cluster_kube02 kubernetes_cluster_kube03 kubernetes_cluster_kube04

cat > kubespray/inventory/inventory.cfg << EOF
[kube-master]
kube01
kube02

[all]
kube01
kube02
kube03
kube04

[k8s-cluster:children]
kube-node
kube-master

[kube-node]
kube01
kube02
kube03
kube04

[etcd]
kube01
kube02
kube03
EOF

# Set password for kube user
test -d kubespray/credentials || mkdir kubespray/credentials
echo "kube123" > kubespray/credentials/kube_user

# Deploy Kubernetes cluster
kubespray deploy --assumeyes --user root --apps efk helm netchecker
```

After the deployment is over you should be able to login to one of the master
node and run + see something like:

```bash
root@kube01:~# kubectl get nodes
NAME      STATUS    ROLES         AGE       VERSION
kube01    Ready     master,node   7m        v1.8.3+coreos.0
kube02    Ready     master,node   7m        v1.8.3+coreos.0
kube03    Ready     node          7m        v1.8.3+coreos.0
kube04    Ready     node          7m        v1.8.3+coreos.0


root@kube01:~# kubectl get componentstatuses
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-0               Healthy   {"health": "true"}
etcd-1               Healthy   {"health": "true"}
etcd-2               Healthy   {"health": "true"}


root@kube01:~# kubectl get daemonSets --all-namespaces
NAMESPACE     NAME                       DESIRED   CURRENT   READY     UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
default       netchecker-agent           4         4         4         4            4           <none>          3m
default       netchecker-agent-hostnet   4         4         4         4            4           <none>          3m
kube-system   calico-node                4         4         4         4            4           <none>          5m
kube-system   fluentd-es-v1.22           4         4         4         4            4           <none>          3m


root@kube01:~# kubectl get deployments --all-namespaces
NAMESPACE     NAME                       DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
default       netchecker-server          1         1         1            1           3m
kube-system   elasticsearch-logging-v1   2         2         2            2           3m
kube-system   kibana-logging             1         1         1            0           3m
kube-system   kube-dns                   2         2         2            2           4m
kube-system   kubedns-autoscaler         1         1         1            1           4m
kube-system   kubernetes-dashboard       1         1         1            1           3m
kube-system   tiller-deploy              1         1         1            1           2m


root@kube01:~# kubectl get services --all-namespaces
NAMESPACE     NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
default       kubernetes              ClusterIP   10.233.0.1      <none>        443/TCP          7m
default       netchecker-service      NodePort    10.233.52.117   <none>        8081:31081/TCP   3m
kube-system   elasticsearch-logging   ClusterIP   10.233.50.47    <none>        9200/TCP         3m
kube-system   kibana-logging          ClusterIP   10.233.55.77    <none>        5601/TCP         3m
kube-system   kube-dns                ClusterIP   10.233.0.3      <none>        53/UDP,53/TCP    4m
kube-system   kubernetes-dashboard    ClusterIP   10.233.23.217   <none>        80/TCP           3m
kube-system   tiller-deploy           ClusterIP   10.233.2.129    <none>        44134/TCP        2m


root@kube01:/home/vagrant# kubectl describe nodes
Name:               kube01
Roles:              master,node
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/hostname=kube01
                    node-role.kubernetes.io/master=true
                    node-role.kubernetes.io/node=true
Annotations:        alpha.kubernetes.io/provided-node-ip=192.168.121.170
                    node.alpha.kubernetes.io/ttl=0
                    volumes.kubernetes.io/controller-managed-attach-detach=true
Taints:             <none>
CreationTimestamp:  Fri, 01 Dec 2017 07:48:12 +0000
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  OutOfDisk        False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:12 +0000   KubeletHasSufficientDisk     kubelet has sufficient disk space available
  MemoryPressure   False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:12 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:12 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  Ready            True    Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:49:23 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  192.168.121.170
  Hostname:    kube01
Capacity:
 cpu:     2
 memory:  2048056Ki
 pods:    110
Allocatable:
 cpu:     1800m
 memory:  1445656Ki
 pods:    110
System Info:
 Machine ID:                 b16219f793e6953e4cc3a6375a15800f
 System UUID:                6CF15F25-6F3A-4AE9-B1DA-417C5F7AEB4B
 Boot ID:                    e696a205-9686-42cf-b126-e127e1125e08
 Kernel Version:             4.4.0-101-generic
 OS Image:                   Ubuntu 16.04.3 LTS
 Operating System:           linux
 Architecture:               amd64
 Container Runtime Version:  docker://Unknown
 Kubelet Version:            v1.8.3+coreos.0
 Kube-Proxy Version:         v1.8.3+coreos.0
ExternalID:                  kube01
Non-terminated Pods:         (8 in total)
  Namespace                  Name                              CPU Requests  CPU Limits  Memory Requests  Memory Limits
  ---------                  ----                              ------------  ----------  ---------------  -------------
  default                    netchecker-agent-hostnet-5wzdd    15m (0%)      30m (1%)    64M (4%)         100M (6%)
  default                    netchecker-agent-zc2wv            15m (0%)      30m (1%)    64M (4%)         100M (6%)
  kube-system                calico-node-kmfz7                 150m (8%)     300m (16%)  64M (4%)         500M (33%)
  kube-system                fluentd-es-v1.22-zsh42            100m (5%)     0 (0%)      200Mi (14%)      200Mi (14%)
  kube-system                kube-apiserver-kube01             100m (5%)     800m (44%)  256M (17%)       2G (135%)
  kube-system                kube-controller-manager-kube01    100m (5%)     250m (13%)  100M (6%)        512M (34%)
  kube-system                kube-proxy-kube01                 150m (8%)     500m (27%)  64M (4%)         2G (135%)
  kube-system                kube-scheduler-kube01             80m (4%)      250m (13%)  170M (11%)       512M (34%)
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  CPU Requests  CPU Limits    Memory Requests  Memory Limits
  ------------  ----------    ---------------  -------------
  710m (39%)    2160m (120%)  991715200 (66%)  5933715200 (400%)
Events:
  Type    Reason                   Age                From             Message
  ----    ------                   ----               ----             -------
  Normal  NodeAllocatableEnforced  12m                kubelet, kube01  Updated Node Allocatable limit across pods
  Normal  NodeHasSufficientDisk    12m (x8 over 12m)  kubelet, kube01  Node kube01 status is now: NodeHasSufficientDisk
  Normal  NodeHasSufficientMemory  12m (x7 over 12m)  kubelet, kube01  Node kube01 status is now: NodeHasSufficientMemory
  Normal  NodeHasNoDiskPressure    12m (x8 over 12m)  kubelet, kube01  Node kube01 status is now: NodeHasNoDiskPressure


Name:               kube02
Roles:              master,node
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/hostname=kube02
                    node-role.kubernetes.io/master=true
                    node-role.kubernetes.io/node=true
Annotations:        alpha.kubernetes.io/provided-node-ip=192.168.121.99
                    node.alpha.kubernetes.io/ttl=0
                    volumes.kubernetes.io/controller-managed-attach-detach=true
Taints:             <none>
CreationTimestamp:  Fri, 01 Dec 2017 07:48:18 +0000
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  OutOfDisk        False   Fri, 01 Dec 2017 08:00:11 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasSufficientDisk     kubelet has sufficient disk space available
  MemoryPressure   False   Fri, 01 Dec 2017 08:00:11 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Fri, 01 Dec 2017 08:00:11 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  Ready            True    Fri, 01 Dec 2017 08:00:11 +0000   Fri, 01 Dec 2017 07:49:19 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  192.168.121.99
  Hostname:    kube02
Capacity:
 cpu:     2
 memory:  2048056Ki
 pods:    110
Allocatable:
 cpu:     1800m
 memory:  1445656Ki
 pods:    110
System Info:
 Machine ID:                 b16219f793e6953e4cc3a6375a15800f
 System UUID:                1D8EF759-33F1-42B0-9F47-49877BCD971A
 Boot ID:                    c5de3f75-d7c6-4c01-8c98-24dad24e6e8a
 Kernel Version:             4.4.0-101-generic
 OS Image:                   Ubuntu 16.04.3 LTS
 Operating System:           linux
 Architecture:               amd64
 Container Runtime Version:  docker://Unknown
 Kubelet Version:            v1.8.3+coreos.0
 Kube-Proxy Version:         v1.8.3+coreos.0
ExternalID:                  kube02
Non-terminated Pods:         (8 in total)
  Namespace                  Name                              CPU Requests  CPU Limits  Memory Requests  Memory Limits
  ---------                  ----                              ------------  ----------  ---------------  -------------
  default                    netchecker-agent-hostnet-5ff9f    15m (0%)      30m (1%)    64M (4%)         100M (6%)
  default                    netchecker-agent-mdgnj            15m (0%)      30m (1%)    64M (4%)         100M (6%)
  kube-system                calico-node-rh9pp                 150m (8%)     300m (16%)  64M (4%)         500M (33%)
  kube-system                fluentd-es-v1.22-d7j4w            100m (5%)     0 (0%)      200Mi (14%)      200Mi (14%)
  kube-system                kube-apiserver-kube02             100m (5%)     800m (44%)  256M (17%)       2G (135%)
  kube-system                kube-controller-manager-kube02    100m (5%)     250m (13%)  100M (6%)        512M (34%)
  kube-system                kube-proxy-kube02                 150m (8%)     500m (27%)  64M (4%)         2G (135%)
  kube-system                kube-scheduler-kube02             80m (4%)      250m (13%)  170M (11%)       512M (34%)
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  CPU Requests  CPU Limits    Memory Requests  Memory Limits
  ------------  ----------    ---------------  -------------
  710m (39%)    2160m (120%)  991715200 (66%)  5933715200 (400%)
Events:
  Type    Reason                   Age                From             Message
  ----    ------                   ----               ----             -------
  Normal  Starting                 12m                kubelet, kube02  Starting kubelet.
  Normal  NodeAllocatableEnforced  12m                kubelet, kube02  Updated Node Allocatable limit across pods
  Normal  NodeHasSufficientDisk    12m (x8 over 12m)  kubelet, kube02  Node kube02 status is now: NodeHasSufficientDisk
  Normal  NodeHasSufficientMemory  12m (x8 over 12m)  kubelet, kube02  Node kube02 status is now: NodeHasSufficientMemory
  Normal  NodeHasNoDiskPressure    12m (x7 over 12m)  kubelet, kube02  Node kube02 status is now: NodeHasNoDiskPressure


Name:               kube03
Roles:              node
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/hostname=kube03
                    node-role.kubernetes.io/node=true
Annotations:        alpha.kubernetes.io/provided-node-ip=192.168.121.183
                    node.alpha.kubernetes.io/ttl=0
                    volumes.kubernetes.io/controller-managed-attach-detach=true
Taints:             <none>
CreationTimestamp:  Fri, 01 Dec 2017 07:48:18 +0000
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  OutOfDisk        False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasSufficientDisk     kubelet has sufficient disk space available
  MemoryPressure   False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:48:18 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  Ready            True    Fri, 01 Dec 2017 08:00:15 +0000   Fri, 01 Dec 2017 07:49:20 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  192.168.121.183
  Hostname:    kube03
Capacity:
 cpu:     2
 memory:  2048056Ki
 pods:    110
Allocatable:
 cpu:     1900m
 memory:  1695656Ki
 pods:    110
System Info:
 Machine ID:                 b16219f793e6953e4cc3a6375a15800f
 System UUID:                D77B14AC-6257-4B9F-A8B7-20870539CFC3
 Boot ID:                    7c6a422b-23d5-424a-b41a-76965bdd6e4d
 Kernel Version:             4.4.0-101-generic
 OS Image:                   Ubuntu 16.04.3 LTS
 Operating System:           linux
 Architecture:               amd64
 Container Runtime Version:  docker://Unknown
 Kubelet Version:            v1.8.3+coreos.0
 Kube-Proxy Version:         v1.8.3+coreos.0
ExternalID:                  kube03
Non-terminated Pods:         (11 in total)
  Namespace                  Name                                        CPU Requests  CPU Limits  Memory Requests  Memory Limits
  ---------                  ----                                        ------------  ----------  ---------------  -------------
  default                    netchecker-agent-hostnet-qn246              15m (0%)      30m (1%)    64M (3%)         100M (5%)
  default                    netchecker-agent-tnhvb                      15m (0%)      30m (1%)    64M (3%)         100M (5%)
  default                    netchecker-server-77b8944dc-5zrk7           50m (2%)      100m (5%)   64M (3%)         256M (14%)
  kube-system                calico-node-wk69p                           150m (7%)     300m (15%)  64M (3%)         500M (28%)
  kube-system                elasticsearch-logging-v1-dbf5df58b-v5987    100m (5%)     1 (52%)     0 (0%)           0 (0%)
  kube-system                fluentd-es-v1.22-g6ckh                      100m (5%)     0 (0%)      200Mi (12%)      200Mi (12%)
  kube-system                kibana-logging-649489c8bb-76qgn             100m (5%)     100m (5%)   0 (0%)           0 (0%)
  kube-system                kube-dns-cf9d8c47-2rr88                     260m (13%)    0 (0%)      110Mi (6%)       170Mi (10%)
  kube-system                kube-proxy-kube03                           150m (7%)     500m (26%)  64M (3%)         2G (115%)
  kube-system                kubedns-autoscaler-86c47697df-jwk6l         20m (1%)      0 (0%)      10Mi (0%)        0 (0%)
  kube-system                nginx-proxy-kube03                          25m (1%)      300m (15%)  32M (1%)         512M (29%)
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  CPU Requests  CPU Limits    Memory Requests  Memory Limits
  ------------  ----------    ---------------  -------------
  985m (51%)    2360m (124%)  687544320 (39%)  3855973120 (222%)
Events:
  Type    Reason                   Age                From                Message
  ----    ------                   ----               ----                -------
  Normal  Starting                 12m                kubelet, kube03     Starting kubelet.
  Normal  NodeAllocatableEnforced  12m                kubelet, kube03     Updated Node Allocatable limit across pods
  Normal  NodeHasSufficientDisk    12m (x8 over 12m)  kubelet, kube03     Node kube03 status is now: NodeHasSufficientDisk
  Normal  NodeHasSufficientMemory  12m (x8 over 12m)  kubelet, kube03     Node kube03 status is now: NodeHasSufficientMemory
  Normal  NodeHasNoDiskPressure    12m (x7 over 12m)  kubelet, kube03     Node kube03 status is now: NodeHasNoDiskPressure
  Normal  Starting                 12m                kube-proxy, kube03  Starting kube-proxy.


Name:               kube04
Roles:              node
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/hostname=kube04
                    node-role.kubernetes.io/node=true
Annotations:        alpha.kubernetes.io/provided-node-ip=192.168.121.92
                    node.alpha.kubernetes.io/ttl=0
                    volumes.kubernetes.io/controller-managed-attach-detach=true
Taints:             <none>
CreationTimestamp:  Fri, 01 Dec 2017 07:48:17 +0000
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  OutOfDisk        False   Fri, 01 Dec 2017 08:00:12 +0000   Fri, 01 Dec 2017 07:48:17 +0000   KubeletHasSufficientDisk     kubelet has sufficient disk space available
  MemoryPressure   False   Fri, 01 Dec 2017 08:00:12 +0000   Fri, 01 Dec 2017 07:48:17 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Fri, 01 Dec 2017 08:00:12 +0000   Fri, 01 Dec 2017 07:48:17 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  Ready            True    Fri, 01 Dec 2017 08:00:12 +0000   Fri, 01 Dec 2017 07:49:18 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  192.168.121.92
  Hostname:    kube04
Capacity:
 cpu:     2
 memory:  2048056Ki
 pods:    110
Allocatable:
 cpu:     1900m
 memory:  1695656Ki
 pods:    110
System Info:
 Machine ID:                 b16219f793e6953e4cc3a6375a15800f
 System UUID:                6DC8CDBF-7D48-4E25-A6D7-E5803A18A59C
 Boot ID:                    3ea8882e-bf05-4e26-8028-ffa54638e562
 Kernel Version:             4.4.0-101-generic
 OS Image:                   Ubuntu 16.04.3 LTS
 Operating System:           linux
 Architecture:               amd64
 Container Runtime Version:  docker://Unknown
 Kubelet Version:            v1.8.3+coreos.0
 Kube-Proxy Version:         v1.8.3+coreos.0
ExternalID:                  kube04
Non-terminated Pods:         (10 in total)
  Namespace                  Name                                        CPU Requests  CPU Limits  Memory Requests  Memory Limits
  ---------                  ----                                        ------------  ----------  ---------------  -------------
  default                    netchecker-agent-hostnet-kr6pn              15m (0%)      30m (1%)    64M (3%)         100M (5%)
  default                    netchecker-agent-mtqnz                      15m (0%)      30m (1%)    64M (3%)         100M (5%)
  kube-system                calico-node-2sjrc                           150m (7%)     300m (15%)  64M (3%)         500M (28%)
  kube-system                elasticsearch-logging-v1-dbf5df58b-dk9vq    100m (5%)     1 (52%)     0 (0%)           0 (0%)
  kube-system                fluentd-es-v1.22-kg6zc                      100m (5%)     0 (0%)      200Mi (12%)      200Mi (12%)
  kube-system                kube-dns-cf9d8c47-qkp4j                     260m (13%)    0 (0%)      110Mi (6%)       170Mi (10%)
  kube-system                kube-proxy-kube04                           150m (7%)     500m (26%)  64M (3%)         2G (115%)
  kube-system                kubernetes-dashboard-7fd45476f8-fl9sj       50m (2%)      100m (5%)   64M (3%)         256M (14%)
  kube-system                nginx-proxy-kube04                          25m (1%)      300m (15%)  32M (1%)         512M (29%)
  kube-system                tiller-deploy-546cf9696c-x9pgt              0 (0%)        0 (0%)      0 (0%)           0 (0%)
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  CPU Requests  CPU Limits    Memory Requests  Memory Limits
  ------------  ----------    ---------------  -------------
  865m (45%)    2260m (118%)  677058560 (38%)  3855973120 (222%)
Events:
  Type    Reason                   Age                From             Message
  ----    ------                   ----               ----             -------
  Normal  Starting                 12m                kubelet, kube04  Starting kubelet.
  Normal  NodeAllocatableEnforced  12m                kubelet, kube04  Updated Node Allocatable limit across pods
  Normal  NodeHasSufficientDisk    12m (x8 over 12m)  kubelet, kube04  Node kube04 status is now: NodeHasSufficientDisk
  Normal  NodeHasSufficientMemory  12m (x8 over 12m)  kubelet, kube04  Node kube04 status is now: NodeHasSufficientMemory
  Normal  NodeHasNoDiskPressure    12m (x7 over 12m)  kubelet, kube04  Node kube04 status is now: NodeHasNoDiskPressure
```

Then you can work with the Kubernetes Cluster like usual...

You can see the whole installation here:

Some parts mentioned above are specific to Fedora 26, but most of it can be
achievable on the other distros.

Enjoy ;-)
