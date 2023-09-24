---
title: Trivy Operator Dashboard in Grafana
author: Petr Ruzicka
date: 2023-03-08
description: Deploy Trivy Operator and Grafana Dashboard
categories: [Kubernetes, Amazon EKS, Security]
tags: [Amazon EKS, k8s, kubernetes, grafana, trivy-operator, dashboard]
image:
  path: https://raw.githubusercontent.com/aquasecurity/trivy-vscode-extension/02fa1bf2b5e1333647ebd1bced679f4e94f8bf39/media/trivy.svg
---

In the previous post related to
[Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})
I decided to install [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
to enable cluster monitoring containing [Grafana](https://grafana.com/), [Prometheus](https://prometheus.io/)
and few other components.

There are many tools which allows you to scan container images and show their
vulnerabilities like [Trivy](https://trivy.dev/), [Grype](https://github.com/anchore/grype)
or [Clair](https://github.com/quay/clair).

Unfortunately there are not so many OSS tools which can show you vulnerabilities
of the container images running inside the K8s.
This is usually paid offering provided by 3rd party vendors like [Palo Alto](https://www.paloaltonetworks.com/prisma/cloud),
[Aqua](https://www.aquasec.com/), [Wiz](https://www.wiz.io/), and many others...

Let's looks at the [Trivy Operator](https://github.com/aquasecurity/trivy-operator)
which can help you build the security posture (Compliance, Vulnerabilities,
RBAC, ...) for your Kubernetes cluster.

I'll walk you through the installation, integration it with Prometheus+Grafana
and some examples to better understand how it works...

Links:

* [Trivy Operator Dashboard in Grafana](https://aquasecurity.github.io/trivy-operator/v0.12.0/tutorials/grafana-dashboard/)
* [Kubernetes Benchmark Scans with Trivy: CIS and NSA Reports](https://blog.aquasec.com/kubernetes-benchmark-scans-trivy-cis-nsa-reports)

## Requirements

* Amazon EKS cluster with [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
  installed (described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}))
* [Helm](https://helm.sh/)

Variables which are being used in the next steps:

```bash
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

## Install Trivy Operator

Install `trivy-operator`
[helm chart](https://artifacthub.io/packages/helm/trivy-operator/trivy-operator)
and modify the
[default values](https://github.com/aquasecurity/trivy-operator/blob/main/deploy/helm/values.yaml).

![trivy-operator](https://raw.githubusercontent.com/aquasecurity/trivy-operator/e5722da903ff16d5fd926ed46fdffacf5d50d9b5/docs/images/trivy-operator-logo.png
"trivy-operator"){: width="500" }

```bash
# renovate: datasource=helm depName=trivy-operator registryUrl=https://aquasecurity.github.io/helm-charts/
TRIVY_OPERATOR_HELM_CHART_VERSION="0.18.0"

helm repo add --force-update aqua https://aquasecurity.github.io/helm-charts/
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-trivy-operator.yml" << EOF
serviceMonitor:
  enabled: true
trivy:
  ignoreUnfixed: true
EOF
helm upgrade --install --version "${TRIVY_OPERATOR_HELM_CHART_VERSION}" --namespace trivy-system --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-trivy-operator.yml" trivy-operator aqua/trivy-operator
```

Once the helm chart is installed you can see the trivy-operator initiated
"scanning":

```bash
kubectl get pods -n trivy-system
```

```console
NAME                                        READY   STATUS      RESTARTS   AGE
node-collector-7555455fcf-q4dp6             0/1     Completed   0          11s
node-collector-7f544b4779-7p5zr             0/1     Completed   0          11s
scan-vulnerabilityreport-55bc49bd77-nr5br   0/2     Init:0/1    0          9s
scan-vulnerabilityreport-594f6f446-v64sp    0/1     Init:0/1    0          2s
scan-vulnerabilityreport-65cd458f97-6zbs8   0/3     Init:0/1    0          4s
scan-vulnerabilityreport-6d9888f48-vrtxg    0/4     Init:0/1    0          2s
scan-vulnerabilityreport-74b9cf67dd-mpqgj   0/1     Init:0/1    0          11s
scan-vulnerabilityreport-77875c6784-vwkv2   0/1     Init:0/1    0          1s
scan-vulnerabilityreport-7bd5758c7b-5wjqq   0/1     Init:0/1    0          8s
scan-vulnerabilityreport-7dc9c49c47-gfrlk   0/3     Init:0/1    0          6s
scan-vulnerabilityreport-978494f65-ggd8g    0/3     Init:0/1    0          7s
scan-vulnerabilityreport-c7b7fbfdd-284zv    0/1     Init:0/1    0          5s
trivy-operator-56bdc96f8-dls8c              1/1     Running     0          15s
```

## Trivy Operator details

Let's take some examples to see how the [Trivy Operator](https://github.com/aquasecurity/trivy-operator)
can help with identifying the security issues in the K8s cluster.

> The outputs below were created on the 2023-03-12 and will be different in the
> future...
{: .prompt-warning }

### Vulnerability Reports

Deploy vulnerable (old) version of the [nginx:1.22.0](https://hub.docker.com/layers/library/nginx/1.22.0/images/sha256-b3a676a9145dc005062d5e79b92d90574fb3bf2396f4913dc1732f9065f55c4b?context=explore)
to the cluster:

[//]: # (https://github.com/kubernetes/kubernetes/issues/83242)

{% raw %}

```bash
kubectl create namespace test-trivy1
kubectl run nginx --namespace=test-trivy1 --image=nginx:1.22.0

echo -n "Waiting for trivy-operator to create VulnerabilityReports: "
until kubectl get vulnerabilityreports -n test-trivy1 -o go-template='{{.items | len}}' | grep -qxF 1; do
  echo -n "."
  sleep 3
done
```

{% endraw %}

See the summary of the container image vulnerabilities which are present in old
version of nginx:

```bash
kubectl get vulnerabilityreports -n test-trivy1 -o wide
```

```console
NAME              REPOSITORY      TAG      SCANNER   AGE     CRITICAL   HIGH   MEDIUM   LOW   UNKNOWN
pod-nginx-nginx   library/nginx   1.22.0   Trivy     4m33s   3          18     39       0     0
```

Examine [VulnerabilityReports](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/vulnerability-report/)
which represents the latest vulnerabilities found in a container image of
a given Kubernetes workload. It consists of a list of OS package and application
vulnerabilities with a summary of vulnerabilities grouped by severity.

```bash
kubectl describe vulnerabilityreports -n test-trivy1
```

```console
Name:         pod-nginx-nginx
Namespace:    test-trivy1
Labels:       resource-spec-hash=5b79d7b777
              trivy-operator.container.name=nginx
              trivy-operator.resource.kind=Pod
              trivy-operator.resource.name=nginx
              trivy-operator.resource.namespace=test-trivy1
Annotations:  trivy-operator.aquasecurity.github.io/report-ttl: 24h0m0s
API Version:  aquasecurity.github.io/v1alpha1
Kind:         VulnerabilityReport
Metadata:
  Creation Timestamp:  2023-03-14T04:28:11Z
  Generation:          1
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:28:11Z
  Owner References:
    API Version:           v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  Pod
    Name:                  nginx
    UID:                   c879915a-7f0a-4ac1-a507-c9c47e69aa42
  Resource Version:        114086
  UID:                     7531bd9b-2fe2-40cd-9223-280af46bebec
Report:
  Artifact:
    Repository:  library/nginx
    Tag:         1.22.0
  Registry:
    Server:  index.docker.io
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.38.2
  Summary:
    Critical Count:  3
    High Count:      18
    Low Count:       0
    Medium Count:    39
    None Count:      0
    Unknown Count:   0
  Update Timestamp:  2023-03-14T04:28:11Z
  Vulnerabilities:
    Fixed Version:      7.74.0-1.3+deb11u5
    Installed Version:  7.74.0-1.3+deb11u3
    Links:
    Primary Link:       https://avd.aquasec.com/nvd/cve-2022-32221
    Resource:           curl
    Score:              4.8
    Severity:           CRITICAL
    Target:
    Title:              curl: POST following PUT confusion
    Vulnerability ID:   CVE-2022-32221
    Fixed Version:      7.74.0-1.3+deb11u7
    Installed Version:  7.74.0-1.3+deb11u3
    Links:
    Primary Link:       https://avd.aquasec.com/nvd/cve-2023-23916
    Resource:           curl
    Score:              6.5
    Severity:           HIGH
    Target:
    Title:              curl: HTTP multi-header compression denial of service
    Vulnerability ID:   CVE-2023-23916
    Fixed Version:      7.74.0-1.3+deb11u5
    Installed Version:  7.74.0-1.3+deb11u3
    Links:
    Primary Link:       https://avd.aquasec.com/nvd/cve-2022-43552
    Resource:           curl
    Score:              5.9
    Severity:           MEDIUM
...
```

You can easily get the list of container image vulnerabilities for the whole
cluster:

```bash
kubectl get vulnerabilityreports --all-namespaces -o wide
```

```console
NAMESPACE               NAME                                                              REPOSITORY                                       TAG          SCANNER   AGE   CRITICAL   HIGH   MEDIUM   LOW   UNKNOWN
cert-manager            replicaset-6bdbc5f78f                                             jetstack/cert-manager-cainjector                 v1.11.0      Trivy     12m   0          1      0        0     0
cert-manager            replicaset-cert-manager-68784d64d7-cert-manager-controller        jetstack/cert-manager-controller                 v1.11.0      Trivy     12m   0          1      0        0     0
cert-manager            replicaset-cert-manager-webhook-6787f645b9-cert-manager-webhook   jetstack/cert-manager-webhook                    v1.11.0      Trivy     13m   0          1      0        0     0
external-dns            replicaset-external-dns-58995955b-external-dns                    external-dns/external-dns                        v0.13.2      Trivy     12m   0          13     4        0     0
forecastle              replicaset-forecastle-7b645d64bf-forecastle                       stakater/forecastle                              v1.0.121     Trivy     12m   0          1      1        0     0
ingress-nginx           replicaset-ingress-nginx-controller-f958b4d8d-controller          ingress-nginx/controller                                      Trivy     12m   2          3      2        0     0
karpenter               replicaset-karpenter-565b558f9-controller                         karpenter/controller                                          Trivy     12m   0          0      0        0     0
kube-prometheus-stack   daemonset-6c9bb4f54f                                              prometheus/node-exporter                         v1.5.0       Trivy     13m   0          1      1        0     0
kube-prometheus-stack   replicaset-56c596c9bb                                             curlimages/curl                                  7.85.0       Trivy     13m   0          6      3        0     0
kube-prometheus-stack   replicaset-5b5d6f8fb8                                             kiwigrid/k8s-sidecar                             1.22.0       Trivy     13m   0          7      2        0     0
kube-prometheus-stack   replicaset-64556849bd                                             prometheus-operator/prometheus-operator          v0.63.0      Trivy     12m   0          1      1        0     0
kube-prometheus-stack   replicaset-79cd99d94                                              kiwigrid/k8s-sidecar                             1.22.0       Trivy     13m   0          7      2        0     0
kube-prometheus-stack   replicaset-d894b795d                                              kube-state-metrics/kube-state-metrics            v2.8.1       Trivy     13m   0          1      0        0     0
kube-prometheus-stack   replicaset-kube-prometheus-stack-grafana-646bc57bb6-grafana       grafana/grafana                                  9.3.8        Trivy     13m   0          2      3        0     0
kube-prometheus-stack   statefulset-55c7d87c7d                                            prometheus-operator/prometheus-config-reloader   v0.63.0      Trivy     13m   0          0      0        0     0
kube-prometheus-stack   statefulset-646865b49b                                            prometheus-operator/prometheus-config-reloader   v0.63.0      Trivy     13m   0          0      0        0     0
kube-prometheus-stack   statefulset-6547f6bbc9                                            prometheus/prometheus                            v2.42.0      Trivy     13m   0          2      0        0     0
kube-prometheus-stack   statefulset-6ddfb59cf5                                            prometheus-operator/prometheus-config-reloader   v0.63.0      Trivy     13m   0          0      0        0     0
kube-prometheus-stack   statefulset-758c4b8b8                                             prometheus/alertmanager                          v0.25.0      Trivy     13m   0          2      0        0     0
kube-system             daemonset-6b8684d996                                              aws-ec2/aws-node-termination-handler             v1.19.0      Trivy     13m   0          2      1        0     0
kube-system             replicaset-metrics-server-7df9d78f65-metrics-server               metrics-server/metrics-server                    v0.6.2       Trivy     12m   1          3      2        0     0
mailhog                 replicaset-mailhog-6f54fccf85-mailhog                             cd2team/mailhog                                  1663459324   Trivy     13m   0          6      2        0     0
oauth2-proxy            replicaset-oauth2-proxy-f5f86cd5d-oauth2-proxy                    oauth2-proxy/oauth2-proxy                        v7.4.0       Trivy     12m   0          8      3        0     0
test-trivy1             pod-nginx-nginx                                                   library/nginx                                    1.22.0       Trivy     12m   3          18     39       0     0
trivy-system            replicaset-trivy-operator-56bdc96f8-trivy-operator                aquasecurity/trivy-operator                      0.12.1       Trivy     13m   0          0      0        0     0
```

### Compliance Reports

I'm going to deploy a pod with `hostIPC: true` and then look at the compliance
report.

Links:

* [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
* [Bad Pod #7: HOSTIPC Only](https://bishopfox.com/blog/kubernetes-pod-privilege-escalation#pod7)

![Center for Internet Security](https://upload.wikimedia.org/wikipedia/en/2/2e/Center_for_Internet_Security_Logo.png)
_Center for Internet Security_

Here is the list of supported Compliance Reports:

```bash
kubectl get clustercompliancereports
```

```console
NAME             AGE
cis              15m
nsa              15m
pss-baseline     15m
pss-restricted   15m
```

We are currently interested in [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
and [Minimize the admission of containers wishing to share the host IPC namespace](https://github.com/aquasecurity/kube-bench/blob/7aeb6c39774763e74979a0904e374df01844bf21/cfg/cis-1.20/policies.yaml):

```bash
kubectl get clustercompliancereports cis -o json | jq '.spec.compliance.controls[] | select(.name=="Minimize the admission of containers wishing to share the host IPC namespace")'
```

```json
{
  "checks": [
    {
      "id": "AVD-KSV-0008"
    }
  ],
  "description": "Do not generally permit containers to be run with the hostIPC flag set to true",
  "id": "5.2.4",
  "name": "Minimize the admission of containers wishing to share the host IPC namespace",
  "severity": "HIGH"
}
```

Let's create new namespace with the pod which has `hostIPC: true` parameter
present k8s yaml manifest:

{% raw %}

```bash
kubectl create namespace test-trivy2
kubectl apply --namespace=test-trivy2 -f - << \EOF
apiVersion: v1
kind: Pod
metadata:
  name: hostipc-exec-pod
  labels:
    app: pentest
spec:
  automountServiceAccountToken: false
  hostIPC: true                            # <<<<<<<< This is the security issue
  containers:
  - name: hostipc-pod
    image: k8s.gcr.io/pause:3.6
    resources:
      requests:
        memory: "1Mi"
        cpu: "1m"
      limits:
        memory: "16Mi"
        cpu: "20m"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
      readOnlyRootFilesystem: true
      runAsGroup: 30000
      runAsNonRoot: true
      runAsUser: 20000
      seccompProfile:
        type: RuntimeDefault
EOF

echo -n "Waiting for trivy-operator to create ConfigAuditReports: "
until kubectl get configauditreports -n test-trivy2 -o go-template='{{.items | len}}' | grep -qxF 1; do
  echo -n "."
  sleep 5
done
```

{% endraw %}

An instance of the [ConfigAuditReports](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/configaudit-report/)
represents checks performed by [Trivy](https://trivy.dev/), against a Kubernetes
object's configuration.

The introduced security issue is visible in [ConfigAuditReports](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/configaudit-report/):

```bash
kubectl describe configauditreports -n test-trivy2
```

```console
Name:         pod-hostipc-exec-pod
Namespace:    test-trivy2
Labels:       plugin-config-hash=659b7b9c46
              resource-spec-hash=7f9b85d646
              trivy-operator.resource.kind=Pod
              trivy-operator.resource.name=hostipc-exec-pod
              trivy-operator.resource.namespace=test-trivy2
Annotations:  trivy-operator.aquasecurity.github.io/report-ttl: 24h0m0s
API Version:  aquasecurity.github.io/v1alpha1
Kind:         ConfigAuditReport
Metadata:
  Creation Timestamp:  2023-03-14T04:41:51Z
  Generation:          2
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:41:53Z
  Owner References:
    API Version:           v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  Pod
    Name:                  hostipc-exec-pod
    UID:                   c1b84929-b947-452c-95b4-d1fc2f8dc11d
  Resource Version:        117561
  UID:                     5deb58ae-b18d-4c85-b757-5e877c3abeae
Report:
  Checks:
    Category:     Kubernetes Security Check
    Check ID:     KSV008
    Description:  Sharing the host's IPC namespace allows container processes to communicate with processes on the host.
    Messages:
      Pod 'hostipc-exec-pod' should not set 'spec.template.spec.hostIPC' to true
    Severity:  HIGH
    Success:   false
    Title:     Access to host IPC namespace
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.12.1
  Summary:
    Critical Count:  0
    High Count:      1
    Low Count:       0
    Medium Count:    0
  Update Timestamp:  2023-03-14T04:41:53Z
Events:              <none>
```

Like in previous example you can see the compliance report of the whole cluster:

```bash
kubectl get configauditreports --all-namespaces -o wide
```

```console
NAMESPACE               NAME                                                             SCANNER   AGE   CRITICAL   HIGH   MEDIUM   LOW
cert-manager            replicaset-cert-manager-68784d64d7                               Trivy     16m   0          0      0        7
cert-manager            replicaset-cert-manager-cainjector-547c9b8f95                    Trivy     15m   0          0      0        7
cert-manager            replicaset-cert-manager-webhook-6787f645b9                       Trivy     14m   0          0      0        7
cert-manager            service-cert-manager                                             Trivy     14m   0          0      0        0
cert-manager            service-cert-manager-webhook                                     Trivy     15m   0          0      0        0
default                 service-kubernetes                                               Trivy     14m   0          0      0        1
external-dns            replicaset-external-dns-58995955b                                Trivy     16m   0          0      1        6
external-dns            service-external-dns                                             Trivy     15m   0          0      0        0
forecastle              replicaset-forecastle-7b645d64bf                                 Trivy     15m   0          0      2        10
forecastle              service-forecastle                                               Trivy     15m   0          0      0        0
ingress-nginx           replicaset-ingress-nginx-controller-f958b4d8d                    Trivy     15m   0          0      3        6
ingress-nginx           service-ingress-nginx-controller                                 Trivy     14m   0          0      0        0
ingress-nginx           service-ingress-nginx-controller-admission                       Trivy     15m   0          0      0        0
ingress-nginx           service-ingress-nginx-controller-metrics                         Trivy     15m   0          0      0        0
karpenter               replicaset-karpenter-565b558f9                                   Trivy     15m   0          0      2        10
karpenter               service-karpenter                                                Trivy     15m   0          0      0        0
kube-prometheus-stack   daemonset-kube-prometheus-stack-prometheus-node-exporter         Trivy     15m   0          3      2        10
kube-prometheus-stack   replicaset-kube-prometheus-stack-grafana-646bc57bb6              Trivy     14m   0          0      8        34
kube-prometheus-stack   replicaset-kube-prometheus-stack-kube-state-metrics-5979d9d98c   Trivy     16m   0          0      2        10
kube-prometheus-stack   replicaset-kube-prometheus-stack-operator-5df65d688f             Trivy     15m   0          0      0        9
kube-prometheus-stack   service-alertmanager-operated                                    Trivy     14m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-alertmanager                       Trivy     16m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-grafana                            Trivy     15m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-kube-state-metrics                 Trivy     16m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-operator                           Trivy     16m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-prometheus                         Trivy     14m   0          0      0        0
kube-prometheus-stack   service-kube-prometheus-stack-prometheus-node-exporter           Trivy     14m   0          0      0        0
kube-prometheus-stack   service-prometheus-operated                                      Trivy     14m   0          0      0        0
kube-prometheus-stack   statefulset-alertmanager-kube-prometheus-stack-alertmanager      Trivy     16m   0          0      0        8
kube-prometheus-stack   statefulset-prometheus-kube-prometheus-stack-prometheus          Trivy     16m   0          0      0        11
kube-system             daemonset-aws-node                                               Trivy     16m   0          3      7        17
kube-system             daemonset-aws-node-termination-handler                           Trivy     15m   0          1      2        9
kube-system             daemonset-ebs-csi-node                                           Trivy     15m   0          1      8        12
kube-system             daemonset-ebs-csi-node-windows                                   Trivy     16m   0          0      8        14
kube-system             daemonset-kube-proxy                                             Trivy     16m   0          2      4        9
kube-system             replicaset-coredns-7975d6fb9b                                    Trivy     14m   0          0      3        5
kube-system             replicaset-ebs-csi-controller-646b59c99                          Trivy     15m   0          0      1        20
kube-system             replicaset-metrics-server-7df9d78f65                             Trivy     15m   0          0      1        9
kube-system             service-kube-dns                                                 Trivy     15m   0          0      1        0
kube-system             service-kube-prometheus-stack-coredns                            Trivy     14m   0          0      1        0
kube-system             service-kube-prometheus-stack-kubelet                            Trivy     14m   0          0      1        0
kube-system             service-metrics-server                                           Trivy     14m   0          0      1        0
mailhog                 replicaset-mailhog-6f54fccf85                                    Trivy     14m   0          0      0        7
mailhog                 service-mailhog                                                  Trivy     16m   0          0      0        0
oauth2-proxy            replicaset-oauth2-proxy-f5f86cd5d                                Trivy     15m   0          0      2        10
oauth2-proxy            service-oauth2-proxy                                             Trivy     14m   0          0      0        0
test-trivy1             pod-nginx                                                        Trivy     15m   0          0      3        10
test-trivy2             pod-hostipc-exec-pod                                             Trivy     59s   0          1      0        0
trivy-system            replicaset-trivy-operator-56bdc96f8                              Trivy     14m   0          0      1        7
trivy-system            service-trivy-operator                                           Trivy     15m   0          0      0        0
```

### Exposed Secrets Report

[ExposedSecretReport](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/exposedsecret-report/)
represents the secrets found in a container image of a given Kubernetes
workload.

Look at the example of the container which has ssh keys inside it:

{% raw %}

```bash
kubectl create namespace test-trivy3
kubectl run ubuntu-sshd-exposed-secrets --namespace=test-trivy3 --image=peru/ubuntu_sshd --overrides='{"spec": { "nodeSelector": {"kubernetes.io/arch": "amd64"}}}'

echo -n "Waiting for trivy-operator to create ExposedSecretReports: "
until kubectl get exposedsecretreports -n test-trivy3 -o go-template='{{.items | len}}' | grep -qxF 1; do
  echo -n "."
  sleep 3
done
```

{% endraw %}

After looking into the [ExposedSecretReport](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/exposedsecret-report/)
details it should be easy to identify the problem:

```bash
kubectl describe exposedsecretreport -n test-trivy3
```

```console
Name:         pod-ubuntu-sshd-exposed-secrets-ubuntu-sshd-exposed-secrets
Namespace:    test-trivy3
Labels:       resource-spec-hash=b9d794b6b
              trivy-operator.container.name=ubuntu-sshd-exposed-secrets
              trivy-operator.resource.kind=Pod
              trivy-operator.resource.name=ubuntu-sshd-exposed-secrets
              trivy-operator.resource.namespace=test-trivy3
Annotations:  trivy-operator.aquasecurity.github.io/report-ttl: 24h0m0s
API Version:  aquasecurity.github.io/v1alpha1
Kind:         ExposedSecretReport
Metadata:
  Creation Timestamp:  2023-03-14T04:44:08Z
  Generation:          2
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:44:38Z
  Owner References:
    API Version:           v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  Pod
    Name:                  ubuntu-sshd-exposed-secrets
    UID:                   d3a57ab4-e187-4e76-8691-2a97ef293c62
  Resource Version:        118720
  UID:                     23a924b1-ac50-4cc9-957b-6b28ad504b65
Report:
  Artifact:
    Repository:  peru/ubuntu_sshd
    Tag:         latest
  Registry:
    Server:  index.docker.io
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.38.2
  Secrets:
    Category:  AsymmetricPrivateKey
    Match:     ----BEGIN RSA PRIVATE KEY-----**********************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************-----END RSA PRIVATE
    Rule ID:   private-key
    Severity:  HIGH
    Target:    /etc/ssh/ssh_host_rsa_key
    Title:     Asymmetric Private Key
    Category:  AsymmetricPrivateKey
    Match:     -----BEGIN EC PRIVATE KEY-----************************************************************************************************************************************************************************-----END EC PRIVATE
    Rule ID:   private-key
    Severity:  HIGH
    Target:    /etc/ssh/ssh_host_ecdsa_key
    Title:     Asymmetric Private Key
    Category:  AsymmetricPrivateKey
    Match:     BEGIN OPENSSH PRIVATE KEY-----******************************************************************************************************************************************************************************************************************************************************************************************************************************************************-----END OPENSSH PRI
    Rule ID:   private-key
    Severity:  HIGH
    Target:    /etc/ssh/ssh_host_ed25519_key
    Title:     Asymmetric Private Key
  Summary:
    Critical Count:  0
    High Count:      3
    Low Count:       0
    Medium Count:    0
  Update Timestamp:  2023-03-14T04:44:38Z
Events:              <none>
```

Cluster wide output will show us the whole picture of the Exposed Secrets:

```bash
kubectl get exposedsecretreport -n test-trivy3 -o wide
```

```console
NAME                                                          REPOSITORY         TAG      SCANNER   AGE   CRITICAL   HIGH   MEDIUM   LOW
pod-ubuntu-sshd-exposed-secrets-ubuntu-sshd-exposed-secrets   peru/ubuntu_sshd   latest   Trivy     99s   0          3      0        0
```

### RBAC Assessment Report

RBAC Assessment Report exists in two "versions" (CRDs):

* [RbacAssessmentReport](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/rbacassessment-report/)
* ClusterRbacAssessmentReport

#### RbacAssessmentReport

Let's have example with role which allows manipulation and reading the secrets:

{% raw %}

```bash
kubectl create namespace test-trivy4
kubectl apply --namespace=test-trivy4 -f - << \EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["*"]#                              <<<<<<<< This is the security issue
EOF

echo -n "Waiting for trivy-operator to create RbacAssessmentReport: "
until kubectl get rbacassessmentreport -n test-trivy4 -o go-template='{{.items | len}}' | grep -qxF 1; do
  echo -n "."
  sleep 3
done
```

{% endraw %}

The generated [RbacAssessmentReport](https://aquasecurity.github.io/trivy-operator/v0.12.0/docs/crds/rbacassessment-report/)
will look contain the CRITICAL issue about secret management:

```bash
kubectl describe rbacassessmentreport --namespace test-trivy4
```

```console
Name:         role-secret-reader
Namespace:    test-trivy4
Labels:       plugin-config-hash=659b7b9c46
              resource-spec-hash=6f775df776
              trivy-operator.resource.kind=Role
              trivy-operator.resource.name=secret-reader
              trivy-operator.resource.namespace=test-trivy4
Annotations:  trivy-operator.aquasecurity.github.io/report-ttl: 24h0m0s
API Version:  aquasecurity.github.io/v1alpha1
Kind:         RbacAssessmentReport
Metadata:
  Creation Timestamp:  2023-03-14T04:46:33Z
  Generation:          1
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:46:33Z
  Owner References:
    API Version:           rbac.authorization.k8s.io/v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  Role
    Name:                  secret-reader
    UID:                   d97c0dc5-6d81-440a-9bc3-6e7c3621635c
  Resource Version:        119225
  UID:                     6b9a7b0f-768e-4487-b288-538433e2045d
Report:
  Checks:
    Category:     Kubernetes Security Check
    Check ID:     KSV045
    Description:  Check whether role permits wildcard verb on specific resources
    Messages:
      Role permits wildcard verb on specific resources
    Severity:     CRITICAL
    Success:      false
    Title:        No wildcard verb roles
    Category:     Kubernetes Security Check
    Check ID:     KSV041
    Description:  Check whether role permits managing secrets
    Messages:
      Role permits management of secret(s)
    Severity:  CRITICAL
    Success:   false
    Title:     Do not allow management of secrets
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.12.1
  Summary:
    Critical Count:  2
    High Count:      0
    Low Count:       0
    Medium Count:    0
Events:              <none>
```

You can also look at all the "Role issues" in cluster:

```bash
kubectl get rbacassessmentreport --all-namespaces --output=wide
```

```console
NAMESPACE               NAME                                             SCANNER   AGE   CRITICAL   HIGH   MEDIUM   LOW
cert-manager            role-565fd84cf                                   Trivy     21m   1          0      0        0
default                 role-864ddd97cb                                  Trivy     19m   0          1      0        1
ingress-nginx           role-ingress-nginx                               Trivy     20m   1          0      0        0
karpenter               role-karpenter                                   Trivy     19m   1          0      1        0
kube-prometheus-stack   role-kube-prometheus-stack-grafana               Trivy     19m   0          0      0        0
kube-public             role-b99d4b8d7                                   Trivy     20m   0          0      1        0
kube-system             role-54bf889b86                                  Trivy     19m   0          0      1        0
kube-system             role-5c6cd5c956                                  Trivy     19m   0          0      0        0
kube-system             role-5cc59f98f6                                  Trivy     19m   0          0      0        0
kube-system             role-5df4dbbd98                                  Trivy     19m   0          0      1        0
kube-system             role-668d4b4c7b                                  Trivy     20m   0          2      1        0
kube-system             role-6fbccbcb9d                                  Trivy     19m   0          0      1        0
kube-system             role-77cd64c645                                  Trivy     19m   0          0      1        0
kube-system             role-79f88497                                    Trivy     19m   0          0      1        0
kube-system             role-7f4d588ff9                                  Trivy     18m   0          0      0        0
kube-system             role-8498b9b6d4                                  Trivy     19m   0          0      1        0
kube-system             role-864ddd97cb                                  Trivy     20m   0          0      0        0
kube-system             role-868458b9d6                                  Trivy     20m   1          0      0        0
kube-system             role-8c86c9467                                   Trivy     19m   0          0      0        0
kube-system             role-b99d4b8d7                                   Trivy     19m   1          0      0        0
kube-system             role-eks-vpc-resource-controller-role            Trivy     19m   0          0      1        0
kube-system             role-extension-apiserver-authentication-reader   Trivy     19m   0          0      0        0
kube-system             role-karpenter-dns                               Trivy     20m   0          0      0        0
test-trivy4             role-secret-reader                               Trivy     49s   2          0      0        0
trivy-system            role-trivy-operator                              Trivy     21m   1          0      1        0
trivy-system            role-trivy-operator-leader-election              Trivy     19m   0          0      0        0
```

#### ClusterRbacAssessmentReport

Creating the following [ClusterRole](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole)
will make another security violation against [Least privilege](https://kubernetes.io/docs/concepts/security/rbac-good-practices/#least-privilege)
principles.

```bash
kubectl apply -f - << \EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: wildcard-resource
rules:
- apiGroups: [""]
  resources: ["*"]                         # <<<<<<<< This is the security issue
  verbs: ["*"]
EOF

echo -n "Waiting for trivy-operator to create ClusterRbacAssessmentReport: "
until kubectl get clusterrbacassessmentreport clusterrole-wildcard-resource 2> /dev/null; do
  echo -n "."
  sleep 3
done
```

See the details:

```bash
kubectl describe clusterrbacassessmentreport clusterrole-wildcard-resource
```

```console
Name:         clusterrole-wildcard-resource
Namespace:
Labels:       plugin-config-hash=659b7b9c46
              resource-spec-hash=6c64bd7d7
              trivy-operator.resource.kind=ClusterRole
              trivy-operator.resource.name=wildcard-resource
              trivy-operator.resource.namespace=
Annotations:  <none>
API Version:  aquasecurity.github.io/v1alpha1
Kind:         ClusterRbacAssessmentReport
Metadata:
  Creation Timestamp:  2023-03-14T04:47:57Z
  Generation:          1
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:47:57Z
  Owner References:
    API Version:           rbac.authorization.k8s.io/v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  ClusterRole
    Name:                  wildcard-resource
    UID:                   ef842392-d8cc-47c9-b60d-8a713232596b
  Resource Version:        119581
  UID:                     1fc1eb0a-7ad4-4ee9-9e1a-725847e2ed11
Report:
  Checks:
    Category:     Kubernetes Security Check
    Check ID:     KSV046
    Description:  Check whether role permits specific verb on wildcard resources
    Messages:
      Role permits specific verb on wildcard resource
    Severity:  CRITICAL
    Success:   false
    Title:     No wildcard resource roles
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.12.1
  Summary:
    Critical Count:  1
    High Count:      0
    Low Count:       0
    Medium Count:    0
Events:              <none>
```

Look at all the "ClusterRole issues" in cluster:

```bash
kubectl get clusterrbacassessmentreport --all-namespaces --output=wide
```

```console
NAME                                                             SCANNER   AGE   CRITICAL   HIGH   MEDIUM   LOW
clusterrole-54bb85d744                                           Trivy     20m   0          0      0        0
clusterrole-54bf889b86                                           Trivy     21m   0          0      0        0
clusterrole-54ccb57cc4                                           Trivy     20m   0          0      0        0
clusterrole-54cdc9b678                                           Trivy     21m   1          0      0        0
clusterrole-5585c7b9ff                                           Trivy     19m   0          0      0        0
clusterrole-565cd5fdf                                            Trivy     19m   0          0      0        0
clusterrole-567cc86fc6                                           Trivy     19m   0          0      0        0
clusterrole-569d87574c                                           Trivy     22m   1          0      0        0
clusterrole-575b7f6784                                           Trivy     20m   0          0      0        0
clusterrole-57d745d4cc                                           Trivy     23m   1          0      0        0
clusterrole-5857f84f59                                           Trivy     21m   0          0      0        0
clusterrole-58bfc7788d                                           Trivy     20m   0          0      0        0
clusterrole-59dc5c9cb6                                           Trivy     19m   0          0      0        0
clusterrole-5b458986c5                                           Trivy     19m   0          0      0        0
clusterrole-5b97d66885                                           Trivy     20m   0          0      0        0
clusterrole-5bd7cc878d                                           Trivy     19m   0          0      0        0
clusterrole-5c6cd5c956                                           Trivy     20m   0          0      0        0
clusterrole-5cbfdf6f9d                                           Trivy     21m   0          0      0        0
clusterrole-5f9f8f6b4c                                           Trivy     21m   1          0      0        0
clusterrole-644b85fbb5                                           Trivy     21m   0          0      0        0
clusterrole-6496b874bc                                           Trivy     20m   0          0      0        0
clusterrole-64cd5dd8c5                                           Trivy     19m   0          0      0        0
clusterrole-64f9898979                                           Trivy     21m   0          0      0        0
clusterrole-658cbf7c48                                           Trivy     19m   0          0      0        0
clusterrole-6594cc4fb6                                           Trivy     19m   0          1      0        0
clusterrole-65bd45754b                                           Trivy     20m   0          0      0        0
clusterrole-65ff89d4f6                                           Trivy     19m   0          0      0        0
clusterrole-668d4b4c7b                                           Trivy     19m   2          0      0        0
clusterrole-679f75d6b5                                           Trivy     21m   0          0      0        0
clusterrole-6858fccb98                                           Trivy     21m   0          0      0        0
clusterrole-68679985fd                                           Trivy     19m   0          0      0        0
clusterrole-69c4fbc9c4                                           Trivy     20m   1          0      0        0
clusterrole-6b696dd9d5                                           Trivy     20m   0          0      0        0
clusterrole-6b6f997745                                           Trivy     20m   0          0      0        0
clusterrole-6c9cb84f7b                                           Trivy     20m   0          0      0        0
clusterrole-6d7d6f9d9c                                           Trivy     22m   0          1      0        0
clusterrole-6f54fcfddd                                           Trivy     20m   0          0      0        0
clusterrole-6f647d9bdc                                           Trivy     20m   0          0      0        0
clusterrole-6f69bb5b79                                           Trivy     21m   0          0      0        0
clusterrole-74586d59d6                                           Trivy     20m   0          0      1        0
clusterrole-74f98bf848                                           Trivy     20m   0          0      0        0
clusterrole-7557d9789b                                           Trivy     20m   0          0      0        0
clusterrole-75f5d55dd8                                           Trivy     21m   0          0      0        0
clusterrole-76c6b6cf99                                           Trivy     19m   0          0      0        0
clusterrole-77898f44f5                                           Trivy     21m   0          1      0        0
clusterrole-779895897b                                           Trivy     21m   0          0      0        0
clusterrole-779f88d9b5                                           Trivy     21m   0          1      0        0
clusterrole-77f88d49d                                            Trivy     23m   0          0      0        0
clusterrole-79d4fc89cd                                           Trivy     22m   1          0      0        0
clusterrole-79ff87886f                                           Trivy     20m   0          0      0        0
clusterrole-7b884bc5d8                                           Trivy     21m   1          2      1        0
clusterrole-7bdcc749f8                                           Trivy     19m   0          1      0        0
clusterrole-7c4d8f665                                            Trivy     19m   1          1      0        0
clusterrole-7c5d4b78b6                                           Trivy     20m   0          1      0        0
clusterrole-7c7649d468                                           Trivy     22m   0          0      0        0
clusterrole-7dfccfdf                                             Trivy     19m   0          0      0        0
clusterrole-7f76ddfb76                                           Trivy     20m   0          0      0        0
clusterrole-7f7cc8689f                                           Trivy     20m   0          0      0        0
clusterrole-7ff7dbc7fd                                           Trivy     20m   0          0      0        0
clusterrole-8498b9b6d4                                           Trivy     20m   0          0      0        0
clusterrole-8545bb4f4d                                           Trivy     20m   0          0      0        0
clusterrole-865d464ff8                                           Trivy     20m   0          0      0        0
clusterrole-8686d64c5                                            Trivy     19m   0          1      0        0
clusterrole-8689f7c759                                           Trivy     21m   0          0      0        0
clusterrole-86ccd5dd47                                           Trivy     20m   1          0      0        0
clusterrole-889f4b7cc                                            Trivy     20m   0          0      0        0
clusterrole-8b7445588                                            Trivy     22m   0          0      0        0
clusterrole-96685f56d                                            Trivy     20m   0          1      0        0
clusterrole-984fc85d                                             Trivy     21m   0          1      0        0
clusterrole-9d8f67c6d                                            Trivy     20m   0          0      0        0
clusterrole-admin                                                Trivy     20m   2          2      1        0
clusterrole-aggregate-config-audit-reports-view                  Trivy     20m   0          0      0        0
clusterrole-aggregate-exposed-secret-reports-view                Trivy     20m   0          0      0        0
clusterrole-aggregate-vulnerability-reports-view                 Trivy     20m   0          0      0        0
clusterrole-aws-node                                             Trivy     19m   1          0      0        0
clusterrole-aws-node-termination-handler                         Trivy     20m   0          0      0        0
clusterrole-b754c4cc6                                            Trivy     20m   2          1      0        0
clusterrole-bf7d9ff77                                            Trivy     21m   0          0      1        0
clusterrole-c497699bd                                            Trivy     20m   0          0      0        0
clusterrole-cert-manager-cainjector                              Trivy     19m   1          0      0        0
clusterrole-cert-manager-controller-certificates                 Trivy     19m   1          0      0        0
clusterrole-cert-manager-controller-certificatesigningrequests   Trivy     20m   0          0      0        0
clusterrole-cert-manager-controller-challenges                   Trivy     20m   1          1      0        0
clusterrole-cert-manager-controller-clusterissuers               Trivy     19m   1          0      0        0
clusterrole-cert-manager-controller-ingress-shim                 Trivy     21m   0          0      0        0
clusterrole-cert-manager-controller-issuers                      Trivy     20m   1          0      0        0
clusterrole-cert-manager-controller-orders                       Trivy     19m   1          0      0        0
clusterrole-cert-manager-edit                                    Trivy     21m   0          0      0        0
clusterrole-cert-manager-view                                    Trivy     20m   0          0      0        0
clusterrole-cf7d59df5                                            Trivy     19m   0          0      0        0
clusterrole-cluster-admin                                        Trivy     22m   2          0      0        0
clusterrole-d6d6b6c99                                            Trivy     19m   0          0      0        0
clusterrole-df67d86bd                                            Trivy     19m   0          1      0        0
clusterrole-ebs-csi-node-role                                    Trivy     20m   0          0      0        0
clusterrole-ebs-external-attacher-role                           Trivy     19m   0          0      0        0
clusterrole-ebs-external-provisioner-role                        Trivy     19m   0          0      0        0
clusterrole-ebs-external-resizer-role                            Trivy     20m   0          0      0        0
clusterrole-ebs-external-snapshotter-role                        Trivy     20m   0          0      0        0
clusterrole-edit                                                 Trivy     20m   1          2      1        0
clusterrole-external-dns                                         Trivy     20m   0          0      0        0
clusterrole-f44d6476f                                            Trivy     19m   0          0      0        0
clusterrole-forecastle-cluster-ingress-role                      Trivy     20m   0          0      0        0
clusterrole-ingress-nginx                                        Trivy     19m   1          0      0        0
clusterrole-karpenter                                            Trivy     19m   0          0      0        0
clusterrole-karpenter-admin                                      Trivy     20m   0          0      0        0
clusterrole-karpenter-core                                       Trivy     20m   0          0      0        0
clusterrole-kube-prometheus-stack-grafana-clusterrole            Trivy     20m   1          0      0        0
clusterrole-kube-prometheus-stack-kube-state-metrics             Trivy     19m   1          0      0        0
clusterrole-kube-prometheus-stack-operator                       Trivy     19m   2          2      1        0
clusterrole-kube-prometheus-stack-prometheus                     Trivy     21m   0          0      0        0
clusterrole-trivy-operator                                       Trivy     21m   1          1      0        0
clusterrole-view                                                 Trivy     21m   0          0      0        0
clusterrole-vpc-resource-controller-role                         Trivy     23m   0          0      0        0
clusterrole-wildcard-resource                                    Trivy     97s   1          0      0        0
```

### Cluster Infra Assessment Reports

Cluster Infra Assessment Reports should help you hardening your k8s cluster.
Because I'm using Amazon EKS (managed service) I'm not sure how useful it is,
but I can test it for the reference.

Cluster summary of node issues:

```bash
kubectl get clusterinfraassessmentreports -o wide
```

```console
NAME                                  SCANNER   AGE    CRITICAL   HIGH   MEDIUM   LOW
node-ip-192-168-12-204.ec2.internal   Trivy     23m    5          5      0        0
node-ip-192-168-77-76.ec2.internal    Trivy     6m5s   5          5      0        0
node-ip-192-168-8-119.ec2.internal    Trivy     24m    5          5      0        0
```

Details about nodes:

```bash
NODE=$(kubectl get clusterinfraassessmentreports --no-headers=true -o custom-columns=":metadata.name" | head -1)
kubectl describe clusterinfraassessmentreports "${NODE}"
```

```console
Name:         node-ip-192-168-12-204.ec2.internal
Namespace:
Labels:       plugin-config-hash=659b7b9c46
              resource-spec-hash=54fdd9476
              trivy-operator.resource.kind=Node
              trivy-operator.resource.name=ip-192-168-12-204.ec2.internal
              trivy-operator.resource.namespace=
Annotations:  <none>
API Version:  aquasecurity.github.io/v1alpha1
Kind:         ClusterInfraAssessmentReport
Metadata:
  Creation Timestamp:  2023-03-14T04:26:37Z
  Generation:          1
  Managed Fields:
    API Version:  aquasecurity.github.io/v1alpha1
    Fields Type:  FieldsV1
...
    Manager:    trivy-operator
    Operation:  Update
    Time:       2023-03-14T04:26:37Z
  Owner References:
    API Version:           v1
    Block Owner Deletion:  false
    Controller:            true
    Kind:                  Node
    Name:                  ip-192-168-12-204.ec2.internal
    UID:                   d74b3dc1-eed2-45e8-af14-b7ca8c49277a
  Resource Version:        113102
  UID:                     c19ff166-d97c-4b16-94c2-17c39101cb69
Report:
  Checks:
    Category:     Kubernetes Security Check
    Check ID:     KCV0089
    Description:  Setup TLS connection on the Kubelets.
    Messages:
      Ensure that the --tls-key-file argument are set as appropriate
    Severity:     CRITICAL
    Success:      false
    Title:        Ensure that the --tls-key-file argument are set as appropriate
    Category:     Kubernetes Security Check
    Check ID:     KCV0088
    Description:  Setup TLS connection on the Kubelets.
    Messages:
      Ensure that the --tls-cert-file argument are set as appropriate
    Severity:     CRITICAL
    Success:      false
    Title:        Ensure that the --tls-cert-file argument are set as appropriate
    Category:     Kubernetes Security Check
    Check ID:     KCV0091
    Description:  Enable kubelet server certificate rotation.
    Messages:
      Verify that the RotateKubeletServerCertificate argument is set to true
    Severity:     HIGH
    Success:      false
    Title:        Verify that the RotateKubeletServerCertificate argument is set to true
    Category:     Kubernetes Security Check
    Check ID:     KCV0079
    Description:  Disable anonymous requests to the Kubelet server.
    Messages:
      Ensure that the --anonymous-auth argument is set to false
    Severity:     CRITICAL
    Success:      false
    Title:        Ensure that the --anonymous-auth argument is set to false
    Category:     Kubernetes Security Check
    Check ID:     KCV0092
    Description:  Ensure that the Kubelet is configured to only use strong cryptographic ciphers.
    Messages:
      Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers
    Severity:     CRITICAL
    Success:      false
    Title:        Ensure that the Kubelet only makes use of Strong Cryptographic Ciphers
    Category:     Kubernetes Security Check
    Check ID:     KCV0081
    Description:  Enable Kubelet authentication using certificates.
    Messages:
      Ensure that the --client-ca-file argument is set as appropriate
    Severity:     CRITICAL
    Success:      false
    Title:        Ensure that the --client-ca-file argument is set as appropriate
    Category:     Kubernetes Security Check
    Check ID:     KCV0080
    Description:  Do not allow all requests. Enable explicit authorization.
    Messages:
      Ensure that the --authorization-mode argument is not set to AlwaysAllow
    Severity:     HIGH
    Success:      false
    Title:        Ensure that the --authorization-mode argument is not set to AlwaysAllow
    Category:     Kubernetes Security Check
    Check ID:     KCV0082
    Description:  Disable the read-only port.
    Messages:
      Verify that the --read-only-port argument is set to 0
    Severity:     HIGH
    Success:      false
    Title:        Verify that the --read-only-port argument is set to 0
    Category:     Kubernetes Security Check
    Check ID:     KCV0090
    Description:  Enable kubelet client certificate rotation.
    Messages:
      Ensure that the --rotate-certificates argument is not set to false
    Severity:     HIGH
    Success:      false
    Title:        Ensure that the --rotate-certificates argument is not set to false
    Category:     Kubernetes Security Check
    Check ID:     KCV0083
    Description:  Protect tuned kernel parameters from overriding kubelet default kernel parameter values.
    Messages:
      Ensure that the --protect-kernel-defaults is set to true
    Severity:  HIGH
    Success:   false
    Title:     Ensure that the --protect-kernel-defaults is set to true
  Scanner:
    Name:     Trivy
    Vendor:   Aqua Security
    Version:  0.12.1
  Summary:
    Critical Count:  5
    High Count:      5
    Low Count:       0
    Medium Count:    0
Events:              <none>
```

## Grafana

Add Trivy Grafana Dashboards:

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="51.2.0"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-trivy-operator-grafana.yml" << EOF
grafana:
  dashboards:
    default:
      17813-trivy-operator-dashboard:
        # renovate: depName="Trivy Operator Dashboard"
        gnetId: 17813
        revision: 2
        datasource: Prometheus
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-trivy-operator-grafana.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

Add the following Grafana Dashboards to existng [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
helm chart:

* [16652] - [Trivy Operator Dashboard](https://grafana.com/grafana/dashboards/17813-trivy-operator-dashboard/)
  ![Trivy Operator Dashboard](/assets/img/posts/2023/2023-03-08-trivy-operator-grafana/grafana-dashboard-17813-trivy-operator-dashboard.avif)
  _Trivy Operator Dashboard_

* [16742] - [Trivy Image Vulnerability Overview](https://grafana.com/grafana/dashboards/16742-trivy-image-vulnerability-overview/)
  ![Trivy Image Vulnerability Overview](/assets/img/posts/2023/2023-03-08-trivy-operator-grafana/grafana-dashboard-16742-trivy-image-vulnerability-overview.avif)
  _Trivy Image Vulnerability Overview_

* [16652] - [Trivy Operator Reports](https://grafana.com/grafana/dashboards/16652-trivy-operator-reports/)
  ![Trivy Operator Reports](/assets/img/posts/2023/2023-03-08-trivy-operator-grafana/grafana-dashboard-16652-trivy-operator-reports.avif)
  _Trivy Operator Reports_

---

Delete previously created namespaces:

```bash
kubectl delete namespace test-trivy1 test-trivy2 test-trivy3 test-trivy4 || true
```

Enjoy ... 😉
