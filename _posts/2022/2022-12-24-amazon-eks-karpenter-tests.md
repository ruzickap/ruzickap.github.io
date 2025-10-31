---
title: Amazon EKS - Karpenter tests
author: Petr Ruzicka
date: 2022-12-24
description: Run Amazon EKS and create workloads for Karpenter
categories: [Kubernetes, Amazon EKS, Karpenter]
tags: [Amazon EKS, k8s, kubernetes, karpenter, eksctl]
image: https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png
---

In the previous post,
"[Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})",
I described installing [Karpenter](https://karpenter.sh/) to improve the
efficiency and cost-effectiveness of running workloads on the cluster.

Many articles describe what Karpenter is, how it works, and the benefits of
using it.

Here are a few notes from my testing, demonstrating how it works with
real-world examples.

## Requirements

- An Amazon EKS cluster with Karpenter configured as described in
  "[Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})"
- [Helm](https://helm.sh)

The following variables are used in the subsequent steps:

```bash
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

## Install tools

Install the following handy tools:

- [eks-node-viewer](https://github.com/awslabs/eks-node-viewer)
- [viewnode](https://github.com/NTTDATA-DACH/viewnode)
- [kubectl-view-allocations](https://github.com/davidB/kubectl-view-allocations)
- [kube-capacity](https://github.com/robscott/kube-capacity)

```bash
ARCH="amd64"
curl -sL "https://github.com/kubernetes-sigs/krew/releases/download/v0.4.5/krew-linux_${ARCH}.tar.gz" | tar -xvzf - -C "${TMP_DIR}" --no-same-owner --strip-components=1 --wildcards "*/krew-linux*"
"${TMP_DIR}/krew-linux_${ARCH}" install krew
rm "${TMP_DIR}/krew-linux_${ARCH}"
export PATH="${HOME}/.krew/bin:${PATH}"
kubectl krew install resource-capacity view-allocations viewnode
```

## Workloads

Let's run some example workloads to observe how [Karpenter](https://karpenter.sh/)
functions.

### Consolidation example

Start `amd64` [nginx](https://hub.docker.com/_/nginx) pods in the
`test-karpenter` namespace:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-deployment-nginx.yml" << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: test-karpenter
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: test-karpenter
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: 500m
            memory: 16Mi
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: managedBy
                operator: In
                values:
                - karpenter
              - key: provisioner
                operator: In
                values:
                - default
      nodeSelector:
        kubernetes.io/arch: amd64
EOF

kubectl wait --for=condition=Available=True --timeout=5m --namespace=test-karpenter deployment nginx-deployment
```

Karpenter will start a new `t3a.small` spot EC2 instance
`ip-192-168-66-142.ec2.internal`:

![eks-node-viewer](/assets/img/posts/2022/2022-12-24-amazon-eks-karpenter-tests/eks-node-viewer-nginx-01-replicas-2.avif)

```bash
kubectl view-allocations --namespace test-karpenter --utilization --resource-name=memory --resource-name=cpu
```

```console
 Resource                                 Utilization    Requested  Limit  Allocatable    Free
  cpu                                     (3%) 194.0m    (17%) 1.0     __          5.8     4.8
  ├─ ip-192-168-14-250.ec2.internal                __           __     __          1.9      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __          1.9      __
  └─ ip-192-168-66-142.ec2.internal         (0%) 2.0m    (52%) 1.0     __          1.9  930.0m
     ├─ nginx-deployment-589b44547-6k82l         1.0m       500.0m     __           __      __
     └─ nginx-deployment-589b44547-ssp97         1.0m       500.0m     __           __      __
  memory                                  (20%) 1.5Gi  (0%) 32.0Mi     __        7.9Gi   7.9Gi
  ├─ ip-192-168-14-250.ec2.internal                __           __     __        3.2Gi      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __        3.2Gi      __
  └─ ip-192-168-66-142.ec2.internal        (0%) 5.3Mi  (2%) 32.0Mi     __        1.5Gi   1.4Gi
     ├─ nginx-deployment-589b44547-6k82l        2.6Mi       16.0Mi     __           __      __
     └─ nginx-deployment-589b44547-ssp97        2.7Mi       16.0Mi     __           __      __
```

Karpenter logs:

```bash
kubectl logs -n karpenter --since=2m -l app.kubernetes.io/name=karpenter
```

Outputs:

```console
...
2023-01-29T18:35:16.902Z  DEBUG  controller.provisioner  390 out of 599 instance types were excluded because they would breach provisioner limits  {"commit": "5a7faa0-dirty"}
2023-01-29T18:35:16.905Z  INFO  controller.provisioner  found provisionable pod(s)  {"commit": "5a7faa0-dirty", "pods": 2}
2023-01-29T18:35:16.905Z  INFO  controller.provisioner  computed new node(s) to fit pod(s)  {"commit": "5a7faa0-dirty", "newNodes": 1, "pods": 2}
2023-01-29T18:35:16.905Z  INFO  controller.provisioner  launching node with 2 pods requesting {"cpu":"1155m","memory":"152Mi","pods":"7"} from types t3a.xlarge, t3a.2xlarge, t3a.small, t3a.medium, t3a.large  {"commit": "5a7faa0-dirty", "provisioner": "default"}
2023-01-29T18:35:17.352Z  DEBUG  controller.provisioner.cloudprovider  created launch template  {"commit": "5a7faa0-dirty", "provisioner": "default", "launch-template-name": "Karpenter-k01-2845501446139737819", "launch-template-id": "lt-0a4dbdf22b4e80f45"}
2023-01-29T18:35:19.382Z  INFO  controller.provisioner.cloudprovider  launched new instance  {"commit": "5a7faa0-dirty", "provisioner": "default", "id": "i-059d06b02509680a0", "hostname": "ip-192-168-66-142.ec2.internal", "instance-type": "t3a.small", "zone": "us-east-1a", "capacity-type": "spot"}
```

Increase the replica count to `5`. This will prompt Karpenter to add a new
spot worker node to run the `3` additional nginx pods:

```bash
kubectl scale deployment nginx-deployment --namespace test-karpenter --replicas 5
kubectl wait --for=condition=Available=True --timeout=5m --namespace test-karpenter deployment nginx-deployment
```

![eks-node-viewer](/assets/img/posts/2022/2022-12-24-amazon-eks-karpenter-tests/eks-node-viewer-nginx-02-replicas-5.avif)

Check the details:

```bash
kubectl view-allocations --namespace test-karpenter --utilization --resource-name=memory --resource-name=cpu
```

```console
 Resource                                 Utilization    Requested  Limit  Allocatable    Free
  cpu                                     (3%) 208.0m    (32%) 2.5     __          7.7     5.2
  ├─ ip-192-168-14-250.ec2.internal                __           __     __          1.9      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __          1.9      __
  ├─ ip-192-168-66-142.ec2.internal         (0%) 3.0m    (78%) 1.5     __          1.9  430.0m
  │  ├─ nginx-deployment-589b44547-6k82l         1.0m       500.0m     __           __      __
  │  ├─ nginx-deployment-589b44547-ssp97         1.0m       500.0m     __           __      __
  │  └─ nginx-deployment-589b44547-x7bvl         1.0m       500.0m     __           __      __
  └─ ip-192-168-94-105.ec2.internal         (0%) 2.0m    (52%) 1.0     __          1.9  930.0m
     ├─ nginx-deployment-589b44547-5jhkb         1.0m       500.0m     __           __      __
     └─ nginx-deployment-589b44547-vjzns         1.0m       500.0m     __           __      __
  memory                                  (18%) 1.7Gi  (1%) 80.0Mi     __        9.4Gi   9.3Gi
  ├─ ip-192-168-14-250.ec2.internal                __           __     __        3.2Gi      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __        3.2Gi      __
  ├─ ip-192-168-66-142.ec2.internal        (1%) 8.0Mi  (3%) 48.0Mi     __        1.5Gi   1.4Gi
  │  ├─ nginx-deployment-589b44547-6k82l        2.6Mi       16.0Mi     __           __      __
  │  ├─ nginx-deployment-589b44547-ssp97        2.7Mi       16.0Mi     __           __      __
  │  └─ nginx-deployment-589b44547-x7bvl        2.7Mi       16.0Mi     __           __      __
  └─ ip-192-168-94-105.ec2.internal        (0%) 5.3Mi  (2%) 32.0Mi     __        1.5Gi   1.4Gi
     ├─ nginx-deployment-589b44547-5jhkb        2.7Mi       16.0Mi     __           __      __
     └─ nginx-deployment-589b44547-vjzns        2.6Mi       16.0Mi     __           __      __
```

Karpenter logs:

```bash
kubectl logs -n karpenter --since=2m -l app.kubernetes.io/name=karpenter
```

Outputs:

```console
...
2023-01-29T18:38:07.389Z  DEBUG  controller.provisioner  391 out of 599 instance types were excluded because they would breach provisioner limits  {"commit": "5a7faa0-dirty"}
2023-01-29T18:38:07.392Z  INFO  controller.provisioner  found provisionable pod(s)  {"commit": "5a7faa0-dirty", "pods": 2}
2023-01-29T18:38:07.392Z  INFO  controller.provisioner  computed new node(s) to fit pod(s)  {"commit": "5a7faa0-dirty", "newNodes": 1, "pods": 2}
2023-01-29T18:38:07.392Z  INFO  controller.provisioner  launching node with 2 pods requesting {"cpu":"1155m","memory":"152Mi","pods":"7"} from types t3a.medium, t3a.large, t3a.xlarge, t3a.2xlarge, t3a.small  {"commit": "5a7faa0-dirty", "provisioner": "default"}
2023-01-29T18:38:09.682Z  INFO  controller.provisioner.cloudprovider  launched new instance  {"commit": "5a7faa0-dirty", "provisioner": "default", "id": "i-008c19ef038857a28", "hostname": "ip-192-168-94-105.ec2.internal", "instance-type": "t3a.small", "zone": "us-east-1a", "capacity-type": "spot"}
```

If the number of replicas is reduced to `3`, Karpenter will determine that the
workload running on two spot nodes can be consolidated onto a single node:

```bash
kubectl scale deployment nginx-deployment --namespace test-karpenter --replicas 3
kubectl wait --for=condition=Available=True --timeout=5m --namespace test-karpenter deployment nginx-deployment
sleep 20
```

![eks-node-viewer](/assets/img/posts/2022/2022-12-24-amazon-eks-karpenter-tests/eks-node-viewer-nginx-03-replicas-3.avif)

Thanks to the [consolidation](https://karpenter.sh/v1.0/concepts/disruption/#consolidation)
feature (described in the
"[AWS re:Invent 2022 - Kubernetes virtually anywhere, for everyone](https://youtu.be/OB7IZolZk78?t=2629)"
talk), the logs will look like this:

```bash
kubectl logs -n karpenter --since=2m -l app.kubernetes.io/name=karpenter
```

```console
...
2023-01-29T18:41:03.918Z  INFO  controller.deprovisioning  deprovisioning via consolidation delete, terminating 1 nodes ip-192-168-66-142.ec2.internal/t3a.small/spot  {"commit": "5a7faa0-dirty"}
2023-01-29T18:41:03.982Z  INFO  controller.termination  cordoned node  {"commit": "5a7faa0-dirty", "node": "ip-192-168-66-142.ec2.internal"}
2023-01-29T18:41:06.715Z  INFO  controller.termination  deleted node  {"commit": "5a7faa0-dirty", "node": "ip-192-168-66-142.ec2.internal"}
```

Check the details:

```bash
kubectl view-allocations --namespace test-karpenter --utilization --resource-name=memory --resource-name=cpu
```

```console
 Resource                                 Utilization    Requested  Limit  Allocatable    Free
  cpu                                     (2%) 121.0m    (26%) 1.5     __          5.8     4.3
  ├─ ip-192-168-14-250.ec2.internal                __           __     __          1.9      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __          1.9      __
  └─ ip-192-168-94-105.ec2.internal         (0%) 3.0m    (78%) 1.5     __          1.9  430.0m
     ├─ nginx-deployment-589b44547-5jhkb         1.0m       500.0m     __           __      __
     ├─ nginx-deployment-589b44547-lnskq         1.0m       500.0m     __           __      __
     └─ nginx-deployment-589b44547-vjzns         1.0m       500.0m     __           __      __
  memory                                  (20%) 1.6Gi  (1%) 48.0Mi     __        7.9Gi   7.9Gi
  ├─ ip-192-168-14-250.ec2.internal                __           __     __        3.2Gi      __
  ├─ ip-192-168-16-172.ec2.internal                __           __     __        3.2Gi      __
  └─ ip-192-168-94-105.ec2.internal        (1%) 8.0Mi  (3%) 48.0Mi     __        1.5Gi   1.4Gi
     ├─ nginx-deployment-589b44547-5jhkb        2.7Mi       16.0Mi     __           __      __
     ├─ nginx-deployment-589b44547-lnskq        2.6Mi       16.0Mi     __           __      __
     └─ nginx-deployment-589b44547-vjzns        2.6Mi       16.0Mi     __           __      __
```

Remove the nginx workload and the `test-karpenter` namespace:

```sh
kubectl delete namespace test-karpenter || true
```

![eks-node-viewer](/assets/img/posts/2022/2022-12-24-amazon-eks-karpenter-tests/eks-node-viewer-nginx-04-delete.avif)

### Simple autoscaling

It would be helpful to document a standard autoscaling example, including all
relevant outputs and logs.

![podinfo](https://raw.githubusercontent.com/stefanprodan/podinfo/a7be119f20369b97f209d220535506af7c49b4ea/screens/podinfo-ui-v3.png){:width="500"}

Install the `podinfo` [Helm chart](https://artifacthub.io/packages/helm/podinfo/podinfo)
and modify its [default values](https://github.com/stefanprodan/podinfo/blob/6.5.4/charts/podinfo/values.yaml):

```bash
# renovate: datasource=helm depName=podinfo registryUrl=https://stefanprodan.github.io/podinfo
PODINFO_HELM_CHART_VERSION="6.5.4"

helm repo add --force-update sp https://stefanprodan.github.io/podinfo
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-podinfo.yml" << EOF
ingress:
  enabled: true
  className: nginx
  annotations:
    forecastle.stakater.com/expose: "true"
    forecastle.stakater.com/icon: https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/cuddle_bunny.gif
    forecastle.stakater.com/appName: Podinfo
  hosts:
    - host: podinfo.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
        - podinfo.${CLUSTER_FQDN}
resources:
  requests:
    cpu: 1
    memory: 16Mi
EOF
helm upgrade --install --version "${PODINFO_HELM_CHART_VERSION}" --namespace podinfo --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-podinfo.yml" podinfo sp/podinfo
```

Check cluster and node details:

```bash
kubectl get nodes -o wide
```

```console
NAME                             STATUS   ROLES    AGE   VERSION               INTERNAL-IP      EXTERNAL-IP     OS-IMAGE                                KERNEL-VERSION   CONTAINER-RUNTIME
ip-192-168-14-250.ec2.internal   Ready    <none>   46h   v1.24.9-eks-4f83af2   192.168.14.250   54.158.242.60   Bottlerocket OS 1.12.0 (aws-k8s-1.24)   5.15.79          containerd://1.6.15+bottlerocket
ip-192-168-16-172.ec2.internal   Ready    <none>   46h   v1.24.9-eks-4f83af2   192.168.16.172   3.90.15.21      Bottlerocket OS 1.12.0 (aws-k8s-1.24)   5.15.79          containerd://1.6.15+bottlerocket
ip-192-168-84-230.ec2.internal   Ready    <none>   79s   v1.24.9-eks-4f83af2   192.168.84.230   <none>          Bottlerocket OS 1.12.0 (aws-k8s-1.24)   5.15.79          containerd://1.6.15+bottlerocket
```

Display details about node instance types and architectures:

```bash
kubectl get nodes -o json | jq -Cjr '.items[] | .metadata.name," ",.metadata.labels."node.kubernetes.io/instance-type"," ",.metadata.labels."kubernetes.io/arch", "\n"' | sort -k2 -r | column -t
```

```console
ip-192-168-84-230.ec2.internal  t4g.small   arm64
ip-192-168-16-172.ec2.internal  t4g.medium  arm64
ip-192-168-14-250.ec2.internal  t4g.medium  arm64
```

View details about node capacity:

```bash
kubectl resource-capacity --sort cpu.util --util --pod-count
```

```console
NODE                             CPU REQUESTS   CPU LIMITS    CPU UTIL     MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL    POD COUNT
*                                3285m (56%)    3500m (60%)   417m (7%)    2410Mi (30%)      6840Mi (85%)    3112Mi (39%)   36/45
ip-192-168-14-250.ec2.internal   715m (37%)     1300m (67%)   299m (15%)   750Mi (22%)       2404Mi (72%)    1635Mi (49%)   17/17
ip-192-168-16-172.ec2.internal   1415m (73%)    1900m (98%)   82m (4%)     1524Mi (46%)      3668Mi (111%)   1024Mi (31%)   13/17
ip-192-168-84-230.ec2.internal   1155m (59%)    300m (15%)    37m (1%)     136Mi (9%)        768Mi (55%)     453Mi (32%)    6/11
```

A graphical view of CPU and memory utilization per node (including pricing
information), produced by [eks-node-viewer](https://github.com/awslabs/eks-node-viewer):

```shell
eks-node-viewer --resources cpu,memory
```

```console
3 nodes 3285m/5790m      56.7% cpu    ███████████████████████░░░░░░░░░░░░░░░░░ 0.067/hour $49.056/month
        2410Mi/8163424Ki 30.2% memory ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░
36 pods (0 pending 36 running 36 bound)

ip-192-168-16-172.ec2.internal cpu    ██████████████████████████░░░░░░░░░  73% (13 pods) t4g.medium/$0.034 On-Demand - Ready
                               memory ████████████████░░░░░░░░░░░░░░░░░░░  46%
ip-192-168-14-250.ec2.internal cpu    █████████████░░░░░░░░░░░░░░░░░░░░░░  37% (17 pods) t4g.medium/$0.034 On-Demand - Ready
                               memory ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░  23%
ip-192-168-84-230.ec2.internal cpu    █████████████████████░░░░░░░░░░░░░░  60% (6 pods)  t4g.small         Spot      - Ready
                               memory ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  10%
```

Other details, produced by [viewnode](https://github.com/NTTDATA-DACH/viewnode):

```bash
kubectl viewnode --all-namespaces --show-metrics
```

```console
36 pod(s) in total
0 unscheduled pod(s)
3 running node(s) with 36 scheduled pod(s):
- ip-192-168-14-250.ec2.internal running 17 pod(s) (linux/arm64/containerd://1.6.15+bottlerocket | mem: 1.6 GiB)
  * external-dns: external-dns-7d5dfdc9bc-dwf2j (running | mem usage: 22.1 MiB)
  * forecastle: forecastle-fd9fbf494-mz78d (running | mem usage: 8.4 MiB)
  * ingress-nginx: ingress-nginx-controller-5c58df8c6f-5qtsj (running | mem usage: 77.9 MiB)
  * kube-prometheus-stack: alertmanager-kube-prometheus-stack-alertmanager-0 (running | mem usage: 20.8 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-kube-state-metrics-75b97d7857-4q29f (running | mem usage: 15.3 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-operator-c4576c8c5-lv9tj (running | mem usage: 33.6 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-grtqf (running | mem usage: 10.1 MiB)
  * kube-prometheus-stack: prometheus-kube-prometheus-stack-prometheus-0 (running | mem usage: 607.1 MiB)
  * kube-system: aws-node-m8bqr (running | mem usage: 30.9 MiB)
  * kube-system: aws-node-termination-handler-4d4vt (running | mem usage: 12.8 MiB)
  * kube-system: ebs-csi-controller-fd8649d65-dzr77 (running | mem usage: 54.8 MiB)
  * kube-system: ebs-csi-node-lnhz4 (running | mem usage: 20.9 MiB)
  * kube-system: kube-proxy-snhd4 (running | mem usage: 13.3 MiB)
  * kube-system: metrics-server-7bf7496f67-hg8dt (running | mem usage: 17.7 MiB)
  * mailhog: mailhog-7fd4cdc758-c6pht (running | mem usage: 4.0 MiB)
  * oauth2-proxy: oauth2-proxy-c74b9b769-7fx6m (running | mem usage: 8.4 MiB)
  * wiz: wiz-kubernetes-connector-broker-5d8fcfdb94-nq2lw (running | mem usage: 6.1 MiB)
- ip-192-168-16-172.ec2.internal running 13 pod(s) (linux/arm64/containerd://1.6.15+bottlerocket | mem: 1.0 GiB)
  * cert-manager: cert-manager-7fb84796f4-mmp7g (running | mem usage: 30.7 MiB)
  * cert-manager: cert-manager-cainjector-7f694c4c58-s5f4s (running | mem usage: 33.8 MiB)
  * cert-manager: cert-manager-webhook-7cd8c769bb-5cr5d (running | mem usage: 11.5 MiB)
  * karpenter: karpenter-7b786469d4-s52fc (running | mem usage: 151.8 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-grafana-b45c4f79-h67r8 (running | mem usage: 221.3 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-gtgv7 (running | mem usage: 9.3 MiB)
  * kube-system: aws-node-4d64v (running | mem usage: 28.0 MiB)
  * kube-system: aws-node-termination-handler-v9jpw (running | mem usage: 12.0 MiB)
  * kube-system: coredns-79989457d9-9bz5s (running | mem usage: 15.8 MiB)
  * kube-system: coredns-79989457d9-pv2gz (running | mem usage: 15.0 MiB)
  * kube-system: ebs-csi-controller-fd8649d65-pllkv (running | mem usage: 56.1 MiB)
  * kube-system: ebs-csi-node-cffz8 (running | mem usage: 19.3 MiB)
  * kube-system: kube-proxy-zvnhr (running | mem usage: 12.2 MiB)
- ip-192-168-84-230.ec2.internal running 6 pod(s) (linux/arm64/containerd://1.6.15+bottlerocket | mem: 454.4 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-pd8qx (running | mem usage: 7.3 MiB)
  * kube-system: aws-node-4c49x (running | mem usage: 24.2 MiB)
  * kube-system: aws-node-termination-handler-dsd64 (running | mem usage: 11.6 MiB)
  * kube-system: ebs-csi-node-s7b85 (running | mem usage: 15.7 MiB)
  * kube-system: kube-proxy-2gblp (running | mem usage: 12.7 MiB)
  * podinfo: podinfo-59d6468db-jmwxh (running | mem usage: 13.4 MiB)
```

Further details, produced by [kubectl-view-allocations](https://github.com/davidB/kubectl-view-allocations):

```bash
kubectl view-allocations --utilization
```

```console
 Resource                                                            Utilization      Requested          Limit  Allocatable     Free
  attachable-volumes-aws-ebs                                                  __             __             __        117.0       __
  ├─ ip-192-168-14-250.ec2.internal                                           __             __             __         39.0       __
  ├─ ip-192-168-16-172.ec2.internal                                           __             __             __         39.0       __
  └─ ip-192-168-84-230.ec2.internal                                           __             __             __         39.0       __
  cpu                                                                (3%) 183.0m      (57%) 3.3      (60%) 3.5          5.8      2.3
  ├─ ip-192-168-14-250.ec2.internal                                  (6%) 122.0m   (37%) 715.0m      (67%) 1.3          1.9   630.0m
  │  ├─ alertmanager-kube-prometheus-stack-alertmanager-0                   2.0m         200.0m         200.0m           __       __
  │  ├─ aws-node-m8bqr                                                      2.0m          25.0m             __           __       __
  │  ├─ aws-node-termination-handler-4d4vt                                  1.0m             __             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-dzr77                                  6.0m          60.0m         600.0m           __       __
  │  ├─ ebs-csi-node-lnhz4                                                  3.0m          30.0m         300.0m           __       __
  │  ├─ external-dns-7d5dfdc9bc-dwf2j                                       1.0m             __             __           __       __
  │  ├─ forecastle-fd9fbf494-mz78d                                          1.0m             __             __           __       __
  │  ├─ ingress-nginx-controller-5c58df8c6f-5qtsj                           1.0m         100.0m             __           __       __
  │  ├─ kube-prometheus-stack-kube-state-metrics-75b97d7857-4q29f           1.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-operator-c4576c8c5-lv9tj                      1.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-grtqf                1.0m             __             __           __       __
  │  ├─ kube-proxy-snhd4                                                    1.0m         100.0m             __           __       __
  │  ├─ mailhog-7fd4cdc758-c6pht                                            1.0m             __             __           __       __
  │  ├─ metrics-server-7bf7496f67-hg8dt                                     3.0m             __             __           __       __
  │  ├─ oauth2-proxy-c74b9b769-7fx6m                                        1.0m             __             __           __       __
  │  ├─ prometheus-kube-prometheus-stack-prometheus-0                      95.0m         200.0m         200.0m           __       __
  │  └─ wiz-kubernetes-connector-broker-5d8fcfdb94-nq2lw                    1.0m             __             __           __       __
  ├─ ip-192-168-16-172.ec2.internal                                   (3%) 50.0m      (73%) 1.4      (98%) 1.9          1.9    30.0m
  │  ├─ aws-node-4d64v                                                      2.0m          25.0m             __           __       __
  │  ├─ aws-node-termination-handler-v9jpw                                  1.0m             __             __           __       __
  │  ├─ cert-manager-7fb84796f4-mmp7g                                       1.0m             __             __           __       __
  │  ├─ cert-manager-cainjector-7f694c4c58-s5f4s                            1.0m             __             __           __       __
  │  ├─ cert-manager-webhook-7cd8c769bb-5cr5d                               1.0m             __             __           __       __
  │  ├─ coredns-79989457d9-9bz5s                                            1.0m         100.0m             __           __       __
  │  ├─ coredns-79989457d9-pv2gz                                            1.0m         100.0m             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-pllkv                                  6.0m          60.0m         600.0m           __       __
  │  ├─ ebs-csi-node-cffz8                                                  3.0m          30.0m         300.0m           __       __
  │  ├─ karpenter-7b786469d4-s52fc                                         15.0m            1.0            1.0           __       __
  │  ├─ kube-prometheus-stack-grafana-b45c4f79-h67r8                       16.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-gtgv7                1.0m             __             __           __       __
  │  └─ kube-proxy-zvnhr                                                    1.0m         100.0m             __           __       __
  └─ ip-192-168-84-230.ec2.internal                                   (1%) 11.0m      (60%) 1.2   (16%) 300.0m          1.9   775.0m
     ├─ aws-node-4c49x                                                      3.0m          25.0m             __           __       __
     ├─ aws-node-termination-handler-dsd64                                  1.0m             __             __           __       __
     ├─ ebs-csi-node-s7b85                                                  3.0m          30.0m         300.0m           __       __
     ├─ kube-prometheus-stack-prometheus-node-exporter-pd8qx                1.0m             __             __           __       __
     ├─ kube-proxy-2gblp                                                    1.0m         100.0m             __           __       __
     └─ podinfo-59d6468db-jmwxh                                             2.0m            1.0             __           __       __
  ephemeral-storage                                                           __             __             __        53.8G       __
  ├─ ip-192-168-14-250.ec2.internal                                           __             __             __        17.9G       __
  ├─ ip-192-168-16-172.ec2.internal                                           __             __             __        17.9G       __
  └─ ip-192-168-84-230.ec2.internal                                           __             __             __        17.9G       __
  memory                                                             (21%) 1.6Gi    (30%) 2.4Gi    (86%) 6.7Gi        7.8Gi    1.1Gi
  ├─ ip-192-168-14-250.ec2.internal                                (29%) 967.2Mi  (23%) 750.0Mi    (73%) 2.3Gi        3.2Gi  894.4Mi
  │  ├─ alertmanager-kube-prometheus-stack-alertmanager-0                 20.8Mi        250.0Mi         50.0Mi           __       __
  │  ├─ aws-node-m8bqr                                                    30.9Mi             __             __           __       __
  │  ├─ aws-node-termination-handler-4d4vt                                12.9Mi             __             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-dzr77                                54.8Mi        240.0Mi          1.5Gi           __       __
  │  ├─ ebs-csi-node-lnhz4                                                20.9Mi        120.0Mi        768.0Mi           __       __
  │  ├─ external-dns-7d5dfdc9bc-dwf2j                                     22.1Mi             __             __           __       __
  │  ├─ forecastle-fd9fbf494-mz78d                                         8.4Mi             __             __           __       __
  │  ├─ ingress-nginx-controller-5c58df8c6f-5qtsj                         77.9Mi         90.0Mi             __           __       __
  │  ├─ kube-prometheus-stack-kube-state-metrics-75b97d7857-4q29f         15.3Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-operator-c4576c8c5-lv9tj                    33.6Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-grtqf              10.0Mi             __             __           __       __
  │  ├─ kube-proxy-snhd4                                                  13.3Mi             __             __           __       __
  │  ├─ mailhog-7fd4cdc758-c6pht                                           4.0Mi             __             __           __       __
  │  ├─ metrics-server-7bf7496f67-hg8dt                                   17.8Mi             __             __           __       __
  │  ├─ oauth2-proxy-c74b9b769-7fx6m                                       8.4Mi             __             __           __       __
  │  ├─ prometheus-kube-prometheus-stack-prometheus-0                    609.9Mi         50.0Mi         50.0Mi           __       __
  │  └─ wiz-kubernetes-connector-broker-5d8fcfdb94-nq2lw                   6.1Mi             __             __           __       __
  ├─ ip-192-168-16-172.ec2.internal                                (19%) 613.6Mi    (46%) 1.5Gi   (111%) 3.6Gi        3.2Gi      0.0
  │  ├─ aws-node-4d64v                                                    28.0Mi             __             __           __       __
  │  ├─ aws-node-termination-handler-v9jpw                                12.0Mi             __             __           __       __
  │  ├─ cert-manager-7fb84796f4-mmp7g                                     30.7Mi             __             __           __       __
  │  ├─ cert-manager-cainjector-7f694c4c58-s5f4s                          33.8Mi             __             __           __       __
  │  ├─ cert-manager-webhook-7cd8c769bb-5cr5d                             11.5Mi             __             __           __       __
  │  ├─ coredns-79989457d9-9bz5s                                          15.6Mi         70.0Mi        170.0Mi           __       __
  │  ├─ coredns-79989457d9-pv2gz                                          15.0Mi         70.0Mi        170.0Mi           __       __
  │  ├─ ebs-csi-controller-fd8649d65-pllkv                                56.1Mi        240.0Mi          1.5Gi           __       __
  │  ├─ ebs-csi-node-cffz8                                                19.3Mi        120.0Mi        768.0Mi           __       __
  │  ├─ karpenter-7b786469d4-s52fc                                       148.0Mi          1.0Gi          1.0Gi           __       __
  │  ├─ kube-prometheus-stack-grafana-b45c4f79-h67r8                     221.9Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-gtgv7               9.3Mi             __             __           __       __
  │  └─ kube-proxy-zvnhr                                                  12.2Mi             __             __           __       __
  └─ ip-192-168-84-230.ec2.internal                                  (6%) 86.5Mi  (10%) 136.0Mi  (56%) 768.0Mi        1.3Gi  607.3Mi
     ├─ aws-node-4c49x                                                    24.4Mi             __             __           __       __
     ├─ aws-node-termination-handler-dsd64                                12.1Mi             __             __           __       __
     ├─ ebs-csi-node-s7b85                                                16.5Mi        120.0Mi        768.0Mi           __       __
     ├─ kube-prometheus-stack-prometheus-node-exporter-pd8qx               7.3Mi             __             __           __       __
     ├─ kube-proxy-2gblp                                                  12.7Mi             __             __           __       __
     └─ podinfo-59d6468db-jmwxh                                           13.4Mi         16.0Mi             __           __       __
  pods                                                                        __     (80%) 36.0     (80%) 36.0         45.0      9.0
  ├─ ip-192-168-14-250.ec2.internal                                           __    (100%) 17.0    (100%) 17.0         17.0      0.0
  ├─ ip-192-168-16-172.ec2.internal                                           __     (76%) 13.0     (76%) 13.0         17.0      4.0
  └─ ip-192-168-84-230.ec2.internal                                           __      (55%) 6.0      (55%) 6.0         11.0      5.0
```

---

Uninstall [Podinfo](https://github.com/stefanprodan/podinfo):

```sh
kubectl delete namespace podinfo || true
```

Remove files from the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{helm_values-podinfo,k8s-deployment-nginx}.yml; do
  if [[ -f "${FILE}" ]]; then
    rm -v "${FILE}"
  else
    echo "*** File not found: ${FILE}"
  fi
done
```

Enjoy ... 😉
