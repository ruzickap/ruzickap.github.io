---
title: Run the cheapest Amazon EKS
author: Petr Ruzicka
date: 2022-11-27
description: Start the cheapest Amazon EKS using eksctl
categories: [Kubernetes, Amazon EKS]
tags:
  [
    Amazon EKS,
    k8s,
    kubernetes,
    karpenter,
    eksctl,
    cert-manager,
    external-dns,
    podinfo,
  ]
image: https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/icon-aws-amazon-eks.svg
---

Sometimes, it's necessary to save costs and run [Amazon EKS](https://aws.amazon.com/eks/)
in the most cost-effective way.

The following notes describe how to run [Amazon EKS](https://aws.amazon.com/eks/)
at the lowest possible price.

Requirements:

- Utilize two Availability Zones (AZs), or use a single zone if feasible to
  reduce costs associated with cross-AZ traffic
- Use Spot instances
- Choose a less expensive AWS region, such as `us-east-1`
- Employ the most price-efficient EC2 instance type, `t4g.medium` (2 CPUs,
  4GB RAM), which uses [AWS Graviton](https://aws.amazon.com/ec2/graviton/)
  processors based on ARM architecture
- Use [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) for a
  minimal operating system, CPU, and memory footprint
- Use a [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  as it is a cost-efficient and optimized load balancing solution
- Configure worker nodes to run the maximum number of pods possible using the
  `max-pods-per-node` setting
  - <https://stackoverflow.com/questions/57970896/pod-limit-on-node-aws-eks>
  - <https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/>

## Build Amazon EKS cluster

### Requirements

You will need to configure the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and set up other necessary secrets and variables.

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
export AWS_ROLE_TO_ASSUME="arn:aws:iam::7xxxxxxxxxx7:role/Gixxxxxxxxxxxxxxxxxxxxle"
export GOOGLE_CLIENT_ID="10xxxxxxxxxxxxxxxud.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="GOxxxxxxxxxxxxxxxtw"
```

If you would like to follow this document and its tasks, you will need to set
up a few environment variables, such as:

```bash
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
# Base Domain: k8s.mylabs.dev
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
# Cluster Name: k01
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"
# Tags used to tag the AWS resources
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev,Cluster=${CLUSTER_FQDN}}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) && export AWS_ACCOUNT_ID
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

Verify that all necessary variables have been set:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_ROLE_TO_ASSUME?}"
: "${GOOGLE_CLIENT_ID?}"
: "${GOOGLE_CLIENT_SECRET?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Install the necessary tools:

