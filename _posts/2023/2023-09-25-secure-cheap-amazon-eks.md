---
title: Build secure and cheap Amazon EKS
author: Petr Ruzicka
date: 2023-09-25
description: Build "cheap and secure" Amazon EKS with network policies, cluster encryption and logging
categories: [Kubernetes, Amazon EKS, Security]
tags:
  [
    Amazon EKS,
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

I will outline the steps for setting up an [Amazon EKS](https://aws.amazon.com/eks/)
environment that is cost-effective while prioritizing security, and include
standard applications in the configuration.

Amazon EKS should align with these cost-effective criteria:

- Two AZ, use one zone if possible (less payments for cross AZ traffic)
- Spot instances
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type `t4g.medium` (2 x CPU, 4GB RAM) using
  [AWS Graviton](https://aws.amazon.com/ec2/graviton/) based on ARM
- Use [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) -
  minimal operation system / CPU / Memory footprint
- Use [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  as a most cost efficient + cost optimized load balancer
- [Karpenter](https://karpenter.sh/) - enables automatic node scaling to match
  the specific resource requirements of pods

Amazon EKS should meet the following security requirements:

- Amazon EKS must be [encrypted by KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes needs to be encrypted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- Cluster logging ([CloudWatch](https://aws.amazon.com/cloudwatch/)) needs to be
  configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
  should be enabled wherever they are supported

## Build Amazon EKS cluster

### Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables like:

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

Confirm whether all essential variables have been properly configured:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
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

### Create Route53 zone and KMS key

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

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-kms")
AWS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
AWS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
```

After running the CF stack you should see the following Route53 zones:

![Route53 k01.k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k01.k8s.mylabs.dev.avif)
_Route53 k01.k8s.mylabs.dev zone_

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedones-k8s.mylabs.dev-2.avif)
_Route53 k8s.mylabs.dev zone_

You should see the following KMS key:

![KMS key](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key.avif)
_KMS key_

## Create Amazon EKS

I'm going to use [eksctl](https://eksctl.io/) to create the [Amazon EKS](https://aws.amazon.com/eks/)
cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png){:width="700"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" << EOF
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
  version: v0.35.0
  createServiceAccount: true
  withSpotInterruptionQueue: true
addons:
  - name: vpc-cni
    version: latest
    configurationValues: |-
      enableNetworkPolicy: "true"
      env:
        ENABLE_PREFIX_DELEGATION: "true"
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
    maxPodsPerNode: 110
    privateNetworking: true
    bottlerocket:
      settings:
        kubernetes:
          seccomp-default: true
secretsEncryption:
  keyARN: ${AWS_KMS_KEY_ARN}
cloudWatch:
  clusterLogging:
    logRetentionInDays: 1
    enableTypes:
      - all
EOF
```

Get the kubeconfig to access the cluster:

```bash
if [[ ! -s "${KUBECONFIG}" ]]; then
  if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null; then
    eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" --kubeconfig "${KUBECONFIG}"
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

The command "sed" used earlier modified the aws-cf-route53-kms.yml file by
incorporating newly established IAM roles (`eksctl-k01-irsa-aws-ebs-csi-driver`
and `eksctl-k01-iamservice-role`), enabling them to utilize the KMS key.

![KMS key with new IAM roles](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key-2.avif)
_KMS key with new IAM roles_

```bash
AWS_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=${CLUSTER_NAME}" --query 'Vpcs[*].VpcId' --output text)
AWS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${AWS_VPC_ID}" "Name=group-name,Values=default" --query 'SecurityGroups[*].GroupId' --output text)
AWS_NACL_ID=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=${AWS_VPC_ID}" --query 'NetworkAcls[*].NetworkAclId' --output text)
```

Enhance the security stance of the EKS cluster by addressing the following concerns:

- Default security group should have no rules configured:

  ```bash
  aws ec2 revoke-security-group-egress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --cidr 0.0.0.0/0 | jq || true
  aws ec2 revoke-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --source-group "${AWS_SECURITY_GROUP_ID}" | jq || true
  ```

- VPC NACL allows unrestricted SSH access + VPC NACL allows unrestricted RDP access:

  ```bash
  aws ec2 create-network-acl-entry --network-acl-id "${AWS_NACL_ID}" --ingress --rule-number 1 --protocol tcp --port-range "From=22,To=22" --cidr-block 0.0.0.0/0 --rule-action Deny
  aws ec2 create-network-acl-entry --network-acl-id "${AWS_NACL_ID}" --ingress --rule-number 2 --protocol tcp --port-range "From=3389,To=3389" --cidr-block 0.0.0.0/0 --rule-action Deny
  ```

- Namespace does not have PSS level assigned:

  ```bash
  kubectl label namespace default pod-security.kubernetes.io/enforce=baseline
  ```

### Karpenter

[Karpenter](https://karpenter.sh/) is a Kubernetes Node Autoscaler built
for flexibility, performance, and simplicity.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png){:width="500"}

Configure [Karpenter](https://karpenter.sh/):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-karpenter-provisioner.yml" << EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  consolidation:
    enabled: true
  # https://karpenter.sh/preview/concepts/provisioners/#cilium-startup-taint
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

### snapshot-controller

Install Volume Snapshot Custom Resource Definitions (CRDs):

```bash
kubectl apply --kustomize https://github.com/kubernetes-csi/external-snapshotter.git/client/config/crd/
```

![CSI](https://raw.githubusercontent.com/cncf/artwork/d8ed92555f9aae960ebd04788b788b8e8d65b9f6/other/csi/horizontal/color/csi-horizontal-color.svg){:width="500"}

Install volume snapshot controller `snapshot-controller`
[helm chart](https://github.com/piraeusdatastore/helm-charts/tree/main/charts/snapshot-controller)
and modify the
[default values](https://github.com/piraeusdatastore/helm-charts/blob/main/charts/snapshot-controller/values.yaml):

```bash
# renovate: datasource=helm depName=snapshot-controller registryUrl=https://piraeus.io/helm-charts/
SNAPSHOT_CONTROLLER_HELM_CHART_VERSION="2.2.0"

helm repo add piraeus-charts https://piraeus.io/helm-charts/
helm upgrade --install --version "${SNAPSHOT_CONTROLLER_HELM_CHART_VERSION}" --namespace snapshot-controller --create-namespace snapshot-controller piraeus-charts/snapshot-controller
kubectl label namespace snapshot-controller pod-security.kubernetes.io/enforce=baseline
```

### aws-ebs-csi-driver

The [Amazon Elastic Block Store](https://aws.amazon.com/ebs/) Container Storage
Interface (CSI) Driver provides a [CSI](https://github.com/container-storage-interface/spec/blob/master/spec.md)
interface used by Container Orchestrators to manage the lifecycle of Amazon EBS
volumes.

Install Amazon EBS CSI Driver `aws-ebs-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/tree/master/charts/aws-ebs-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/charts/aws-ebs-csi-driver/values.yaml).
(The ServiceAccount `ebs-csi-controller-sa` was created by `eksctl`)

```bash
# renovate: datasource=helm depName=aws-ebs-csi-driver registryUrl=https://kubernetes-sigs.github.io/aws-ebs-csi-driver
AWS_EBS_CSI_DRIVER_HELM_CHART_VERSION="2.28.1"

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
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

Delete `gp2` StorageClass, because the `gp3` will be used instead:

```bash
kubectl delete storageclass gp2 || true
```

### aws-node-termination-handler

[AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler)
gracefully handle EC2 instance shutdown within Kubernetes.

Install `aws-node-termination-handler`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-node-termination-handler)
and modify the
[default values](https://github.com/aws/aws-node-termination-handler/blob/main/config/helm/aws-node-termination-handler/values.yaml):

```bash
# renovate: datasource=helm depName=aws-node-termination-handler registryUrl=https://aws.github.io/eks-charts
AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION="0.21.0"

helm repo add eks https://aws.github.io/eks-charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" << EOF
awsRegion: ${AWS_DEFAULT_REGION}
EOF
helm upgrade --install --version "${AWS_NODE_TERMINATION_HANDLER_HELM_CHART_VERSION}" --namespace kube-system --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-node-termination-handler.yml" aws-node-termination-handler eks/aws-node-termination-handler
```

### mailpit

Mailpit will be used to receive email alerts from the Prometheus.

![mailpit](https://raw.githubusercontent.com/sj26/mailcatcher/main/assets/images/logo_large.png){:width="200"}

Install `mailpit`
[helm chart](https://artifacthub.io/packages/helm/jouve/mailpit)
and modify the
[default values](https://github.com/jouve/charts/blob/main/charts/mailpit/values.yaml).

```bash
# renovate: datasource=helm depName=mailpit registryUrl=https://jouve.github.io/charts/
MAILPIT_HELM_CHART_VERSION="0.13.2"

helm repo add jouve https://jouve.github.io/charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" << EOF
ingress:
  enabled: true
  annotations:
    forecastle.stakater.com/expose: "true"
    forecastle.stakater.com/icon: https://raw.githubusercontent.com/sj26/mailcatcher/main/assets/images/logo_large.png
    forecastle.stakater.com/appName: Mailpit
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  ingressClassName: nginx
  hostname: mailpit.${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${MAILPIT_HELM_CHART_VERSION}" --namespace mailpit --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" mailpit jouve/mailpit
kubectl label namespace mailpit pod-security.kubernetes.io/enforce=baseline
```

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

![Prometheus](https://raw.githubusercontent.com/cncf/artwork/40e2e8948509b40e4bad479446aaec18d6273bf2/projects/prometheus/horizontal/color/prometheus-horizontal-color.svg){:width="500"}

Install `kube-prometheus-stack`
[helm chart](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
and modify the
[default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml):

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="56.19.0"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" << EOF
defaultRules:
  rules:
    etcd: false
    kubernetesSystem: false
    kubeScheduler: false
alertmanager:
  config:
    global:
      smtp_smarthost: "mailpit-smtp.mailpit.svc.cluster.local:25"
      smtp_from: "alertmanager@${CLUSTER_FQDN}"
    route:
      group_by: ["alertname", "job"]
      receiver: email
      routes:
        - receiver: 'null'
          matchers:
            - alertname =~ "InfoInhibitor|Watchdog"
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
        gnetId: 35038
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
        gnetId: 16761
        revision: 16
        datasource: Prometheus
      15762-kubernetes-system-coredns:
        # renovate: depName="Kubernetes / System / CoreDNS"
        gnetId: 15762
        revision: 17
        datasource: Prometheus
      19105-prometheus:
        # renovate: depName="Prometheus"
        gnetId: 29205
        revision: 2
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
    host: "mailpit-smtp.mailpit.svc.cluster.local:25"
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
  selfMonitor:
    enabled: true
prometheus-node-exporter:
  networkPolicy:
    enabled: true
prometheusOperator:
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
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

### karpenter

[Karpenter](https://karpenter.sh/) automatically launches just the right compute
resources to handle your cluster's applications.

Change [karpenter](https://karpenter.sh/) default installation by upgrading:
[helm chart](https://artifacthub.io/packages/helm/oci-karpenter/karpenter)
and modify the
[default values](https://github.com/aws/karpenter/blob/main/charts/karpenter/values.yaml).

```bash
# renovate: datasource=github-tags depName=aws/karpenter extractVersion=^(?<version>.*)$
KARPENTER_HELM_CHART_VERSION="v0.35.0"

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
kubectl label namespace karpenter pod-security.kubernetes.io/enforce=baseline
```

### aws-for-fluent-bit

[Fluent Bit](https://fluentbit.io/) is an open source Log Processor and
Forwarder which allows you to collect any data like metrics and logs from
different sources, enrich them with filters and send them to multiple
destinations.

Install `aws-for-fluent-bit`
[helm chart](https://artifacthub.io/packages/helm/aws/aws-for-fluent-bit)
and modify the
[default values](https://github.com/aws/eks-charts/blob/master/stable/aws-for-fluent-bit/values.yaml):

```bash
# renovate: datasource=helm depName=aws-for-fluent-bit registryUrl=https://aws.github.io/eks-charts
AWS_FOR_FLUENT_BIT_HELM_CHART_VERSION="0.1.32"

tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-for-fluent-bit.yml" << EOF
cloudWatchLogs:
  region: ${AWS_DEFAULT_REGION}
  logGroupTemplate: "/aws/eks/${CLUSTER_NAME}/cluster"
  logStreamTemplate: "\$kubernetes['namespace_name'].\$kubernetes['pod_name']"
serviceAccount:
  create: false
  name: aws-for-fluent-bit
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
issuers as resource types in Kubernetes clusters, and simplifies the process
of obtaining, renewing and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="200"}

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify the
[default values](https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.14.3"

helm repo add jetstack https://charts.jetstack.io
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
kubectl label namespace cert-manager pod-security.kubernetes.io/enforce=baseline
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

### metrics-server

[Metrics Server](https://github.com/kubernetes-sigs/metrics-server) is
a scalable, efficient source of container resource metrics for Kubernetes
built-in autoscaling pipelines.

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/metrics-server/metrics-server)
and modify the
[default values](https://github.com/kubernetes-sigs/metrics-server/blob/master/charts/metrics-server/values.yaml):

```bash
# renovate: datasource=helm depName=metrics-server registryUrl=https://kubernetes-sigs.github.io/metrics-server/
METRICS_SERVER_HELM_CHART_VERSION="3.12.0"

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-metrics-server.yml" << EOF
metrics:
  enabled: true
serviceMonitor:
  enabled: true
EOF
helm upgrade --install --version "${METRICS_SERVER_HELM_CHART_VERSION}" --namespace kube-system --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-metrics-server.yml" metrics-server metrics-server/metrics-server
```

### external-dns

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns) synchronizes
exposed Kubernetes Services and Ingresses with DNS providers.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="300"}

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and modify the
[default values](https://github.com/kubernetes-sigs/external-dns/blob/master/charts/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.14.3"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
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
kubectl label namespace external-dns pod-security.kubernetes.io/enforce=baseline
```

### ingress-nginx

[ingress-nginx](https://kubernetes.github.io/ingress-nginx/) is an Ingress
controller for Kubernetes using [NGINX](https://www.nginx.org/) as a reverse
proxy and load balancer.

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.10.0"

kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-staging

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
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
kubectl label namespace ingress-nginx pod-security.kubernetes.io/enforce=baseline
```

### forecastle

[Forecastle](https://github.com/stakater/Forecastle) is a control panel which
dynamically discovers and provides a launchpad to access applications deployed
on Kubernetes.

![Forecastle](https://raw.githubusercontent.com/stakater/Forecastle/c70cc130b5665be2649d00101670533bba66df0c/frontend/public/logo512.png){:width="200"}

Install `forecastle`
[helm chart](https://artifacthub.io/packages/helm/stakater/forecastle)
and modify the
[default values](https://github.com/stakater/Forecastle/blob/master/deployments/kubernetes/chart/forecastle/values.yaml).

```bash
# renovate: datasource=helm depName=forecastle registryUrl=https://stakater.github.io/stakater-charts
FORECASTLE_HELM_CHART_VERSION="1.0.137"

helm repo add stakater https://stakater.github.io/stakater-charts
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
kubectl label namespace forecastle pod-security.kubernetes.io/enforce=baseline
```

### oauth2-proxy

Use [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect
the endpoints by Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg){:width="400"}

Install `oauth2-proxy`
[helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify the
[default values](https://github.com/oauth2-proxy/manifests/blob/main/helm/oauth2-proxy/values.yaml).

```bash
# renovate: datasource=helm depName=oauth2-proxy registryUrl=https://oauth2-proxy.github.io/manifests
OAUTH2_PROXY_HELM_CHART_VERSION="6.24.2"

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
kubectl label namespace oauth2-proxy pod-security.kubernetes.io/enforce=baseline
```

### Enforce Pod Security Standards with Namespace Labels

Label all namespaces to warn when going against the Pod Security Standards:

```bash
kubectl label namespace --all pod-security.kubernetes.io/warn=baseline
```

Details can be found in: [Enforce Pod Security Standards with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)

## Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg){:width="400"}

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

Remove orphan EC2s created by Karpenter:

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text) ; do
  echo "Removing EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Remove CloudWatch log group:

```sh
aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
```

Remove CloudFormation stack:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-kms"
```

Wait for all CloudFormation stacks to be deleted:

```sh
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

Remove `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
[[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]] && rm -rvf "${TMP_DIR}/${CLUSTER_FQDN}" && [[ -d "${TMP_DIR}" ]] && rmdir -v "${TMP_DIR}" || true
```

Enjoy ... 😉
