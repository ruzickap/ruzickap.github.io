---
title: Amazon EKS - Karpenter tests
author: Petr Ruzicka
date: 2022-12-24
description: Run Amazon EKS and create workloads for Karpenter
categories: [Kubernetes, Amazon EKS, Karpenter]
tags: [Amazon EKS, k8s, kubernetes, karpenter, eksctl]
image:
  path: https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png
  width: 600
  alt: Karpenter
---

In the previous post related to
[Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}).
I decided to install [Karpenter](https://karpenter.sh/) to improve
the efficiency and cost of running workloads on the cluster.

There are many articles describing what Karpenter is, how it works and what are
the benefits of using it.

Here are few notes when I was testing it and learn how it works on real
examples.

## Requirements

- Amazon EKS cluster with Karpenter configuration described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})
- [Helm](https://helm.sh/)
- [eks-node-viewer](https://github.com/awslabs/eks-node-viewer)
- [viewnode](https://github.com/NTTDATA-DACH/viewnode)
  - `kubectl krew install viewnode`
- [kubectl-view-allocations](https://github.com/davidB/kubectl-view-allocations)
  - `kubectl krew install view-allocations`
- [kube-capacity](https://github.com/robscott/kube-capacity)
  - `kubectl krew install resource-capacity`

```bash
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
```

## Workloads

Run some workload on the K8s...

Start the amd64 only container:

```bash
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 1
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
```

Install `podinfo`
[helm chart](https://artifacthub.io/packages/helm/podinfo/podinfo)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

![podinfo](https://raw.githubusercontent.com/stefanprodan/podinfo/a7be119f20369b97f209d220535506af7c49b4ea/screens/podinfo-ui-v3.png
"podinfo"){: width="500" }

```bash
# renovate: datasource=helm depName=podinfo registryUrl=https://stefanprodan.github.io/podinfo
PODINFO_HELM_CHART_VERSION="6.3.0"

helm repo add --force-update sp https://stefanprodan.github.io/podinfo
helm upgrade --install --version "${PODINFO_HELM_CHART_VERSION}" --namespace podinfo --create-namespace --wait --values - podinfo sp/podinfo << EOF
certificate:
  create: true
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-${LETSENCRYPT_ENVIRONMENT}-dns
  dnsNames:
    - podinfo.${CLUSTER_FQDN}
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
    - secretName: podinfo-tls
      hosts:
        - podinfo.${CLUSTER_FQDN}
resources:
  requests:
    cpu: 1
    memory: 16Mi
EOF

kubectl scale deployment -n podinfo podinfo --replicas 1
```

Check cluster + node details:

```bash
kubectl get nodes -o wide
```

Output:

```text
NAME                             STATUS   ROLES    AGE     VERSION               INTERNAL-IP      EXTERNAL-IP     OS-IMAGE                                KERNEL-VERSION   CONTAINER-RUNTIME
ip-192-168-17-209.ec2.internal   Ready    <none>   78m     v1.24.6-eks-4360b32   192.168.17.209   18.233.226.48   Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-6-208.ec2.internal    Ready    <none>   78m     v1.24.6-eks-4360b32   192.168.6.208    34.201.45.18    Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-67-1.ec2.internal     Ready    <none>   5m59s   v1.24.6-eks-4360b32   192.168.67.1     <none>          Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-77-156.ec2.internal   Ready    <none>   6m10s   v1.24.6-eks-4360b32   192.168.77.156   <none>          Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
```

Display details about node size and architecture:

```bash
kubectl get nodes -o json | jq -Cjr '.items[] | .metadata.name," ",.metadata.labels."node.kubernetes.io/instance-type"," ",.metadata.labels."kubernetes.io/arch", "\n"' | sort -k2 -r | column -t
```

Output:

```text
ip-192-168-67-1.ec2.internal    t4g.small   arm64
ip-192-168-6-208.ec2.internal   t4g.medium  arm64
ip-192-168-17-209.ec2.internal  t4g.medium  arm64
ip-192-168-77-156.ec2.internal  t3a.large   amd64
```

Details about node capacity:

```bash
kubectl resource-capacity --sort cpu.util --util --pod-count
```

Output:

```text
NODE                             CPU REQUESTS   CPU LIMITS     CPU UTIL    MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL    POD COUNT
*                                4440m (57%)    3800m (49%)    284m (3%)   2546Mi (16%)      7608Mi (50%)    3125Mi (20%)   41/80
ip-192-168-6-208.ec2.internal    1615m (83%)    2300m (119%)   98m (5%)    1684Mi (51%)      3428Mi (104%)   1123Mi (34%)   12/17
ip-192-168-17-209.ec2.internal   515m (26%)     900m (46%)     91m (4%)    590Mi (17%)       2644Mi (80%)    1148Mi (34%)   17/17
ip-192-168-77-156.ec2.internal   1155m (59%)    300m (15%)     53m (2%)    136Mi (1%)        768Mi (10%)     419Mi (5%)     6/35
ip-192-168-67-1.ec2.internal     1155m (59%)    300m (15%)     44m (2%)    136Mi (9%)        768Mi (56%)     438Mi (31%)    6/11
```

Graphical view of cpu + memory utilization per node (+ pices):

```shell
eks-node-viewer --resources cpu,memory
```

Output:

```text
4 nodes 4440m/7720m       57.5% cpu    ███████████████████████░░░░░░░░░░░░░░░░░ 0.159/hour $116.216/month
        2546Mi/15429160Ki 16.9% memory ███████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
41 pods (0 pending 41 running 41 bound)

ip-192-168-6-208.ec2.internal  cpu    █████████████████████████████░░░░░░  84% (12 pods) t4g.medium/$0.034 On-Demand Ready
                               memory ██████████████████░░░░░░░░░░░░░░░░░  51%
ip-192-168-17-209.ec2.internal cpu    █████████░░░░░░░░░░░░░░░░░░░░░░░░░░  27% (17 pods) t4g.medium/$0.034 On-Demand Ready
                               memory ██████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  18%
ip-192-168-77-156.ec2.internal cpu    █████████████████████░░░░░░░░░░░░░░  60% (6 pods)  t3a.large/$0.075  Spot      Ready
                               memory █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   2%
ip-192-168-67-1.ec2.internal   cpu    █████████████████████░░░░░░░░░░░░░░  60% (6 pods)  t4g.small/$0.017  Spot      Ready
                               memory ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  10%
```

Other details produced by [viewnode](https://github.com/NTTDATA-DACH/viewnode):

```bash
kubectl viewnode --all-namespaces --show-metrics
```

Output:

```text
41 pod(s) in total
0 unscheduled pod(s)
4 running node(s) with 41 scheduled pod(s):
- ip-192-168-17-209.ec2.internal running 17 pod(s) (linux/arm64/containerd://1.6.8+bottlerocket | mem: 1.1 GiB)
  * cert-manager: cert-manager-7fb84796f4-c587j (running | mem usage: 26.9 MiB)
  * cert-manager: cert-manager-cainjector-7f694c4c58-5dpmc (running | mem usage: 31.6 MiB)
  * cert-manager: cert-manager-webhook-7cd8c769bb-x979v (running | mem usage: 10.1 MiB)
  * external-dns: external-dns-7d5dfdc9bc-2lrqg (running | mem usage: 19.9 MiB)
  * forecastle: forecastle-fd9fbf494-xltlr (running | mem usage: 17.8 MiB)
  * ingress-nginx: ingress-nginx-controller-5c58df8c6f-x65mj (running | mem usage: 77.5 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-grafana-6b88768cb6-w9fzj (running | mem usage: 218.7 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-fx7kk (running | mem usage: 8.4 MiB)
  * kube-system: aws-node-termination-handler-m8jts (running | mem usage: 12.1 MiB)
  * kube-system: aws-node-xtlj2 (running | mem usage: 29.2 MiB)
  * kube-system: coredns-79989457d9-cgvsx (running | mem usage: 14.3 MiB)
  * kube-system: coredns-79989457d9-lx2ff (running | mem usage: 15.8 MiB)
  * kube-system: ebs-csi-controller-fd8649d65-5qd79 (running | mem usage: 54.8 MiB)
  * kube-system: ebs-csi-node-2h44c (running | mem usage: 20.1 MiB)
  * kube-system: kube-proxy-brhjr (running | mem usage: 12.0 MiB)
  * kube-system: metrics-server-7bf7496f67-fsnjq (running | mem usage: 18.8 MiB)
  * mailhog: mailhog-7fd4cdc758-7c98m (running | mem usage: 6.0 MiB)
- ip-192-168-6-208.ec2.internal running 12 pod(s) (linux/arm64/containerd://1.6.8+bottlerocket | mem: 1.1 GiB)
  * karpenter: karpenter-6d57cdbbd6-gv697 (running | mem usage: 133.7 MiB)
  * kube-prometheus-stack: alertmanager-kube-prometheus-stack-alertmanager-0 (running | mem usage: 20.1 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-kube-state-metrics-75b97d7857-k7d7g (running | mem usage: 13.7 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-operator-84447c55bc-s8fl2 (running | mem usage: 28.1 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-hj95w (running | mem usage: 8.4 MiB)
  * kube-prometheus-stack: prometheus-kube-prometheus-stack-prometheus-0 (running | mem usage: 371.5 MiB)
  * kube-system: aws-node-termination-handler-t7z6t (running | mem usage: 12.1 MiB)
  * kube-system: aws-node-z6jb8 (running | mem usage: 27.4 MiB)
  * kube-system: ebs-csi-controller-fd8649d65-xbpf9 (running | mem usage: 54.7 MiB)
  * kube-system: ebs-csi-node-zwrzb (running | mem usage: 19.9 MiB)
  * kube-system: kube-proxy-q2tt5 (running | mem usage: 11.1 MiB)
  * oauth2-proxy: oauth2-proxy-76b5b4ff7f-9jscb (running | mem usage: 9.0 MiB)
- ip-192-168-67-1.ec2.internal running 6 pod(s) (linux/arm64/containerd://1.6.8+bottlerocket | mem: 435.8 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-5j9rt (running | mem usage: 8.0 MiB)
  * kube-system: aws-node-4zj9z (running | mem usage: 25.6 MiB)
  * kube-system: aws-node-termination-handler-8v5hg (running | mem usage: 11.9 MiB)
  * kube-system: ebs-csi-node-cxvvl (running | mem usage: 19.0 MiB)
  * kube-system: kube-proxy-cw4j7 (running | mem usage: 10.5 MiB)
  * podinfo: podinfo-59d6468db-6pcgc (running | mem usage: 14.5 MiB)
- ip-192-168-77-156.ec2.internal running 6 pod(s) (linux/amd64/containerd://1.6.8+bottlerocket | mem: 421.8 MiB)
  * default: nginx-deployment-7cc6cf5f95-c9zft (running | mem usage: 2.7 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-7hl46 (running | mem usage: 7.7 MiB)
  * kube-system: aws-node-termination-handler-vgjpl (running | mem usage: 12.1 MiB)
  * kube-system: aws-node-wxr4l (running | mem usage: 31.7 MiB)
  * kube-system: ebs-csi-node-mlhs5 (running | mem usage: 19.1 MiB)
  * kube-system: kube-proxy-kj7kn (running | mem usage: 9.8 MiB)
```

Other details produced by [kubectl-view-allocations](https://github.com/davidB/kubectl-view-allocations):

```bash
kubectl view-allocations --utilization
```

Output:

```text
Resource                                                            Utilization      Requested          Limit  Allocatable     Free
  attachable-volumes-aws-ebs                                                  __             __             __        142.0       __
  ├─ ip-192-168-17-209.ec2.internal                                           __             __             __         39.0       __
  ├─ ip-192-168-6-208.ec2.internal                                            __             __             __         39.0       __
  ├─ ip-192-168-67-1.ec2.internal                                             __             __             __         39.0       __
  └─ ip-192-168-77-156.ec2.internal                                           __             __             __         25.0       __
  cpu                                                                 (1%) 95.0m      (58%) 4.4      (49%) 3.8          7.7      3.3
  ├─ ip-192-168-17-209.ec2.internal                                   (2%) 33.0m   (27%) 515.0m   (47%) 900.0m          1.9      1.0
  │  ├─ aws-node-termination-handler-m8jts                                  1.0m             __             __           __       __
  │  ├─ aws-node-xtlj2                                                      3.0m          25.0m             __           __       __
  │  ├─ cert-manager-7fb84796f4-c587j                                       1.0m             __             __           __       __
  │  ├─ cert-manager-cainjector-7f694c4c58-5dpmc                            1.0m             __             __           __       __
  │  ├─ cert-manager-webhook-7cd8c769bb-x979v                               1.0m             __             __           __       __
  │  ├─ coredns-79989457d9-cgvsx                                            1.0m         100.0m             __           __       __
  │  ├─ coredns-79989457d9-lx2ff                                            1.0m         100.0m             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-5qd79                                  6.0m          60.0m         600.0m           __       __
  │  ├─ ebs-csi-node-2h44c                                                  3.0m          30.0m         300.0m           __       __
  │  ├─ external-dns-7d5dfdc9bc-2lrqg                                       1.0m             __             __           __       __
  │  ├─ forecastle-fd9fbf494-xltlr                                          1.0m             __             __           __       __
  │  ├─ ingress-nginx-controller-5c58df8c6f-x65mj                           1.0m         100.0m             __           __       __
  │  ├─ kube-prometheus-stack-grafana-6b88768cb6-w9fzj                      6.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-fx7kk                1.0m             __             __           __       __
  │  ├─ kube-proxy-brhjr                                                    1.0m         100.0m             __           __       __
  │  ├─ mailhog-7fd4cdc758-7c98m                                            1.0m             __             __           __       __
  │  └─ metrics-server-7bf7496f67-fsnjq                                     3.0m             __             __           __       __
  ├─ ip-192-168-6-208.ec2.internal                                    (2%) 42.0m      (84%) 1.6     (119%) 2.3          1.9      0.0
  │  ├─ alertmanager-kube-prometheus-stack-alertmanager-0                   2.0m         200.0m         200.0m           __       __
  │  ├─ aws-node-termination-handler-t7z6t                                  1.0m             __             __           __       __
  │  ├─ aws-node-z6jb8                                                      3.0m          25.0m             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-xbpf9                                  6.0m          60.0m         600.0m           __       __
  │  ├─ ebs-csi-node-zwrzb                                                  3.0m          30.0m         300.0m           __       __
  │  ├─ karpenter-6d57cdbbd6-gv697                                         12.0m            1.0            1.0           __       __
  │  ├─ kube-prometheus-stack-kube-state-metrics-75b97d7857-k7d7g           1.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-operator-84447c55bc-s8fl2                     1.0m             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-hj95w                1.0m             __             __           __       __
  │  ├─ kube-proxy-q2tt5                                                    1.0m         100.0m             __           __       __
  │  ├─ oauth2-proxy-76b5b4ff7f-9jscb                                       1.0m             __             __           __       __
  │  └─ prometheus-kube-prometheus-stack-prometheus-0                      10.0m         200.0m         200.0m           __       __
  ├─ ip-192-168-67-1.ec2.internal                                      (0%) 9.0m      (60%) 1.2   (16%) 300.0m          1.9   775.0m
  │  ├─ aws-node-4zj9z                                                      1.0m          25.0m             __           __       __
  │  ├─ aws-node-termination-handler-8v5hg                                  1.0m             __             __           __       __
  │  ├─ ebs-csi-node-cxvvl                                                  3.0m          30.0m         300.0m           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-5j9rt                1.0m             __             __           __       __
  │  ├─ kube-proxy-cw4j7                                                    1.0m         100.0m             __           __       __
  │  └─ podinfo-59d6468db-6pcgc                                             2.0m            1.0             __           __       __
  └─ ip-192-168-77-156.ec2.internal                                   (1%) 11.0m      (60%) 1.2   (16%) 300.0m          1.9   775.0m
     ├─ aws-node-termination-handler-vgjpl                                  1.0m             __             __           __       __
     ├─ aws-node-wxr4l                                                      3.0m          25.0m             __           __       __
     ├─ ebs-csi-node-mlhs5                                                  3.0m          30.0m         300.0m           __       __
     ├─ kube-prometheus-stack-prometheus-node-exporter-7hl46                2.0m             __             __           __       __
     ├─ kube-proxy-kj7kn                                                    1.0m         100.0m             __           __       __
     └─ nginx-deployment-7cc6cf5f95-c9zft                                   1.0m            1.0             __           __       __
  ephemeral-storage                                                           __             __             __        71.7G       __
  ├─ ip-192-168-17-209.ec2.internal                                           __             __             __        17.9G       __
  ├─ ip-192-168-6-208.ec2.internal                                            __             __             __        17.9G       __
  ├─ ip-192-168-67-1.ec2.internal                                             __             __             __        17.9G       __
  └─ ip-192-168-77-156.ec2.internal                                           __             __             __        17.9G       __
  memory                                                             (10%) 1.4Gi    (17%) 2.5Gi    (50%) 7.4Gi       14.7Gi    7.3Gi
  ├─ ip-192-168-17-209.ec2.internal                                (18%) 580.5Mi  (18%) 590.0Mi    (80%) 2.6Gi        3.2Gi  646.4Mi
  │  ├─ aws-node-termination-handler-m8jts                                12.1Mi             __             __           __       __
  │  ├─ aws-node-xtlj2                                                    29.2Mi             __             __           __       __
  │  ├─ cert-manager-7fb84796f4-c587j                                     26.9Mi             __             __           __       __
  │  ├─ cert-manager-cainjector-7f694c4c58-5dpmc                          31.6Mi             __             __           __       __
  │  ├─ cert-manager-webhook-7cd8c769bb-x979v                             10.1Mi             __             __           __       __
  │  ├─ coredns-79989457d9-cgvsx                                          14.3Mi         70.0Mi        170.0Mi           __       __
  │  ├─ coredns-79989457d9-lx2ff                                          15.8Mi         70.0Mi        170.0Mi           __       __
  │  ├─ ebs-csi-controller-fd8649d65-5qd79                                54.9Mi        240.0Mi          1.5Gi           __       __
  │  ├─ ebs-csi-node-2h44c                                                20.1Mi        120.0Mi        768.0Mi           __       __
  │  ├─ external-dns-7d5dfdc9bc-2lrqg                                     19.9Mi             __             __           __       __
  │  ├─ forecastle-fd9fbf494-xltlr                                         9.3Mi             __             __           __       __
  │  ├─ ingress-nginx-controller-5c58df8c6f-x65mj                         77.6Mi         90.0Mi             __           __       __
  │  ├─ kube-prometheus-stack-grafana-6b88768cb6-w9fzj                   215.1Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-fx7kk               8.8Mi             __             __           __       __
  │  ├─ kube-proxy-brhjr                                                  12.0Mi             __             __           __       __
  │  ├─ mailhog-7fd4cdc758-7c98m                                           3.7Mi             __             __           __       __
  │  └─ metrics-server-7bf7496f67-fsnjq                                   19.2Mi             __             __           __       __
  ├─ ip-192-168-6-208.ec2.internal                                 (22%) 731.2Mi    (51%) 1.6Gi   (104%) 3.3Gi        3.2Gi      0.0
  │  ├─ alertmanager-kube-prometheus-stack-alertmanager-0                 19.9Mi        250.0Mi         50.0Mi           __       __
  │  ├─ aws-node-termination-handler-t7z6t                                12.2Mi             __             __           __       __
  │  ├─ aws-node-z6jb8                                                    27.4Mi             __             __           __       __
  │  ├─ ebs-csi-controller-fd8649d65-xbpf9                                54.7Mi        240.0Mi          1.5Gi           __       __
  │  ├─ ebs-csi-node-zwrzb                                                19.9Mi        120.0Mi        768.0Mi           __       __
  │  ├─ karpenter-6d57cdbbd6-gv697                                       141.9Mi          1.0Gi          1.0Gi           __       __
  │  ├─ kube-prometheus-stack-kube-state-metrics-75b97d7857-k7d7g         13.7Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-operator-84447c55bc-s8fl2                   28.1Mi             __             __           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-hj95w               8.4Mi             __             __           __       __
  │  ├─ kube-proxy-q2tt5                                                  11.1Mi             __             __           __       __
  │  ├─ oauth2-proxy-76b5b4ff7f-9jscb                                      9.0Mi             __             __           __       __
  │  └─ prometheus-kube-prometheus-stack-prometheus-0                    384.9Mi         50.0Mi         50.0Mi           __       __
  ├─ ip-192-168-67-1.ec2.internal                                    (7%) 89.5Mi  (10%) 136.0Mi  (56%) 768.0Mi        1.3Gi  599.4Mi
  │  ├─ aws-node-4zj9z                                                    25.6Mi             __             __           __       __
  │  ├─ aws-node-termination-handler-8v5hg                                11.9Mi             __             __           __       __
  │  ├─ ebs-csi-node-cxvvl                                                19.1Mi        120.0Mi        768.0Mi           __       __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-5j9rt               8.0Mi             __             __           __       __
  │  ├─ kube-proxy-cw4j7                                                  10.5Mi             __             __           __       __
  │  └─ podinfo-59d6468db-6pcgc                                           14.5Mi         16.0Mi             __           __       __
  └─ ip-192-168-77-156.ec2.internal                                  (1%) 83.4Mi   (2%) 136.0Mi  (11%) 768.0Mi        7.0Gi    6.2Gi
     ├─ aws-node-termination-handler-vgjpl                                12.2Mi             __             __           __       __
     ├─ aws-node-wxr4l                                                    31.7Mi             __             __           __       __
     ├─ ebs-csi-node-mlhs5                                                19.2Mi        120.0Mi        768.0Mi           __       __
     ├─ kube-prometheus-stack-prometheus-node-exporter-7hl46               7.8Mi             __             __           __       __
     ├─ kube-proxy-kj7kn                                                   9.8Mi             __             __           __       __
     └─ nginx-deployment-7cc6cf5f95-c9zft                                  2.7Mi         16.0Mi             __           __       __
  pods                                                                        __     (51%) 41.0     (51%) 41.0         80.0     39.0
  ├─ ip-192-168-17-209.ec2.internal                                           __    (100%) 17.0    (100%) 17.0         17.0      0.0
  ├─ ip-192-168-6-208.ec2.internal                                            __     (71%) 12.0     (71%) 12.0         17.0      5.0
  ├─ ip-192-168-67-1.ec2.internal                                             __      (55%) 6.0      (55%) 6.0         11.0      5.0
  └─ ip-192-168-77-156.ec2.internal                                           __      (17%) 6.0      (17%) 6.0         35.0     29.0
```

Enjoy ... 😉
