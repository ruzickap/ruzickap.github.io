---
title: My favourite krew plugins for kubectl
author: Petr Ruzicka
date: 2023-06-06
description: My favourite krew plugins for kubectl command-line tool
categories: [Kubernetes, krew, kubectl, plugins, plugin-manager]
tags: [kubernetes, krew, kubectl, plugins, plugin-manager]
image: https://raw.githubusercontent.com/kubernetes-sigs/krew/4ec386cc021b4a7896de95d91c5d8025d98eaa4f/assets/logo/stacked/color/krew-stacked-color.svg
---

I would like to share few notes about kubectl plugins installed by [krew](https://krew.sigs.k8s.io/)
which I'm using... It should not be comprehensive description of plugins, but I
prefer to focus on the examples and screenshots.

Links:

- [Suman Chakraborty's Post](https://www.linkedin.com/posts/schakraborty007_opensource-kubernetes-k8s-activity-7038698712470089728-ADeV)
- [Top 15 Kubectl plugins for security engineers](https://sysdig.com/blog/top-15-kubectl-plugins-for-security-engineers)
- [Kubernetes: Krew plugins manager, and useful kubectl plugins list](https://devpress.csdn.net/cicd/62ec6d5c89d9027116a10eb0.html)
- [Making Kubernetes Operations Easy with kubectl Plugins](https://martinheinz.dev/blog/58)

## Requirements

- Amazon EKS cluster (described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}))
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)

## Install krew

Install Krew plugin manager for kubectl command-line tool:

![Krew](https://raw.githubusercontent.com/kubernetes-sigs/krew/4ec386cc021b4a7896de95d91c5d8025d98eaa4f/assets/logo/horizontal/color/krew-horizontal-color.svg){:width="500"}

```bash
TMP_DIR="${TMP_DIR:-${PWD}}"
ARCH="amd64"
curl -sL "https://github.com/kubernetes-sigs/krew/releases/download/v0.4.5/krew-linux_${ARCH}.tar.gz" | tar -xvzf - -C "${TMP_DIR}" --no-same-owner --strip-components=1 --wildcards "*/krew-linux*"
"${TMP_DIR}/krew-linux_${ARCH}" install krew
rm "${TMP_DIR}/krew-linux_${ARCH}"
export PATH="${HOME}/.krew/bin:${PATH}"
```

## My Favorite krew + kubectl plugins

List of my favorite krew + kubectl plugins:

### [cert-manager](https://github.com/cert-manager/cert-manager)

- Kubectl add-on to automate the management and issuance of TLS certificates.
  Allows for direct interaction with cert-manager resources e.g. manual renewal
  of Certificate resources.

[cert-manager](https://github.com/cert-manager/cert-manager) krew plugin
installation:

```bash
kubectl krew install cert-manager
```

Get details about the current status of a cert-manager Certificate resource,
including information on related resources like CertificateRequest or Order:

```bash
kubectl cert-manager status certificate --namespace cert-manager ingress-cert-staging
```

```console
Name: ingress-cert-staging
Namespace: cert-manager
Created at: 2023-06-18T07:31:46Z
Conditions:
  Ready: True, Reason: Ready, Message: Certificate is up to date and has not expired
DNS Names:
- *.k01.k8s.mylabs.dev
- k01.k8s.mylabs.dev
Events:
  Type    Reason     Age                From                                       Message
  ----    ------     ----               ----                                       -------
  Normal  Issuing    41m                cert-manager-certificates-trigger          Issuing certificate as Secret does not exist
  Normal  Generated  41m                cert-manager-certificates-key-manager      Stored new private key in temporary Secret resource "ingress-cert-staging-jbw7s"
  Normal  Requested  41m                cert-manager-certificates-request-manager  Created new CertificateRequest resource "ingress-cert-staging-r2mnb"
  Normal  Reused     37m                cert-manager-certificates-key-manager      Reusing private key stored in existing Secret resource "ingress-cert-staging"
  Normal  Requested  37m                cert-manager-certificates-request-manager  Created new CertificateRequest resource "ingress-cert-staging-jm8c2"
  Normal  Issuing    37m (x2 over 38m)  cert-manager-certificates-issuing          The certificate has been successfully issued
Issuer:
  Name: letsencrypt-staging-dns
  Kind: ClusterIssuer
  Conditions:
    Ready: True, Reason: ACMEAccountRegistered, Message: The ACME account was registered with the ACME server
  Events:  <none>
Secret:
  Name: ingress-cert-staging
  Issuer Country: US
  Issuer Organisation: (STAGING) Let's Encrypt
  Issuer Common Name: (STAGING) Artificial Apricot R3
  Key Usage: Digital Signature, Key Encipherment
  Extended Key Usages: Server Authentication, Client Authentication
  Public Key Algorithm: RSA
  Signature Algorithm: SHA256-RSA
  Subject Key ID: 6ad5d66e8d4e46409107d6af11283ef603f5113b
  Authority Key ID: de727a48df31c3a650df9f8523df57374b5d2e65
  Serial Number: fabb47cea28a80ce5add9eb5e02c5e7c8273
  Events:  <none>
Not Before: 2023-06-18T06:36:23Z
Not After: 2023-09-16T06:36:22Z
Renewal Time: 2023-08-17T06:36:22Z
No CertificateRequest found for this Certificate
```

Mark cert-manager Certificate resources for manual renewal:

```bash
kubectl cert-manager renew --namespace cert-manager ingress-cert-staging
sleep 5
kubectl cert-manager inspect secret --namespace cert-manager ingress-cert-staging | grep -A2 -E 'Validity period'
```

```console
Manually triggered issuance of Certificate cert-manager/ingress-cert-staging

Validity period:
  Not Before: Sun, 18 Jun 2023 07:15:58 UTC
  Not After: Sat, 16 Sep 2023 07:15:57 UTC
```

The Certificate was created at `2023-06-18 06:36:23` and then rotated
`18 Jun 2023 07:15:58`...

### [get-all](https://github.com/corneliusweig/ketall)

- Like `kubectl get all`, but get really all resources.

[get-all](https://github.com/corneliusweig/ketall) krew plugin installation:

```bash
kubectl krew install get-all
```

Get all resources from `default` namespace:

```bash
kubectl get-all -n default
```

```console
NAME                                       NAMESPACE  AGE
configmap/kube-root-ca.crt                 default    68m
endpoints/kubernetes                       default    69m
serviceaccount/default                     default    68m
service/kubernetes                         default    69m
endpointslice.discovery.k8s.io/kubernetes  default    69m
```

### [ice](https://github.com/NimbleArchitect/kubectl-ice)

- [ice](https://github.com/NimbleArchitect/kubectl-ice) is an open-source tool
  for Kubernetes users to monitor and optimize container resource usage.

[ice](https://github.com/NimbleArchitect/kubectl-ice) krew plugin installation:

```bash
kubectl krew install ice
```

List containers cpu info from pods:

```bash
kubectl ice cpu -n kube-prometheus-stack --sort used
```

```console
PODNAME                                                    CONTAINER               USED  REQUEST  LIMIT  %REQ  %LIMIT
prometheus-kube-prometheus-stack-prometheus-0              config-reloader         0m    200m     200m   -     -
alertmanager-kube-prometheus-stack-alertmanager-0          alertmanager            1m    0m       0m     -     -
alertmanager-kube-prometheus-stack-alertmanager-0          config-reloader         1m    200m     200m   0.01  0.01
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana-sc-dashboard    1m    -        -      -     -
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana-sc-datasources  1m    -        -      -     -
kube-prometheus-stack-operator-7f45586f68-9rz6j            kube-prometheus-stack   1m    -        -      -     -
kube-prometheus-stack-kube-state-metrics-669bd5c594-vfznb  kube-state-metrics      2m    -        -      -     -
kube-prometheus-stack-prometheus-node-exporter-m4k5m       node-exporter           2m    -        -      -     -
kube-prometheus-stack-prometheus-node-exporter-x5bhm       node-exporter           2m    -        -      -     -
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana                 8m    -        -      -     -
prometheus-kube-prometheus-stack-prometheus-0              prometheus              52m   -        -      -     -
```

List containers memory info from pods:

```bash
kubectl ice memory -n kube-prometheus-stack --node-tree
```

```console
NAMESPACE              NAME                                                                USED     REQUEST  LIMIT    %REQ  %LIMIT
kube-prometheus-stack  StatefulSet/alertmanager-kube-prometheus-stack-alertmanager         19.62Mi  250.00Mi 50.00Mi  0.04  0.01
kube-prometheus-stack  └─Pod/alertmanager-kube-prometheus-stack-alertmanager-0             19.62Mi  250.00Mi 50.00Mi  0.04  0.01
kube-prometheus-stack    └─Container/alertmanager                                          16.44Mi  200Mi    0        8.22  -
kube-prometheus-stack    └─Container/config-reloader                                       3.18Mi   50Mi     50Mi     6.35  6.35
-                      Node/ip-192-168-26-84.ec2.internal                                  241.14Mi 0        0        -     -
kube-prometheus-stack  └─Deployment/kube-prometheus-stack-grafana                          231.98Mi 0        0        -     -
kube-prometheus-stack    └─ReplicaSet/kube-prometheus-stack-grafana-896f8645               231.98Mi 0        0        -     -
kube-prometheus-stack     └─Pod/kube-prometheus-stack-grafana-896f8645-6q9lb               231.98Mi 0        0        -     -
kube-prometheus-stack      └─Container/grafana-sc-dashboard                                70.99Mi  -        -        -     -
kube-prometheus-stack      └─Container/grafana-sc-datasources                              72.67Mi  -        -        -     -
kube-prometheus-stack      └─Container/grafana                                             88.32Mi  -        -        -     -
kube-prometheus-stack  └─DaemonSet/kube-prometheus-stack-prometheus-node-exporter          9.16Mi   0        0        -     -
kube-prometheus-stack    └─Pod/kube-prometheus-stack-prometheus-node-exporter-m4k5m        9.16Mi   0        0        -     -
kube-prometheus-stack     └─Container/node-exporter                                        9.16Mi   -        -        -     -
-                      Node/ip-192-168-7-23.ec2.internal                                   44.42Mi  0        0        -     -
kube-prometheus-stack  └─Deployment/kube-prometheus-stack-kube-state-metrics               12.68Mi  0        0        -     -
kube-prometheus-stack    └─ReplicaSet/kube-prometheus-stack-kube-state-metrics-669bd5c594  12.68Mi  0        0        -     -
kube-prometheus-stack     └─Pod/kube-prometheus-stack-kube-state-metrics-669bd5c594-vfznb  12.68Mi  0        0        -     -
kube-prometheus-stack      └─Container/kube-state-metrics                                  12.68Mi  -        -        -     -
kube-prometheus-stack  └─Deployment/kube-prometheus-stack-operator                         22.64Mi  0        0        -     -
kube-prometheus-stack    └─ReplicaSet/kube-prometheus-stack-operator-7f45586f68            22.64Mi  0        0        -     -
kube-prometheus-stack     └─Pod/kube-prometheus-stack-operator-7f45586f68-9rz6j            22.64Mi  0        0        -     -
kube-prometheus-stack      └─Container/kube-prometheus-stack                               22.64Mi  -        -        -     -
kube-prometheus-stack  └─DaemonSet/kube-prometheus-stack-prometheus-node-exporter          9.10Mi   0        0        -     -
kube-prometheus-stack    └─Pod/kube-prometheus-stack-prometheus-node-exporter-x5bhm        9.10Mi   0        0        -     -
kube-prometheus-stack     └─Container/node-exporter                                        9.11Mi   -        -        -     -
kube-prometheus-stack  StatefulSet/prometheus-kube-prometheus-stack-prometheus             400.28Mi 50.00Mi  50.00Mi  0.80  0.80
kube-prometheus-stack  └─Pod/prometheus-kube-prometheus-stack-prometheus-0                 400.28Mi 50.00Mi  50.00Mi  0.80  0.80
kube-prometheus-stack    └─Container/prometheus                                            393.89Mi -        -        -     -
kube-prometheus-stack    └─Container/config-reloader                                       6.38Mi   50Mi     50Mi     12.77 12.77
```

List containers image info from pods:

```bash
kubectl ice image -n cert-manager
```

```console
PODNAME                                   CONTAINER                PULL          IMAGE                                     TAG
cert-manager-777fbdc9f8-ng8dg             cert-manager-controller  IfNotPresent  quay.io/jetstack/cert-manager-controller  v1.12.2
cert-manager-cainjector-65857fccf8-krpr9  cert-manager-cainjector  IfNotPresent  quay.io/jetstack/cert-manager-cainjector  v1.12.2
cert-manager-webhook-54f9d96756-plv84     cert-manager-webhook     IfNotPresent  quay.io/jetstack/cert-manager-webhook     v1.12.2
```

List individual container status from pods:

```bash
kubectl ice status -n kube-prometheus-stack
```

```console
PODNAME                                                    CONTAINER               READY  STARTED  RESTARTS  STATE       REASON     EXIT-CODE  SIGNAL  AGE
alertmanager-kube-prometheus-stack-alertmanager-0          init-config-reloader    true   -        0         Terminated  Completed  0          0       100m
alertmanager-kube-prometheus-stack-alertmanager-0          alertmanager            true   true     0         Running     -          -          -       100m
alertmanager-kube-prometheus-stack-alertmanager-0          config-reloader         true   true     0         Running     -          -          -       100m
kube-prometheus-stack-grafana-896f8645-6q9lb               download-dashboards     true   -        0         Terminated  Completed  0          0       100m
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana                 true   true     0         Running     -          -          -       100m
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana-sc-dashboard    true   true     0         Running     -          -          -       100m
kube-prometheus-stack-grafana-896f8645-6q9lb               grafana-sc-datasources  true   true     0         Running     -          -          -       100m
kube-prometheus-stack-kube-state-metrics-669bd5c594-vfznb  kube-state-metrics      true   true     0         Running     -          -          -       100m
kube-prometheus-stack-operator-7f45586f68-9rz6j            kube-prometheus-stack   true   true     0         Running     -          -          -       100m
kube-prometheus-stack-prometheus-node-exporter-m4k5m       node-exporter           true   true     0         Running     -          -          -       100m
kube-prometheus-stack-prometheus-node-exporter-x5bhm       node-exporter           true   true     0         Running     -          -          -       100m
prometheus-kube-prometheus-stack-prometheus-0              init-config-reloader    true   -        0         Terminated  Completed  0          0       100m
prometheus-kube-prometheus-stack-prometheus-0              config-reloader         true   true     0         Running     -          -          -       100m
prometheus-kube-prometheus-stack-prometheus-0              prometheus              true   true     0         Running     -          -          -       100m
```

### [ktop](https://github.com/vladimirvivien/ktop)

- A top-like tool for your Kubernetes clusters.

[ktop](https://github.com/vladimirvivien/ktop) krew plugin installation:

```bash
kubectl krew install ktop
```

Run `ktop`:

```shell
kubectl ktop
```

![ktop screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-ktop.avif)
_ktop screenshot_

### [kubepug](https://github.com/rikatz/kubepug)

- Kubernetes PreUpGrade (Checker)

![ktop screenshot](https://raw.githubusercontent.com/rikatz/kubepug/a5c56351c64a3b8328fe9412b732930b199f716d/assets/kubepug.png)
_KubePug logo_

[deprecations](https://github.com/rikatz/kubepug) krew plugin installation:

```bash
kubectl krew install deprecations
```

Shows all the deprecated objects in a Kubernetes cluster allowing the operator
to verify them before upgrading the cluster:

```bash
kubectl deprecations --k8s-version=v1.27.0
```

<!-- markdownlint-disable -->
<!---
RESULTS:
Deprecated APIs:

ComponentStatus found in /v1
   ├─ ComponentStatus (and ComponentStatusList) holds the cluster validation info. Deprecated: This API is deprecated in v1.19+
    -> GLOBAL: etcd-1
    -> GLOBAL: scheduler
    -> GLOBAL: etcd-2
    -> GLOBAL: controller-manager
    -> GLOBAL: etcd-0


Deleted APIs:
-->
<!-- markdownlint-restore -->

![deprecations screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-deprecations.avif)
_deprecations screenshot_

![deprecations screenshot](https://raw.githubusercontent.com/rikatz/kubepug/a5c56351c64a3b8328fe9412b732930b199f716d/assets/screenshot.png)
_deprecations screenshot from official GitHub repository_

### [node-ssm](https://github.com/VioletCranberry/kubectl-node-ssm)

- Kubectl plugin that allows direct connections to AWS EKS cluster Systems
  Manager managed nodes relying on local AWS CLI and session-manager-plugin
  installed.

[node-ssm](https://github.com/VioletCranberry/kubectl-node-ssm) krew plugin
installation:

```bash
kubectl krew install node-ssm
```

Access the node using SSM:

```shell
K8S_NODE=$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers | head -n 1)
kubectl node-ssm --target "${K8S_NODE}"
```

```console
Starting session with SessionId: ruzickap@M-C02DP163ML87-k8s-1687787750-03553ad56b6a28df6
          Welcome to Bottlerocket's control container!
    ╱╲
   ╱┄┄╲   This container gives you access to the Bottlerocket API,
...
...
...
[ssm-user@control]$
```

### [ns](https://github.com/ahmetb/kubectx)

- Faster way to switch between namespaces in kubectl.

[ns](https://github.com/ahmetb/kubectx) krew plugin installation:

```bash
kubectl krew install ns
```

Change the active namespace of current context and list secrets from
`cert-manager` without using `--namespace` or `-n` option:

```bash
kubectl ns cert-manager
kubectl get secrets
```

```console
Context "arn:aws:eks:us-east-1:729560437327:cluster/k01" modified.
Active namespace is "cert-manager".

NAME                                 TYPE                 DATA   AGE
cert-manager-webhook-ca              Opaque               3      107m
ingress-cert-staging                 kubernetes.io/tls    2      102m
letsencrypt-staging-dns              Opaque               1      106m
sh.helm.release.v1.cert-manager.v1   helm.sh/release.v1   1      107m
```

### [open-svc](https://github.com/superbrothers/kubectl-open-svc-plugin)

- Kubectl open-svc plugin makes services accessible via their ClusterIP from
  outside your cluster.

[open-svc](https://github.com/superbrothers/kubectl-open-svc-plugin) krew plugin
installation:

```bash
kubectl krew install open-svc
```

Open Grafana Dashboard URL in the browser:

```shell
kubectl open-svc kube-prometheus-stack-grafana -n kube-prometheus-stack
```

![open-svc screenshot](https://raw.githubusercontent.com/superbrothers/kubectl-open-svc-plugin/4e3bec16af9fbf676a28d5f794ad6d7883fe9315/screenshots/kubectl-open-svc-plugin.gif)
_open-svc screenshot from official GitHub repository_

### [pod-lens](https://github.com/sunny0826/kubectl-pod-lens)

- Kubectl plugin for show pod-related resources.

![pod-lens screenshot](https://raw.githubusercontent.com/sunny0826/kubectl-pod-lens/c66b6e7c9a0ace381f14daa3ff15ed20fdf3edde/docs/static/logo.png){:width="150"}
_pod-lens logo_

[pod-lens](https://github.com/sunny0826/kubectl-pod-lens) krew plugin
installation:

```bash
kubectl krew install pod-lens
```

Find related workloads, namespace, node, service, configmap, secret, ingress,
PVC, HPA and PDB by pod name and display them in a tree:

```bash
kubectl pod-lens -n kube-prometheus-stack prometheus-kube-prometheus-stack-prometheus-0
```

<!-- markdownlint-disable -->
<!---
 [Namespace]  kube-prometheus-stack
└─┬ [Namespace]  kube-prometheus-stack                                                                          Replica: 1/1
  └─┬ [statefulset]  prometheus-kube-prometheus-stack-prometheus                                                [Ready] Node IP: 192.168.7.23
    ├─┬ [Node]  ip-192-168-7-23.ec2.internal                                                                    [Running] Pod IP: 192.168.3.131
    │ └─┬ [Pod]  prometheus-kube-prometheus-stack-prometheus-0                                                  [Completed] Restart: 0
    │   ├── [initContainer]  init-config-reloader                                                               [Running] Restart: 0
    │   ├── [Container]  config-reloader                                                                        [Running] Restart: 0
    │   └── [Container]  prometheus
    ├── [PVC]  prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
    ├── [Secret]  prometheus-kube-prometheus-stack-prometheus
    ├── [Secret]  prometheus-kube-prometheus-stack-prometheus-tls-assets-0
    ├── [ConfigMap]  prometheus-kube-prometheus-stack-prometheus-rulefiles-0
    ├── [Secret]  prometheus-kube-prometheus-stack-prometheus-web-config
    └── [ConfigMap]  kube-root-ca.crt

 Related Resources

Kind:           PVC
Name:           prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
Storage Class:  gp2
Access Modes:   ReadWriteOnce
Size:           2Gi
PV Name:        pvc-2ab27f7a-b656-4560-808b-3840760ed79c
---             ---
-->
<!-- markdownlint-restore -->

![pod-lens kube-prometheus-stack screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-pod-lens-kube-prometheus-stack.avif)
_pod-lens showing details in kube-prometheus-stack namespace_

```bash
kubectl pod-lens -n karpenter karpenter-
```

<!-- markdownlint-disable -->
<!---
 [Namespace]  karpenter
└─┬ [Namespace]  karpenter                        Replica: 1/1
  └─┬ [Deployment]  karpenter                     [Ready] Node IP: 192.168.26.84
    ├─┬ [Node]  ip-192-168-26-84.ec2.internal     [Running] Pod IP: 192.168.13.47
    │ └─┬ [Pod]  karpenter-6bd66c788f-xnc4s       [Running] Restart: 0
    │   └── [Container]  controller
    └── [ConfigMap]  kube-root-ca.crt

 Related Resources

Kind:         Deployment
Name:         karpenter
Replicas:     1
---           ---
Kind:         Service
Name:         karpenter
Cluster IP:   10.100.140.164
Ports
              ---
              Name: http-metrics
              Port: 8080
              TargetPort:
              http-metrics
              ---
              Name:
              https-webhook
              Port: 443
              TargetPort:
              https-webhook
---           ---
Kind:         ConfigMap
Name:         config-logging
---           ---
Kind:         ConfigMap
Name:         karpenter-global-settings
---           ---
Kind:         Secrets
Name:         karpenter-cert
---           ---
Kind:         PDB
Name:         karpenter
MaxAvailable: 1
Disruptions:  1
---           ---
-->
<!-- markdownlint-restore -->

![pod-lens karpenter screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-pod-lens-karpenter.avif){:width="500"}
_pod-lens showing details in karpenter namespace_

### [rbac-tool](https://github.com/alcideio/rbac-tool)

[rbac-tool](https://github.com/alcideio/rbac-tool) krew plugin
installation:

```bash
kubectl krew install rbac-tool
```

Shows which subjects have RBAC `get` permissions to `/apis`:

```bash
kubectl rbac-tool who-can get /apis
```

```console
  TYPE  | SUBJECT              | NAMESPACE
+-------+----------------------+-----------+
  Group | system:authenticated |
  Group | system:masters       |
  User  | eks:addon-manager    |
```

Shows which subjects have RBAC `watch` permissions to `deployments.apps`:

```bash
kubectl rbac-tool who-can watch deployments.apps
```

```console
  TYPE           | SUBJECT                                  | NAMESPACE
+----------------+------------------------------------------+-----------------------+
  Group          | eks:service-operations                   |
  Group          | system:masters                           |
  ServiceAccount | deployment-controller                    | kube-system
  ServiceAccount | disruption-controller                    | kube-system
  ServiceAccount | eks-vpc-resource-controller              | kube-system
  ServiceAccount | generic-garbage-collector                | kube-system
  ServiceAccount | karpenter                                | karpenter
  ServiceAccount | kube-prometheus-stack-kube-state-metrics | kube-prometheus-stack
  ServiceAccount | resourcequota-controller                 | kube-system
  User           | eks:addon-manager                        |
  User           | eks:vpc-resource-controller              |
  User           | system:kube-controller-manager           |
```

Get details about the current "user":

```shell
kubectl rbac-tool whoami
```

```console
{Username: "kubernetes-admin",
 UID:      "aws-iam-authenticator:7xxxxxxxxxx7:AxxxxxxxxxxxxxxxxxxxL",
 Groups:   ["system:masters",
            "system:authenticated"],
 Extra:    {accessKeyId:  ["AxxxxxxxxxxxxxxxxxxA"],
            arn:          ["arn:aws:sts::7xxxxxxxxxx7:assumed-role/GitHubRole/ruzickap@mymac-k8s-1111111111"],
            canonicalArn: ["arn:aws:iam::7xxxxxxxxxx7:role/GitHubRole"],
            principalId:  ["AxxxxxxxxxxxxxxxxxxxL"],
            sessionName:  ["ruzickap@mymac-k8s-1111111111"]}}
```

List Kubernetes RBAC Roles/ClusterRoles used by a given
User/ServiceAccount/Group:

```bash
kubectl rbac-tool lookup kube-prometheus
```

```console
  SUBJECT                                  | SUBJECT TYPE   | SCOPE       | NAMESPACE             | ROLE
+------------------------------------------+----------------+-------------+-----------------------+-------------------------------------------+
  kube-prometheus-stack-grafana            | ServiceAccount | ClusterRole |                       | kube-prometheus-stack-grafana-clusterrole
  kube-prometheus-stack-grafana            | ServiceAccount | Role        | kube-prometheus-stack | kube-prometheus-stack-grafana
  kube-prometheus-stack-kube-state-metrics | ServiceAccount | ClusterRole |                       | kube-prometheus-stack-kube-state-metrics
  kube-prometheus-stack-operator           | ServiceAccount | ClusterRole |                       | kube-prometheus-stack-operator
  kube-prometheus-stack-prometheus         | ServiceAccount | ClusterRole |                       | kube-prometheus-stack-prometheus
```

Kubernetes RBAC visualizer:

```bash
kubectl rbac-tool visualize --include-namespaces ingress-nginx,external-dns --outfile "${TMP_DIR}/rbac.html"
```

![rbac-tool visualize](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-rbac-tool-vis-html.avif)
_rbac-tool visualize_

### [resource-capacity](https://github.com/robscott/kube-capacity)

- Provides an overview of the resource requests, limits, and utilization
  in a Kubernetes cluster.

[resource-capacity](https://github.com/robscott/kube-capacity) krew plugin
installation:

```bash
kubectl krew install resource-capacity
```

Resources + capacity of the nodes:

```bash
kubectl resource-capacity --pod-count --util
```

```console
NODE                            CPU REQUESTS   CPU LIMITS   CPU UTIL    MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL    POD COUNT
*                               1130m (29%)    400m (10%)   135m (3%)   1250Mi (27%)      5048Mi (110%)   2423Mi (53%)   29/220
ip-192-168-26-84.ec2.internal   515m (26%)     0m (0%)      72m (3%)    590Mi (25%)       2644Mi (116%)   1320Mi (57%)   16/110
ip-192-168-7-23.ec2.internal    615m (31%)     400m (20%)   64m (3%)    660Mi (29%)       2404Mi (105%)   1103Mi (48%)   13/110
```

List Resources + capacity of the pods:

```bash
kubectl resource-capacity --pods --util
```

```console
NODE                            NAMESPACE               POD                                                         CPU REQUESTS   CPU LIMITS   CPU UTIL    MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL
*                               *                       *                                                           1130m (29%)    400m (10%)   142m (3%)   1250Mi (27%)      5048Mi (110%)   2414Mi (53%)

ip-192-168-26-84.ec2.internal   *                       *                                                           515m (26%)     0m (0%)      79m (4%)    590Mi (25%)       2644Mi (116%)   1315Mi (57%)
ip-192-168-26-84.ec2.internal   kube-system             aws-node-79jc6                                              25m (1%)       0m (0%)      3m (0%)     0Mi (0%)          0Mi (0%)        32Mi (1%)
ip-192-168-26-84.ec2.internal   kube-system             aws-node-termination-handler-hj8hm                          0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        12Mi (0%)
ip-192-168-26-84.ec2.internal   cert-manager            cert-manager-777fbdc9f8-ng8dg                               0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        25Mi (1%)
ip-192-168-26-84.ec2.internal   cert-manager            cert-manager-cainjector-65857fccf8-krpr9                    0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        22Mi (0%)
ip-192-168-26-84.ec2.internal   cert-manager            cert-manager-webhook-54f9d96756-plv84                       0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-26-84.ec2.internal   kube-system             coredns-7975d6fb9b-hqmxm                                    100m (5%)      0m (0%)      1m (0%)     70Mi (3%)         170Mi (7%)      16Mi (0%)
ip-192-168-26-84.ec2.internal   kube-system             coredns-7975d6fb9b-jhzkw                                    100m (5%)      0m (0%)      2m (0%)     70Mi (3%)         170Mi (7%)      15Mi (0%)
ip-192-168-26-84.ec2.internal   kube-system             ebs-csi-controller-8cc6766cf-nsk5r                          60m (3%)       0m (0%)      3m (0%)     240Mi (10%)       1536Mi (67%)    61Mi (2%)
ip-192-168-26-84.ec2.internal   kube-system             ebs-csi-node-mct6d                                          30m (1%)       0m (0%)      1m (0%)     120Mi (5%)        768Mi (33%)     22Mi (0%)
ip-192-168-26-84.ec2.internal   ingress-nginx           ingress-nginx-controller-9d7cf6ffb-xcw5t                    100m (5%)      0m (0%)      1m (0%)     90Mi (3%)         0Mi (0%)        84Mi (3%)
ip-192-168-26-84.ec2.internal   karpenter               karpenter-6bd66c788f-xnc4s                                  0m (0%)        0m (0%)      11m (0%)    0Mi (0%)          0Mi (0%)        146Mi (6%)
ip-192-168-26-84.ec2.internal   kube-prometheus-stack   kube-prometheus-stack-grafana-896f8645-6q9lb                0m (0%)        0m (0%)      8m (0%)     0Mi (0%)          0Mi (0%)        229Mi (10%)
ip-192-168-26-84.ec2.internal   kube-prometheus-stack   kube-prometheus-stack-prometheus-node-exporter-m4k5m        0m (0%)        0m (0%)      3m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-26-84.ec2.internal   kube-system             kube-proxy-6rfnc                                            100m (5%)      0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        12Mi (0%)
ip-192-168-26-84.ec2.internal   kube-system             metrics-server-57bd7b96f9-nllnn                             0m (0%)        0m (0%)      3m (0%)     0Mi (0%)          0Mi (0%)        20Mi (0%)
ip-192-168-26-84.ec2.internal   oauth2-proxy            oauth2-proxy-87bd47488-v97kg                                0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        8Mi (0%)

ip-192-168-7-23.ec2.internal    *                       *                                                           615m (31%)     400m (20%)   64m (3%)    660Mi (29%)       2404Mi (105%)   1099Mi (48%)
ip-192-168-7-23.ec2.internal    kube-prometheus-stack   alertmanager-kube-prometheus-stack-alertmanager-0           200m (10%)     200m (10%)   1m (0%)     250Mi (10%)       50Mi (2%)       20Mi (0%)
ip-192-168-7-23.ec2.internal    kube-system             aws-node-bg2hc                                              25m (1%)       0m (0%)      2m (0%)     0Mi (0%)          0Mi (0%)        34Mi (1%)
ip-192-168-7-23.ec2.internal    kube-system             aws-node-termination-handler-s66vl                          0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        12Mi (0%)
ip-192-168-7-23.ec2.internal    kube-system             ebs-csi-controller-8cc6766cf-6v668                          60m (3%)       0m (0%)      2m (0%)     240Mi (10%)       1536Mi (67%)    55Mi (2%)
ip-192-168-7-23.ec2.internal    kube-system             ebs-csi-node-zx7bk                                          30m (1%)       0m (0%)      1m (0%)     120Mi (5%)        768Mi (33%)     21Mi (0%)
ip-192-168-7-23.ec2.internal    external-dns            external-dns-7fdb8769ff-dxpdn                               0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        21Mi (0%)
ip-192-168-7-23.ec2.internal    forecastle              forecastle-58d7ccb8f8-hlsf5                                 0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        5Mi (0%)
ip-192-168-7-23.ec2.internal    kube-prometheus-stack   kube-prometheus-stack-kube-state-metrics-669bd5c594-vfznb   0m (0%)        0m (0%)      2m (0%)     0Mi (0%)          0Mi (0%)        13Mi (0%)
ip-192-168-7-23.ec2.internal    kube-prometheus-stack   kube-prometheus-stack-operator-7f45586f68-9rz6j             0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        24Mi (1%)
ip-192-168-7-23.ec2.internal    kube-prometheus-stack   kube-prometheus-stack-prometheus-node-exporter-x5bhm        0m (0%)        0m (0%)      2m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-7-23.ec2.internal    kube-system             kube-proxy-gzqct                                            100m (5%)      0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        13Mi (0%)
ip-192-168-7-23.ec2.internal    mailhog                 mailhog-6f54fccf85-dgbp2                                    0m (0%)        0m (0%)      1m (0%)     0Mi (0%)          0Mi (0%)        4Mi (0%)
ip-192-168-7-23.ec2.internal    kube-prometheus-stack   prometheus-kube-prometheus-stack-prometheus-0               200m (10%)     200m (10%)   25m (1%)    50Mi (2%)         50Mi (2%)       415Mi (18%)
```

### [rolesum](https://github.com/Ladicle/kubectl-rolesum)

- Summarize Kubernetes RBAC roles for the specified subjects.

[rbac-tool](https://github.com/alcideio/rbac-tool) krew plugin
installation:

```bash
kubectl krew install rolesum
```

Show karpenter `ServiceAccount` details:

```bash
kubectl rolesum --namespace karpenter karpenter
```

<!-- markdownlint-disable -->
<!---
ServiceAccount: karpenter/karpenter
Secrets:

Policies:
• [RB] karpenter/karpenter ⟶  [R] karpenter/karpenter
  Resource                          Name        Exclude  Verbs  G L W C U P D DC
  configmaps                        [*]           [-]     [-]   ✖ ✖ ✖ ✔ ✖ ✖ ✖ ✖
  leases.coordination.k8s.io        [*]           [-]     [-]   ✖ ✖ ✖ ✔ ✖ ✖ ✖ ✖
  namespaces                        [*]           [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  secrets                     [karpenter-cert]    [-]     [-]   ✖ ✖ ✖ ✖ ✔ ✖ ✖ ✖


• [CRB] */karpenter ⟶  [CR] */karpenter
  Resource                                                                       Name                   Exclude  Verbs  G L W C U P D DC
  awsnodetemplates.karpenter.k8s.aws                                             [*]                      [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  awsnodetemplates.karpenter.k8s.aws/status                                      [*]                      [-]     [-]   ✖ ✖ ✖ ✖ ✔ ✔ ✖ ✖
  mutatingwebhookconfigurations.admissionregistration.k8s.io    [defaulting.webhook.karpenter.k8s.aws]    [-]     [-]   ✖ ✖ ✖ ✖ ✔ ✖ ✖ ✖
  validatingwebhookconfigurations.admissionregistration.k8s.io  [validation.webhook.karpenter.k8s.aws]    [-]     [-]   ✖ ✖ ✖ ✖ ✔ ✖ ✖ ✖


• [CRB] */karpenter-core ⟶  [CR] */karpenter-core
  Resource                                                                                        Name                                     Exclude  Verbs  G L W C U P D DC
  csinodes.storage.k8s.io                                                                          [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  daemonsets.apps                                                                                  [*]                                       [-]     [-]   ✖ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  deployments.apps                                                                                 [*]                                       [-]     [-]   ✖ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  events                                                                                           [*]                                       [-]     [-]   ✖ ✖ ✖ ✔ ✖ ✔ ✖ ✖
  machines.karpenter.sh                                                                            [*]                                       [-]     [-]   ✔ ✔ ✔ ✔ ✖ ✔ ✔ ✖
  machines.karpenter.sh/status                                                                     [*]                                       [-]     [-]   ✔ ✔ ✔ ✔ ✖ ✔ ✔ ✖
  mutatingwebhookconfigurations.admissionregistration.k8s.io                                       [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  namespaces                                                                                       [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  nodes                                                                                            [*]                                       [-]     [-]   ✔ ✔ ✔ ✔ ✖ ✔ ✔ ✖
  persistentvolumeclaims                                                                           [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  persistentvolumes                                                                                [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  poddisruptionbudgets.policy                                                                      [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  pods                                                                                             [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  pods/eviction                                                                                    [*]                                       [-]     [-]   ✖ ✖ ✖ ✔ ✖ ✖ ✖ ✖
  provisioners.karpenter.sh                                                                        [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  provisioners.karpenter.sh/status                                                                 [*]                                       [-]     [-]   ✔ ✔ ✔ ✔ ✖ ✔ ✔ ✖
  replicasets.apps                                                                                 [*]                                       [-]     [-]   ✖ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  replicationcontrollers                                                                           [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  statefulsets.apps                                                                                [*]                                       [-]     [-]   ✖ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  storageclasses.storage.k8s.io                                                                    [*]                                       [-]     [-]   ✔ ✔ ✔ ✖ ✖ ✖ ✖ ✖
  validatingwebhookconfigurations.admissionregistration.k8s.io  [validation.webhook.karpenter.sh, validation.webhook.config.karpenter.sh]    [-]     [-]   ✖ ✖ ✖ ✖ ✔ ✖ ✖ ✖
-->
<!-- markdownlint-restore -->

![rolesum screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-rolesum.avif)
_rolesum screenshot_

### [stern](https://github.com/stern/stern)

- Multi pod and container log tailing for Kubernetes.

[stern](https://github.com/stern/stern) krew plugin
installation:

```bash
kubectl krew install stern
```

Check logs for all pods in `cert-manager` namespace in past 1 hour:

```bash
kubectl stern -n cert-manager . --tail 5 --since 1h --no-follow
```

<!-- markdownlint-disable -->
<!---
+ cert-manager-webhook-54f9d96756-8nbqx › cert-manager-webhook
+ cert-manager-777fbdc9f8-qhk2d › cert-manager-controller
+ cert-manager-cainjector-65857fccf8-t68lk › cert-manager-cainjector
cert-manager-cainjector-65857fccf8-t68lk cert-manager-cainjector I0624 11:34:24.790420       1 reconciler.go:118] "cert-manager: could not find any ca data in data source for target" kind="validatingwebhookconfiguration" kind="validatingwebhookconfiguration" name="cert-manager-webhook"
cert-manager-cainjector-65857fccf8-t68lk cert-manager-cainjector I0624 11:34:25.603904       1 reconciler.go:142] "cert-manager: Updated object" kind="mutatingwebhookconfiguration" kind="mutatingwebhookconfiguration" name="cert-manager-webhook"
cert-manager-cainjector-65857fccf8-t68lk cert-manager-cainjector I0624 11:34:25.604466       1 reconciler.go:142] "cert-manager: Updated object" kind="validatingwebhookconfiguration" kind="validatingwebhookconfiguration" name="cert-manager-webhook"
cert-manager-cainjector-65857fccf8-t68lk cert-manager-cainjector I0624 11:34:25.609019       1 reconciler.go:142] "cert-manager: Updated object" kind="mutatingwebhookconfiguration" kind="mutatingwebhookconfiguration" name="cert-manager-webhook"
cert-manager-cainjector-65857fccf8-t68lk cert-manager-cainjector I0624 11:34:25.609755       1 reconciler.go:142] "cert-manager: Updated object" kind="validatingwebhookconfiguration" kind="validatingwebhookconfiguration" name="cert-manager-webhook"
cert-manager-777fbdc9f8-qhk2d cert-manager-controller I0624 11:39:26.254284       1 acme.go:233] "cert-manager/certificaterequests-issuer-acme/sign: certificate issued" resource_name="ingress-cert-staging-tnp9z" resource_namespace="cert-manager" resource_kind="CertificateRequest" resource_version="v1" related_resource_name="ingress-cert-staging-tnp9z-569747980" ...
- cert-manager-cainjector-65857fccf8-t68lk › cert-manager-cainjector
cert-manager-777fbdc9f8-qhk2d cert-manager-controller I0624 11:39:26.254523       1 conditions.go:252] Found status change for CertificateRequest "ingress-cert-staging-tnp9z" condition "Ready": "False" -> "True"; setting lastTransitionTime to 2023-06-24 11:39:26.254515881 +0000 UTC m=+301.629669662
cert-manager-777fbdc9f8-qhk2d cert-manager-controller I0624 11:39:26.309171       1 controller.go:162] "cert-manager/certificates-readiness: re-queuing item due to optimistic locking on resource" key="cert-manager/ingress-cert-staging" error="Operation cannot be fulfilled on certificates.cert-manager.io \"ingress-cert-staging\": the object has been modified; please ...
cert-manager-777fbdc9f8-qhk2d cert-manager-controller I0624 11:39:26.322662       1 controller.go:162] "cert-manager/certificates-issuing: re-queuing item due to optimistic locking on resource" key="cert-manager/ingress-cert-staging" error="Operation cannot be fulfilled on certificates.cert-manager.io \"ingress-cert-staging\": the object has been modified; please ...
cert-manager-777fbdc9f8-qhk2d cert-manager-controller I0624 11:39:26.331743       1 controller.go:162] "cert-manager/certificates-key-manager: re-queuing item due to optimistic locking on resource" key="cert-manager/ingress-cert-staging" error="Operation cannot be fulfilled on certificates.cert-manager.io \"ingress-cert-staging\": the object has been modified; ...
- cert-manager-777fbdc9f8-qhk2d › cert-manager-controller
cert-manager-webhook-54f9d96756-8nbqx cert-manager-webhook I0624 11:34:50.197304       1 logs.go:59] http: TLS handshake error from 192.168.113.49:47560: EOF
cert-manager-webhook-54f9d96756-8nbqx cert-manager-webhook I0624 11:34:50.200121       1 logs.go:59] http: TLS handshake error from 192.168.113.49:47572: read tcp 192.168.10.192:10250->192.168.113.49:47572: read: connection reset by peer
cert-manager-webhook-54f9d96756-8nbqx cert-manager-webhook I0624 11:38:31.687229       1 logs.go:59] http: TLS handshake error from 192.168.113.49:54464: EOF
cert-manager-webhook-54f9d96756-8nbqx cert-manager-webhook I0624 11:39:26.294153       1 logs.go:59] http: TLS handshake error from 192.168.113.49:49836: EOF
cert-manager-webhook-54f9d96756-8nbqx cert-manager-webhook I0624 11:39:26.318155       1 logs.go:59] http: TLS handshake error from 192.168.113.49:49852: EOF
- cert-manager-webhook-54f9d96756-8nbqx › cert-manager-webhook
-->
<!-- markdownlint-restore -->

![stern screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-stern.avif)
_stern screenshot_

### [view-allocations](https://github.com/davidB/kubectl-view-allocations)

- Kubectl plugin lists allocations for resources (cpu, memory, gpu,...) as
  defined into the manifest of nodes and running pods.

[view-allocations](https://github.com/davidB/kubectl-view-allocations) krew plugin
installation:

```bash
kubectl krew install view-allocations
```

```bash
kubectl view-allocations --utilization
```

<!-- markdownlint-disable -->
<!---
 Resource                                                            Utilization      Requested         Limit  Allocatable   Free
  attachable-volumes-aws-ebs                                                  __             __            __         78.0     __
  ├─ ip-192-168-19-143.ec2.internal                                           __             __            __         39.0     __
  └─ ip-192-168-3-70.ec2.internal                                             __             __            __         39.0     __
  cpu                                                                 (2%) 74.0m      (29%) 1.1  (10%) 400.0m          3.9    2.7
  ├─ ip-192-168-19-143.ec2.internal                                   (2%) 38.0m   (27%) 515.0m            __          1.9    1.4
  │  ├─ aws-node-gfn9v                                                      2.0m          25.0m            __           __     __
  │  ├─ aws-node-termination-handler-fhcmv                                  1.0m             __            __           __     __
  │  ├─ cert-manager-777fbdc9f8-qhk2d                                       1.0m             __            __           __     __
  │  ├─ cert-manager-cainjector-65857fccf8-t68lk                            1.0m             __            __           __     __
  │  ├─ cert-manager-webhook-54f9d96756-8nbqx                               1.0m             __            __           __     __
  │  ├─ coredns-7975d6fb9b-29885                                            1.0m         100.0m            __           __     __
  │  ├─ coredns-7975d6fb9b-mrfws                                            1.0m         100.0m            __           __     __
  │  ├─ ebs-csi-controller-8cc6766cf-x5mb9                                  6.0m          60.0m            __           __     __
  │  ├─ ebs-csi-node-xtqww                                                  3.0m          30.0m            __           __     __
  │  ├─ ingress-nginx-controller-9d7cf6ffb-vtjhx                            1.0m         100.0m            __           __     __
  │  ├─ karpenter-79455db76f-79q7h                                          6.0m             __            __           __     __
  │  ├─ kube-prometheus-stack-grafana-896f8645-972n2                        9.0m             __            __           __     __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-rw9kh                1.0m             __            __           __     __
  │  ├─ kube-proxy-c97d8                                                    1.0m         100.0m            __           __     __
  │  ├─ metrics-server-57bd7b96f9-mqnqq                                     2.0m             __            __           __     __
  │  └─ oauth2-proxy-66b84b895c-8hv8d                                       1.0m             __            __           __     __
  └─ ip-192-168-3-70.ec2.internal                                     (2%) 36.0m   (32%) 615.0m  (21%) 400.0m          1.9    1.3
     ├─ alertmanager-kube-prometheus-stack-alertmanager-0                   2.0m         200.0m        200.0m           __     __
     ├─ aws-node-termination-handler-hrjv8                                  1.0m             __            __           __     __
     ├─ aws-node-vsr54                                                      3.0m          25.0m            __           __     __
     ├─ ebs-csi-controller-8cc6766cf-69plv                                  6.0m          60.0m            __           __     __
     ├─ ebs-csi-node-j6p6d                                                  3.0m          30.0m            __           __     __
     ├─ external-dns-7fdb8769ff-hjsxr                                       1.0m             __            __           __     __
     ├─ forecastle-58d7ccb8f8-l9dfs                                         1.0m             __            __           __     __
     ├─ kube-prometheus-stack-kube-state-metrics-669bd5c594-jqcjb           1.0m             __            __           __     __
     ├─ kube-prometheus-stack-operator-7f45586f68-jfzhb                     1.0m             __            __           __     __
     ├─ kube-prometheus-stack-prometheus-node-exporter-g7t7l                1.0m             __            __           __     __
     ├─ kube-proxy-d6wqx                                                    1.0m         100.0m            __           __     __
     ├─ mailhog-6f54fccf85-6s7bt                                            1.0m             __            __           __     __
     └─ prometheus-kube-prometheus-stack-prometheus-0                      14.0m         200.0m        200.0m           __     __
  ephemeral-storage                                                           __             __            __        35.9G     __
  ├─ ip-192-168-19-143.ec2.internal                                           __             __            __        17.9G     __
  └─ ip-192-168-3-70.ec2.internal                                             __             __            __        17.9G     __
  memory                                                             (28%) 1.2Gi    (27%) 1.2Gi  (111%) 4.9Gi        4.4Gi    0.0
  ├─ ip-192-168-19-143.ec2.internal                                (31%) 706.9Mi  (26%) 590.0Mi  (116%) 2.6Gi        2.2Gi    0.0
  │  ├─ aws-node-gfn9v                                                    30.8Mi             __            __           __     __
  │  ├─ aws-node-termination-handler-fhcmv                                11.9Mi             __            __           __     __
  │  ├─ cert-manager-777fbdc9f8-qhk2d                                     24.8Mi             __            __           __     __
  │  ├─ cert-manager-cainjector-65857fccf8-t68lk                          22.5Mi             __            __           __     __
  │  ├─ cert-manager-webhook-54f9d96756-8nbqx                              9.4Mi             __            __           __     __
  │  ├─ coredns-7975d6fb9b-29885                                          14.8Mi         70.0Mi       170.0Mi           __     __
  │  ├─ coredns-7975d6fb9b-mrfws                                          14.6Mi         70.0Mi       170.0Mi           __     __
  │  ├─ ebs-csi-controller-8cc6766cf-x5mb9                                54.8Mi        240.0Mi         1.5Gi           __     __
  │  ├─ ebs-csi-node-xtqww                                                21.1Mi        120.0Mi       768.0Mi           __     __
  │  ├─ ingress-nginx-controller-9d7cf6ffb-vtjhx                          74.0Mi         90.0Mi            __           __     __
  │  ├─ karpenter-79455db76f-79q7h                                       150.3Mi             __            __           __     __
  │  ├─ kube-prometheus-stack-grafana-896f8645-972n2                     232.3Mi             __            __           __     __
  │  ├─ kube-prometheus-stack-prometheus-node-exporter-rw9kh               8.6Mi             __            __           __     __
  │  ├─ kube-proxy-c97d8                                                  11.9Mi             __            __           __     __
  │  ├─ metrics-server-57bd7b96f9-mqnqq                                   18.1Mi             __            __           __     __
  │  └─ oauth2-proxy-66b84b895c-8hv8d                                      7.1Mi             __            __           __     __
  └─ ip-192-168-3-70.ec2.internal                                  (24%) 546.6Mi  (29%) 660.0Mi  (106%) 2.3Gi        2.2Gi    0.0
     ├─ alertmanager-kube-prometheus-stack-alertmanager-0                 18.1Mi        250.0Mi        50.0Mi           __     __
     ├─ aws-node-termination-handler-hrjv8                                11.9Mi             __            __           __     __
     ├─ aws-node-vsr54                                                    30.8Mi             __            __           __     __
     ├─ ebs-csi-controller-8cc6766cf-69plv                                53.0Mi        240.0Mi         1.5Gi           __     __
     ├─ ebs-csi-node-j6p6d                                                21.3Mi        120.0Mi       768.0Mi           __     __
     ├─ external-dns-7fdb8769ff-hjsxr                                     20.4Mi             __            __           __     __
     ├─ forecastle-58d7ccb8f8-l9dfs                                        4.3Mi             __            __           __     __
     ├─ kube-prometheus-stack-kube-state-metrics-669bd5c594-jqcjb         12.1Mi             __            __           __     __
     ├─ kube-prometheus-stack-operator-7f45586f68-jfzhb                   23.9Mi             __            __           __     __
     ├─ kube-prometheus-stack-prometheus-node-exporter-g7t7l               8.0Mi             __            __           __     __
     ├─ kube-proxy-d6wqx                                                  10.5Mi             __            __           __     __
     ├─ mailhog-6f54fccf85-6s7bt                                           3.3Mi             __            __           __     __
     └─ prometheus-kube-prometheus-stack-prometheus-0                    329.1Mi         50.0Mi        50.0Mi           __     __
  pods                                                                        __     (13%) 29.0    (13%) 29.0        220.0  191.0
  ├─ ip-192-168-19-143.ec2.internal                                           __     (15%) 16.0    (15%) 16.0        110.0   94.0
  └─ ip-192-168-3-70.ec2.internal                                             __     (12%) 13.0    (12%) 13.0        110.0   97.0
-->
<!-- markdownlint-restore -->

![view-allocations screenshot](/assets/img/posts/2023/2023-06-06-my-favourite-krew-plugins-kubectl/kubectl-plugin-view-allocations.avif)
_view-allocations screenshot_

### [viewnode](https://github.com/NTTDATA-DACH/viewnode)

- Viewnode displays Kubernetes cluster nodes with their pods and containers.

[viewnode](https://github.com/NTTDATA-DACH/viewnode) krew plugin
installation:

```bash
kubectl krew install viewnode
```

```bash
kubectl viewnode --all-namespaces --show-metrics
```

```console
29 pod(s) in total
0 unscheduled pod(s)
2 running node(s) with 29 scheduled pod(s):
- ip-192-168-19-143.ec2.internal running 16 pod(s) (linux/arm64/containerd://1.6.20+bottlerocket | mem: 1.3 GiB)
  * cert-manager: cert-manager-777fbdc9f8-qhk2d (running | mem usage: 24.8 MiB)
  * cert-manager: cert-manager-cainjector-65857fccf8-t68lk (running | mem usage: 22.4 MiB)
  * cert-manager: cert-manager-webhook-54f9d96756-8nbqx (running | mem usage: 9.4 MiB)
  * ingress-nginx: ingress-nginx-controller-9d7cf6ffb-vtjhx (running | mem usage: 74.3 MiB)
  * karpenter: karpenter-79455db76f-79q7h (running | mem usage: 164.2 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-grafana-896f8645-972n2 (running | mem usage: 232.2 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-rw9kh (running | mem usage: 8.0 MiB)
  * kube-system: aws-node-gfn9v (running | mem usage: 30.8 MiB)
  * kube-system: aws-node-termination-handler-fhcmv (running | mem usage: 11.9 MiB)
  * kube-system: coredns-7975d6fb9b-29885 (running | mem usage: 14.8 MiB)
  * kube-system: coredns-7975d6fb9b-mrfws (running | mem usage: 14.6 MiB)
  * kube-system: ebs-csi-controller-8cc6766cf-x5mb9 (running | mem usage: 55.3 MiB)
  * kube-system: ebs-csi-node-xtqww (running | mem usage: 21.2 MiB)
  * kube-system: kube-proxy-c97d8 (running | mem usage: 11.9 MiB)
  * kube-system: metrics-server-57bd7b96f9-mqnqq (running | mem usage: 17.7 MiB)
  * oauth2-proxy: oauth2-proxy-66b84b895c-8hv8d (running | mem usage: 6.8 MiB)
- ip-192-168-3-70.ec2.internal running 13 pod(s) (linux/arm64/containerd://1.6.20+bottlerocket | mem: 940.6 MiB)
  * external-dns: external-dns-7fdb8769ff-hjsxr (running | mem usage: 19.6 MiB)
  * forecastle: forecastle-58d7ccb8f8-l9dfs (running | mem usage: 4.3 MiB)
  * kube-prometheus-stack: alertmanager-kube-prometheus-stack-alertmanager-0 (running | mem usage: 18.2 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-kube-state-metrics-669bd5c594-jqcjb (running | mem usage: 12.2 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-operator-7f45586f68-jfzhb (running | mem usage: 22.8 MiB)
  * kube-prometheus-stack: kube-prometheus-stack-prometheus-node-exporter-g7t7l (running | mem usage: 8.5 MiB)
  * kube-prometheus-stack: prometheus-kube-prometheus-stack-prometheus-0 (running | mem usage: 328.1 MiB)
  * kube-system: aws-node-termination-handler-hrjv8 (running | mem usage: 11.9 MiB)
  * kube-system: aws-node-vsr54 (running | mem usage: 30.8 MiB)
  * kube-system: ebs-csi-controller-8cc6766cf-69plv (running | mem usage: 53.0 MiB)
  * kube-system: ebs-csi-node-j6p6d (running | mem usage: 21.5 MiB)
  * kube-system: kube-proxy-d6wqx (running | mem usage: 10.5 MiB)
  * mailhog: mailhog-6f54fccf85-6s7bt (running | mem usage: 3.4 MiB)
```

Show various details for `kube-prometheus-stack` namespace:

```bash
kubectl viewnode -n kube-prometheus-stack --container-block-view --show-containers --show-metrics --show-pod-start-times --show-requests-and-limits
```

```console
7 pod(s) in total
0 unscheduled pod(s)
2 running node(s) with 7 scheduled pod(s):
- ip-192-168-19-143.ec2.internal running 2 pod(s) (linux/arm64/containerd://1.6.20+bottlerocket | mem: 1.3 GiB)
  * kube-prometheus-stack-grafana-896f8645-972n2 (running/Sat Jun 24 11:34:12 UTC 2023 | mem usage: 229.3 MiB) 3 container/s:
    0: grafana (running) [cpu: - | mem: - | mem usage: 86.7 MiB]
    1: grafana-sc-dashboard (running) [cpu: - | mem: - | mem usage: 70.6 MiB]
    2: grafana-sc-datasources (running) [cpu: - | mem: - | mem usage: 72.0 MiB]
  * kube-prometheus-stack-prometheus-node-exporter-rw9kh (running/Sat Jun 24 11:34:12 UTC 2023 | mem usage: 8.2 MiB) 1 container/s:
    0: node-exporter (running) [cpu: - | mem: - | mem usage: 8.2 MiB]
- ip-192-168-3-70.ec2.internal running 5 pod(s) (linux/arm64/containerd://1.6.20+bottlerocket | mem: 942.2 MiB)
  * alertmanager-kube-prometheus-stack-alertmanager-0 (running/Sat Jun 24 11:34:15 UTC 2023 | mem usage: 18.2 MiB) 2 container/s:
    0: alertmanager (running) [cpu: - | mem: 200Mi<- | mem usage: 15.6 MiB]
    1: config-reloader (running) [cpu: 200m<200m | mem: 50Mi<50Mi | mem usage: 2.7 MiB]
  * kube-prometheus-stack-kube-state-metrics-669bd5c594-jqcjb (running/Sat Jun 24 11:34:12 UTC 2023 | mem usage: 12.2 MiB) 1 container/s:
    0: kube-state-metrics (running) [cpu: - | mem: - | mem usage: 12.2 MiB]
  * kube-prometheus-stack-operator-7f45586f68-jfzhb (running/Sat Jun 24 11:34:12 UTC 2023 | mem usage: 22.5 MiB) 1 container/s:
    0: kube-prometheus-stack (running) [cpu: - | mem: - | mem usage: 22.5 MiB]
  * kube-prometheus-stack-prometheus-node-exporter-g7t7l (running/Sat Jun 24 11:34:12 UTC 2023 | mem usage: 8.7 MiB) 1 container/s:
    0: node-exporter (running) [cpu: - | mem: - | mem usage: 8.7 MiB]
  * prometheus-kube-prometheus-stack-prometheus-0 (running/Sat Jun 24 11:34:20 UTC 2023 | mem usage: 328.1 MiB) 2 container/s:
    0: config-reloader (running) [cpu: 200m<200m | mem: 50Mi<50Mi | mem usage: 6.0 MiB]
    1: prometheus (running) [cpu: - | mem: - | mem usage: 322.0 MiB]
```

There are few "kubectl krew plugins" which I looked at, but I'm not using them:
[aks](https://github.com/Azure/kubectl-aks), [view-cert](https://github.com/lmolas/kubectl-view-cert),
[cost](https://github.com/kubecost/kubectl-cost), [cyclonus](https://github.com/mattfenwick/kubectl-cyclonus),
[graph](https://github.com/steveteuber/kubectl-graph), [ingress-nginx](https://kubernetes.github.io/ingress-nginx/kubectl-plugin/)
[node-shell](https://github.com/kvaps/kubectl-node-shell), [nodepools](https://github.com/grafana/kubectl-nodepools),
[np-viewer](https://github.com/runoncloud/kubectl-np-viewer), [oomd](https://github.com/jdockerty/kubectl-oomd),
[permissions](https://github.com/garethjevans/kubectl-permissions), [popeye](https://popeyecli.io/),
[pv-migrate](https://github.com/utkuozdemir/pv-migrate), [score](https://kube-score.com/),
[ssh-jump](https://github.com/yokawasa/kubectl-plugin-ssh-jump), [tree](https://github.com/ahmetb/kubectl-tree),
[unlimited](https://github.com/nilic/kubectl-unlimited), [whoami](https://github.com/rajatjindal/kubectl-whoami)

## Clean-up

Remove files in `${TMP_DIR}` directory:

```sh
for FILE in "${TMP_DIR}"/{krew-linux_amd64,rbac.html}; do
  if [[ -f "${FILE}" ]]; then
    rm -v "${FILE}"
  else
    echo "*** File not found: ${FILE}"
  fi
done
```

Enjoy ... 😉
