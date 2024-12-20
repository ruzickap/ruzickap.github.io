---
title: Build secure and cheap Amazon EKS Auto Mode
author: Petr Ruzicka
date: 2024-12-14
description: Build "cheap and secure" Amazon EKS Auto Mode with network policies, cluster encryption and logging
categories: [Kubernetes, Amazon EKS Auto Mode, Security]
tags:
  [
    amazon eks,
    amaozn eks auto mode,
    k8s,
    kubernetes,
    security,
    eksctl,
    cert-manager,
    external-dns,
    podinfo,
    prometheus,
    sso,
    oauth2-proxy,
    metrics-server,
  ]
image: https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/icon-aws-amazon-eks.svg
---

I will outline the steps for setting up an [Amazon EKS Auto Mode](https://aws.amazon.com/eks/auto-mode/)
environment that is cost-effective while prioritizing security, and include
standard applications in the configuration.

Amazon EKS Auto Mode should align with these cost-effective criteria:

- Two AZ, use one zone if possible (less payments for cross AZ traffic)
- Spot instances
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type `t4g.medium` (2 x CPU, 4GB RAM) using
  [AWS Graviton](https://aws.amazon.com/ec2/graviton/) based on ARM
- Use [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) -
  minimal operation system / CPU / Memory footprint
- Use [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  as a most cost efficient + cost optimized load balancer

Amazon EKS Auto Mode should meet the following security requirements:

- Amazon EKS Auto Mode must be [encrypted by KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes needs to be encrypted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- Cluster logging ([CloudWatch](https://aws.amazon.com/cloudwatch/)) needs to be
  configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
  should be enabled wherever they are supported

## Build Amazon EKS Auto Mode

### Requirements

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

If you would like to follow this documents and it's task you will need to set up
few environment variables like:

```bash
# AWS Region
export AWS_REGION="${AWS_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="k01.k8s.mylabs.dev"
# Base Domain: k8s.mylabs.dev
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
# Cluster Name: k01
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"
# Tags used to tag the AWS resources
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev,Cluster=${CLUSTER_FQDN}}"
export AWS_PARTITION="aws"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) && export AWS_ACCOUNT_ID
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

Confirm whether all essential variables have been properly configured:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_ROLE_TO_ASSUME?}"
: "${GOOGLE_CLIENT_ID?}"
: "${GOOGLE_CLIENT_SECRET?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Deploy the required tools:

<!-- prettier-ignore-start -->
> You may bypass these procedures if you already have all the essential software
> installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)
- [helm](https://github.com/helm/helm)

## Configure AWS Route 53 Domain delegation

<!-- prettier-ignore-start -->
> DNS delegation tasks should be executed as a one-time operation
{: .prompt-info }
<!-- prettier-ignore-end -->

Create DNS zone for EKS clusters:

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

Utilize your domain registrar to update the nameservers for your zone, such as
`mylabs.dev` to point to the Amazon Route 53 nameservers. Here's the process to
discover the Route 53 nameservers.

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Establish the NS record in `k8s.mylabs.dev` (`BASE_DOMAIN`) for proper zone
delegation. This operation's specifics may vary based on your domain registrar.
In my case, I'm utilizing CloudFlare and employing Ansible for automation
purposes:

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

## Create the service-linked role

<!-- prettier-ignore-start -->
> Creating service-linked role for Spot Instance is a one-time operation
{: .prompt-info }
<!-- prettier-ignore-end -->

Create `AWSServiceRoleForEC2Spot` to use spot instances in the Amazon EKS cluster:

```shell
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

Details: [Work with Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html)

## Create Route53 zone and KMS key infrastructure

Generate a CloudFormation template that encompasses an [Amazon Route 53](https://aws.amazon.com/route53/)
zone and a [AWS Key Management Service (KMS)](https://aws.amazon.com/kms/) key.

Add the new domain `CLUSTER_FQDN` to Route 53 and set up DNS delegation from the
`BASE_DOMAIN`.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries and KMS key

Parameters:
  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live - Ex: k8s.mylabs.dev"
    Type: String
  ClusterFQDN:
    Description: "Cluster FQDN (domain for all applications) - Ex: k01.k8s.mylabs.dev"
    Type: String
  ClusterName:
    Description: "Cluster Name - Ex: k01"
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
  KMSAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub "alias/eks-${ClusterName}"
      TargetKeyId: !Ref KMSKey
  KMSKey:
    Type: AWS::KMS::Key
    Properties:
      Description: !Sub "KMS key for ${ClusterName} Amazon EKS"
      EnableKeyRotation: true
      PendingWindowInDays: 7
      KeyPolicy:
        Version: "2012-10-17"
        Id: !Sub "eks-key-policy-${ClusterName}"
        Statement:
          - Sid: Allow direct access to key metadata to the account
            Effect: Allow
            Principal:
              AWS:
                - !Sub "arn:${AWS::Partition}:iam::${AWS::AccountId}:root"
            Action:
              - kms:*
            Resource: "*"
          - Sid: Allow access through EBS for all principals in the account that are authorized to use EBS
            Effect: Allow
            Principal:
              AWS: "*"
            Action:
              - kms:Encrypt
              - kms:Decrypt
              - kms:ReEncrypt*
              - kms:GenerateDataKey*
              - kms:CreateGrant
              - kms:DescribeKey
            Resource: "*"
            Condition:
              StringEquals:
                kms:ViaService: !Sub "ec2.${AWS::Region}.amazonaws.com"
                kms:CallerAccount: !Sub "${AWS::AccountId}"
Outputs:
  KMSKeyArn:
    Description: The ARN of the created KMS Key to encrypt EKS related services
    Value: !GetAtt KMSKey.Arn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-KMSKeyArn"
  KMSKeyId:
    Description: The ID of the created KMS Key to encrypt EKS related services
    Value: !Ref KMSKey
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-KMSKeyId"
EOF

# shellcheck disable=SC2001
eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "BaseDomain=${BASE_DOMAIN} ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME}" \
  --stack-name "${CLUSTER_NAME}-route53-kms" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" --tags "${TAGS//,/ }"

# shellcheck disable=SC2016
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-kms" --query 'Stacks[0].Outputs[? OutputKey==`KMSKeyArn` || OutputKey==`KMSKeyId`].{OutputKey:OutputKey,OutputValue:OutputValue}')
AWS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
AWS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
```

After running the CF stack you should see the following Route53 zones:

![Route53 k01.k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k01.k8s.mylabs.dev.avif)
_Route53 k01.k8s.mylabs.dev zone_

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedones-k8s.mylabs.dev-2.avif)
_Route53 k8s.mylabs.dev zone_

You should see the following KMS key:

![KMS key](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key.avif)
_KMS key_

## Create Amazon EKS Auto Mode

I'm going to use [eksctl](https://eksctl.io/) to create the [Amazon EKS Auto Mode](https://aws.amazon.com/eks/auto-mode/)
cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png){:width="700"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  tags:
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
availabilityZones:
  - ${AWS_REGION}a
  - ${AWS_REGION}b
accessConfig:
  accessEntries:
    - principalARN: arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/admin
      accessPolicies:
        - policyARN: arn:${AWS_PARTITION}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
          accessScope:
            type: cluster
iam:
  podIdentityAssociations:
    - namespace: cert-manager
      serviceAccountName: cert-manager
      roleName: eksctl-${CLUSTER_NAME}-pia-cert-manager
      wellKnownPolicies:
        certManager: true
    - namespace: external-dns
      serviceAccountName: external-dns
      roleName: eksctl-${CLUSTER_NAME}-pia-external-dns
      wellKnownPolicies:
        externalDNS: true
autoModeConfig:
  enabled: true
  nodePools: ["system"]
secretsEncryption:
  keyARN: ${AWS_KMS_KEY_ARN}
cloudWatch:
  clusterLogging:
    logRetentionInDays: 1
    enableTypes:
      - all
EOF
eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" --kubeconfig "${KUBECONFIG}" || eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
```

To use network policies with EKS Auto Mode, you first need to enable the Network
Policy Controller by applying a ConfigMap to your cluster:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-configmap-amazon-vpc-cni.yml" << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: amazon-vpc-cni
  namespace: kube-system
data:
  enable-network-policy-controller: "true"
EOF
```

Create a [Node Class](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
for Amazon EKS which  defines infrastructure-level settings that apply to groups
of nodes in your EKS cluster, including network configuration, storage settings,
and resource tagging:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-eks-nodeclass.yml" << EOF | kubectl apply -f -
apiVersion: eks.amazonaws.com/v1
kind: NodeClass
metadata:
  name: my-default
spec:
$(kubectl get nodeclasses default -o yaml | yq '.spec | pick(["role", "securityGroupSelectorTerms", "subnetSelectorTerms"])' | sed 's/\(.*\)/  \1/')
  networkPolicyEventLogs: Enabled
  ephemeralStorage:
    size: 20Gi
  # Tags are not working due to bug: https://github.com/aws/containers-roadmap/issues/2487
  # tags:
  #   Name: ${CLUSTER_NAME}
EOF
```

Create a Node Pool for EKS Auto Mode to define specific requirements for your
compute resources, including instance types, availability zones, architectures,
and capacity types:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-karpenter-nodepool.yml" << EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: my-default
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: my-default
      requirements:
        - key: eks.amazonaws.com/instance-category
          operator: In
          values: ["t"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["${AWS_REGION}a"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
  limits:
    cpu: 8
    memory: 32Gi
EOF
```

Create a new StorageClass based upon [EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-storage-storageclass.yml" << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  name: gp3
provisioner: ebs.csi.eks.amazonaws.com
# https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md
parameters:
  kmsKeyId: ${AWS_KMS_KEY_ID}
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

### Mailpit

Mailpit will be used to receive email alerts from the Prometheus.

![mailpit](https://raw.githubusercontent.com/axllent/mailpit/61241f11ac94eb33bd84e399129992250eff56ce/server/ui/favicon.svg){:width="150"}

Install `mailpit`
[helm chart](https://artifacthub.io/packages/helm/jouve/mailpit)
and modify the
[default values](https://github.com/jouve/charts/blob/mailpit-0.18.6/charts/mailpit/values.yaml).

```bash
# renovate: datasource=helm depName=mailpit registryUrl=https://jouve.github.io/charts/
MAILPIT_HELM_CHART_VERSION="0.21.0"

helm repo add jouve https://jouve.github.io/charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" << EOF
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/description: An email and SMTP testing tool with API for developers
    gethomepage.dev/group: Media
    gethomepage.dev/icon: https://raw.githubusercontent.com/axllent/mailpit/61241f11ac94eb33bd84e399129992250eff56ce/server/ui/favicon.svg
    gethomepage.dev/name: Mailpit
    gethomepage.dev/widget.type: mailpit
    gethomepage.dev/widget.url: https://mailpit.${CLUSTER_FQDN}
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hostname: mailpit.${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${MAILPIT_HELM_CHART_VERSION}" --namespace mailpit --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" mailpit jouve/mailpit
```

Screenshot:

![Mailpit](/assets/img/posts/2024/2024-05-03-secure-cheap-amazon-eks-with-pod-identities/mailpit.avif){:width="700"}

### kube-prometheus-stack

Prometheus should be the initial application installed on the Kubernetes cluster
because numerous K8s services and applications have the capability to export
metrics to it.

[kube-prometheus stack](https://github.com/prometheus-operator/kube-prometheus)
is a collection of Kubernetes manifests, [Grafana](https://grafana.com/)
dashboards, and [Prometheus rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
combined with documentation and scripts to provide easy to operate end-to-end
Kubernetes cluster monitoring with [Prometheus](https://prometheus.io/) using
the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).

![Prometheus](https://raw.githubusercontent.com/cncf/artwork/40e2e8948509b40e4bad479446aaec18d6273bf2/projects/prometheus/horizontal/color/prometheus-horizontal-color.svg){:width="400"}

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-66.6.0/charts/kube-prometheus-stack/values.yaml):

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="66.7.1"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false
# https://github.com/prometheus-community/helm-charts/blob/main/charts/alertmanager/values.yaml
alertmanager:
  config:
    global:
      smtp_smarthost: "mailpit-smtp.mailpit.svc.cluster.local:25"
      smtp_from: "alertmanager@${CLUSTER_FQDN}"
    route:
      group_by: ["alertname", "job"]
      receiver: email
      routes:
        - receiver: email
          matchers:
            - severity =~ "warning|critical"
    receivers:
      - name: email
        email_configs:
          - to: "notification@${CLUSTER_FQDN}"
            require_tls: false
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      gethomepage.dev/enabled: "true"
      gethomepage.dev/description: The Alertmanager handles alerts sent by client applications such as the Prometheus server
      gethomepage.dev/group: Media
      gethomepage.dev/icon: alertmanager.svg
      gethomepage.dev/name: Alert Manager
      gethomepage.dev/widget.type: alertmanager
      gethomepage.dev/widget.url: https://alertmanager.${CLUSTER_FQDN}
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
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      gethomepage.dev/enabled: "true"
      gethomepage.dev/description: The open and composable observability and data visualization platform
      gethomepage.dev/group: Media
      gethomepage.dev/icon: grafana.svg
      gethomepage.dev/name: Grafana
      gethomepage.dev/widget.type: grafana
      gethomepage.dev/widget.url: https://grafana.${CLUSTER_FQDN}
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
  sidecar:
    datasources:
      url: http://kube-prometheus-stack-prometheus.kube-prometheus-stack:9090
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
        revision: 37
        datasource: Prometheus
      3662-prometheus-2-0-overview:
        # renovate: depName="Prometheus 2.0 Overview"
        gnetId: 3662
        revision: 2
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
      15038-external-dns:
        # renovate: depName="External-dns"
        gnetId: 15038
        revision: 3
        datasource: Prometheus
      # https://github.com/DevOps-Nirvana/Grafana-Dashboards
      14314-kubernetes-nginx-ingress-controller-nextgen-devops-nirvana:
        # renovate: depName="Kubernetes Nginx Ingress Prometheus NextGen"
        gnetId: 14314
        revision: 2
        datasource: Prometheus
      # https://grafana.com/orgs/imrtfm/dashboards - https://github.com/dotdc/grafana-dashboards-kubernetes
      15760-kubernetes-views-pods:
        # renovate: depName="Kubernetes / Views / Pods"
        gnetId: 15760
        revision: 28
        datasource: Prometheus
      15757-kubernetes-views-global:
        # renovate: depName="Kubernetes / Views / Global"
        gnetId: 15757
        revision: 42
        datasource: Prometheus
      15758-kubernetes-views-namespaces:
        # renovate: depName="Kubernetes / Views / Namespaces"
        gnetId: 15758
        revision: 41
        datasource: Prometheus
      15759-kubernetes-views-nodes:
        # renovate: depName="Kubernetes / Views / Nodes"
        gnetId: 15759
        revision: 32
        datasource: Prometheus
      15761-kubernetes-system-api-server:
        # renovate: depName="Kubernetes / System / API Server"
        gnetId: 15761
        revision: 18
        datasource: Prometheus
      15762-kubernetes-system-coredns:
        # renovate: depName="Kubernetes / System / CoreDNS"
        gnetId: 15762
        revision: 19
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
      karpenter-capacity-dashboard:
        url: https://karpenter.sh/v0.37/getting-started/getting-started-with-karpenter/karpenter-capacity-dashboard.json
      karpenter-performance-dashboard:
        url: https://karpenter.sh/v0.37/getting-started/getting-started-with-karpenter/karpenter-performance-dashboard.json
  grafana.ini:
    analytics:
      check_for_updates: false
    # server:
    #   root_url: https://grafana.${CLUSTER_FQDN}
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
    host: mailpit-smtp.mailpit.svc.cluster.local:25
    from_address: grafana@${CLUSTER_FQDN}
  networkPolicy:
    enabled: true
# EKS this is not available https://github.com/aws/containers-roadmap/issues/1298
kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
# EKS this is not available https://github.com/aws/containers-roadmap/issues/1298
kubeScheduler:
  enabled: false
# in EKS the kube-proxy metrics are not available https://github.com/aws/containers-roadmap/issues/657
kubeProxy:
  enabled: false
kube-state-metrics:
  selfMonitor:
    enabled: true
# https://github.com/prometheus-community/helm-charts/issues/3613
prometheus-node-exporter:
  prometheus:
    monitor:
      attachMetadata:
        node: true
      relabelings:
      - sourceLabels:
        - __meta_kubernetes_endpoint_node_name
        targetLabel: node
        action: replace
        regex: (.+)
        replacement: \${1}
prometheusOperator:
  networkPolicy:
    enabled: true
prometheus:
  networkPolicy:
    enabled: true
    ingress:
      - from:
        - namespaceSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus-adapter
              kubernetes.io/metadata.name: prometheus-adapter
        - podSelector:
            matchLabels:
              app.kubernetes.io/instance: prometheus-adapter
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      gethomepage.dev/enabled: "true"
      gethomepage.dev/description: Prometheus is a systems and service monitoring system
      gethomepage.dev/group: Media
      gethomepage.dev/icon: prometheus.svg
      gethomepage.dev/name: Prometheus
      gethomepage.dev/widget.type: prometheus
      gethomepage.dev/widget.url: https://prometheus.${CLUSTER_FQDN}
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
    probeSelectorNilUsesHelmValues: false
    retentionSize: 1GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters, and simplifies the process
of obtaining, renewing and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="150"}

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify the
[default values](https://github.com/cert-manager/cert-manager/blob/v1.16.2/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.16.2"

helm repo add jetstack https://charts.jetstack.io
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" << EOF
crds:
  enabled: true
serviceAccount:
  name: cert-manager
enableCertificateOwnerRef: true
prometheus:
  servicemonitor:
    enabled: true
webhook:
  networkPolicy:
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
            region: ${AWS_REGION}
EOF
kubectl wait --namespace cert-manager --timeout=15m --for=condition=Ready clusterissuer --all
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

### Prometheus Adapter

[Prometheus Adapter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-adapter)
is an implementation of the custom.metrics.k8s.io API using Prometheus. I'm
using it as [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
replacement as descibed [here](https://github.com/prometheus-community/helm-charts/issues/3613).

Install `prometheus-adapter`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/prometheus-adapter)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/prometheus-adapter-4.11.0/charts/prometheus-adapter/values.yaml):

```bash
# renovate: datasource=helm depName=prometheus-adapter registryUrl=https://prometheus-community.github.io/helm-charts
PROMETHEUS_ADAPTER_HELM_CHART_VERSION="4.11.0"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-prometheus-adapter.yml" << \EOF
prometheus:
  url: http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local
rules:
  resource:
    cpu:
      containerQuery: |
        sum by (<<.GroupBy>>) (
          rate(container_cpu_usage_seconds_total{container!="",<<.LabelMatchers>>}[3m])
        )
      nodeQuery: |
        sum  by (<<.GroupBy>>) (
          rate(node_cpu_seconds_total{mode!="idle",mode!="iowait",mode!="steal",<<.LabelMatchers>>}[3m])
        )
      resources:
        overrides:
          node:
            resource: node
          namespace:
            resource: namespace
          pod:
            resource: pod
      containerLabel: container
    memory:
      containerQuery: |
        sum by (<<.GroupBy>>) (
          avg_over_time(container_memory_working_set_bytes{container!="",<<.LabelMatchers>>}[3m])
        )
      nodeQuery: |
        sum by (<<.GroupBy>>) (
          avg_over_time(node_memory_MemTotal_bytes{<<.LabelMatchers>>}[3m])
          -
          avg_over_time(node_memory_MemAvailable_bytes{<<.LabelMatchers>>}[3m])
        )
      resources:
        overrides:
          node:
            resource: node
          namespace:
            resource: namespace
          pod:
            resource: pod
      containerLabel: container
    window: 3m
EOF
helm upgrade --install --version "${PROMETHEUS_ADAPTER_HELM_CHART_VERSION}" --namespace prometheus-adapter --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-prometheus-adapter.yml" prometheus-adapter prometheus-community/prometheus-adapter
```

### ExternalDNS

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns) synchronizes
exposed Kubernetes Services and Ingresses with DNS providers.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="200"}

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and modify the
[default values](https://github.com/kubernetes-sigs/external-dns/blob/external-dns-helm-chart-1.15.0/charts/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.15.0"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" << EOF
serviceAccount:
  name: external-dns
serviceMonitor:
  enabled: true
interval: 20s
policy: sync
domainFilters:
  - ${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${EXTERNAL_DNS_HELM_CHART_VERSION}" --namespace external-dns --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" external-dns external-dns/external-dns
```

### Ingress NGINX Controller

[ingress-nginx](https://kubernetes.github.io/ingress-nginx/) is an Ingress
controller for Kubernetes using [NGINX](https://www.nginx.org/) as a reverse
proxy and load balancer.

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.11.3/charts/ingress-nginx/values.yaml).

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.11.3"

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-staging

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" << EOF
controller:
  allowSnippetAnnotations: true
  networkPolicy:
    enabled: true
  ingressClassResource:
    default: true
  extraArgs:
    default-ssl-certificate: "cert-manager/ingress-cert-staging"
  admissionWebhooks:
    networkPolicy:
      enabled: true
  service:
    annotations:
      # https://www.qovery.com/blog/our-migration-from-kubernetes-built-in-nlb-to-alb-controller/
      # https://www.youtube.com/watch?v=xwiRjimKW9c
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: ${TAGS//\'/}
      # service.beta.kubernetes.io/aws-load-balancer-alpn-policy: HTTP2Preferred
      service.beta.kubernetes.io/aws-load-balancer-name: eks-${CLUSTER_NAME}
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      # service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-type: external
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
          expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds{host!="_"}) by (host) - time()) < 604800
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

### OAuth2 Proxy

Use [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect
the endpoints by Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg){:width="300"}

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify the
[default values](https://github.com/oauth2-proxy/manifests/blob/oauth2-proxy-7.8.2/helm/oauth2-proxy/values.yaml).

```bash
# renovate: datasource=helm depName=oauth2-proxy registryUrl=https://oauth2-proxy.github.io/manifests
OAUTH2_PROXY_HELM_CHART_VERSION="7.8.2"

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
  ingressClassName: nginx
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

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg){:width="300"}

Remove EKS cluster and created components:

```sh
if eksctl get cluster --name="${CLUSTER_NAME}"; then
  eksctl delete cluster --name="${CLUSTER_NAME}" --force
fi
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

Remove CloudFormation stack:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-kms"
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53-kms"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove Volumes and Snapshots related to the cluster (just in case):

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text) ; do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done
```

Remove CloudWatch log group:

```sh
aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
```

Remove `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
[[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]] && rm -rvf "${TMP_DIR}/${CLUSTER_FQDN}"
```

Enjoy ... 😉
