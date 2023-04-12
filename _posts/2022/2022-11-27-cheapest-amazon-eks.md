---
title: Run the cheapest Amazon EKS
author: Petr Ruzicka
date: 2022-11-27
description: Start cheapest Amazon EKS using eksctl
categories: [Kubernetes, Amazon EKS]
tags: [Amazon EKS, k8s, kubernetes, karpenter, eksctl, cert-manager, external-dns, podinfo]
image:
  path: https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/icon-aws-amazon-eks.svg
  alt: Amazon EKS
---

Sometimes it is necessary to save costs and run the [Amazon EKS](https://aws.amazon.com/eks/)
the "cheapest way".

The following notes are about running [Amazon EKS](https://aws.amazon.com/eks/)
with lowest price.

Requirements:

- Single AZ only - no payments for cross availability zones traffic
- Spot instances "everywhere"
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type - ARM Graviton based `t4g.medium`
  (2 x CPU, 4GB RAM)
- Use ARM based EC2 instances
- Use Bottlerocket - small operation system / CPU / Memory footprint
- Use Network Load Balancer (NLB) as a most cost efficient + cost optimized LB
- Run as many pods as possible on worker nodes `max-pods-per-node`
  - <https://stackoverflow.com/questions/57970896/pod-limit-on-node-aws-eks>
  - <https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/>

## Build Amazon EKS cluster

### Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables.

`BASE_DOMAIN` (`k8s.mylabs.dev`) contains DNS records for all your Kubernetes
clusters. The cluster names will look like `CLUSTER_NAME`.`BASE_DOMAIN`
(`k01.k8s.mylabs.dev`).

```bash
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"
# Tags used to tag the AWS resources
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev}"
```

You will need to configure [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and other secrets/variables.

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
export AWS_ROLE_TO_ASSUME="arn:aws:iam::7xxxxxxxxxx7:role/Gixxxxxxxxxxxxxxxxxxxxle"
export GOOGLE_CLIENT_ID="10xxxxxxxxxxxxxxxud.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="GOxxxxxxxxxxxxxxxtw"
```

Verify if all the necessary variables were set:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_ROLE_TO_ASSUME?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${GOOGLE_CLIENT_ID?}"
: "${GOOGLE_CLIENT_SECRET?}"
: "${KUBECONFIG?}"
: "${MY_EMAIL?}"
: "${TAGS?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

### Prepare the local working environment

> You can skip these steps if you have all the required software already
> installed.
{: .prompt-tip }

Required:

- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)

## Configure AWS Route 53 Domain delegation

> DNS delegation should be done only once.
{: .prompt-info }

Create DNS zone for EKS clusters:

```shell
export CLOUDFLARE_EMAIL="petr.ruzicka@gmail.com"
export CLOUDFLARE_API_KEY="1xxxxxxxxx0"

aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
`mylabs.dev`) to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.mylabs.dev` (`BASE_DOMAIN`) for
proper zone delegation. This step depends on your domain registrar - I'm using
CloudFlare and using Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

<!-- markdownlint-disable blanks-around-fences -->
```console
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-885.awsdns-46.net",
            "created_on": "2020-11-13T06:25:32.18642Z",
            "id": "dxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:32.18642Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-1692.awsdns-19.co.uk",
            "created_on": "2020-11-13T06:25:37.605605Z",
            "id": "9xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:37.605605Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
```
<!-- markdownlint-enable blanks-around-fences -->

### Create Route53

Create CloudFormation template containing policies for Route53 and Domain.

Put new domain `CLUSTER_FQDN` to the Route 53 and configure the DNS delegation
from the `BASE_DOMAIN`.

Create temporary directory for files used for creating/configuring EKS Cluster
and it's components:

```bash
mkdir -p "${TMP_DIR}/${CLUSTER_FQDN}"
```

Create Route53 zone:

```bash
cat > "${TMP_DIR}/${CLUSTER_FQDN}/cf-route53.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries

Parameters:

  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String

  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: kube1.k8s.mylabs.dev"
    Type: String

Resources:

  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref ClusterFQDN

  RecordSet:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneName: !Sub "${BaseDomain}."
      Name: !Ref ClusterFQDN
      Type: NS
      TTL: 60
      ResourceRecords: !GetAtt HostedZone.NameServers
EOF

if [[ $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query "StackSummaries[?starts_with(StackName, \`${CLUSTER_NAME}-route53\`) == \`true\`].StackName" --output text) == "" ]]; then
  # shellcheck disable=SC2001
  eval aws cloudformation "create-stack" \
    --parameters "ParameterKey=BaseDomain,ParameterValue=${BASE_DOMAIN} ParameterKey=ClusterFQDN,ParameterValue=${CLUSTER_FQDN}" \
    --stack-name "${CLUSTER_NAME}-route53" \
    --template-body "file://${TMP_DIR}/${CLUSTER_FQDN}/cf-route53.yml" \
    --tags "$(echo "${TAGS}" | sed -e 's/\([^=]*\)=\([^,]*\),*/Key=\1,Value=\2 /g')" || true
fi
```

## Create Amazon EKS

I'm going to use [eksctl](https://eksctl.io/) to create the Amazon EKS cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png
"eksctl"){: width="700" }

Create [Amazon EKS](https://aws.amazon.com/eks/) using [eksctl](https://eksctl.io/):

```bash
cat > "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  tags: &tags
    karpenter.sh/discovery: "${CLUSTER_NAME}"
$(echo "${TAGS}" | sed 's/^/    /g ; s/=\([^,]*\),*/: "\1"\n    /g')
availabilityZones:
  - ${AWS_DEFAULT_REGION}a
  - ${AWS_DEFAULT_REGION}b
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
      roleName: eksctl-${CLUSTER_NAME}-irsa-cert-manager
    - metadata:
        name: external-dns
        namespace: external-dns
      wellKnownPolicies:
        externalDNS: true
      roleName: eksctl-${CLUSTER_NAME}-irsa-external-dns
karpenter:
  # renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
  version: v0.27.2
  createServiceAccount: true
  withSpotInterruptionQueue: true
addons:
  - name: vpc-cni
  - name: kube-proxy
  - name: coredns
  - name: aws-ebs-csi-driver
managedNodeGroups:
  - name: mng01
    amiFamily: Bottlerocket
    # Minimal instance type for running add-ons + karpenter - ARM t4g.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    # Minimal instance type for running add-ons + karpenter - X86 t3a.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    instanceType: t4g.medium
    # Due to karpenter we need 2 instances
    desiredCapacity: 2
    availabilityZones:
      - ${AWS_DEFAULT_REGION}a
    minSize: 2
    maxSize: 5
    volumeSize: 20
    volumeType: gp3
    disablePodIMDS: true
    tags:
      <<: *tags
    volumeEncrypted: true
    disableIMDSv1: true
    # For instances with less than 30 vCPUs the maximum number is 110 and for all other instances the maximum number is 250
    # https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
    maxPodsPerNode: 110
EOF
```

Get the kubeconfig to access the cluster:

```bash
if [[ ! -s "${KUBECONFIG}" ]]; then
  if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null; then
    eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" --kubeconfig "${KUBECONFIG}"
    # Allow users which are consuming the AWS_ROLE_TO_ASSUME to access the EKS
    eksctl create iamidentitymapping --cluster="${CLUSTER_NAME}" --region="${AWS_DEFAULT_REGION}" --arn="${AWS_ROLE_TO_ASSUME}" --group system:masters --username admin
  else
    eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  fi
fi

aws eks update-kubeconfig --name="${CLUSTER_NAME}"
echo -e "***************\n export KUBECONFIG=${KUBECONFIG} \n***************"
```

Enable the parameter to assign prefixes to network interfaces for the
Amazon VPC CNI:

```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
```

Configure [Karpenter](https://karpenter.sh/):

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png
"Karpenter"){: width="500" }

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-karpenter-provisioner.yml" << EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  namespace: karpenter
  name: default
spec:
  # Enables consolidation which attempts to reduce cluster cost by both removing
  # un-needed nodes and down-sizing those that can't be removed.
  # https://youtu.be/OB7IZolZk78?t=2629
  consolidation:
    enabled: true
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
    - key: kubernetes.io/arch
      operator: In
      values: ["amd64", "arm64"]
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: ["${AWS_DEFAULT_REGION}a"]
    - key: karpenter.k8s.aws/instance-family
      operator: In
      values: ["t3a", "t4g"]
  # Resource limits constrain the total size of the cluster.
  # Limits prevent Karpenter from creating new instances once the limit is exceeded.
  limits:
    resources:
      cpu: 8
      memory: 32Gi
  providerRef:
    name: default
  # Labels are arbitrary key-values that are applied to all nodes
  labels:
    managedBy: karpenter
    provisioner: default
---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  namespace: karpenter
  name: default
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  tags:
    KarpenerProvisionerName: "default"
    Name: "${CLUSTER_NAME}-karpenter"
$(echo "${TAGS}" | sed 's/^/    /g ; s/=\([^,]*\),*/: "\1"\n    /g')
EOF
```

Install `aws-node-termination-handler`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-node-termination-handler)
and modify the
[default values](https://github.com/aws/aws-node-termination-handler/blob/main/config/helm/aws-node-termination-handler/values.yaml):

```bash
# renovate: datasource=helm depName=aws-node-termination-handler registryUrl=https://aws.github.io/eks-charts
AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION="0.21.0"

helm repo add eks https://aws.github.io/eks-charts/ && helm repo update > /dev/null
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" << EOF
awsRegion: ${AWS_DEFAULT_REGION}
EOF
helm upgrade --install --version "${AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION}" --namespace kube-system --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" aws-node-termination-handler eks/aws-node-termination-handler
```

## Prometheus, DNS, Ingress, Certificates and others

There are many k8s services / applications which can export metrics to
Prometheus. That is the reason why the prometheus should be "first" application
which should be installed on the k8s cluster.

Then you will need some basic tools / integrations, like [external-dns](https://github.com/kubernetes-sigs/external-dns),
[ingress-nginx](https://kubernetes.github.io/ingress-nginx/),
[cert-manager](https://cert-manager.io/), [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/),
...

### mailhog

Install `mailhog`
[helm chart](https://artifacthub.io/packages/helm/codecentric/mailhog)
and modify the
[default values](https://github.com/codecentric/helm-charts/blob/master/charts/mailhog/values.yaml).

![MailHog](https://raw.githubusercontent.com/sj26/mailcatcher/main/assets/images/logo_large.png
"mailhog"){: width="200" }

```bash
# renovate: datasource=helm depName=mailhog registryUrl=https://codecentric.github.io/helm-charts
MAILHOG_HELM_CHART_VERSION="5.2.3"

helm repo add codecentric https://codecentric.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailhog.yml" << EOF
image:
  repository: docker.io/cd2team/mailhog
  tag: "1663459324"
ingress:
  enabled: true
  annotations:
    forecastle.stakater.com/expose: "true"
    forecastle.stakater.com/icon: https://raw.githubusercontent.com/sj26/mailcatcher/main/assets/images/logo_large.png
    forecastle.stakater.com/appName: Mailhog
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  ingressClassName: nginx
  hosts:
    - host: mailhog.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
        - mailhog.${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${MAILHOG_HELM_CHART_VERSION}" --namespace mailhog --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailhog.yml" mailhog codecentric/mailhog
```

### kube-prometheus-stack

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

![Prometheus](https://raw.githubusercontent.com/cncf/artwork/40e2e8948509b40e4bad479446aaec18d6273bf2/projects/prometheus/horizontal/color/prometheus-horizontal-color.svg
"prometheus"){: width="500" }

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="45.9.1"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false
alertmanager:
  config:
    global:
      smtp_smarthost: "mailhog.mailhog.svc.cluster.local:1025"
      smtp_from: "alertmanager@${CLUSTER_FQDN}"
    route:
      group_by: ["alertname", "job"]
      receiver: email-notifications
      routes:
        - receiver: email-notifications
          matchers: [ '{severity=~"warning|critical"}' ]
    receivers:
      - name: email-notifications
        email_configs:
          - to: "notification@${CLUSTER_FQDN}"
            require_tls: false
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      forecastle.stakater.com/expose: "true"
      forecastle.stakater.com/icon: https://raw.githubusercontent.com/stakater/ForecastleIcons/master/alert-manager.png
      forecastle.stakater.com/appName: Alert Manager
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - alertmanager.${CLUSTER_FQDN}
    paths: ["/"]
    pathType: ImplementationSpecific
    tls:
      - hosts:
          - alertmanager.${CLUSTER_FQDN}
# https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
grafana:
  defaultDashboardsEnabled: false
  serviceMonitor:
    enabled: true
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      forecastle.stakater.com/expose: "true"
      forecastle.stakater.com/icon: https://raw.githubusercontent.com/stakater/ForecastleIcons/master/grafana.png
      forecastle.stakater.com/appName: Grafana
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
      nginx.ingress.kubernetes.io/configuration-snippet: |
        auth_request_set \$email \$upstream_http_x_auth_request_email;
        proxy_set_header X-Email \$email;
    hosts:
      - grafana.${CLUSTER_FQDN}
    paths: ["/"]
    pathType: ImplementationSpecific
    tls:
      - hosts:
          - grafana.${CLUSTER_FQDN}
  datasources:
    datasource.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://kube-prometheus-stack-prometheus.kube-prometheus-stack:9090/
          access: proxy
          isDefault: true
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: "default"
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      k8s-cluster-summary:
        gnetId: 8685
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 30
        datasource: Prometheus
      prometheus-2-0-overview:
        gnetId: 3662
        revision: 2
        datasource: Prometheus
      stians-disk-graphs:
        gnetId: 9852
        revision: 1
        datasource: Prometheus
      kubernetes-apiserver:
        gnetId: 12006
        revision: 1
        datasource: Prometheus
      ingress-nginx:
        gnetId: 9614
        revision: 1
        datasource: Prometheus
      ingress-nginx2:
        gnetId: 11875
        revision: 1
        datasource: Prometheus
      external-dns:
        gnetId: 15038
        revision: 1
        datasource: Prometheus
      kubernetes-monitor:
        gnetId: 15398
        revision: 6
        datasource: Prometheus
      kubernetes-nginx-ingress-prometheus-nextgen:
        gnetId: 14314
        revision: 2
        datasource: Prometheus
      portefaix-kubernetes-cluster-overview:
        gnetId: 13473
        revision: 2
        datasource: Prometheus
      # https://grafana.com/orgs/imrtfm/dashboards - https://github.com/dotdc/grafana-dashboards-kubernetes
      kubernetes-views-pods:
        gnetId: 15760
        revision: 22
        datasource: Prometheus
      kubernetes-views-global:
        gnetId: 15757
        revision: 14
        datasource: Prometheus
      kubernetes-views-namespaces:
        gnetId: 15758
        revision: 15
        datasource: Prometheus
      kubernetes-views-nodes:
        gnetId: 15759
        revision: 14
        datasource: Prometheus
      kubernetes-system-api-server:
        gnetId: 15761
        revision: 11
        datasource: Prometheus
      kubernetes-system-coredns:
        gnetId: 15762
        revision: 11
        datasource: Prometheus
      cluster-capacity-karpenter:
        gnetId: 16237
        revision: 1
        datasource: Prometheus
      pod-statistic-karpenter:
        gnetId: 16236
        revision: 1
        datasource: Prometheus
  grafana.ini:
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    # Use oauth2-proxy instead of default Grafana Oauth
    auth.basic:
      enabled: false
    auth.proxy:
      auto_sign_up: true
      enabled: true
      header_name: X-Email
      header_property: email
    users:
      allow_sign_up: false
      auto_assign_org: true
      auto_assign_org_role: Admin
  smtp:
    enabled: true
    host: "mailhog.mailhog.svc.cluster.local:1025"
    from_address: grafana@${CLUSTER_FQDN}
kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
prometheusOperator:
  tls:
    enabled: false
  admissionWebhooks:
    enabled: false
prometheus:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      forecastle.stakater.com/expose: "true"
      forecastle.stakater.com/icon: https://raw.githubusercontent.com/cncf/artwork/master/projects/prometheus/icon/color/prometheus-icon-color.svg
      forecastle.stakater.com/appName: Prometheus
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    paths: ["/"]
    pathType: ImplementationSpecific
    hosts:
      - prometheus.${CLUSTER_FQDN}
    tls:
      - hosts:
          - prometheus.${CLUSTER_FQDN}
  prometheusSpec:
    externalLabels:
      cluster: ${CLUSTER_FQDN}
    externalUrl: https://prometheus.${CLUSTER_FQDN}
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    retentionSize: 1GB
    walCompression: true
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

### karpenter

Change [karpenter](https://karpenter.sh/) default installation by upgrading:
[helm chart](https://artifacthub.io/packages/helm/oci-karpenter/karpenter)
and modify the
[default values](https://github.com/aws/karpenter/blob/main/charts/karpenter/values.yaml).

![karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png
"karpenter"){: width="400" }

```bash
# renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
KARPENTER_HELM_CHART_VERSION="v0.27.2"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" << EOF
replicas: 1
serviceMonitor:
  enabled: true
EOF
helm upgrade --install --version "${KARPENTER_HELM_CHART_VERSION}" --namespace karpenter --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" karpenter oci://public.ecr.aws/karpenter/karpenter
```

### cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify the
[default values](https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg
"cert-manager"){: width="200" }

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.11.1"

helm repo add jetstack https://charts.jetstack.io
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" << EOF
installCRDs: true
serviceAccount:
  create: false
  name: cert-manager
extraArgs:
  - --cluster-resource-namespace=cert-manager
  - --enable-certificate-owner-ref=true
securityContext:
  fsGroup: 1001
prometheus:
  servicemonitor:
    enabled: true
EOF
helm upgrade --install --version "${CERT_MANAGER_HELM_CHART_VERSION}" --namespace cert-manager --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" cert-manager jetstack/cert-manager
```

Add ClusterIssuers for Let's Encrypt staging:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-cert-manager-clusterissuer-staging.yml" << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns
  namespace: cert-manager
  labels:
    letsencrypt: staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: ${AWS_DEFAULT_REGION}
EOF

kubectl wait --namespace cert-manager --timeout=10m --for=condition=Ready clusterissuer --all
```

Create certificate:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-cert-manager-certificate-staging.yml" << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ingress-cert-staging
  namespace: cert-manager
  labels:
    letsencrypt: staging
spec:
  secretName: ingress-cert-staging
  secretTemplate:
    labels:
      letsencrypt: staging
  issuerRef:
    name: letsencrypt-staging-dns
    kind: ClusterIssuer
  commonName: "*.${CLUSTER_FQDN}"
  dnsNames:
    - "*.${CLUSTER_FQDN}"
    - "${CLUSTER_FQDN}"
EOF
```

### metrics-server

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/metrics-server/metrics-server)
and modify the
[default values](https://github.com/kubernetes-sigs/metrics-server/blob/master/charts/metrics-server/values.yaml):

```bash
# renovate: datasource=helm depName=metrics-server registryUrl=https://kubernetes-sigs.github.io/metrics-server/
METRICS_SERVER_HELM_CHART_VERSION="3.9.0"

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install --version "${METRICS_SERVER_HELM_CHART_VERSION}" --namespace kube-system metrics-server metrics-server/metrics-server
```

### external-dns

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and modify the
[default values](https://github.com/kubernetes-sigs/external-dns/blob/master/charts/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png
"external-dns"){: width="300" }

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.12.2"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" << EOF
domainFilters:
  - ${CLUSTER_FQDN}
interval: 20s
policy: sync
serviceAccount:
  create: false
  name: external-dns
serviceMonitor:
  enabled: true
EOF
helm upgrade --install --version "${EXTERNAL_DNS_HELM_CHART_VERSION}" --namespace external-dns --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" external-dns external-dns/external-dns
```

### ingress-nginx

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.6.0"

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-staging

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" << EOF
controller:
  ingressClassResource:
    default: true
  extraArgs:
    default-ssl-certificate: "cert-manager/ingress-cert-staging"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "${TAGS}"
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
    prometheusRule:
      enabled: true
      rules:
        - alert: NGINXConfigFailed
          expr: count(nginx_ingress_controller_config_last_reload_successful == 0) > 0
          for: 1s
          labels:
            severity: critical
          annotations:
            description: bad ingress config - nginx config test failed
            summary: uninstall the latest ingress changes to allow config reloads to resume
        - alert: NGINXCertificateExpiry
          expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds) by (host) - time()) < 604800
          for: 1s
          labels:
            severity: critical
          annotations:
            description: ssl certificate(s) will expire in less then a week
            summary: renew expiring certificates to avoid downtime
        - alert: NGINXTooMany500s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"5.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 5XXs
            summary: More than 5% of all requests returned 5XX, this requires your attention
        - alert: NGINXTooMany400s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"4.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 4XXs
            summary: More than 5% of all requests returned 4XX, this requires your attention
EOF
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" ingress-nginx ingress-nginx/ingress-nginx
```

### forecastle

Install `forecastle`
[helm chart](https://artifacthub.io/packages/helm/stakater/forecastle)
and modify the
[default values](https://github.com/stakater/Forecastle/blob/master/deployments/kubernetes/chart/forecastle/values.yaml).

![Forecastle](https://raw.githubusercontent.com/stakater/Forecastle/c70cc130b5665be2649d00101670533bba66df0c/frontend/public/logo512.png
"forecastle"){: width="200" }

```bash
# renovate: datasource=helm depName=forecastle registryUrl=https://stakater.github.io/stakater-charts
FORECASTLE_HELM_CHART_VERSION="1.0.122"

helm repo add stakater https://stakater.github.io/stakater-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-forecastle.yml" << EOF
forecastle:
  config:
    namespaceSelector:
      any: true
    title: Launch Pad
  ingress:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    className: nginx
    hosts:
      - host: ${CLUSTER_FQDN}
        paths:
          - path: /
            pathType: Prefix
    tls:
      - hosts:
          - ${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${FORECASTLE_HELM_CHART_VERSION}" --namespace forecastle --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-forecastle.yml" forecastle stakater/forecastle
```

### oauth2-proxy

Use [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect
the endpoints by Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg
"oauth2-proxy"){: width="400" }

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify the
[default values](https://github.com/oauth2-proxy/manifests/blob/main/helm/oauth2-proxy/values.yaml).

```bash
# renovate: datasource=helm depName=oauth2-proxy registryUrl=https://oauth2-proxy.github.io/manifests
OAUTH2_PROXY_HELM_CHART_VERSION="6.10.1"

helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-oauth2-proxy.yml" << EOF
config:
  clientID: ${GOOGLE_CLIENT_ID}
  clientSecret: ${GOOGLE_CLIENT_SECRET}
  cookieSecret: "$(openssl rand -base64 32 | head -c 32 | base64)"
  configFile: |-
    cookie_domains = ".${CLUSTER_FQDN}"
    set_authorization_header = "true"
    set_xauthrequest = "true"
    upstreams = [ "file:///dev/null" ]
    whitelist_domains = ".${CLUSTER_FQDN}"
authenticatedEmailsFile:
  enabled: true
  restricted_access: |-
    ${MY_EMAIL}
ingress:
  enabled: true
  className: nginx
  hosts:
    - oauth2-proxy.${CLUSTER_FQDN}
  tls:
    - hosts:
        - oauth2-proxy.${CLUSTER_FQDN}
metrics:
  servicemonitor:
    enabled: true
EOF
helm upgrade --install --version "${OAUTH2_PROXY_HELM_CHART_VERSION}" --namespace oauth2-proxy --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-oauth2-proxy.yml" oauth2-proxy oauth2-proxy/oauth2-proxy
```

## Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg
"Clean-up"){: width="400" }

Set necessary variables and verify if all the necessary variables were set:

```sh
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-/tmp}"
export KUBECONFIG="${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"

: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${KUBECONFIG?}"
```

Remove EKS cluster and created components:

```sh
if eksctl get cluster --name="${CLUSTER_NAME}" 2> /dev/null; then
  eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  eksctl delete cluster --name="${CLUSTER_NAME}" --force
fi
```

Remove orphan EC2s created by Karpenter:

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text) ; do
  echo "Removing EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Remove orphan Remove Network ELBs (if exists):

```sh
for NETWORK_ELB_ARN in $(aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn" --output=text) ; do
  if [[ "$(aws elbv2 describe-tags --resource-arns "${NETWORK_ELB_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" =~ ${CLUSTER_NAME} ]]; then
    echo "*** Deleting Network ELB: ${NETWORK_ELB_ARN}"
    aws elbv2 delete-load-balancer --load-balancer-arn "${NETWORK_ELB_ARN}"
  fi
done
```

Remove orphan Target Groups (if exists):

```sh
for TARGET_GROUP_ARN in $(aws elbv2 describe-target-groups --region=eu-central-1 --query "TargetGroups[].TargetGroupArn" --output=text) ; do
  if [[ "$(aws elbv2 describe-tags --resource-arns "${TARGET_GROUP_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" =~ ${CLUSTER_NAME} ]]; then
    echo "*** Deleting Target Group: ${TARGET_GROUP_ARN}"
    aws elbv2 delete-target-group --target-group-arn "${TARGET_GROUP_ARN}"
  fi
done
```

Remove Route 53 DNS records from DNS Zone:

```sh
CLUSTER_FQDN_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
if [[ -n "${CLUSTER_FQDN_ZONE_ID}" ]]; then
  aws route53 list-resource-record-sets --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" | jq -c '.ResourceRecordSets[] | select (.Type != "SOA" and .Type != "NS")' |
    while read -r RESOURCERECORDSET; do
      aws route53 change-resource-record-sets \
        --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" \
        --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"${RESOURCERECORDSET}"' }]}' \
        --output text --query 'ChangeInfo.Id'
    done
fi
```

Remove CloudFormation stacks:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53"
```

Wait for all CloudFormation stacks to be deleted:

```sh
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove Volumes and Snapshots related to the cluster:

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text) ; do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done
```

Remove `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
[[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]] && rm -rf "${TMP_DIR}/${CLUSTER_FQDN}" && [[ -d "${TMP_DIR}" ]] && rmdir "${TMP_DIR}" || true
```

Enjoy ... 😉
