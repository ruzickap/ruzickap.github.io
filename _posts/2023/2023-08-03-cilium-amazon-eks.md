---
title: Build secure Amazon EKS with Cilium and network encryption
author: Petr Ruzicka
date: 2023-08-03
description: Build "cheap and secure" Amazon EKS with Karpenter and Cilium
categories: [Kubernetes, Amazon EKS, Cilium, Security]
tags:
  [
    Amazon EKS,
    k8s,
    kubernetes,
    security,
    karpenter,
    eksctl,
    cert-manager,
    external-dns,
    podinfo,
    cilium,
    prometheus,
    sso,
    oauth2-proxy,
    metrics-server,
  ]
image: https://raw.githubusercontent.com/cncf/artwork/ac38e11ed57f017a06c9dcb19013bcaed92115a9/projects/cilium/icon/color/cilium_icon-color.svg
---

I will describe how to install [Amazon EKS](https://aws.amazon.com/eks/) with
Karpenter and Cilium, along with other standard applications.

The Amazon EKS setup aims to meet the following cost-efficiency requirements:

- Use only two Availability Zones (AZs) to reduce payments for cross-AZ
  traffic
- Spot instances
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type `t4g.medium` (2 x CPU, 4GB RAM) using
  [AWS Graviton](https://aws.amazon.com/ec2/graviton/) based on ARM
- Use [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) - small
  operation system / CPU / Memory footprint
- Use [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  as a most cost efficient + cost optimized load balancer
- [Karpenter](https://karpenter.sh/) to autoscale with appropriately sized nodes
  matching pod requirements

The Amazon EKS setup should also meet the following security requirements:

- The Amazon EKS control plane must be [encrypted using KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes must be encrypted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- Cluster logging to [CloudWatch](https://aws.amazon.com/cloudwatch/) must be
  configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

The Cilium installation aims to meet these requirements:

- [Transparent network encryption](https://isovalent.com/videos/wireguard-node-to-node-encryption-on-cilium/)
  for node-to-node traffic should be enabled
- Encryption should use [WireGuard](https://en.wikipedia.org/wiki/WireGuard) as
  it is considered a fast encryption method
- Use [Elastic Network Interface (ENI)](https://docs.cilium.io/en/v1.14/network/concepts/ipam/eni/#aws-eni)
  integration
- [Layer 7 network observability](https://docs.cilium.io/en/v1.14/observability/visibility/)
  should be enabled
- The Cilium [Hubble](https://github.com/cilium/hubble) UI should be protected by
  Single Sign-On (SSO)

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

If you plan to follow this document and its tasks, you will need to set up a
few environment variables, such as:

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
- [cilium](https://github.com/cilium/cilium-cli)
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
`mylabs.dev`) to use Amazon Route 53 nameservers. You can find the required
Route 53 nameservers as follows:

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

### Create Route53 zone and KMS key

Create a CloudFormation template that defines the [Route53](https://aws.amazon.com/route53/)
zone and a [KMS](https://aws.amazon.com/kms/) key.

Add the new domain `CLUSTER_FQDN` to Route 53 and configure DNS delegation
from the `BASE_DOMAIN`.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries and KMS key

Parameters:
  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String
  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: k01.k8s.mylabs.dev"
    Type: String
  ClusterName:
    Description: "Cluster Name Ex: k01"
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
          - Sid: Enable IAM User Permissions
            Effect: Allow
            Principal:
              AWS:
                - !Sub "arn:aws:iam::${AWS::AccountId}:root"
            Action: kms:*
            Resource: "*"
          - Sid: Allow use of the key
            Effect: Allow
            Principal:
              AWS:
                - !Sub "arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
                # The following roles needs to be enabled after the EKS cluster is created
                # aws-ebs-csi-driver + Karpenter should be able to use the KMS key
                # - !Sub "arn:aws:iam::${AWS::AccountId}:role/eksctl-${ClusterName}-irsa-aws-ebs-csi-driver"
                # - !Sub "arn:aws:iam::${AWS::AccountId}:role/eksctl-${ClusterName}-iamservice-role"
            Action:
              - kms:Encrypt
              - kms:Decrypt
              - kms:ReEncrypt*
              - kms:GenerateDataKey*
              - kms:DescribeKey
            Resource: "*"
          - Sid: Allow attachment of persistent resources
            Effect: Allow
            Principal:
              AWS:
                - !Sub "arn:aws:iam::${AWS::AccountId}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
                # - !Sub "arn:aws:iam::${AWS::AccountId}:role/eksctl-${ClusterName}-irsa-aws-ebs-csi-driver"
                # - !Sub "arn:aws:iam::${AWS::AccountId}:role/eksctl-${ClusterName}-iamservice-role"
            Action:
              - kms:CreateGrant
            Resource: "*"
            Condition:
              Bool:
                kms:GrantIsForAWSResource: true
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

if [[ $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query "StackSummaries[?starts_with(StackName, \`${CLUSTER_NAME}-route53-kms\`) == \`true\`].StackName" --output text) == "" ]]; then
  # shellcheck disable=SC2001
  eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "BaseDomain=${BASE_DOMAIN} ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME}" \
    --stack-name "${CLUSTER_NAME}-route53-kms" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" --tags "${TAGS//,/ }"
fi

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-kms" --query "Stacks[0].Outputs[? OutputKey==\`KMSKeyArn\` || OutputKey==\`KMSKeyId\`].{OutputKey:OutputKey,OutputValue:OutputValue}")
AWS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
AWS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
```

After running the CloudFormation stack, you should see the following Route53
zones:

![Route53 k01.k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k01.k8s.mylabs.dev.avif)
_Route53 k01.k8s.mylabs.dev zone_

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedones-k8s.mylabs.dev-2.avif)
_Route53 k8s.mylabs.dev zone_

You should also see the following KMS key:

![KMS key](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key.avif)
_KMS key_

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
        name: aws-for-fluent-bit
        namespace: aws-for-fluent-bit
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
      roleName: eksctl-${CLUSTER_NAME}-irsa-aws-for-fluent-bit
    - metadata:
        name: ebs-csi-controller-sa
        namespace: aws-ebs-csi-driver
      wellKnownPolicies:
        ebsCSIController: true
      roleName: eksctl-${CLUSTER_NAME}-irsa-aws-ebs-csi-driver
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
      roleName: eksctl-${CLUSTER_NAME}-irsa-cert-manager
    - metadata:
        name: cilium-operator
        namespace: cilium
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
      roleName: eksctl-${CLUSTER_NAME}-irsa-cilium
      roleOnly: true
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
  - name: kube-proxy
  - name: coredns
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
    volumeKmsKeyID: ${AWS_KMS_KEY_ID}
    taints:
     - key: "node.cilium.io/agent-not-ready"
       value: "true"
       effect: "NoExecute"
    maxPodsPerNode: 110
    privateNetworking: true
  # Second node group is needed for karpenter to start (will be removed later) (Issue: https://github.com/eksctl-io/eksctl/issues/7003)
  - name: mng02-ng
    amiFamily: Bottlerocket
    instanceType: t4g.small
    desiredCapacity: 2
    availabilityZones:
      - ${AWS_DEFAULT_REGION}a
    volumeSize: 5
    volumeEncrypted: true
    volumeKmsKeyID: ${AWS_KMS_KEY_ID}
    spot: true
    privateNetworking: true
secretsEncryption:
  keyARN: ${AWS_KMS_KEY_ARN}
cloudWatch:
  clusterLogging:
    logRetentionInDays: 1
    enableTypes:
      - all
EOF
```

Get the kubeconfig file to access the cluster:

```bash
if [[ ! -s "${KUBECONFIG}" ]]; then
  if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null; then
    eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yml" --kubeconfig "${KUBECONFIG}"
    # Add roles created by eksctl to the KMS policy to allow aws-ebs-csi-driver work with encrypted EBS volumes
    sed -i "s@# \(- \!Sub \"arn:aws:iam::\${AWS::AccountId}:role/eksctl-\${ClusterName}.*\)@\1@" "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml"
    eval aws cloudformation update-stack \
      --parameters "ParameterKey=BaseDomain,ParameterValue=${BASE_DOMAIN} ParameterKey=ClusterFQDN,ParameterValue=${CLUSTER_FQDN} ParameterKey=ClusterName,ParameterValue=${CLUSTER_NAME}" \
      --stack-name "${CLUSTER_NAME}-route53-kms" --template-body "file://${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml"
  else
    eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  fi
fi

aws eks update-kubeconfig --name="${CLUSTER_NAME}"
```

The `sed` command used earlier modified the `aws-cf-route53-kms.yml` file by
incorporating the newly established IAM roles
(`eksctl-k01-irsa-aws-ebs-csi-driver` and `eksctl-k01-iamservice-role`),
enabling them to utilize the KMS key.

![KMS key with new IAM roles](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key-2.avif)
_KMS key with new IAM roles_

### Harden the Amazon EKS cluster and components

Get the necessary details about the VPC, NACLs, and SGs:

```bash
AWS_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=${CLUSTER_NAME}" --query 'Vpcs[*].VpcId' --output text)
AWS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${AWS_VPC_ID}" "Name=group-name,Values=default" --query 'SecurityGroups[*].GroupId' --output text)
```

Fix a "high" rated security issue "Default security group should have no rules
configured":

```bash
aws ec2 revoke-security-group-egress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --cidr 0.0.0.0/0 | jq || true
aws ec2 revoke-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --source-group "${AWS_SECURITY_GROUP_ID}" | jq || true
```

### Cilium

[Cilium](https://cilium.io/) is a networking, observability, and security
solution featuring an eBPF-based dataplane.

Endpoint ports:

- 4244 (peer-service)
- 9962 (metrics)
- 9963 (cilium-operator/metrics)
- 9964 (envoy-metrics), 9965 (hubble-metrics)

![Cilium](https://raw.githubusercontent.com/cilium/cilium/eb3662e6f72d8fa1d2c884967e8de6bf063cb108/Documentation/images/logo.svg){:width="500"}

Install [Cilium](https://cilium.io/) and remove the `mng02-ng` nodegroup used
for the "eksctl karpenter" installation (it is no longer needed because Cilium
will be installed and the taints will be removed):

```bash
CILIUM_OPERATOR_SERVICE_ACCOUNT_ROLE_ARN=$(eksctl get iamserviceaccount --cluster "${CLUSTER_NAME}" --output json | jq -r ".[] | select(.metadata.name==\"cilium-operator\") .status.roleARN")
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cilium.yml" << EOF
cluster:
  name: ${CLUSTER_NAME}
  id: 0
serviceAccounts:
  operator:
    name: cilium-operator
    annotations:
      eks.amazonaws.com/role-arn: ${CILIUM_OPERATOR_SERVICE_ACCOUNT_ROLE_ARN}
bandwidthManager:
  enabled: true
egressMasqueradeInterfaces: eth0
encryption:
  enabled: true
  type: wireguard
eni:
  enabled: true
  awsEnablePrefixDelegation: true
  awsReleaseExcessIPs: true
  eniTags:
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
  iamRole: ${CILIUM_OPERATOR_SERVICE_ACCOUNT_ROLE_ARN}
hubble:
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - http
  relay:
    enabled: true
ipam:
  mode: eni
kubeProxyReplacement: disabled
tunnel: disabled
EOF

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io/
CILIUM_HELM_CHART_VERSION="1.14.0"

if ! kubectl get namespace cilium &> /dev/null; then
  kubectl create ns cilium
  cilium install --namespace cilium --version "${CILIUM_HELM_CHART_VERSION}" --wait --helm-values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cilium.yml"
  eksctl delete nodegroup mng02-ng --cluster "${CLUSTER_NAME}" --wait
fi
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
  consolidation:
    enabled: true
  startupTaints:
    - key: node.cilium.io/agent-not-ready
      value: "true"
      effect: NoExecute
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
        kmsKeyID: ${AWS_KMS_KEY_ARN}
    - deviceName: /dev/xvdb
      ebs:
        volumeSize: 20Gi
        volumeType: gp3
        encrypted: true
        kmsKeyID: ${AWS_KMS_KEY_ARN}
  tags:
    KarpenerProvisionerName: "default"
    Name: "${CLUSTER_NAME}-karpenter"
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
EOF
```

### aws-node-termination-handler

The [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
gracefully handles EC2 instance shutdowns within Kubernetes.

It is not needed when using EKS managed node groups, as discussed in
[Use with managed node groups](https://github.com/aws/aws-node-termination-handler/issues/186).

### snapshot-controller

Install the Volume Snapshot Custom Resource Definitions (CRDs):

```bash
kubectl apply --kustomize 'https://github.com/kubernetes-csi/external-snapshotter//client/config/crd/?ref=v8.1.0'
```

![CSI](https://raw.githubusercontent.com/cncf/artwork/d8ed92555f9aae960ebd04788b788b8e8d65b9f6/other/csi/horizontal/color/csi-horizontal-color.svg){:width="500"}

Install the volume snapshot controller `snapshot-controller` [Helm chart](https://github.com/piraeusdatastore/helm-charts/tree/main/charts/snapshot-controller)
and modify its [default values](https://github.com/piraeusdatastore/helm-charts/blob/snapshot-controller-2.2.0/charts/snapshot-controller/values.yaml):

```bash
# renovate: datasource=helm depName=snapshot-controller registryUrl=https://piraeus.io/helm-charts/
SNAPSHOT_CONTROLLER_HELM_CHART_VERSION="2.2.0"

helm repo add --force-update piraeus-charts https://piraeus.io/helm-charts/
helm upgrade --wait --install --version "${SNAPSHOT_CONTROLLER_HELM_CHART_VERSION}" --namespace snapshot-controller --create-namespace snapshot-controller piraeus-charts/snapshot-controller
```

### aws-ebs-csi-driver

The [Amazon Elastic Block Store](https://aws.amazon.com/ebs/) (Amazon EBS)
Container Storage Interface (CSI) Driver provides a [CSI](https://github.com/container-storage-interface/spec/blob/master/spec.md)
interface used by Container Orchestrators to manage the lifecycle of Amazon EBS
volumes.

The `ebs-csi-controller-sa` ServiceAccount was created by `eksctl`.
Install the Amazon EBS CSI Driver `aws-ebs-csi-driver` [Helm chart](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/charts/aws-ebs-csi-driver)
and modify its [default values](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/helm-chart-aws-ebs-csi-driver-2.27.0/charts/aws-ebs-csi-driver/values.yaml):

```bash
# renovate: datasource=helm depName=aws-ebs-csi-driver registryUrl=https://kubernetes-sigs.github.io/aws-ebs-csi-driver
AWS_EBS_CSI_DRIVER_HELM_CHART_VERSION="2.27.0"

helm repo add --force-update aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-ebs-csi-driver.yml" << EOF
controller:
  enableMetrics: false
  serviceMonitor:
    forceEnable: true
  k8sTagClusterId: ${CLUSTER_NAME}
  extraVolumeTags:
    "eks:cluster-name": ${CLUSTER_NAME}
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
  serviceAccount:
    create: false
    name: ebs-csi-controller-sa
  region: ${AWS_DEFAULT_REGION}
node:
  securityContext:
    # The node pod must be run as root to bind to the registration/driver sockets
    runAsNonRoot: false
storageClasses:
  - name: gp3
    annotations:
      storageclass.kubernetes.io/is-default-class: "true"
    parameters:
      encrypted: "true"
      kmskeyid: ${AWS_KMS_KEY_ARN}
volumeSnapshotClasses:
  - name: ebs-vsc
    annotations:
      snapshot.storage.kubernetes.io/is-default-class: "true"
    deletionPolicy: Delete
EOF
helm upgrade --install --version "${AWS_EBS_CSI_DRIVER_HELM_CHART_VERSION}" --namespace aws-ebs-csi-driver --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-ebs-csi-driver.yml" aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver
```

Delete the `gp2` StorageClass, as `gp3` will be used instead:

```bash
kubectl delete storageclass gp2 || true
```

## Prometheus, DNS, Ingress, Certificates and others

Many Kubernetes services and applications can export metrics to Prometheus. For
this reason, Prometheus should be one of the first applications installed on a
Kubernetes cluster.

Then, you will need some basic tools and integrations, such as [external-dns](https://github.com/kubernetes-sigs/external-dns),
[ingress-nginx](https://kubernetes.github.io/ingress-nginx/), [cert-manager](https://cert-manager.io/),
[oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), and others.

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

Endpoint ports:

- 10260 (kube-prometheus-stack-operator/https)
- 8080 (kube-prometheus-stack-prometheus/reloader-web)
- 9090 (kube-prometheus-stack-prometheus/http-web)
- 8080 (kube-prometheus-stack-kube-state-metrics/http)
- 9100 (kube-prometheus-stack-prometheus-node-exporter/http-metrics)
- 10250 (kube-prometheus-stack-kubelet/https-metrics) -> 10253 (conflicts with
  kubelet, cert-manager, ...)
- 10255 (kube-prometheus-stack-kubelet/http-metrics)
- 4194 (kube-prometheus-stack-kubelet/cadvisor)
- 8081 (kube-prometheus-stack-kube-state-metrics/telemetry-port) -> 8082
  (conflicts with karpenter)

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
      16611-cilium-metrics:
        # renovate: depName="Cilium v1.12 Agent Metrics"
        gnetId: 16611
        revision: 1
        datasource: Prometheus
      16612-cilium-operator:
        # renovate: depName="Cilium v1.12 Operator Metrics"
        gnetId: 16612
        revision: 1
        datasource: Prometheus
      16613-hubble:
        # renovate: depName="Cilium v1.12 Hubble Metrics"
        gnetId: 16613
        revision: 1
        datasource: Prometheus
      19268-prometheus:
        # renovate: depName="Prometheus All Metrics"
        gnetId: 19268
        revision: 1
        datasource: Prometheus
      18855-fluent-bit:
        # renovate: depName="Fluent Bit"
        gnetId: 18855
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
  hostNetwork: true
  networkPolicy:
    enabled: true
  selfMonitor:
    enabled: true
    telemetryPort: 8082
prometheus-node-exporter:
  networkPolicy:
    enabled: true
  hostNetwork: true
prometheusOperator:
  tls:
    # https://github.com/prometheus-community/helm-charts/issues/2248
    internalPort: 10253
  networkPolicy:
    enabled: true
  hostNetwork: true
prometheus:
  networkPolicy:
    enabled: true
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
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
    hostNetwork: true
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

### karpenter

Endpoint ports:

- 8000 (http-metrics)
- 8081
- 8443 (https-webhook) -> 8444 (conflicts with ingress-nginx)

Customize the [Karpenter](https://karpenter.sh/) default installation by
upgrading its [Helm chart](https://artifacthub.io/packages/helm/oci-karpenter/karpenter)
and modifying the [default values](https://github.com/aws/karpenter/blob/v0.31.4/charts/karpenter/values.yaml):

```bash
# renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
KARPENTER_HELM_CHART_VERSION="v0.31.4"

tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" << EOF
replicas: 1
serviceMonitor:
  enabled: true
hostNetwork: true
webhook:
  port: 8444
settings:
  aws:
    enablePodENI: true
    reservedENIs: "1"
EOF
helm upgrade --install --version "${KARPENTER_HELM_CHART_VERSION}" --namespace karpenter --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" karpenter oci://public.ecr.aws/karpenter/karpenter
```

### Cilium - monitoring

Add Hubble to Cilium, enabling Prometheus metrics and other observability
features:

```bash
helm repo add --force-update cilium https://helm.cilium.io/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cilium.yml" << EOF
hubble:
  metrics:
    serviceMonitor:
      enabled: true
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - http
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
  relay:
    enabled: true
    prometheus:
      enabled: true
      serviceMonitor:
        enabled: true
  ui:
    enabled: true
    ingress:
      enabled: true
      annotations:
        forecastle.stakater.com/expose: "true"
        forecastle.stakater.com/icon: https://raw.githubusercontent.com/cilium/hubble/83a6345a7100531d4e8c54ba0a92352051b8c861/Documentation/images/hubble_logo.png
        forecastle.stakater.com/appName: Hubble UI
        nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
        nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
      className: nginx
      hosts:
        - hubble.${CLUSTER_FQDN}
      tls:
        - hosts:
            - hubble.${CLUSTER_FQDN}
prometheus:
  enabled: true
  serviceMonitor:
    enabled: true
envoy:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
operator:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
EOF
helm upgrade --install --version "${CILIUM_HELM_CHART_VERSION}" --namespace cilium --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cilium.yml" cilium cilium/cilium
```

### aws-for-fluent-bit

Fluent Bit is an open-source log processor and forwarder that allows you to
collect data like metrics and logs from different sources, enrich it with
filters, and send it to multiple destinations.

Endpoint ports:

- 2020 (monitor-agent)

Install the `aws-for-fluent-bit` [Helm chart](https://artifacthub.io/packages/helm/aws/aws-for-fluent-bit)
and modify its [default values](https://github.com/aws/eks-charts/blob/master/stable/aws-for-fluent-bit/values.yaml):

```bash
# renovate: datasource=helm depName=aws-for-fluent-bit registryUrl=https://aws.github.io/eks-charts
AWS_FOR_FLUENT_BIT_HELM_CHART_VERSION="0.1.32"

helm repo add --force-update eks https://aws.github.io/eks-charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-for-fluent-bit.yml" << EOF
cloudWatchLogs:
  region: ${AWS_DEFAULT_REGION}
  logGroupTemplate: "/aws/eks/${CLUSTER_NAME}/cluster"
  logStreamTemplate: "\$kubernetes['namespace_name'].\$kubernetes['pod_name']"
serviceAccount:
  create: false
  name: aws-for-fluent-bit
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
serviceMonitor:
  enabled: true
  extraEndpoints:
    - port: metrics
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
      scheme: http
EOF
helm upgrade --install --version "${AWS_FOR_FLUENT_BIT_HELM_CHART_VERSION}" --namespace aws-for-fluent-bit --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-for-fluent-bit.yml" aws-for-fluent-bit eks/aws-for-fluent-bit
```

### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters and simplifies the process of
obtaining, renewing, and using those certificates.

Endpoint ports:

- 10250 (cert-manager-webhook/https) -> 10251 (conflicts with
  kube-prometheus-stack-kubelet/https-metrics)

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="200"}

The `cert-manager` ServiceAccount was created by `eksctl`.
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
  securePort: 10251
  hostNetwork: true
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

ExternalDNS will manage the DNS records. The `external-dns` ServiceAccount was
created by `eksctl`.
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

Endpoint ports:

- 80 (http)
- 443 (https)
- 8443 (https-webhook)
- 10254 (metrics)

Install the `ingress-nginx` [Helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify its [default values](https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.9.1/charts/ingress-nginx/values.yaml):

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.9.1"

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-staging

helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" << EOF
controller:
  hostNetwork: true
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

Use [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect
application endpoints with Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg){:width="400"}

Install the `oauth2-proxy` [Helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify its [default values](https://github.com/oauth2-proxy/manifests/blob/oauth2-proxy-6.24.2/helm/oauth2-proxy/values.yaml):

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

### Cilium details

Let's check the Cilium status using the [Cilium CLI](https://github.com/cilium/cilium-cli):

```bash
cilium status -n cilium
```

```console
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
Deployment             cilium-operator    Desired: 1, Ready: 1/1, Available: 1/1
DaemonSet              cilium             Desired: 2, Ready: 2/2, Available: 2/2
Containers:            hubble-relay       Running: 1
                       cilium-operator    Running: 1
                       cilium             Running: 2
                       hubble-ui          Running: 1
Cluster Pods:          18/18 managed by Cilium
Helm chart version:    1.14.0
Image versions         hubble-relay       quay.io/cilium/hubble-relay:v1.14.0@sha256:bfe6ef86a1c0f1c3e8b105735aa31db64bcea97dd4732db6d0448c55a3c8e70c: 1
                       cilium-operator    quay.io/cilium/operator-aws:v1.14.0@sha256:396953225ca4b356a22e526a9e1e04e65d33f84a0447bc6374c14da12f5756cd: 1
                       cilium             quay.io/cilium/cilium:v1.14.0@sha256:5a94b561f4651fcfd85970a50bc78b201cfbd6e2ab1a03848eab25a82832653a: 2
                       hubble-ui          quay.io/cilium/hubble-ui:v0.12.0@sha256:1c876cfa1d5e35bc91e1025c9314f922041592a88b03313c22c1f97a5d2ba88f: 1
                       hubble-ui          quay.io/cilium/hubble-ui-backend:v0.12.0@sha256:8a79a1aad4fc9c2aa2b3e4379af0af872a89fcec9d99e117188190671c66fc2e: 1
```

The Cilium configuration can be found in the `cilium-config` ConfigMap:

```bash
kubectl -n cilium get configmap cilium-config -o yaml
```

```console
apiVersion: v1
data:
  agent-not-ready-taint-key: node.cilium.io/agent-not-ready
  arping-refresh-period: 30s
  auto-create-cilium-node-resource: "true"
  auto-direct-node-routes: "false"
  aws-enable-prefix-delegation: "true"
  aws-release-excess-ips: "true"
  bpf-lb-external-clusterip: "false"
  bpf-lb-map-max: "65536"
  bpf-lb-sock: "false"
  bpf-map-dynamic-size-ratio: "0.0025"
  bpf-policy-map-max: "16384"
  bpf-root: /sys/fs/bpf
  cgroup-root: /run/cilium/cgroupv2
  cilium-endpoint-gc-interval: 5m0s
  cluster-id: "0"
  cluster-name: k01
  cni-exclusive: "true"
  cni-log-file: /var/run/cilium/cilium-cni.log
  cnp-node-status-gc-interval: 0s
  custom-cni-conf: "false"
  debug: "false"
  debug-verbose: ""
  disable-cnp-status-updates: "true"
  ec2-api-endpoint: ""
  egress-gateway-reconciliation-trigger-interval: 1s
  egress-masquerade-interfaces: eth0
  enable-auto-protect-node-port-range: "true"
  enable-bandwidth-manager: "true"
  enable-bbr: "false"
  enable-bgp-control-plane: "false"
  enable-bpf-clock-probe: "false"
  enable-endpoint-health-checking: "true"
  enable-endpoint-routes: "true"
  enable-health-check-nodeport: "true"
  enable-health-checking: "true"
  enable-hubble: "true"
  enable-hubble-open-metrics: "false"
  enable-ipv4: "true"
  enable-ipv4-big-tcp: "false"
  enable-ipv4-masquerade: "true"
  enable-ipv6: "false"
  enable-ipv6-big-tcp: "false"
  enable-ipv6-masquerade: "true"
  enable-k8s-networkpolicy: "true"
  enable-k8s-terminating-endpoint: "true"
  enable-l2-neigh-discovery: "true"
  enable-l7-proxy: "true"
  enable-local-redirect-policy: "false"
  enable-metrics: "true"
  enable-policy: default
  enable-remote-node-identity: "true"
  enable-sctp: "false"
  enable-svc-source-range-check: "true"
  enable-vtep: "false"
  enable-well-known-identities: "false"
  enable-wireguard: "true"
  enable-xt-socket-fallback: "true"
  eni-tags: '{"cluster":"k01.k8s.mylabs.dev","owner":"petr.ruzicka@gmail.com","product_id":"12345","used_for":"dev"}'
  external-envoy-proxy: "false"
  hubble-disable-tls: "false"
  hubble-listen-address: :4244
  hubble-metrics: dns drop tcp flow icmp http
  hubble-metrics-server: :9965
  hubble-socket-path: /var/run/cilium/hubble.sock
  hubble-tls-cert-file: /var/lib/cilium/tls/hubble/server.crt
  hubble-tls-client-ca-files: /var/lib/cilium/tls/hubble/client-ca.crt
  hubble-tls-key-file: /var/lib/cilium/tls/hubble/server.key
  identity-allocation-mode: crd
  identity-gc-interval: 15m0s
  identity-heartbeat-timeout: 30m0s
  install-no-conntrack-iptables-rules: "false"
  ipam: eni
  ipam-cilium-node-update-rate: 15s
  k8s-client-burst: "10"
  k8s-client-qps: "5"
  kube-proxy-replacement: disabled
  mesh-auth-enabled: "true"
  mesh-auth-gc-interval: 5m0s
  mesh-auth-queue-size: "1024"
  mesh-auth-rotated-identities-queue-size: "1024"
  monitor-aggregation: medium
  monitor-aggregation-flags: all
  monitor-aggregation-interval: 5s
  node-port-bind-protection: "true"
  nodes-gc-interval: 5m0s
  operator-api-serve-addr: 127.0.0.1:9234
  operator-prometheus-serve-addr: :9963
  preallocate-bpf-maps: "false"
  procfs: /host/proc
  prometheus-serve-addr: :9962
  proxy-connect-timeout: "2"
  proxy-max-connection-duration-seconds: "0"
  proxy-max-requests-per-connection: "0"
  proxy-prometheus-port: "9964"
  remove-cilium-node-taints: "true"
  routing-mode: native
  set-cilium-is-up-condition: "true"
  set-cilium-node-taints: "true"
  sidecar-istio-proxy-image: cilium/istio_proxy
  skip-cnp-status-startup-clean: "false"
  synchronize-k8s-nodes: "true"
  tofqdns-dns-reject-response-code: refused
  tofqdns-enable-dns-compression: "true"
  tofqdns-endpoint-max-ip-per-hostname: "50"
  tofqdns-idle-connection-grace-period: 0s
  tofqdns-max-deferred-connection-deletes: "10000"
  tofqdns-proxy-response-max-delay: 100ms
  unmanaged-pod-watcher-interval: "15"
  update-ec2-adapter-limit-via-api: "true"
  vtep-cidr: ""
  vtep-endpoint: ""
  vtep-mac: ""
  vtep-mask: ""
  write-cni-conf-when-ready: /host/etc/cni/net.d/05-cilium.conflist
kind: ConfigMap
metadata:
  annotations:
    meta.helm.sh/release-name: cilium
    meta.helm.sh/release-namespace: cilium
  creationTimestamp: "2023-08-18T17:02:55Z"
  labels:
    app.kubernetes.io/managed-by: Helm
  name: cilium-config
  namespace: cilium
  resourceVersion: "5229"
  uid: 9d1392b8-6a3b-403c-81ce-500393eeb3e3
```

Here's a different way to run `cilium status` on a Kubernetes worker node:

```bash
kubectl exec -n cilium ds/cilium -- cilium status
```

```console
Defaulted container "cilium-agent" out of: cilium-agent, config (init), mount-cgroup (init), apply-sysctl-overwrites (init), mount-bpf-fs (init), clean-cilium-state (init), install-cni-binaries (init)
KVStore:                 Ok   Disabled
Kubernetes:              Ok   1.25+ (v1.25.12-eks-2d98532) [linux/amd64]
Kubernetes APIs:         ["EndpointSliceOrEndpoint", "cilium/v2::CiliumClusterwideNetworkPolicy", "cilium/v2::CiliumEndpoint", "cilium/v2::CiliumNetworkPolicy", "cilium/v2::CiliumNode", "cilium/v2alpha1::CiliumCIDRGroup", "core/v1::Namespace", "core/v1::Pods", "core/v1::Service", "networking.k8s.io/v1::NetworkPolicy"]
KubeProxyReplacement:    Disabled
Host firewall:           Disabled
CNI Chaining:            none
Cilium:                  Ok   1.14.0 (v1.14.0-b5013e15)
NodeMonitor:             Listening for events on 2 CPUs with 64x4096 of shared memory
Cilium health daemon:    Ok
IPAM:                    IPv4: 9/32 allocated,
IPv4 BIG TCP:            Disabled
IPv6 BIG TCP:            Disabled
BandwidthManager:        EDT with BPF [CUBIC] [eth0]
Host Routing:            Legacy
Masquerading:            IPTables [IPv4: Enabled, IPv6: Disabled]
Controller Status:       55/55 healthy
Proxy Status:            OK, ip 192.168.8.67, 0 redirects active on ports 10000-20000, Envoy: embedded
Global Identity Range:   min 256, max 65535
Hubble:                  Ok              Current/Max Flows: 4095/4095 (100.00%), Flows/s: 8.21   Metrics: Ok
Encryption:              Wireguard       [NodeEncryption: Disabled, cilium_wg0 (Pubkey: AxE7xXNN/Izr5ajkE48eSWtOH2WeQBTwhjS3Rma1tDo=, Port: 51871, Peers: 1)]
Cluster health:          2/2 reachable   (2023-08-18T17:53:44Z)
```

Useful details about Cilium networking can be found by listing the
`ciliumnodes` CRD:

```shell
kubectl describe ciliumnodes.cilium.io
```

```console
Name:         ip-192-168-19-152.ec2.internal
Namespace:
Labels:       alpha.eksctl.io/cluster-name=k01
              alpha.eksctl.io/nodegroup-name=mng01-ng
              beta.kubernetes.io/arch=arm64
              beta.kubernetes.io/instance-type=t4g.medium
              beta.kubernetes.io/os=linux
              eks.amazonaws.com/capacityType=ON_DEMAND
              eks.amazonaws.com/nodegroup=mng01-ng
              eks.amazonaws.com/nodegroup-image=ami-05d67a5609bec1651
              eks.amazonaws.com/sourceLaunchTemplateId=lt-077e09aaa2d4af922
              eks.amazonaws.com/sourceLaunchTemplateVersion=1
              failure-domain.beta.kubernetes.io/region=us-east-1
              failure-domain.beta.kubernetes.io/zone=us-east-1a
              k8s.io/cloud-provider-aws=4484beb1485b6869a3e7e4b77bb31f1f
              kubernetes.io/arch=arm64
              kubernetes.io/hostname=ip-192-168-19-152.ec2.internal
              kubernetes.io/os=linux
              node.kubernetes.io/instance-type=t4g.medium
              topology.ebs.csi.aws.com/zone=us-east-1a
              topology.kubernetes.io/region=us-east-1
              topology.kubernetes.io/zone=us-east-1a
              vpc.amazonaws.com/has-trunk-attached=false
Annotations:  network.cilium.io/wg-pub-key: lxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
API Version:  cilium.io/v2
Kind:         CiliumNode
Metadata:
  Creation Timestamp:  2023-08-18T17:03:10Z
  Generation:          6
  Owner References:
    API Version:     v1
    Kind:            Node
    Name:            ip-192-168-19-152.ec2.internal
    UID:             b956ae10-e866-4167-9ff1-7d6c889fed44
  Resource Version:  7677
  UID:               36fbc130-b9e7-46a8-a62b-b723c6dbb5a3
Spec:
  Addresses:
    Ip:    192.168.19.152
    Type:  InternalIP
    Ip:    54.147.78.10
    Type:  ExternalIP
    Ip:    192.168.13.220
    Type:  CiliumInternalIP
  Alibaba - Cloud:
  Azure:
  Encryption:
  Eni:
    Availability - Zone:            us-east-1a
    Disable - Prefix - Delegation:  false
    First - Interface - Index:      0
    Instance - Type:                t4g.medium
    Node - Subnet - Id:             subnet-0ac4e4f9d12641825
    Use - Primary - Address:        false
    Vpc - Id:                       vpc-0aaac805cdcd49be5
  Health:
    ipv4:  192.168.0.71
  Ingress:
  Instance - Id:  i-042bf8f0cee76e7f0
  Ipam:
    Pod CID Rs:
      10.152.0.0/16
    Pool:
      192.168.0.64:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.65:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.66:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.67:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.68:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.69:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.70:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.71:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.72:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.73:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.74:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.75:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.76:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.77:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.78:
        Resource:  eni-01d99349e4f322bf6
      192.168.0.79:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.208:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.209:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.210:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.211:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.212:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.213:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.214:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.215:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.216:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.217:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.218:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.219:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.220:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.221:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.222:
        Resource:  eni-01d99349e4f322bf6
      192.168.13.223:
        Resource:  eni-01d99349e4f322bf6
    Pools:
    Pre - Allocate:  8
Status:
  Alibaba - Cloud:
  Azure:
  Eni:
    Enis:
      eni-01d99349e4f322bf6:
        Addresses:
          192.168.13.208
          192.168.13.209
          192.168.13.210
          192.168.13.211
          192.168.13.212
          192.168.13.213
          192.168.13.214
          192.168.13.215
          192.168.13.216
          192.168.13.217
          192.168.13.218
          192.168.13.219
          192.168.13.220
          192.168.13.221
          192.168.13.222
          192.168.13.223
          192.168.0.64
          192.168.0.65
          192.168.0.66
          192.168.0.67
          192.168.0.68
          192.168.0.69
          192.168.0.70
          192.168.0.71
          192.168.0.72
          192.168.0.73
          192.168.0.74
          192.168.0.75
          192.168.0.76
          192.168.0.77
          192.168.0.78
          192.168.0.79
        Id:   eni-01d99349e4f322bf6
        Ip:   192.168.19.152
        Mac:  12:6d:a9:a9:74:f1
        Prefixes:
          192.168.13.208/28
          192.168.0.64/28
        Security - Groups:
          sg-0e72cf267ee2c8aa2
        Subnet:
          Cidr:  192.168.0.0/19
          Id:    subnet-0ac4e4f9d12641825
        Tags:
          cluster.k8s.amazonaws.com/name:      k01
          node.k8s.amazonaws.com/instance_id:  i-042bf8f0cee76e7f0
        Vpc:
          Id:              vpc-0aaac805cdcd49be5
          Primary - Cidr:  192.168.0.0/16
  Ipam:
    Operator - Status:
    Used:
      192.168.0.69:
        Owner:     oauth2-proxy/oauth2-proxy-7d5fd7948f-qvnhr
        Resource:  eni-01d99349e4f322bf6
      192.168.0.71:
        Owner:     health
        Resource:  eni-01d99349e4f322bf6
      192.168.0.73:
        Owner:     kube-prometheus-stack/kube-prometheus-stack-grafana-54dbcd857d-2hh4x [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.0.75:
        Owner:     cilium/hubble-relay-d44b99d7b-tllkk
        Resource:  eni-01d99349e4f322bf6
      192.168.0.76:
        Owner:     cilium/hubble-ui-869b75b895-cjs2w
        Resource:  eni-01d99349e4f322bf6
      192.168.0.77:
        Owner:     external-dns/external-dns-7fdb8769ff-srj48
        Resource:  eni-01d99349e4f322bf6
      192.168.13.211:
        Owner:     kube-prometheus-stack/kube-prometheus-stack-kube-state-metrics-78c9594f8f-22lgc [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.13.213:
        Owner:     aws-ebs-csi-driver/ebs-csi-node-svjd8 [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.13.215:
        Owner:     kube-system/coredns-7975d6fb9b-jzqv7 [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.13.217:
        Owner:     kube-system/coredns-7975d6fb9b-c5rfb [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.13.220:
        Owner:     router
        Resource:  eni-01d99349e4f322bf6
      192.168.13.222:
        Owner:     aws-ebs-csi-driver/ebs-csi-controller-7847774b66-b4lsl [restored]
        Resource:  eni-01d99349e4f322bf6
      192.168.13.223:
        Owner:     forecastle/forecastle-58d7ccb8f8-vw5ct
        Resource:  eni-01d99349e4f322bf6
Events:            <none>


Name:         ip-192-168-3-237.ec2.internal
Namespace:
Labels:       alpha.eksctl.io/cluster-name=k01
              alpha.eksctl.io/nodegroup-name=mng01-ng
              beta.kubernetes.io/arch=arm64
              beta.kubernetes.io/instance-type=t4g.medium
              beta.kubernetes.io/os=linux
              eks.amazonaws.com/capacityType=ON_DEMAND
              eks.amazonaws.com/nodegroup=mng01-ng
              eks.amazonaws.com/nodegroup-image=ami-05d67a5609bec1651
              eks.amazonaws.com/sourceLaunchTemplateId=lt-077e09aaa2d4af922
              eks.amazonaws.com/sourceLaunchTemplateVersion=1
              failure-domain.beta.kubernetes.io/region=us-east-1
              failure-domain.beta.kubernetes.io/zone=us-east-1a
              k8s.io/cloud-provider-aws=4484beb1485b6869a3e7e4b77bb31f1f
              kubernetes.io/arch=arm64
              kubernetes.io/hostname=ip-192-168-3-237.ec2.internal
              kubernetes.io/os=linux
              node.kubernetes.io/instance-type=t4g.medium
              topology.ebs.csi.aws.com/zone=us-east-1a
              topology.kubernetes.io/region=us-east-1
              topology.kubernetes.io/zone=us-east-1a
              vpc.amazonaws.com/has-trunk-attached=false
Annotations:  network.cilium.io/wg-pub-key: AxE7xXNN/Izr5ajkE48eSWtOH2WeQBTwhjS3Rma1tDo=
API Version:  cilium.io/v2
Kind:         CiliumNode
Metadata:
  Creation Timestamp:  2023-08-18T17:03:11Z
  Generation:          6
  Owner References:
    API Version:     v1
    Kind:            Node
    Name:            ip-192-168-3-237.ec2.internal
    UID:             d088d0dd-e531-4652-9a2b-fe6f80516f00
  Resource Version:  6220
  UID:               2e961861-ea2b-412b-820f-962a9db28b60
Spec:
  Addresses:
    Ip:    192.168.3.237
    Type:  InternalIP
    Ip:    18.208.178.29
    Type:  ExternalIP
    Ip:    192.168.8.67
    Type:  CiliumInternalIP
  Alibaba - Cloud:
  Azure:
  Encryption:
  Eni:
    Availability - Zone:            us-east-1a
    Disable - Prefix - Delegation:  false
    First - Interface - Index:      0
    Instance - Type:                t4g.medium
    Node - Subnet - Id:             subnet-0ac4e4f9d12641825
    Use - Primary - Address:        false
    Vpc - Id:                       vpc-0aaac805cdcd49be5
  Health:
    ipv4:  192.168.8.66
  Ingress:
  Instance - Id:  i-086acad17bd2d676b
  Ipam:
    Pod CID Rs:
      10.237.0.0/16
    Pool:
      192.168.30.32:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.33:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.34:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.35:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.36:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.37:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.38:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.39:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.40:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.41:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.42:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.43:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.44:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.45:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.46:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.30.47:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.64:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.65:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.66:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.67:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.68:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.69:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.70:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.71:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.72:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.73:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.74:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.75:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.76:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.77:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.78:
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.79:
        Resource:  eni-0f47ee6b88bd0143b
    Pools:
    Pre - Allocate:  8
Status:
  Alibaba - Cloud:
  Azure:
  Eni:
    Enis:
      eni-0f47ee6b88bd0143b:
        Addresses:
          192.168.8.64
          192.168.8.65
          192.168.8.66
          192.168.8.67
          192.168.8.68
          192.168.8.69
          192.168.8.70
          192.168.8.71
          192.168.8.72
          192.168.8.73
          192.168.8.74
          192.168.8.75
          192.168.8.76
          192.168.8.77
          192.168.8.78
          192.168.8.79
          192.168.30.32
          192.168.30.33
          192.168.30.34
          192.168.30.35
          192.168.30.36
          192.168.30.37
          192.168.30.38
          192.168.30.39
          192.168.30.40
          192.168.30.41
          192.168.30.42
          192.168.30.43
          192.168.30.44
          192.168.30.45
          192.168.30.46
          192.168.30.47
        Id:   eni-0f47ee6b88bd0143b
        Ip:   192.168.3.237
        Mac:  12:e1:d7:9d:e6:59
        Prefixes:
          192.168.8.64/28
          192.168.30.32/28
        Security - Groups:
          sg-0e72cf267ee2c8aa2
        Subnet:
          Cidr:  192.168.0.0/19
          Id:    subnet-0ac4e4f9d12641825
        Tags:
          cluster.k8s.amazonaws.com/name:      k01
          node.k8s.amazonaws.com/instance_id:  i-086acad17bd2d676b
        Vpc:
          Id:              vpc-0aaac805cdcd49be5
          Primary - Cidr:  192.168.0.0/16
  Ipam:
    Operator - Status:
    Used:
      192.168.8.64:
        Owner:     aws-ebs-csi-driver/ebs-csi-controller-7847774b66-nrlf4 [restored]
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.66:
        Owner:     health
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.67:
        Owner:     router
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.68:
        Owner:     snapshot-controller/snapshot-controller-8658dd5c86-z2z6q [restored]
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.69:
        Owner:     cert-manager/cert-manager-859997c796-j9hh8
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.70:
        Owner:     cert-manager/cert-manager-cainjector-7bb8cb69c5-2q6fk
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.72:
        Owner:     mailhog/mailhog-6f54fccf85-pdb9k [restored]
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.73:
        Owner:     aws-ebs-csi-driver/ebs-csi-node-n8vrn [restored]
        Resource:  eni-0f47ee6b88bd0143b
      192.168.8.78:
        Owner:     kube-prometheus-stack/alertmanager-kube-prometheus-stack-alertmanager-0 [restored]
        Resource:  eni-0f47ee6b88bd0143b
Events:            <none>
```

This command helps find exposed ports (HostNetwork) to check for port
collisions:

```shell
kubectl get endpoints -A -o json | jq '.items[] | (.metadata.name , .subsets[].addresses[].ip, .subsets[].addresses[].nodeName, .subsets[].addresses[].targetRef.name, .subsets[].ports[])'
kubectl get pods -A -o json | jq ".items[] | select (.spec.hostNetwork==true) .spec.containers[].name, .metadata.name, .spec.containers[].ports[0]"
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
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-kms"
```

Wait for all CloudFormation stacks to complete deletion:

```sh
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53-kms"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove Volumes and Snapshots related to the cluster (as a precaution):

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text); do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done
```

Remove the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
if [[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]]; then
  for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{kubeconfig-${CLUSTER_NAME}.conf,{aws-cf-route53-kms,eksctl-${CLUSTER_NAME},k8s-karpenter-provisioner,helm_values-{aws-ebs-csi-driver,aws-for-fluent-bit,cert-manager,cilium,external-dns,forecastle,ingress-nginx,karpenter,kube-prometheus-stack,mailhog,oauth2-proxy},k8s-cert-manager-{certificate,clusterissuer}-staging}.yml}; do
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
