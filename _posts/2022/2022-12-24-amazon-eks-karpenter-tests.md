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

Requirements:

- Amazon EKS cluster with Karpenter configuration described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})
- [Helm](https://helm.sh/)
- [eks-node-viewer](https://github.com/awslabs/eks-node-viewer)

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
NAME                            STATUS   ROLES    AGE    VERSION               INTERNAL-IP     EXTERNAL-IP      OS-IMAGE                                KERNEL-VERSION   CONTAINER-RUNTIME
ip-192-168-28-81.ec2.internal   Ready    <none>   15m    v1.24.6-eks-4360b32   192.168.28.81   44.202.161.146   Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-6-182.ec2.internal   Ready    <none>   15m    v1.24.6-eks-4360b32   192.168.6.182   44.211.220.53    Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-64-64.ec2.internal   Ready    <none>   91s    v1.24.6-eks-4360b32   192.168.64.64   <none>           Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-66-62.ec2.internal   Ready    <none>   107s   v1.24.6-eks-4360b32   192.168.66.62   <none>           Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
```

```bash
kubectl get nodes -o json | jq -Cjr '.items[] | .metadata.name," ",.metadata.labels."node.kubernetes.io/instance-type"," ",.metadata.labels."kubernetes.io/arch", "\n"' | sort -k2 -r | column -t
```

Output:

```text
ip-192-168-64-64.ec2.internal  t4g.small   arm64
ip-192-168-6-182.ec2.internal  t4g.medium  arm64
ip-192-168-28-81.ec2.internal  t4g.medium  arm64
ip-192-168-66-62.ec2.internal  t3a.small   amd64
```

```bash
kubectl resource-capacity --sort cpu.util --util --pod-count
```

Output:

```text
NODE                            CPU REQUESTS   CPU LIMITS     CPU UTIL    MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL    POD COUNT
*                               5840m (75%)    5200m (67%)    249m (3%)   3770Mi (39%)      8832Mi (93%)    3174Mi (33%)   42/53
ip-192-168-28-81.ec2.internal   1615m (83%)    2300m (119%)   92m (4%)    1534Mi (46%)      3478Mi (105%)   1390Mi (42%)   14/17
ip-192-168-6-182.ec2.internal   1915m (99%)    2300m (119%)   72m (3%)    1964Mi (59%)      3818Mi (116%)   822Mi (24%)    16/17
ip-192-168-64-64.ec2.internal   1155m (59%)    300m (15%)     44m (2%)    136Mi (9%)        768Mi (56%)     455Mi (33%)    6/11
ip-192-168-66-62.ec2.internal   1155m (59%)    300m (15%)     42m (2%)    136Mi (9%)        768Mi (51%)     509Mi (34%)    6/8
```

```shell
eks-node-viewer --resources cpu,memory
```

Output:

```text
4 nodes 5840m/7720m      75.6% cpu    ██████████████████████████████░░░░░░░░░░ 0.103/hour $75.044/month
        3770Mi/9664820Ki 39.9% memory ████████████████░░░░░░░░░░░░░░░░░░░░░░░░
42 pods (0 pending 42 running 42 bound)

ip-192-168-28-81.ec2.internal cpu    █████████████████████████████░░░░░░  84% (14 pods) t4g.medium/$0.034 On-Demand Ready
                              memory ████████████████░░░░░░░░░░░░░░░░░░░  47%
ip-192-168-6-182.ec2.internal cpu    ███████████████████████████████████  99% (16 pods) t4g.medium/$0.034 On-Demand Ready
                              memory █████████████████████░░░░░░░░░░░░░░  60%
ip-192-168-66-62.ec2.internal cpu    █████████████████████░░░░░░░░░░░░░░  60% (6 pods)  t3a.small/$0.019  On-Demand Ready
                              memory ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   9%
ip-192-168-64-64.ec2.internal cpu    █████████████████████░░░░░░░░░░░░░░  60% (6 pods)  t4g.small/$0.017  On-Demand Ready
                              memory ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  10%
```

Enjoy ... 😉
