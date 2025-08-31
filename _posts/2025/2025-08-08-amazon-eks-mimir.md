---
title: Amazon EKS and Grafana Mimir
author: Petr Ruzicka
date: 2025-08-08
description: Build secure Amazon EKS cluster with Grafana Mimir
categories: [Kubernetes, Amazon EKS, Security, Mimir]
tags:
  [
    amazon eks,
    k8s,
    kubernetes,
    security,
    eksctl,
    cert-manager,
    external-dns,
    prometheus,
    sso,
    oauth2-proxy,
    mimir,
  ]
image: https://raw.githubusercontent.com/grafana/mimir/843897414dba909dfd44f5b93dad35a8a6694d06/images/logo.png
---

I will outline the steps for setting up an [Amazon EKS](https://aws.amazon.com/eks/)
environment that prioritizes security, including the configuration of standard
applications.

The Amazon EKS setup should align with the following criteria:

- Utilize two Availability Zones (AZs), or a single zone if possible, to reduce
  payments for cross-AZ traffic
- Spot instances
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type `t4g.medium` (2 x CPU, 4GB RAM) using
  [AWS Graviton](https://aws.amazon.com/ec2/graviton/) based on ARM
- Use [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) for a
  minimal operating system, CPU, and memory footprint
- Leverage [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  for highly cost-effective and optimized load balancing, seamlessly integrated
  with [kgateway](https://kgateway.dev/).
- [Karpenter](https://karpenter.sh/) to enable automatic node scaling that
  matches the specific resource requirements of pods
- The Amazon EKS control plane must be [encrypted using KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes must be encrypted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- Cluster logging to [CloudWatch](https://aws.amazon.com/cloudwatch/) must be
  configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
  should be enabled where supported
- [EKS Pod Identities](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
  should be used to allow applications and pods to communicate with AWS APIs

## Build Amazon EKS

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
export AWS_REGION="${AWS_REGION:-us-east-1}"
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
export AWS_PARTITION="aws"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) && export AWS_ACCOUNT_ID
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

Confirm that all essential variables have been properly configured:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_ROLE_TO_ASSUME?}"
: "${GOOGLE_CLIENT_ID?}"
: "${GOOGLE_CLIENT_SECRET?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Install the required tools:

<!-- prettier-ignore-start -->
> You can bypass these procedures if you already have all the essential software
> installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)
- [helm](https://github.com/helm/helm)

## Configure AWS Route 53 Domain delegation

<!-- prettier-ignore-start -->
> The DNS delegation tasks should be executed as a one-time operation.
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

Utilize your domain registrar to update the nameservers for your zone (e.g.,
`mylabs.dev`) to point to Amazon Route 53 nameservers. Here's how to discover
the required Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Establish the NS record in `k8s.mylabs.dev` (your `BASE_DOMAIN`) for proper zone
delegation. This operation's specifics may vary based on your domain
registrar; I use Cloudflare and employ Ansible for automation:

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
> Creating the service-linked role for Spot Instances is a one-time operation.
{: .prompt-info }
<!-- prettier-ignore-end -->

Create the `AWSServiceRoleForEC2Spot` role to use Spot Instances in the Amazon
EKS cluster:

```shell
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

Details: [Work with Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html)

## Create Route53 zone and KMS key infrastructure

Generate a CloudFormation template that defines an [Amazon Route 53](https://aws.amazon.com/route53/)
zone and an [AWS Key Management Service (KMS)](https://aws.amazon.com/kms/) key.

Add the new domain `CLUSTER_FQDN` to Route 53, and set up DNS delegation from
the `BASE_DOMAIN`.

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

## Create Karpenter infrastructure

Use CloudFormation to set up the infrastructure needed by the EKS cluster.
See [CloudFormation](https://karpenter.sh/docs/reference/cloudformation/) for
a complete description of what `cloudformation.yaml` does for Karpenter.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png){:width="400"}

```bash
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/7370b5fd22eb6bec88f7799562b6cb24ac8fbb46/website/content/en/v1.6/getting-started/getting-started-with-karpenter/cloudformation.yaml > "${TMP_DIR}/${CLUSTER_FQDN}/cloudformation-karpenter.yml"
eval aws cloudformation deploy \
  --stack-name "${CLUSTER_NAME}-karpenter" \
  --template-file "${TMP_DIR}/${CLUSTER_FQDN}/cloudformation-karpenter.yml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" --tags "${TAGS//,/ }"
```

## Create Amazon EKS

I will use [eksctl](https://eksctl.io/) to create the [Amazon EKS](https://aws.amazon.com/eks/)
cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png){:width="700"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
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
  withOIDC: true
  podIdentityAssociations:
    # - namespace: aws-ebs-csi-driver
    #   serviceAccountName: ebs-csi-controller-sa
    #   roleName: eksctl-${CLUSTER_NAME}-aws-ebs-csi-driver
    #   wellKnownPolicies:
    #     ebsCSIController: true
    - namespace: aws-load-balancer-controller
      serviceAccountName: aws-load-balancer-controller
      roleName: eksctl-${CLUSTER_NAME}-aws-load-balancer-controller
      wellKnownPolicies:
        awsLoadBalancerController: true
    - namespace: cert-manager
      serviceAccountName: cert-manager
      roleName: eksctl-${CLUSTER_NAME}-cert-manager
      wellKnownPolicies:
        certManager: true
    - namespace: external-dns
      serviceAccountName: external-dns
      roleName: eksctl-${CLUSTER_NAME}-external-dns
      wellKnownPolicies:
        externalDNS: true
    - namespace: karpenter
      serviceAccountName: karpenter
      roleName: eksctl-${CLUSTER_NAME}-karpenter
      permissionPolicyARNs:
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}
    - namespace: mimir
      serviceAccountName: mimir
      roleName: eksctl-${CLUSTER_NAME}-mimir
      permissionPolicy:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Action: [
              "ec2:DescribeVolumes",
              "ec2:DescribeSnapshots",
              "ec2:CreateTags",
              "ec2:CreateSnapshot",
              "ec2:DeleteSnapshots"
            ]
            Resource:
              - "*"
          - Effect: Allow
            Action: [
              "s3:GetObject",
              "s3:DeleteObject",
              "s3:PutObject",
              "s3:PutObjectTagging",
              "s3:AbortMultipartUpload",
              "s3:ListMultipartUploadParts"
            ]
            Resource:
              - "arn:aws:s3:::${CLUSTER_FQDN}/*"
          - Effect: Allow
            Action: [
              "s3:ListBucket",
            ]
            Resource:
              - "arn:aws:s3:::${CLUSTER_FQDN}"
    - namespace: velero
      serviceAccountName: velero
      roleName: eksctl-${CLUSTER_NAME}-velero
      permissionPolicy:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Action: [
              "ec2:DescribeVolumes",
              "ec2:DescribeSnapshots",
              "ec2:CreateTags",
              "ec2:CreateSnapshot",
              "ec2:DeleteSnapshots"
            ]
            Resource:
              - "*"
          - Effect: Allow
            Action: [
              "s3:GetObject",
              "s3:DeleteObject",
              "s3:PutObject",
              "s3:PutObjectTagging",
              "s3:AbortMultipartUpload",
              "s3:ListMultipartUploadParts"
            ]
            Resource:
              - "arn:aws:s3:::${CLUSTER_FQDN}/*"
          - Effect: Allow
            Action: [
              "s3:ListBucket",
            ]
            Resource:
              - "arn:aws:s3:::${CLUSTER_FQDN}"
iamIdentityMappings:
  - arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
addons:
  - name: coredns
    # configurationValues: |
    #   replicaCount: 2
    #   affinity:
    #     podAntiAffinity:
    #       requiredDuringSchedulingIgnoredDuringExecution:
    #         - labelSelector:
    #             matchExpressions:
    #               - key: eks.amazonaws.com/component
    #                 operator: In
    #                 values:
    #                   - coredns
    #           topologyKey: "topology.kubernetes.io/zone"
  - name: eks-pod-identity-agent
  - name: kube-proxy
  - name: snapshot-controller
  - name: aws-ebs-csi-driver
    configurationValues: |-
      defaultStorageClass:
        enabled: true
      controller:
        extraVolumeTags:
          $(echo "${TAGS}" | sed "s/,/\\n          /g; s/=/: /g")
        loggingFormat: json
  - name: vpc-cni
    version: latest
    configurationValues: |-
      enableNetworkPolicy: "true"
      env:
        ENABLE_PREFIX_DELEGATION: "true"
managedNodeGroups:
  - name: mng01-ng
    amiFamily: Bottlerocket
    # Minimal instance type for running add-ons + karpenter - ARM t4g.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    # Minimal instance type for running add-ons + karpenter - X86 t3a.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    instanceType: t4g.medium
    # Due to karpenter we need 2 instances
    desiredCapacity: 2
    availabilityZones:
      - ${AWS_REGION}a
    minSize: 2
    maxSize: 3
    volumeSize: 20
    volumeEncrypted: true
    volumeKmsKeyID: ${AWS_KMS_KEY_ID}
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
eksctl create cluster --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yml" --kubeconfig "${KUBECONFIG}" || eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
```

Enhance the security posture of the EKS cluster by addressing the following
concerns:

```bash
AWS_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=${CLUSTER_NAME}" --query 'Vpcs[*].VpcId' --output text)
AWS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${AWS_VPC_ID}" "Name=group-name,Values=default" --query 'SecurityGroups[*].GroupId' --output text)
AWS_NACL_ID=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=${AWS_VPC_ID}" --query 'NetworkAcls[*].NetworkAclId' --output text)
```

- The default security group should have no rules configured:

  ```bash
  aws ec2 revoke-security-group-egress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --cidr 0.0.0.0/0 | jq || true
  aws ec2 revoke-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" --protocol all --port all --source-group "${AWS_SECURITY_GROUP_ID}" | jq || true
  ```

- The VPC NACL allows unrestricted SSH access, and the VPC NACL allows
  unrestricted RDP access:

  ```bash
  aws ec2 create-network-acl-entry --network-acl-id "${AWS_NACL_ID}" --ingress --rule-number 1 --protocol tcp --port-range "From=22,To=22" --cidr-block 0.0.0.0/0 --rule-action Deny
  aws ec2 create-network-acl-entry --network-acl-id "${AWS_NACL_ID}" --ingress --rule-number 2 --protocol tcp --port-range "From=3389,To=3389" --cidr-block 0.0.0.0/0 --rule-action Deny
  ```

- The VPC should have Route 53 DNS resolver with logging enabled:

  ```bash
  AWS_CLUSTER_LOG_GROUP_ARN=$(aws logs describe-log-groups --query "logGroups[?logGroupName=='/aws/eks/${CLUSTER_NAME}/cluster'].arn" --output text)
  AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID=$(aws route53resolver create-resolver-query-log-config \
    --name "${CLUSTER_NAME}-vpc-dns-logs" \
    --destination-arn "${AWS_CLUSTER_LOG_GROUP_ARN}" \
    --creator-request-id "$(uuidgen)" --query 'ResolverQueryLogConfig.Id' --output text)

  aws route53resolver associate-resolver-query-log-config \
    --resolver-query-log-config-id "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}" \
    --resource-id "${AWS_VPC_ID}"
  ```

### Add Storage Classes and Volume Snapshots

Configure persistent storage for your EKS cluster by setting up GP3 storage
classes and volume snapshot capabilities. This ensures encrypted, expandable
storage with proper backup functionality.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-storageclass-volumesnapshotclass.yml" << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: ${AWS_KMS_KEY_ARN}
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-vsc
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF
```

Delete the `gp2` StorageClass, as `gp3` will be used instead:

```bash
kubectl delete storageclass gp2 || true
```

### Karpenter

[Karpenter](https://karpenter.sh/) is a Kubernetes node autoscaler built for
flexibility, performance, and simplicity.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter-provider-aws/41b115a0b85677641e387635496176c4cc30d4c6/website/static/full_logo.svg){:width="500"}

Install the `karpenter` [Helm chart](https://github.com/aws/karpenter-provider-aws/tree/main/charts/karpenter)
and customize its [default values](https://github.com/aws/karpenter-provider-aws/blob/v1.6.2/charts/karpenter/values.yaml)
to fit your environment and storage backend:

```bash
KARPENTER_HELM_CHART_VERSION="1.6.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" << EOF
settings:
  clusterName: ${CLUSTER_NAME}
  eksControlPlane: true
  interruptionQueue: ${CLUSTER_NAME}
  featureGates:
    spotToSpotConsolidation: true
EOF
helm upgrade --install --version "${KARPENTER_HELM_CHART_VERSION}" --namespace karpenter --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-karpenter.yml" karpenter oci://public.ecr.aws/karpenter/karpenter
```

Configure [Karpenter](https://karpenter.sh/) by applying the following
provisioner definition:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-karpenter-nodepool.yml" << EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Bottlerocket
  amiSelectorTerms:
    - alias: bottlerocket@latest
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  tags:
    Name: "${CLUSTER_NAME}-karpenter"
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
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
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        # keep-sorted start
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["${AWS_DEFAULT_REGION}a"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t4g", "t3a"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64", "amd64"]
        # keep-sorted end
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
EOF
```

### AWS Load Balancer Controller

The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
is a controller that manages Elastic Load Balancers for a Kubernetes cluster.

![AWS Load Balancer Controller](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/05071ecd0f2c240c7e6b815c0fdf731df799005a/docs/assets/images/aws_load_balancer_icon.svg){:width="150"}

Install the `aws-load-balancer-controller` [Helm chart](https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/main/helm/aws-load-balancer-controller)
and modify its [default values](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v2.13.4/helm/aws-load-balancer-controller/values.yaml):

```bash
# renovate: datasource=helm depName=aws-load-balancer-controller registryUrl=https://aws.github.io/eks-charts
AWS_LOAD_BALANCER_CONTROLLER_HELM_CHART_VERSION="1.13.4"

helm repo add --force-update eks https://aws.github.io/eks-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-load-balancer-controller.yml" << EOF
serviceAccount:
  name: aws-load-balancer-controller
clusterName: ${CLUSTER_NAME}
EOF
helm upgrade --install --version "${AWS_LOAD_BALANCER_CONTROLLER_HELM_CHART_VERSION}" --namespace aws-load-balancer-controller --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-aws-load-balancer-controller.yml" aws-load-balancer-controller eks/aws-load-balancer-controller
```

### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters and simplifies the process of
obtaining, renewing, and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="150"}

The `cert-manager` ServiceAccount was created by `eksctl`.
Install the `cert-manager` [Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify its [default values](https://github.com/cert-manager/cert-manager/blob/v1.18.2/deploy/charts/cert-manager/values.yaml):

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.18.2"

helm repo add --force-update jetstack https://charts.jetstack.io
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" << EOF
crds:
  enabled: true
serviceAccount:
  name: cert-manager
enableCertificateOwnerRef: true
# prometheus:
#   servicemonitor:
#     enabled: true
EOF
helm upgrade --install --version "${CERT_MANAGER_HELM_CHART_VERSION}" --namespace cert-manager --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-cert-manager.yml" cert-manager jetstack/cert-manager
```

Create a Let's Encrypt production `ClusterIssuer`:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-cert-manager-clusterissuer-production.yml" << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns
  namespace: cert-manager
  labels:
    letsencrypt: production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-production-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53: {}
EOF
kubectl wait --namespace cert-manager --timeout=15m --for=condition=Ready clusterissuer --all
kubectl label secret --namespace cert-manager letsencrypt-production-dns letsencrypt=production
```

## Install Velero

Velero is an open-source tool for backing up and restoring Kubernetes cluster
resources and persistent volumes. It enables disaster recovery, data migration,
and scheduled backups by integrating with cloud storage providers such as AWS S3.

![velero](https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/heroes/velero.svg){:width="600"}

Install the `velero` [Helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify its [default values](https://github.com/vmware-tanzu/helm-charts/blob/velero-8.3.0/charts/velero/values.yaml):

{% raw %}

```bash
# renovate: datasource=helm depName=velero registryUrl=https://vmware-tanzu.github.io/helm-charts
VELERO_HELM_CHART_VERSION="8.3.0"

helm repo add --force-update vmware-tanzu https://vmware-tanzu.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-velero.yml" << EOF
initContainers:
  - name: velero-plugin-for-aws
    # renovate: datasource=docker depName=velero/velero-plugin-for-aws extractVersion=^(?<version>.+)$
    image: velero/velero-plugin-for-aws:v1.11.1
    volumeMounts:
      - mountPath: /target
        name: plugins
# metrics:
#   serviceMonitor:
#     enabled: true
#   prometheusRule:
#     enabled: true
#     spec:
#       - alert: VeleroBackupPartialFailures
#         annotations:
#           message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} partially failed backups.
#         expr: velero_backup_partial_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
#         for: 15m
#         labels:
#           severity: warning
#       - alert: VeleroBackupFailures
#         annotations:
#           message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed backups.
#         expr: velero_backup_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
#         for: 15m
#         labels:
#           severity: warning
#       - alert: VeleroBackupSnapshotFailures
#         annotations:
#           message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed snapshot backups.
#         expr: increase(velero_volume_snapshot_failure_total{schedule!=""}[1h]) > 0
#         for: 15m
#         labels:
#           severity: warning
#       - alert: VeleroRestorePartialFailures
#         annotations:
#           message: Velero restore {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} partially failed restores.
#         expr: increase(velero_restore_partial_failure_total{schedule!=""}[1h]) > 0
#         for: 15m
#         labels:
#           severity: warning
#       - alert: VeleroRestoreFailures
#         annotations:
#           message: Velero restore {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed restores.
#         expr: increase(velero_restore_failure_total{schedule!=""}[1h]) > 0
#         for: 15m
#         labels:
#           severity: warning
configuration:
  backupStorageLocation:
    - name:
      provider: aws
      bucket: ${CLUSTER_FQDN}
      prefix: velero
      config:
        region: ${AWS_DEFAULT_REGION}
  volumeSnapshotLocation:
    - name:
      provider: aws
      config:
        region: ${AWS_DEFAULT_REGION}
serviceAccount:
  server:
    name: velero
credentials:
  useSecret: false
# Create scheduled backup to periodically backup the let's encrypt production resources in the "cert-manager" namespace:
schedules:
  monthly-backup-cert-manager-production:
    labels:
      letsencrypt: production
    schedule: "@monthly"
    template:
      ttl: 2160h
      includedNamespaces:
        - cert-manager
      includedResources:
        - certificates.cert-manager.io
        - secrets
      labelSelector:
        matchLabels:
          letsencrypt: production
EOF
helm upgrade --install --version "${VELERO_HELM_CHART_VERSION}" --namespace velero --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-velero.yml" velero vmware-tanzu/velero
```

{% endraw %}

## Restore cert-manager objects

The following steps will guide you through restoring a Let's Encrypt production
certificate, previously backed up by Velero to S3, onto a new cluster.

Initiate the restore process for the cert-manager objects.

```bash
velero restore create --from-schedule velero-monthly-backup-cert-manager-production --labels letsencrypt=production --wait --existing-resource-policy=update
```

View details about the restore process:

```bash
velero restore describe --selector letsencrypt=production --details
```

```console
```

Verify that the certificate was restored properly:

```bash
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
```

### ExternalDNS

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns) synchronizes
exposed Kubernetes Services and Ingresses with DNS providers.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="200"}

ExternalDNS will manage the DNS records. The `external-dns` ServiceAccount was
created by `eksctl`.
Install the `external-dns` [Helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and modify its [default values](https://github.com/kubernetes-sigs/external-dns/blob/external-dns-helm-chart-1.18.0/charts/external-dns/values.yaml):

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.18.0"

helm repo add --force-update external-dns https://kubernetes-sigs.github.io/external-dns/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" << EOF
serviceAccount:
  name: external-dns
# serviceMonitor:
#   enabled: true
interval: 20s
policy: sync
domainFilters:
  - ${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${EXTERNAL_DNS_HELM_CHART_VERSION}" --namespace external-dns --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-external-dns.yml" external-dns external-dns/external-dns
```

### Grafana Mimir

[Grafana Mimir](https://grafana.com/oss/mimir/) is an open source, horizontally
scalable, multi-tenant time series database for Prometheus metrics, designed for
high availability and cost efficiency. It enables you to centralize metrics from
multiple clusters or environments, and integrates seamlessly with [Grafana](https://grafana.com/)
dashboards for visualization and alerting.

![Grafana Mimir](https://raw.githubusercontent.com/grafana/mimir/38563275a149baaf659e566990fe66a13db9e3c6/docs/sources/mimir/mimir-logo.png){:width="400"}

Install the `mimir-distributed` [Helm chart](https://github.com/grafana/mimir/tree/main/operations/helm/charts/mimir-distributed)
and customize its [default values](https://github.com/grafana/mimir/blob/mimir-distributed-5.7.0/operations/helm/charts/mimir-distributed/values.yaml)
to fit your environment and storage backend:

```bash
# renovate: datasource=helm depName=mimir-distributed registryUrl=https://grafana.github.io/helm-charts
MIMIR_DISTRIBUTED_HELM_CHART_VERSION="5.7.0"

helm repo add --force-update grafana https://grafana.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mimir-distributed.yml" << EOF
serviceAccount:
  name: mimir
mimir:
  structuredConfig:
    limits:
      compactor_blocks_retention_period: 30d
    common:
      # https://grafana.com/docs/mimir/latest/configure/configuration-parameters/
      storage:
        backend: s3
        s3:
          # bucket_name: "${CLUSTER_FQDN}"
          endpoint: "s3.${AWS_REGION}.amazonaws.com"
          region: ${AWS_REGION}
          storage_class: ONEZONE_IA
    alertmanager_storage:
      s3:
        bucket_name: "${CLUSTER_FQDN}"
      storage_prefix: mimiralertmanager
    blocks_storage:
      s3:
        bucket_name: "${CLUSTER_FQDN}"
      storage_prefix: mimirblocks
    ruler_storage:
      s3:
        bucket_name: "${CLUSTER_FQDN}"
      storage_prefix: mimirruler
ingester:
  replicas: 2
minio:
  enabled: false
nginx:
  enabled: false
EOF
helm upgrade --install --version "${MIMIR_DISTRIBUTED_HELM_CHART_VERSION}" --namespace mimir --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mimir-distributed.yml" mimir grafana/mimir-distributed
```

## Ingress NGINX Controller

[ingress-nginx](https://kubernetes.github.io/ingress-nginx/) is an Ingress
controller for Kubernetes that uses [nginx](https://www.nginx.org/) as a
reverse proxy and load balancer.

Install the `ingress-nginx` [Helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify its [default values](https://github.com/kubernetes/ingress-nginx/blob/helm-chart-4.13.2/charts/ingress-nginx/values.yaml):

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.13.2"

helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" << EOF
controller:
  config:
    annotations-risk-level: Critical
    use-proxy-protocol: true
  allowSnippetAnnotations: true
  ingressClassResource:
    default: true
  extraArgs:
    default-ssl-certificate: cert-manager/ingress-cert-production
  service:
    annotations:
      # https://www.qovery.com/blog/our-migration-from-kubernetes-built-in-nlb-to-alb-controller/
      # https://www.youtube.com/watch?v=xwiRjimKW9c
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: ${TAGS//\'/}
      service.beta.kubernetes.io/aws-load-balancer-name: eks-${CLUSTER_NAME}
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
      service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: proxy_protocol_v2.enabled=true
      service.beta.kubernetes.io/aws-load-balancer-type: external
    # loadBalancerClass: eks.amazonaws.com/nlb
  # metrics:
  #   enabled: true
  #   serviceMonitor:
  #     enabled: true
  #   prometheusRule:
  #     enabled: true
  #     rules:
  #       - alert: NGINXConfigFailed
  #         expr: count(nginx_ingress_controller_config_last_reload_successful == 0) > 0
  #         for: 1s
  #         labels:
  #           severity: critical
  #         annotations:
  #           description: bad ingress config - nginx config test failed
  #           summary: uninstall the latest ingress changes to allow config reloads to resume
  #       - alert: NGINXCertificateExpiry
  #         expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds{host!="_"}) by (host) - time()) < 604800
  #         for: 1s
  #         labels:
  #           severity: critical
  #         annotations:
  #           description: ssl certificate(s) will expire in less then a week
  #           summary: renew expiring certificates to avoid downtime
  #       - alert: NGINXTooMany500s
  #         expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"5.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
  #         for: 1m
  #         labels:
  #           severity: warning
  #         annotations:
  #           description: Too many 5XXs
  #           summary: More than 5% of all requests returned 5XX, this requires your attention
  #       - alert: NGINXTooMany400s
  #         expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"4.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
  #         for: 1m
  #         labels:
  #           severity: warning
  #         annotations:
  #           description: Too many 4XXs
  #           summary: More than 5% of all requests returned 4XX, this requires your attention
EOF
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx.yml" ingress-nginx ingress-nginx/ingress-nginx
```

### Mailpit

Mailpit will be used to receive email alerts from Prometheus.

![mailpit](https://raw.githubusercontent.com/axllent/mailpit/61241f11ac94eb33bd84e399129992250eff56ce/server/ui/favicon.svg){:width="150"}

Install the `mailpit` [Helm chart](https://artifacthub.io/packages/helm/jouve/mailpit)
and modify its [default values](https://github.com/jouve/charts/blob/mailpit-0.27.0/charts/mailpit/values.yaml):

```bash
# renovate: datasource=helm depName=mailpit registryUrl=https://jouve.github.io/charts/
MAILPIT_HELM_CHART_VERSION="0.28.0"

helm repo add --force-update jouve https://jouve.github.io/charts/
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" << EOF
replicaCount: 2
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - mailpit
        topologyKey: kubernetes.io/hostname
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/description: An email and SMTP testing tool with API for developers
    gethomepage.dev/group: Apps
    gethomepage.dev/icon: https://raw.githubusercontent.com/axllent/mailpit/61241f11ac94eb33bd84e399129992250eff56ce/server/ui/favicon.svg
    gethomepage.dev/name: Mailpit
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hostname: mailpit.${CLUSTER_FQDN}
EOF
helm upgrade --install --version "${MAILPIT_HELM_CHART_VERSION}" --namespace mailpit --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-mailpit.yml" mailpit jouve/mailpit
kubectl label namespace mailpit pod-security.kubernetes.io/enforce=baseline
```

Screenshot:

![Mailpit](/assets/img/posts/2024/2024-05-03-secure-cheap-amazon-eks-with-pod-identities/mailpit.avif){:width="700"}

## Grafana

Grafana is an open-source analytics and monitoring platform that allows you to
query, visualize, alert on, and understand your metrics, logs, and traces. It
provides a powerful and flexible way to create dashboards and visualizations for
monitoring your Kubernetes cluster and applications.

![Grafana](https://raw.githubusercontent.com/grafana/grafana/cdca1518d2d2ee5d725517a8d8206b0cfa3656d0/public/img/grafana_text_logo_light.svg){:width="300"}

Install the `grafana` [Helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
and modify its [default values](https://github.com/grafana/helm-charts/blob/grafana-9.4.3/charts/grafana/values.yaml):

```bash
# renovate: datasource=helm depName=grafana registryUrl=https://grafana.github.io/helm-charts
GRAFANA_HELM_CHART_VERSION="9.4.3"

helm repo add --force-update grafana https://grafana.github.io/helm-charts
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-grafana.yml" << EOF
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    gethomepage.dev/description: Visualization Platform
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: Observability
    gethomepage.dev/icon: grafana.svg
    gethomepage.dev/name: Grafana
    gethomepage.dev/app: grafana
    gethomepage.dev/pod-selector: "app.kubernetes.io/name=grafana"
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    nginx.ingress.kubernetes.io/configuration-snippet: |
      auth_request_set \$email \$upstream_http_x_auth_request_email;
      proxy_set_header X-Email \$email;
  path: /
  pathType: Prefix
  hosts:
    - grafana.${CLUSTER_FQDN}
  tls:
    - hosts:
        - grafana.${CLUSTER_FQDN}
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Mimir
        type: prometheus
        url: http://mimir-nginx.mimir.svc.cluster.local:80/prometheus
        access: proxy
        isDefault: true
notifiers:
  notifiers.yaml:
    notifiers:
    - name: email-notifier
      type: email
      uid: email1
      org_id: 1
      is_default: true
      settings:
        addresses: ${MY_EMAIL}
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: "default"
        orgId: 1
        folder: ""
        type: file
        disableDeletion: false
        editable: false
        options:
          path: /var/lib/grafana/dashboards/default
dashboards:
  default:
    # keep-sorted start numeric=yes
    1860-node-exporter-full:
      # renovate: depName="Node Exporter Full"
      gnetId: 1860
      revision: 37
      datasource: Prometheus
    # 3662-prometheus-2-0-overview:
    #   # renovate: depName="Prometheus 2.0 Overview"
    #   gnetId: 3662
    #   revision: 2
    #   datasource: Prometheus
    # 9614-nginx-ingress-controller:
    #   # renovate: depName="NGINX Ingress controller"
    #   gnetId: 9614
    #   revision: 1
    #   datasource: Prometheus
    # 12006-kubernetes-apiserver:
    #   # renovate: depName="Kubernetes apiserver"
    #   gnetId: 12006
    #   revision: 1
    #   datasource: Prometheus
    # # https://github.com/DevOps-Nirvana/Grafana-Dashboards
    # 14314-kubernetes-nginx-ingress-controller-nextgen-devops-nirvana:
    #   # renovate: depName="Kubernetes Nginx Ingress Prometheus NextGen"
    #   gnetId: 14314
    #   revision: 2
    #   datasource: Prometheus
    # 15038-external-dns:
    #   # renovate: depName="External-dns"
    #   gnetId: 15038
    #   revision: 3
    #   datasource: Prometheus
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
    # https://grafana.com/orgs/imrtfm/dashboards - https://github.com/dotdc/grafana-dashboards-kubernetes
    15760-kubernetes-views-pods:
      # renovate: depName="Kubernetes / Views / Pods"
      gnetId: 15760
      revision: 34
      datasource: Prometheus
    15761-kubernetes-system-api-server:
      # renovate: depName="Kubernetes / System / API Server"
      gnetId: 15761
      revision: 18
      datasource: Prometheus
    # 19105-prometheus:
    #   # renovate: depName="Prometheus"
    #   gnetId: 19105
    #   revision: 6
    #   datasource: Prometheus
    # 19268-prometheus:
    #   # renovate: depName="Prometheus All Metrics"
    #   gnetId: 19268
    #   revision: 1
    #   datasource: Prometheus
    # 20340-cert-manager:
    #   # renovate: depName="cert-manager"
    #   gnetId: 20340
    #   revision: 1
    #   datasource: Prometheus
    # 20842-cert-manager-kubernetes:
    #   # renovate: depName="Cert-manager-Kubernetes"
    #   gnetId: 20842
    #   revision: 1
    #   datasource: Prometheus
    # keep-sorted end
grafana.ini:
  analytics:
    check_for_updates: false
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
EOF
helm upgrade --install --version "${GRAFANA_HELM_CHART_VERSION}" --namespace grafana --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-grafana.yml" grafana grafana/grafana
```

### OAuth2 Proxy

Use [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) to protect
application endpoints with Google Authentication.

![OAuth2 Proxy](https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_horizontal.svg){:width="300"}

Install the `oauth2-proxy` [Helm chart](https://artifacthub.io/packages/helm/oauth2-proxy/oauth2-proxy)
and modify its [default values](https://github.com/oauth2-proxy/manifests/blob/oauth2-proxy-7.8.2/helm/oauth2-proxy/values.yaml):

```bash
# renovate: datasource=helm depName=oauth2-proxy registryUrl=https://oauth2-proxy.github.io/manifests
OAUTH2_PROXY_HELM_CHART_VERSION="7.9.2"

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
  ingressClassName: nginx
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/description: A reverse proxy that provides authentication with Google, Azure, OpenID Connect and many more identity providers
    gethomepage.dev/group: Cluster Management
    gethomepage.dev/icon: https://raw.githubusercontent.com/oauth2-proxy/oauth2-proxy/899c743afc71e695964165deb11f50b9a0703c97/docs/static/img/logos/OAuth2_Proxy_icon.svg
    gethomepage.dev/name: OAuth2-Proxy
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

### Homepage

Install [Homepage](https://gethomepage.dev/) to provide a nice dashboard.

![Homepage](https://raw.githubusercontent.com/gethomepage/homepage/e56dccc7f17144a53b97a315c2e4f622fa07e58d/images/banner_light%402x.png){:width="300"}

Install the `homepage` [Helm chart](https://github.com/jameswynn/helm-charts/tree/homepage-2.0.1/charts/homepage)
and modify its [default values](https://github.com/jameswynn/helm-charts/blob/homepage-2.0.1/charts/homepage/values.yaml):

```bash
# renovate: datasource=helm depName=homepage registryUrl=http://jameswynn.github.io/helm-charts
HOMEPAGE_HELM_CHART_VERSION="2.0.1"

helm repo add --force-update jameswynn http://jameswynn.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-homepage.yml" << EOF
enableRbac: true
serviceAccount:
  create: true
ingress:
  main:
    enabled: true
    annotations:
      gethomepage.dev/enabled: "true"
      gethomepage.dev/name: Homepage
      gethomepage.dev/description: A modern, secure, highly customizable application dashboard
      gethomepage.dev/group: Apps
      gethomepage.dev/icon: homepage.png
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    ingressClassName: "nginx"
    hosts:
      - host: ${CLUSTER_FQDN}
        paths:
          - path: /
            pathType: Prefix
    tls:
      - hosts:
          - ${CLUSTER_FQDN}
config:
  bookmarks:
  services:
  widgets:
    - logo:
        icon: kubernetes.svg
    - kubernetes:
        cluster:
          show: true
          cpu: true
          memory: true
          showLabel: true
          label: "${CLUSTER_NAME}"
        nodes:
          show: true
          cpu: true
          memory: true
          showLabel: true
  kubernetes:
    mode: cluster
  settings:
    hideVersion: true
    title: ${CLUSTER_FQDN}
    favicon: https://raw.githubusercontent.com/homarr-labs/dashboard-icons/38631ad11695467d7a9e432d5fdec7a39a31e75f/svg/kubernetes.svg
    layout:
      Apps:
        icon: mdi-apps
      Observability:
        icon: mdi-chart-bell-curve-cumulative
      Cluster Management:
        icon: mdi-tools
env:
  LOG_TARGETS: "stdout"
EOF
helm upgrade --install --version "${HOMEPAGE_HELM_CHART_VERSION}" --namespace homepage --create-namespace --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-homepage.yml" homepage jameswynn/homepage
```

## Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg){:width="300"}

Back up the certificate before deleting the cluster (in case it was renewed):

{% raw %}

```sh
if [[ "$(kubectl get --raw /api/v1/namespaces/cert-manager/services/cert-manager:9402/proxy/metrics | awk '/certmanager_http_acme_client_request_count.*acme-v02\.api.*finalize/ { print $2 }')" -gt 0 ]]; then
  velero backup create --labels letsencrypt=production --ttl 2160h --from-schedule velero-monthly-backup-cert-manager-production
fi
```

{% endraw %}

Stop Karpenter from launching additional nodes:

```sh
helm uninstall -n karpenter karpenter || true
helm uninstall -n ingress-nginx ingress-nginx || true
```

Remove any remaining EC2 instances provisioned by Karpenter (if they still exist):

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=tag:karpenter.sh/nodepool,Values=*" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text); do
  echo "🗑️  Removing Karpenter EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Disassociate a Route 53 Resolver query log configuration from an Amazon VPC:

```sh
AWS_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:alpha.eksctl.io/cluster-name,Values=${CLUSTER_NAME}" --query 'Vpcs[*].VpcId' --output text)

if [[ -n "${AWS_VPC_ID}" ]]; then
  AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOLVER_QUERY_LOG_CONFIG_ID=$(aws route53resolver list-resolver-query-log-config-associations \
    --query "ResolverQueryLogConfigAssociations[?ResourceId=='${AWS_VPC_ID}'].ResolverQueryLogConfigId" --output text)
  if [[ -n "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOLVER_QUERY_LOG_CONFIG_ID}" ]]; then
    aws route53resolver disassociate-resolver-query-log-config --resolver-query-log-config-id "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOLVER_QUERY_LOG_CONFIG_ID}" --resource-id "${AWS_VPC_ID}"
    sleep 5
    # wait4x exec "test "$(aws route53resolver list-resolver-query-log-config-associations --filters Name=ResolverQueryLogConfigId,Values="${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}" --query "ResolverQueryLogConfigAssociations[?ResourceId=='${AWS_VPC_ID}'].Status" --output text)" = """
  fi
fi
```

Clean up AWS Route 53 Resolver query log configurations:

```sh
AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID=$(aws route53resolver list-resolver-query-log-configs --query "ResolverQueryLogConfigs[?Name=='${CLUSTER_NAME}-vpc-dns-logs'].Id" --output text)
if [[ -n "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}" ]]; then
  aws route53resolver delete-resolver-query-log-config --resolver-query-log-config-id "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}"
fi
```

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

Delete Instance profile which belongs to Karpenter role:

```sh
if AWS_INSTANCE_PROFILES_FOR_ROLE=$(aws iam list-instance-profiles-for-role --role-name "KarpenterNodeRole-${CLUSTER_NAME}" --query 'InstanceProfiles[].{Name:InstanceProfileName}' --output text); then
  if [[ -n "${AWS_INSTANCE_PROFILES_FOR_ROLE}" ]]; then
    aws iam remove-role-from-instance-profile --instance-profile-name "${AWS_INSTANCE_PROFILES_FOR_ROLE}" --role-name "KarpenterNodeRole-${CLUSTER_NAME}"
    aws iam delete-instance-profile --instance-profile-name "${AWS_INSTANCE_PROFILES_FOR_ROLE}"
  fi
fi
```

Remove the CloudFormation stack:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53-kms"
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-karpenter"
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53-kms"
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-karpenter"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove volumes and snapshots related to the cluster (as a precaution):

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text); do
  echo "💾 Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done

# Remove EBS snapshots associated with the cluster
for SNAPSHOT in $(aws ec2 describe-snapshots --owner-ids self --filter "Name=tag:Name,Values=${CLUSTER_NAME}-dynamic-snapshot*" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Snapshots[].SnapshotId' --output text); do
  echo "📸 Removing Snapshot: ${SNAPSHOT}"
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
done
```

Remove the CloudWatch log group:

```sh
if [[ "$(aws logs describe-log-groups --query "logGroups[?logGroupName==\`/aws/eks/${CLUSTER_NAME}/cluster\`] | [0].logGroupName" --output text)" = "/aws/eks/${CLUSTER_NAME}/cluster" ]]; then
  aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
fi
```

Remove the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
if [[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]]; then
  for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{kubeconfig-${CLUSTER_NAME}.conf,{aws-cf-route53-kms,cloudformation-karpenter,eksctl-${CLUSTER_NAME},helm_values-{aws-load-balancer-controller,cert-manager,external-dns,grafana,homepage,ingress-nginx,karpenter,mailpit,mimir-distributed,oauth2-proxy,velero},k8s-{cert-manager-clusterissuer-production,karpenter-nodepool,storageclass-volumesnapshotclass}}.yml}; do
    if [[ -f "${FILE}" ]]; then
      rm -v "${FILE}"
    else
      echo "❌ File not found: ${FILE}"
    fi
  done
  rmdir "${TMP_DIR}/${CLUSTER_FQDN}"
fi
```

Enjoy ... 😉