<!-- prettier-ignore-start -->
> You can skip these steps if you have all the required software already
> installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)
- [helm](https://github.com/helm/helm)

## Configure AWS Route 53 Domain delegation

<!-- prettier-ignore-start -->
> The DNS delegation steps should only be done once.
{: .prompt-info }
<!-- prettier-ignore-end -->

Create a DNS zone for the EKS clusters:

```shell
export CLOUDFLARE_EMAIL="petr.ruzicka@gmail.com"
export CLOUDFLARE_API_KEY="1xxxxxxxxx0"

aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k8s.mylabs.dev-1.avif)
_Route53 k8s.mylabs.dev zone_

Use your domain registrar to change the nameservers for your zone (e.g.,
`mylabs.dev`) to use the Amazon Route 53 nameservers. You can find the
required Route 53 nameservers as follows:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.mylabs.dev` (your `BASE_DOMAIN`) for proper zone
delegation. This step depends on your domain registrar; I use Cloudflare and
automate this with Ansible:

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

![CloudFlare mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/cloudflare-mylabs-dev-dns-records.avif)
_CloudFlare mylabs.dev zone_

### Create Route53

Create a CloudFormation template that defines the [Route53](https://aws.amazon.com/route53/)
zone.

Add the new domain `CLUSTER_FQDN` to Route 53 and configure DNS delegation
from the `BASE_DOMAIN`.

Create the Route53 zone:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries

Parameters:
  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String
  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: k01.k8s.mylabs.dev"
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
  eval aws cloudformation create-stack \
    --parameters "ParameterKey=BaseDomain,ParameterValue=${BASE_DOMAIN} ParameterKey=ClusterFQDN,ParameterValue=${CLUSTER_FQDN}" \
    --stack-name "${CLUSTER_NAME}-route53" \
    --template-body "file://${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53.yml" \
    --tags "$(echo "${TAGS}" | sed -e 's/\([^=]*\)=\([^,]*\),*/Key=\1,Value=\2 /g')" || true
fi
```

After running the CloudFormation stack, you should see the following Route53
zones:

![Route53 k01.k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k01.k8s.mylabs.dev.avif)
_Route53 k01.k8s.mylabs.dev zone_

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedones-k8s.mylabs.dev-2.avif)
_Route53 k8s.mylabs.dev zone_

## Create Amazon EKS

I will use [eksctl](https://eksctl.io/) to create the Amazon EKS cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png){:width="700"}

Create the [Amazon EKS](https://aws.amazon.com/eks/) cluster using [eksctl](https://eksctl.io/):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
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
# Allow users which are consuming the AWS_ROLE_TO_ASSUME to access the EKS
iamIdentityMappings:
  - arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/admin
    groups:
      - system:masters
    username: admin
karpenter:
  # renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
  version: v0.31.4
  createServiceAccount: true
  withSpotInterruptionQueue: true
addons:
  - name: vpc-cni
    # min version 1.14.0
    version: latest
    configurationValues: |-
      enableNetworkPolicy: "true"
      env:
        ENABLE_PREFIX_DELEGATION: "true"
  - name: kube-proxy
  - name: coredns
  - name: aws-ebs-csi-driver
managedNodeGroups:
  - name: mng01-ng
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
    disablePodIMDS: true
    volumeEncrypted: true
    # For instances with less than 30 vCPUs the maximum number is 110 and for all other instances the maximum number is 250
    # https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
    maxPodsPerNode: 110
EOF
```

Get the kubeconfig file to access the cluster:

```bash
if [[ ! -s "${KUBECONFIG}" ]]; then
  if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null; then
    eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yml" --kubeconfig "${KUBECONFIG}"
  else
    eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  fi
fi

aws eks update-kubeconfig --name="${CLUSTER_NAME}"
```

### Karpenter

[Karpenter](https://karpenter.sh/) is a Kubernetes node autoscaler built for
flexibility, performance, and simplicity.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png){:width="500"}

Configure [Karpenter](https://karpenter.sh/) by applying the following
provisioner definition:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-karpenter-provisioner.yml" << EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
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
  kubeletConfiguration:
    maxPods: 110
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
  name: default
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 2Gi
        volumeType: gp3
        encrypted: true
    - deviceName: /dev/xvdb
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        encrypted: true
  tags:
    KarpenerProvisionerName: "default"
    Name: "${CLUSTER_NAME}-karpenter"
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
EOF
```

### aws-node-termination-handler

The [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
gracefully handles EC2 instance shutdowns within Kubernetes.

Install the `aws-node-termination-handler` [Helm chart](https://artifacthub.io/packages/helm/aws/aws-node-termination-handler)
and modify its [default values](https://github.com/aws/aws-node-termination-handler/blob/main/config/helm/aws-node-termination-handler/values.yaml)
as shown below:

```bash
# renovate: datasource=helm depName=aws-node-termination-handler registryUrl=https://aws.github.io/eks-charts
AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION="0.21.0"

helm repo add --force-update eks https://aws.github.io/eks-charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" << EOF
awsRegion: ${AWS_DEFAULT_REGION}
EOF
helm upgrade --install --version "${AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION}" --namespace kube-system --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" aws-node-termination-handler eks/aws-node-termination-handler
```

### mailhog

MailHog will be used to receive email alerts from Prometheus.

![MailHog](https://raw.githubusercontent.com/sj26/mailcatcher/main/assets/images/logo_large.png){:width="200"}

Install the `mailhog` [Helm chart](https://artifacthub.io/packages/helm/codecentric/mailhog)
and modify its [default values](https://github.com/codecentric/helm-charts/blob/mailhog-5.2.3/charts/mailhog/values.yaml):

```bash
# renovate: datasource=helm depName=mailhog registryUrl=https://codecentric.github.io/helm-charts
MAILHOG_HELM_CHART_VERSION="5.2.3"

helm repo add --force-update codecentric https://codecentric.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailhog.yml" << EOF
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

The [kube-prometheus-stack](https://github.com/prometheus-operator/kube-prometheus)
is a collection of Kubernetes manifests, [Grafana](https://grafana.com/)
dashboards, and [Prometheus rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/).
It's combined with documentation and scripts to provide easy-to-operate,
end-to-end Kubernetes cluster monitoring with [Prometheus](https://prometheus.io/)
using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).

![Prometheus](https://raw.githubusercontent.com/cncf/artwork/40e2e8948509b40e4bad479446aaec18d6273bf2/projects/prometheus/horizontal/color/prometheus-horizontal-color.svg){:width="500"}

Install the `kube-prometheus-stack` [Helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify its [default values](https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-56.6.2/charts/kube-prometheus-stack/values.yaml):

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="56.6.2"

helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" << EOF
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
      1860-node-exporter-full:
        # renovate: depName="Node Exporter Full"
        gnetId: 1860
        revision: 33
        datasource: Prometheus
      3662-prometheus-2-0-overview:
        # renovate: depName="Prometheus 2.0 Overview"
        gnetId: 3662
        revision: 2
        datasource: Prometheus
      9852-stians-disk-graphs:
        # renovate: depName="node-exporter disk graphs"
        gnetId: 9852
        revision: 1
        datasource: Prometheus
      12006-kubernetes-apiserver:
        # renovate: depName="Kubernetes apiserver"
        gnetId: 12006
        revision: 1
        datasource: Prometheus
      9614-nginx-ingress-controller:
        # renovate: depName="NGINX Ingress controller"
        gnetId: 9614
        revision: 1
        datasource: Prometheus
      11875-kubernetes-ingress-nginx-eks:
        # renovate: depName="Kubernetes Ingress Nginx - EKS"
        gnetId: 11875
        revision: 1
        datasource: Prometheus
      15038-external-dns:
        # renovate: depName="External-dns"
        gnetId: 15038
        revision: 3
        datasource: Prometheus
      14314-kubernetes-nginx-ingress-controller-nextgen-devops-nirvana:
        # renovate: depName="Kubernetes Nginx Ingress Prometheus NextGen"
        gnetId: 14314
        revision: 2
        datasource: Prometheus
      13473-portefaix-kubernetes-cluster-overview:
        # renovate: depName="Portefaix / Kubernetes cluster Overview"
        gnetId: 13473
        revision: 2
        datasource: Prometheus
      # https://grafana.com/orgs/imrtfm/dashboards - https://github.com/dotdc/grafana-dashboards-kubernetes
      15760-kubernetes-views-pods:
        # renovate: depName="Kubernetes / Views / Pods"
        gnetId: 15760
        revision: 26
        datasource: Prometheus
      15757-kubernetes-views-global:
        # renovate: depName="Kubernetes / Views / Global"
        gnetId: 15757
        revision: 37
        datasource: Prometheus
      15758-kubernetes-views-namespaces:
        # renovate: depName="Kubernetes / Views / Namespaces"
        gnetId: 15758
        revision: 34
        datasource: Prometheus
      15759-kubernetes-views-nodes:
        # renovate: depName="Kubernetes / Views / Nodes"
        gnetId: 15759
        revision: 29
        datasource: Prometheus
      15761-kubernetes-system-api-server:
        # renovate: depName="Kubernetes / System / API Server"
        gnetId: 15761
        revision: 16
        datasource: Prometheus
      15762-kubernetes-system-coredns:
        # renovate: depName="Kubernetes / System / CoreDNS"
        gnetId: 15762
        revision: 17
        datasource: Prometheus
      19105-prometheus:
        # renovate: depName="Prometheus"
        gnetId: 19105
        revision: 3
        datasource: Prometheus
      16237-cluster-capacity:
        # renovate: depName="Cluster Capacity (Karpenter)"
        gnetId: 16237
        revision: 1
        datasource: Prometheus
      16236-pod-statistic:
        # renovate: depName="Pod Statistic (Karpenter)"
        gnetId: 16236
        revision: 1
        datasource: Prometheus
      19268-prometheus:
        # renovate: depName="Prometheus All Metrics"
        gnetId: 19268
        revision: 1
        datasource: Prometheus
  grafana.ini:
    analytics:
      check_for_updates: false
    server:
      root_url: https://grafana.${CLUSTER_FQDN}
    # Use oauth2-proxy instead of default Grafana Oauth
    auth.basic:
      enabled: false
    auth.proxy:
      enabled: true
      header_name: X-Email
      header_property: email
    users:
      auto_assign_org_role: Admin
  smtp:
    enabled: true
    host: "mailhog.mailhog.svc.cluster.local:1025"
    from_address: grafana@${CLUSTER_FQDN}
  networkPolicy:
    enabled: true
kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kube-state-metrics:
  networkPolicy:
    enabled: true
prometheus-node-exporter:
  networkPolicy:
    enabled: true
prometheusOperator:
  tls:
    enabled: false
  admissionWebhooks:
    enabled: false
  networkPolicy:
    enabled: true
prometheus:
  networkPolicy:
    enabled: false
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

Customize the [karpenter](https://karpenter.sh/) default installation by
upgrading its [Helm chart](https://artifacthub.io/packages/helm/oci-karpenter/karpenter)
and modifying the [default values](https://github.com/aws/karpenter/blob/v0.31.4/charts/karpenter/values.yaml):

```bash
# renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
KARPENTER_HELM_CHART_VERSION="v0.31.4"

tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" << EOF
replicas: 1
serviceMonitor:
  enabled: true
settings:
  aws:
    enablePodENI: true
    reservedENIs: "1"
EOF
helm upgrade --install --version "${KARPENTER_HELM_CHART_VERSION}" --namespace karpenter --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" karpenter oci://public.ecr.aws/karpenter/karpenter
```

### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters. It also simplifies the
process of obtaining, renewing, and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="200"}

The `cert-manager` service account was previously created by `eksctl`.
Install the `cert-manager` [Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify its [default values](https://github.com/cert-manager/cert-manager/blob/v1.14.3/deploy/charts/cert-manager/values.yaml):

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.14.3"

helm repo add --force-update jetstack https://charts.jetstack.io
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" << EOF
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
webhook:
  networkPolicy:
    enabled: true
EOF
helm upgrade --install --version "${CERT_MANAGER_HELM_CHART_VERSION}" --namespace cert-manager --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" cert-manager jetstack/cert-manager
```

Add ClusterIssuers for the Let's Encrypt staging environment:

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

kubectl wait --namespace cert-manager --timeout=15m --for=condition=Ready clusterissuer --all
```

Create the certificate:

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

### external-dns

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns) synchronizes
exposed Kubernetes Services and Ingresses with DNS providers.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="300"}

ExternalDNS will manage the DNS records. The `external-dns` service account
was previously created by `eksctl`.
Install the `external-dns` [Helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and modify its [default values](https://github.com/kubernetes-sigs/external-dns/blob/external-dns-helm-chart-1.14.3/charts/external-dns/values.yaml):

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.14.3"

helm repo add --force-update external-dns https://kubernetes-sigs.github.io/external-dns/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" << EOF
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

[ingress-nginx](https://kubernetes.github.io/ingress-nginx/) is an Ingress
controller for Kubernetes that uses [nginx](https://www.nginx.org/) as a
reverse proxy and load balancer.

Install the `ingress-nginx` [Helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify its [default values](https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.9.1/charts/ingress-nginx/values.yaml):

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.9.1"

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-staging

helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" << EOF
controller:
  allowSnippetAnnotations: true
  ingressClassResource:
    default: true
  admissionWebhooks:
    networkPolicyEnabled: true
  extraArgs:
    default-ssl-certificate: "cert-manager/ingress-cert-staging"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: ${TAGS//\'/}
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

[Forecastle](https://github.com/stakater/Forecastle) is a control panel that
dynamically discovers and provides a launchpad for accessing applications
deployed on Kubernetes.

![Forecastle](https://raw.githubusercontent.com/stakater/Forecastle/c70cc130b5665be2649d00101670533bba66df0c/frontend/public/logo512.png){:width="200"}

Install the `forecastle` [Helm chart](https://artifacthub.io/packages/helm/stakater/forecastle)
and modify its [default values](https://github.com/stakater/Forecastle/blob/v1.0.136/deployments/kubernetes/chart/forecastle/values.yaml):

```bash
# renovate: datasource=helm depName=forecastle registryUrl=https://stakater.github.io/stakater-charts
FORECASTLE_HELM_CHART_VERSION="1.0.136"

helm repo add --force-update stakater https://stakater.github.io/stakater-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-forecastle.yml" << EOF
forecastle:
  config:
    namespaceSelector:
      any: true
    title: Launch Pad
  networkPolicy:
    enabled: true
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

Use [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect the
application endpoints with Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg){:width="400"}

Install the `oauth2-proxy` [Helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify its [default values](https://github.com/oauth2-proxy/manifests/blob/oauth2-proxy-6.24.1/helm/oauth2-proxy/values.yaml):

```bash
# renovate: datasource=helm depName=oauth2-proxy registryUrl=https://oauth2-proxy.github.io/manifests
OAUTH2_PROXY_HELM_CHART_VERSION="6.24.1"

helm repo add --force-update oauth2-proxy https://oauth2-proxy.github.io/manifests
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-oauth2-proxy.yml" << EOF
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

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg){:width="400"}

Remove the EKS cluster and its created components:

```sh
if eksctl get cluster --name="${CLUSTER_NAME}"; then
  eksctl delete cluster --name="${CLUSTER_NAME}" --force
fi
```

Remove the Route 53 DNS records from the DNS Zone:

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

Remove any orphan EC2 instances created by Karpenter:

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text); do
  echo "Removing EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Remove the CloudWatch log group:

```sh
if [[ "$(aws logs describe-log-groups --query "logGroups[?logGroupName==\`/aws/eks/${CLUSTER_NAME}/cluster\`] | [0].logGroupName" --output text)" = "/aws/eks/${CLUSTER_NAME}/cluster" ]]; then
  aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
fi
```

Remove the CloudFormation stack:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53"
```

Wait for all CloudFormation stacks to complete deletion:

```sh
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove volumes and snapshots related to the cluster (as a precaution):

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text); do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done
```

Remove the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
if [[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]]; then
  for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{kubeconfig-${CLUSTER_NAME}.conf,{aws-cf-route53,eksctl-${CLUSTER_NAME},k8s-karpenter-provisioner,helm_values-{aws-node-termination-handler,cert-manager,external-dns,forecastle,ingress-nginx,karpenter,kube-prometheus-stack,mailhog,oauth2-proxy},k8s-cert-manager-{certificate,clusterissuer}-staging}.yml}; do
    if [[ -f "${FILE}" ]]; then
      rm -v "${FILE}"
    else
      echo "*** File not found: ${FILE}"
    fi
  done
  rmdir "${TMP_DIR}/${CLUSTER_FQDN}"
fi
```

Enjoy ... 😉
