---
title: Amazon EKS with Argo CD capability
author: Petr Ruzicka
date: 2026-03-04
description: Build Amazon EKS with ArgoCD capability and IAM Identity Center
categories: [Kubernetes, Cloud]
tags:
  [amazon-eks, argocd, cert-manager, eks, eksctl, grafana, homepage,
  envoy-gateway, kubernetes, monitoring, sso, velero, victorialogs,
  victoriametrics]
image: https://raw.githubusercontent.com/akuity/awesome-argo/977bf4e5e8b5382325967711d7c3c21e382cba1d/images/argo.png
---

I will outline the steps for setting up an [Amazon EKS](https://aws.amazon.com/eks/)
environment with [Argo CD](https://argoproj.github.io/cd/) as the deployment
engine, using ArgoCD Application CRDs to manage Helm chart installations.

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
  for highly cost-effective and optimized load balancing
- [Karpenter](https://karpenter.sh/) to enable automatic node scaling that
  matches the specific resource requirements of pods
- The Amazon EKS control plane must be [encrypted using KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes must be encrypted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- [EKS cluster logging](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
  to [CloudWatch](https://aws.amazon.com/cloudwatch/) must be configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
  should be enabled where supported
- [EKS Pod Identities](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
  should be used to allow applications and pods to communicate with AWS APIs
- [ArgoCD](https://argoproj.github.io/cd/) deployed as an AWS-managed
  [EKS capability](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html)
  with [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
  for authentication, using Application CRDs for declarative deployments
- [Envoy Gateway](https://gateway.envoyproxy.io/) as the Gateway API
  implementation with OIDC authentication and JWT-based authorization
  via Google for protecting web endpoints
- [Homepage](https://gethomepage.dev/) dashboard for a unified service
  portal
- [VictoriaMetrics](https://victoriametrics.com/) for metrics collection
  and storage, [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
  for centralized log aggregation, and [Grafana](https://grafana.com/) for
  dashboards and visualization

## Build Amazon EKS

### Requirements

You will need to configure the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and set up other necessary secrets and variables:

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
export AWS_ROLE_TO_ASSUME="arn:aws:iam::7xxxxxxxxxx7:role/Gixxxxxxxxxxxxxxxxxxxxle"
export GOOGLE_CLIENT_ID="10xxxxxxxxxxxxxxxud.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="GOxxxxxxxxxxxxxxxtw"
```

If you plan to follow this document and its tasks, you will need to set up
a few environment variables, such as:

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
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
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
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${AWS_ROLE_TO_ASSUME?}"
: "${GOOGLE_CLIENT_ID?}"
: "${GOOGLE_CLIENT_SECRET?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

Install the required tools:

<!-- prettier-ignore-start -->
> You can bypass these procedures if you already have all the essential
> software installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)

### Configure AWS Route 53 Domain delegation

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

Utilize your domain registrar to update the nameservers for your zone
(e.g., `mylabs.dev`) to point to Amazon Route 53 nameservers. Here's how
to discover the required Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Establish the NS record in `k8s.mylabs.dev` (your `BASE_DOMAIN`) for
proper zone delegation. This operation's specifics may vary based on your
domain registrar; I use Cloudflare and employ Ansible for automation:

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

### Create the service-linked role

<!-- prettier-ignore-start -->
> Creating the service-linked role for Spot Instances is a one-time operation.
{: .prompt-info }
<!-- prettier-ignore-end -->

Create the `AWSServiceRoleForEC2Spot` role to use Spot Instances in the
Amazon EKS cluster:

```shell
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
```

Details: [Work with Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html)

### Create Route53, KMS, and IAM Identity Center infrastructure

Generate a CloudFormation template that defines an [Amazon Route 53](https://aws.amazon.com/route53/)
zone, an [AWS Key Management Service (KMS)](https://aws.amazon.com/kms/) key,
and an [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
instance for ArgoCD authentication.

Add the new domain `CLUSTER_FQDN` to Route 53, and set up DNS delegation from
the `BASE_DOMAIN`.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53, KMS key, and IAM Identity Center instance

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
  S3AccessPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "eksctl-${ClusterName}-s3-access-policy"
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Action:
              - s3:AbortMultipartUpload
              - s3:DeleteObject
              - s3:GetObject
              - s3:ListMultipartUploadParts
              - s3:ListObjects
              - s3:PutObject
              - s3:PutObjectTagging
            Resource: !Sub "arn:aws:s3:::${ClusterFQDN}/*"
          - Effect: Allow
            Action:
              - s3:ListBucket
            Resource: !Sub "arn:aws:s3:::${ClusterFQDN}"
  SSOInstance:
    Type: AWS::SSO::Instance
    Properties:
      Name: !Sub "eks-${ClusterName}-idc"
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
  S3AccessPolicyArn:
    Description: IAM policy ARN for S3 access by EKS workloads
    Value: !Ref S3AccessPolicy
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-S3AccessPolicy"
  SSOInstanceArn:
    Description: IAM Identity Center instance ARN for ArgoCD
    Value: !GetAtt SSOInstance.InstanceArn
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-SSOInstanceArn"
  SSOIdentityStoreId:
    Description: IAM Identity Center Identity Store ID
    Value: !GetAtt SSOInstance.IdentityStoreId
    Export:
      Name:
        Fn::Sub: "${AWS::StackName}-SSOIdentityStoreId"
EOF

# shellcheck disable=SC2001
eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "BaseDomain=${BASE_DOMAIN} ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME}" \
  --stack-name "${CLUSTER_NAME}-route53-kms" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" --tags "${TAGS//,/ }"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-kms" --query "Stacks[0].Outputs[? OutputKey==\`KMSKeyArn\` || OutputKey==\`KMSKeyId\` || OutputKey==\`S3AccessPolicyArn\` || OutputKey==\`SSOInstanceArn\` || OutputKey==\`SSOIdentityStoreId\`].{OutputKey:OutputKey,OutputValue:OutputValue}")
AWS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
AWS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
AWS_S3_ACCESS_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"S3AccessPolicyArn\") .OutputValue")
IDC_INSTANCE_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"SSOInstanceArn\") .OutputValue")
IDC_IDENTITY_STORE_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"SSOIdentityStoreId\") .OutputValue")
```

After running the CloudFormation stack, you should see the following
Route53 zones:

![Route53 k01.k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedzones-k01.k8s.mylabs.dev.avif)
_Route53 k01.k8s.mylabs.dev zone_

![Route53 k8s.mylabs.dev zone](/assets/img/posts/2022/2022-11-27-cheapest-amazon-eks/route53-hostedones-k8s.mylabs.dev-2.avif)
_Route53 k8s.mylabs.dev zone_

You should also see the following KMS key:

![KMS key](/assets/img/posts/2023/2023-08-03-cilium-amazon-eks/kms-key.avif)
_KMS key_

-------------------------------> Add screentot of IDC_IDENTITY_STORE !!!!!! xxxx

### Create Karpenter infrastructure

Use CloudFormation to set up the infrastructure needed by the EKS cluster.
See [CloudFormation](https://karpenter.sh/docs/reference/cloudformation/)
for a complete description of what `cloudformation.yaml` does for
Karpenter.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png){:width="400"}

```bash
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/refs/heads/main/website/content/en/v1.9/getting-started/getting-started-with-karpenter/cloudformation.yaml > "${TMP_DIR}/${CLUSTER_FQDN}/cloudformation-karpenter.yml"
eval aws cloudformation deploy --stack-name "${CLUSTER_NAME}-karpenter" \
  --template-file "${TMP_DIR}/${CLUSTER_FQDN}/cloudformation-karpenter.yml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" --tags "${TAGS//,/ }"
```

### Configure IAM Identity Center user

The [ArgoCD EKS capability](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html)
requires [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
for authentication. The IAM Identity Center instance was already
provisioned by the CloudFormation stack above. Create a user in the
Identity Store that will serve as the ArgoCD administrator.

```bash
IDC_USER_ID=$(
  aws identitystore create-user --identity-store-id "${IDC_IDENTITY_STORE_ID}" \
    --user-name "argocd-admin" --display-name "ArgoCD Admin" \
    --name "GivenName=ArgoCD,FamilyName=Admin" \
    --emails "Value=${MY_EMAIL},Type=Work,Primary=true" --query "UserId" --output text
)
echo -e "IDC Instance ARN: ${IDC_INSTANCE_ARN}\nIdentity Store ID: ${IDC_IDENTITY_STORE_ID}\nIDC User ID: ${IDC_USER_ID}"
```

### Create Amazon EKS

I will use [eksctl](https://eksctl.io/) to create the
[Amazon EKS](https://aws.amazon.com/eks/) cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/2b1ec6223c4e7cb8103c08162e6de8ced47376f9/userdocs/src/img/eksctl.png){:width="700"}

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
autoModeConfig:
  enabled: false
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
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}
        - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}
    - namespace: velero
      serviceAccountName: velero
      roleName: eksctl-${CLUSTER_NAME}-velero
      permissionPolicyARNs:
        - ${AWS_S3_ACCESS_POLICY_ARN}
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
    - namespace: kube-system
      serviceAccountName: aws-node
      roleName: eksctl-${CLUSTER_NAME}-vpc-cni
      wellKnownPolicies:
        amazonVPCCNI: true
iamIdentityMappings:
  - arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
capabilities:
  - name: argocd
    type: ARGOCD
    deletePropagationPolicy: RETAIN
    accessPolicies:
      - policyARN: arn:${AWS_PARTITION}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
        accessScope:
          type: cluster
    configuration:
      argocd:
        awsIdc:
          idcInstanceArn: ${IDC_INSTANCE_ARN}
          idcRegion: ${AWS_DEFAULT_REGION}
        rbacRoleMappings:
          - role: ADMIN
            identities:
              - id: ${IDC_USER_ID}
                type: SSO_USER
addons:
  - name: coredns
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
    configurationValues: |-
      enableNetworkPolicy: "true"
      env:
        ENABLE_PREFIX_DELEGATION: "true"
managedNodeGroups:
  - name: mng01-ng
    amiFamily: Bottlerocket
    instanceType: t4g.medium
    desiredCapacity: 2
    availabilityZones:
      - ${AWS_DEFAULT_REGION}a
    minSize: 2
    maxSize: 3
    volumeSize: 20
    volumeEncrypted: true
    volumeKmsKeyID: ${AWS_KMS_KEY_ID}
    privateNetworking: true
    nodeRepairConfig:
      enabled: true
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

Enhance the security posture of the EKS cluster by addressing the
following concerns:

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

- Remove overly permissive NACL rules to follow the principle of least
  privilege:

  ```bash
  # Delete the overly permissive inbound rule
  aws ec2 delete-network-acl-entry \
    --network-acl-id "${AWS_NACL_ID}" \
    --rule-number 100 \
    --ingress

  # Create restrictive inbound TCP rules
  NACL_RULES=(
    "100 443 443 0.0.0.0/0"
    "110 80 80 0.0.0.0/0"
    "120 1024 65535 0.0.0.0/0"
  )

  for RULE in "${NACL_RULES[@]}"; do
    read -r RULE_NUM PORT_FROM PORT_TO CIDR <<< "${RULE}"
    aws ec2 create-network-acl-entry \
      --network-acl-id "${AWS_NACL_ID}" \
      --rule-number "${RULE_NUM}" \
      --protocol "tcp" \
      --port-range "From=${PORT_FROM},To=${PORT_TO}" \
      --cidr-block "${CIDR}" \
      --rule-action allow \
      --ingress
  done

  # Allow all traffic from VPC CIDR
  aws ec2 create-network-acl-entry \
    --network-acl-id "${AWS_NACL_ID}" \
    --rule-number 130 \
    --protocol "all" \
    --cidr-block "192.168.0.0/16" \
    --rule-action allow \
    --ingress
  ```

### ArgoCD

[Argo CD](https://argoproj.github.io/cd/) is a declarative, GitOps
continuous delivery tool for Kubernetes. Amazon EKS provides ArgoCD as a
managed [capability](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html),
eliminating the need to install and manage ArgoCD yourself.

![Argo CD](https://raw.githubusercontent.com/argoproj/argo-cd/c67cff8065bb6540b1c79deb0b71e5e11c87a746/docs/assets/argo.png){:width="200"}

The ArgoCD capability was configured in the `eksctl` ClusterConfig
`capabilities` section and deployed automatically during cluster
creation. The capability uses
[IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
for authentication, which was set up in the previous steps.

Wait for the ArgoCD capability to be fully ready:

```bash
kubectl wait --for=condition=Available --timeout=300s \
  deployment -n argocd -l app.kubernetes.io/part-of=argocd
```

Each ArgoCD Application below carries a
[sync-wave](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
annotation (`argocd.argoproj.io/sync-wave`) that documents the intended
deployment order. The waves ensure that CRDs and infrastructure
components are deployed before the applications that depend on them:

| Wave | Components                                       |
| ---- | ------------------------------------------------ |
| -5   | Gateway API CRDs                                 |
| -3   | AWS LB Controller, Karpenter, cert-manager       |
| -1   | Envoy Gateway, ExternalDNS, Velero               |
| 0    | victoria-metrics-k8s-stack, victoria-logs-single |
| 1    | Grafana                                          |
| 2    | Homepage                                         |

### Gateway API CRDs

Install the [Gateway API](https://gateway-api.sigs.k8s.io/) Custom
Resource Definitions (CRDs) that are required by Envoy Gateway using an
ArgoCD Application CRD pointing at the upstream Git repository:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-gateway-api-crds.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gateway-api-crds
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-5"
spec:
  project: default
  source:
    repoURL: https://github.com/kubernetes-sigs/gateway-api
    targetRevision: v1.4.0
    path: config/crd/standard
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF
```

### AWS Load Balancer Controller

The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
is a controller that manages Elastic Load Balancers for a Kubernetes
cluster.

![AWS Load Balancer Controller](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/05071ecd0f2c240c7e6b815c0fdf731df799005a/docs/assets/images/aws_load_balancer_icon.svg){:width="150"}

Install the `aws-load-balancer-controller`
[Helm chart](https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/main/helm/aws-load-balancer-controller)
using an ArgoCD Application CRD:

```bash
# renovate: datasource=helm depName=aws-load-balancer-controller registryUrl=https://aws.github.io/eks-charts
AWS_LOAD_BALANCER_CONTROLLER_HELM_CHART_VERSION="1.17.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-aws-load-balancer-controller.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aws-load-balancer-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default
  destination:
    namespace: aws-load-balancer-controller
    server: https://kubernetes.default.svc
  source:
    chart: aws-load-balancer-controller
    repoURL: https://aws.github.io/eks-charts
    targetRevision: ${AWS_LOAD_BALANCER_CONTROLLER_HELM_CHART_VERSION}
    helm:
      values: |
        serviceAccount:
          name: aws-load-balancer-controller
        clusterName: ${CLUSTER_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

### Pod Scheduling PriorityClasses

Configure [PriorityClasses](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
to control the scheduling priority of pods in your cluster.
PriorityClasses allow you to influence which pods are scheduled or evicted
first when resources are constrained. These classes help ensure that
critical workloads receive scheduling priority over less important
workloads.

Create custom PriorityClass resources to define priority levels for
different workload types:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-scheduling-priorityclass.yml" << EOF | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-priority
value: 100001000
globalDefault: false
description: "This priority class should be used for critical workloads only"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 100000000
globalDefault: false
description: "This priority class should be used for high priority workloads"
EOF
```

### Add Storage Classes and Volume Snapshots

Configure persistent storage for your EKS cluster by setting up GP3
storage classes and volume snapshot capabilities. This ensures encrypted,
expandable storage with proper backup functionality.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-storage-snapshot-storageclass-volumesnapshotclass.yml" << EOF | kubectl apply -f -
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

[Karpenter](https://karpenter.sh/) is a Kubernetes node autoscaler built
for flexibility, performance, and simplicity.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter-provider-aws/41b115a0b85677641e387635496176c4cc30d4c6/website/static/full_logo.svg){:width="500"}

Install the `karpenter`
[Helm chart](https://github.com/aws/karpenter-provider-aws/tree/main/charts/karpenter)
using an ArgoCD Application CRD:

```bash
# renovate: datasource=github-tags depName=aws/karpenter-provider-aws
KARPENTER_HELM_CHART_VERSION="1.8.4"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-karpenter.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default
  destination:
    namespace: karpenter
    server: https://kubernetes.default.svc
  source:
    chart: karpenter
    repoURL: public.ecr.aws/karpenter
    targetRevision: ${KARPENTER_HELM_CHART_VERSION}
    helm:
      values: |
        settings:
          clusterName: ${CLUSTER_NAME}
          eksControlPlane: true
          interruptionQueue: ${CLUSTER_NAME}
          featureGates:
            spotToSpotConsolidation: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

Wait for the Karpenter ArgoCD Application to be healthy:

```bash
kubectl wait --for=condition=Healthy application/karpenter -n argocd --timeout=300s
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
        - key: "karpenter.k8s.aws/instance-memory"
          operator: Gt
          values: ["4095"]
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

### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and
certificate issuers as resource types in Kubernetes clusters and
simplifies the process of obtaining, renewing, and using those
certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="150"}

Install the `cert-manager`
[Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
using an ArgoCD Application CRD:

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io extractVersion=^(?<version>.+)$
CERT_MANAGER_HELM_CHART_VERSION="v1.19.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-cert-manager.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  project: default
  destination:
    namespace: cert-manager
    server: https://kubernetes.default.svc
  source:
    chart: cert-manager
    repoURL: https://charts.jetstack.io
    targetRevision: ${CERT_MANAGER_HELM_CHART_VERSION}
    helm:
      values: |
        global:
          priorityClassName: high-priority
        crds:
          enabled: true
        extraArgs:
          - --enable-certificate-owner-ref=true
        serviceAccount:
          name: cert-manager
        enableCertificateOwnerRef: true
        webhook:
          replicaCount: 2
          affinity:
            podAntiAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
              - labelSelector:
                  matchLabels:
                    app.kubernetes.io/instance: cert-manager
                    app.kubernetes.io/component: webhook
                topologyKey: kubernetes.io/hostname
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

Wait for the cert-manager ArgoCD Application to be healthy:

```bash
kubectl wait --for=condition=Healthy application/cert-manager -n argocd --timeout=300s
```

Create a [ClusterIssuer](https://cert-manager.io/docs/concepts/issuer/)
for Let's Encrypt production certificates and a wildcard Certificate
for the cluster domain:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-cert-manager-clusterissuer.yml" << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns
  labels:
    letsencrypt: production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-production-dns
    solvers:
      - dns01:
          route53:
            region: ${AWS_DEFAULT_REGION}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ingress-cert-production
  namespace: cert-manager
  labels:
    letsencrypt: production
spec:
  secretName: ingress-cert-production
  secretTemplate:
    labels:
      letsencrypt: production
  issuerRef:
    name: letsencrypt-production-dns
    kind: ClusterIssuer
  commonName: "*.${CLUSTER_FQDN}"
  dnsNames:
    - "*.${CLUSTER_FQDN}"
    - "${CLUSTER_FQDN}"
EOF
```

### Velero

Velero is an open-source tool for backing up and restoring Kubernetes
cluster resources and persistent volumes. It enables disaster recovery,
data migration, and scheduled backups by integrating with cloud storage
providers such as AWS S3.

![velero](https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/Velero.svg){:width="400"}

Install the `velero`
[Helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
using an ArgoCD Application CRD:

{% raw %}

```bash
# renovate: datasource=helm depName=velero registryUrl=https://vmware-tanzu.github.io/helm-charts
VELERO_HELM_CHART_VERSION="11.3.2"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-velero.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: velero
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  destination:
    namespace: velero
    server: https://kubernetes.default.svc
  source:
    chart: velero
    repoURL: https://vmware-tanzu.github.io/helm-charts
    targetRevision: ${VELERO_HELM_CHART_VERSION}
    helm:
      values: |
        initContainers:
          - name: velero-plugin-for-aws
            # renovate: datasource=github-tags depName=vmware-tanzu/velero-plugin-for-aws extractVersion=^(?<version>.+)$
            image: velero/velero-plugin-for-aws:v1.13.1
            volumeMounts:
              - mountPath: /target
                name: plugins
        priorityClassName: high-priority
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
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

{% endraw %}

Wait for the Velero ArgoCD Application to be healthy:

```bash
kubectl wait --for=condition=Healthy application/velero -n argocd --timeout=300s
```

#### Restore cert-manager objects

The following steps will guide you through restoring a Let's Encrypt
production certificate, previously backed up by Velero to S3, onto a
new cluster.

Initiate the restore process for the cert-manager objects.

```bash
while [ -z "$(kubectl -n velero get backupstoragelocations default -o jsonpath='{.status.lastSyncedTime}')" ]; do sleep 5; done
velero restore create --from-schedule velero-monthly-backup-cert-manager-production --labels letsencrypt=production --wait --existing-resource-policy=update
```

View details about the restore process:

```bash
velero restore describe --selector letsencrypt=production --details
```

```console
Name:         velero-monthly-backup-cert-manager-production-20251030075321
Namespace:    velero
Labels:       letsencrypt=production
Annotations:  <none>

Phase:                       Completed
Total items to be restored:  3
Items restored:              3

Started:    2025-10-30 07:53:22 +0100 CET
Completed:  2025-10-30 07:53:24 +0100 CET

Backup:  velero-monthly-backup-cert-manager-production-20250921155028

Namespaces:
  Included:  all namespaces found in the backup
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        nodes, events, events.events.k8s.io, backups.velero.io, restores.velero.io, resticrepositories.velero.io, csinodes.storage.k8s.io, volumeattachments.storage.k8s.io, backuprepositories.velero.io
  Cluster-scoped:  auto

Namespace mappings:  <none>

Label selector:  <none>

Or label selector:  <none>

Restore PVs:  auto

CSI Snapshot Restores: <none included>

Existing Resource Policy:   update
ItemOperationTimeout:       4h0m0s

Preserve Service NodePorts:  auto

Uploader config:


HooksAttempted:   0
HooksFailed:      0

Resource List:
  cert-manager.io/v1/Certificate:
    - cert-manager/ingress-cert-production(created)
  v1/Secret:
    - cert-manager/ingress-cert-production(created)
    - cert-manager/letsencrypt-production-dns(created)
```

Verify that the certificate was restored properly:

```bash
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
Name:         ingress-cert-production
Namespace:    cert-manager
Labels:       letsencrypt=production
              velero.io/backup-name=velero-monthly-backup-cert-manager-production-20250921155028
              velero.io/restore-name=velero-monthly-backup-cert-manager-production-20251030075321
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2025-10-30T06:53:23Z
  Generation:          1
  Resource Version:    5521
  UID:                 33422558-3105-4936-87d8-468befb5dc2b
Spec:
  Common Name:  *.k01.k8s.mylabs.dev
  Dns Names:
    *.k01.k8s.mylabs.dev
    k01.k8s.mylabs.dev
  Issuer Ref:
    Group:      cert-manager.io
    Kind:       ClusterIssuer
    Name:       letsencrypt-production-dns
  Secret Name:  ingress-cert-production
  Secret Template:
    Labels:
      Letsencrypt:  production
Status:
  Conditions:
    Last Transition Time:  2025-10-30T06:53:23Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2025-12-20T10:53:07Z
  Not Before:              2025-09-21T10:53:08Z
  Renewal Time:            2025-11-20T10:53:07Z
Events:                    <none>
```

### ExternalDNS

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns)
synchronizes exposed Kubernetes Services and Ingresses with DNS
providers.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="200"}

ExternalDNS will manage the DNS records. Install the `external-dns`
[Helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
using an ArgoCD Application CRD:

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.20.0"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-external-dns.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  destination:
    namespace: external-dns
    server: https://kubernetes.default.svc
  source:
    chart: external-dns
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    targetRevision: ${EXTERNAL_DNS_HELM_CHART_VERSION}
    helm:
      values: |
        serviceAccount:
          name: external-dns
        priorityClassName: high-priority
        interval: 20s
        policy: sync
        domainFilters:
          - ${CLUSTER_FQDN}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

### Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) is an implementation of
the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) built on
[Envoy Proxy](https://www.envoyproxy.io/) that provides advanced traffic
management, OIDC authentication, and JWT-based authorization.

![Envoy Gateway](https://raw.githubusercontent.com/envoyproxy/gateway/refs/heads/main/site/static/img/envoy-gateway.svg){:width="250"}

Install Envoy Gateway using an ArgoCD Application CRD:

```bash
# renovate: datasource=docker depName=envoyproxy/gateway-helm registryUrl=https://docker.io
ENVOY_GATEWAY_HELM_CHART_VERSION="v1.7.0"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-envoy-gateway.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: envoy-gateway
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  destination:
    namespace: envoy-gateway-system
    server: https://kubernetes.default.svc
  source:
    chart: gateway-helm
    repoURL: docker.io/envoyproxy
    targetRevision: ${ENVOY_GATEWAY_HELM_CHART_VERSION}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
EOF
```

Wait for the Envoy Gateway ArgoCD Application to be healthy:

```bash
kubectl wait --for=condition=Healthy application/envoy-gateway -n argocd --timeout=300s
```

Configure the [Gateway](https://gateway-api.sigs.k8s.io/concepts/api-overview/#gateway)
resource with AWS NLB annotations using an
[EnvoyProxy](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/)
custom resource:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-envoy-gateway-gateway.yml" << EOF | kubectl apply -f -
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: aws-nlb
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: external
          service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
          service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
          service.beta.kubernetes.io/aws-load-balancer-name: eks-${CLUSTER_NAME}
          service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: ${TAGS//\'/}
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production-dns
spec:
  gatewayClassName: eg
  infrastructure:
    parametersRef:
      group: gateway.envoyproxy.io
      kind: EnvoyProxy
      name: aws-nlb
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*.${CLUSTER_FQDN}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ingress-cert-production
            namespace: cert-manager
      allowedRoutes:
        namespaces:
          from: All
    - name: https-apex
      port: 443
      protocol: HTTPS
      hostname: "${CLUSTER_FQDN}"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ingress-cert-production
            namespace: cert-manager
      allowedRoutes:
        namespaces:
          from: All
EOF
```

### victoria-metrics-k8s-stack

[![victoria-metrics-k8s-stack](https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/master/docs/logo.webp){:width="200"}](https://victoriametrics.com/)

Install [victoria-metrics-k8s-stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
which provides a full monitoring stack with [VictoriaMetrics](https://victoriametrics.com/)
components: VMSingle for metrics storage, VMAgent for scraping,
VMAlert for alerting rules, and the VictoriaMetrics Operator with
CRDs (VMServiceScrape, VMPodScrape, VMRule, etc.):

```bash
# renovate: datasource=helm depName=victoria-metrics-k8s-stack registryUrl=https://victoriametrics.github.io/helm-charts
VICTORIA_METRICS_K8S_STACK_HELM_CHART_VERSION="0.72.2"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-victoria-metrics-k8s-stack.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-metrics-k8s-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  destination:
    namespace: monitoring
    server: https://kubernetes.default.svc
  source:
    chart: victoria-metrics-k8s-stack
    repoURL: https://victoriametrics.github.io/helm-charts
    targetRevision: ${VICTORIA_METRICS_K8S_STACK_HELM_CHART_VERSION}
    helm:
      values: |
        argocdReleaseOverride: victoria-metrics-k8s-stack
        vmsingle:
          enabled: true
          spec:
            retentionPeriod: "2"
            replicaCount: 1
            storage:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 10Gi
            extraArgs:
              search.maxStalenessInterval: 5m
        vmcluster:
          enabled: false
        vmagent:
          enabled: true
          spec:
            scrapeInterval: 30s
            selectAllByDefault: true
            externalLabels:
              cluster: ${CLUSTER_NAME}
            extraArgs:
              promscrape.streamParse: "true"
        vmalert:
          enabled: true
          spec:
            evaluationInterval: 30s
            selectAllByDefault: true
        alertmanager:
          enabled: true
          spec:
            replicaCount: 1
          config:
            route:
              receiver: blackhole
              group_by:
                - alertgroup
                - job
              group_wait: 30s
              group_interval: 5m
              repeat_interval: 12h
            receivers:
              - name: blackhole
        grafana:
          enabled: false
        defaultDashboards:
          enabled: true
          annotations:
            argocd.argoproj.io/sync-options: ServerSideApply=true
        defaultRules:
          create: true
          groups:
            etcd:
              create: false
            kubeScheduler:
              create: false
            kubernetesSystemScheduler:
              create: false
            kubernetesSystemControllerManager:
              create: false
        kubelet:
          enabled: true
          vmScrapes:
            cadvisor:
              enabled: true
            probes:
              enabled: true
        kube-state-metrics:
          enabled: true
          vmScrape:
            enabled: true
        prometheus-node-exporter:
          enabled: true
          vmScrape:
            enabled: true
        kubeControllerManager:
          enabled: false
        kubeScheduler:
          enabled: false
        kubeEtcd:
          enabled: false
        kubeProxy:
          enabled: false
        victoria-metrics-operator:
          enabled: true
          crds:
            plain: true
            cleanup:
              enabled: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - RespectIgnoreDifferences=true
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: victoria-metrics-k8s-stack-victoria-metrics-operator-validation
      namespace: monitoring
      jsonPointers:
        - /data
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: victoria-metrics-k8s-stack-victoria-metrics-operator-admission
      jqPathExpressions:
        - '.webhooks[]?.clientConfig.caBundle'
EOF
```

### victoria-logs-single

Install [victoria-logs-single](https://docs.victoriametrics.com/helm/victoria-logs-single/)
for centralized log collection. The chart deploys VictoriaLogs as
a single-node log storage and includes a [Vector](https://vector.dev/)
DaemonSet that collects logs from all pods:

```bash
# renovate: datasource=helm depName=victoria-logs-single registryUrl=https://victoriametrics.github.io/helm-charts
VICTORIA_LOGS_SINGLE_HELM_CHART_VERSION="0.11.28"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-victoria-logs-single.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-logs-single
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  destination:
    namespace: monitoring
    server: https://kubernetes.default.svc
  source:
    chart: victoria-logs-single
    repoURL: https://victoriametrics.github.io/helm-charts
    targetRevision: ${VICTORIA_LOGS_SINGLE_HELM_CHART_VERSION}
    helm:
      values: |
        server:
          retentionPeriod: 30d
          persistentVolume:
            enabled: true
            size: 10Gi
            accessModes:
              - ReadWriteOnce
          extraArgs:
            envflag.enable: "true"
            envflag.prefix: VM_
            loggerFormat: json
          service:
            type: ClusterIP
            servicePort: 9428
        vector:
          enabled: true
          role: Agent
          customConfig:
            data_dir: /vector-data-dir
            api:
              enabled: false
            sources:
              k8s:
                type: kubernetes_logs
            transforms:
              parser:
                type: remap
                inputs:
                  - k8s
                source: |
                  .log = parse_json(.message) ?? .message
                  del(.message)
            sinks:
              vlogs:
                type: elasticsearch
                inputs:
                  - parser
                endpoints:
                  - http://victoria-logs-single-server:9428/insert/elasticsearch/
                mode: bulk
                api_version: v8
                compression: gzip
                healthcheck:
                  enabled: false
                request:
                  headers:
                    VL-Time-Field: timestamp
                    VL-Stream-Fields: stream,kubernetes.pod_name,kubernetes.container_name,kubernetes.pod_namespace
                    VL-Msg-Field: message,msg,_msg,log.msg,log.message,log
                    AccountID: "0"
                    ProjectID: "0"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

### Grafana

[![Grafana](https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg){:width="150"}](https://grafana.com/)

Install [Grafana](https://grafana.com/) with
[VictoriaMetrics](https://victoriametrics.com/) and
[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
datasources preconfigured. The
[victoriametrics-logs-datasource](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/)
Grafana plugin is required for querying VictoriaLogs:

```bash
# renovate: datasource=helm depName=grafana registryUrl=https://grafana.github.io/helm-charts
GRAFANA_HELM_CHART_VERSION="10.5.12"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-grafana.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  destination:
    namespace: monitoring
    server: https://kubernetes.default.svc
  source:
    chart: grafana
    repoURL: https://grafana.github.io/helm-charts
    targetRevision: ${GRAFANA_HELM_CHART_VERSION}
    helm:
      values: |
        plugins:
          - victoriametrics-logs-datasource
        datasources:
          datasources.yaml:
            apiVersion: 1
            datasources:
              - name: VictoriaMetrics
                type: prometheus
                uid: victoriametrics
                access: proxy
                url: http://vmsingle-victoria-metrics-k8s-stack.monitoring.svc:8428
                isDefault: true
                jsonData:
                  httpMethod: POST
                  timeInterval: "30s"
              - name: VictoriaLogs
                type: victoriametrics-logs-datasource
                uid: victorialogs
                access: proxy
                url: http://victoria-logs-single-server.monitoring.svc:9428
        dashboardProviders:
          dashboardproviders.yaml:
            apiVersion: 1
            providers:
              - name: default
                orgId: 1
                folder: ""
                type: file
                disableDeletion: false
                editable: false
                options:
                  path: /var/lib/grafana/dashboards/default
        sidecar:
          dashboards:
            enabled: true
            label: grafana_dashboard
            labelValue: "1"
            searchNamespace: ALL
            folder: /var/lib/grafana/dashboards/default
            provider:
              name: default
              disableDeletion: false
              allowUiUpdates: false
        dashboards:
          default:
            1860-node-exporter-full:
              gnetId: 1860
              revision: 42
              datasource: VictoriaMetrics
            15757-kubernetes-views-global:
              gnetId: 15757
              revision: 43
              datasource: VictoriaMetrics
            15758-kubernetes-views-namespaces:
              gnetId: 15758
              revision: 44
              datasource: VictoriaMetrics
            15759-kubernetes-views-nodes:
              gnetId: 15759
              revision: 40
              datasource: VictoriaMetrics
            15760-kubernetes-views-pods:
              gnetId: 15760
              revision: 37
              datasource: VictoriaMetrics
            15761-kubernetes-system-api-server:
              gnetId: 15761
              revision: 20
              datasource: VictoriaMetrics
            15762-kubernetes-system-coredns:
              gnetId: 15762
              revision: 22
              datasource: VictoriaMetrics
            20842-cert-manager-kubernetes:
              gnetId: 20842
              revision: 3
              datasource: VictoriaMetrics
            22171-karpenter-overview:
              gnetId: 22171
              revision: 3
              datasource: VictoriaMetrics
            22172-karpenter-activity:
              gnetId: 22172
              revision: 3
              datasource: VictoriaMetrics
            22173-karpenter-performance:
              gnetId: 22173
              revision: 3
              datasource: VictoriaMetrics
            23838-velero-overview:
              gnetId: 23838
              revision: 1
              datasource: VictoriaMetrics
            23969-external-dns:
              gnetId: 23969
              revision: 1
              datasource: VictoriaMetrics
        persistence:
          enabled: false
        grafana.ini:
          analytics:
            check_for_updates: false
          server:
            root_url: https://grafana.${CLUSTER_FQDN}
          auth:
            disable_login_form: true
          auth.google:
            enabled: true
            allow_sign_up: true
            auto_login: true
            scopes: openid email profile
            auth_url: https://accounts.google.com/o/oauth2/v2/auth
            token_url: https://oauth2.googleapis.com/token
            api_url: https://www.googleapis.com/oauth2/v2/userinfo
            client_id: ${GOOGLE_CLIENT_ID}
            client_secret: ${GOOGLE_CLIENT_SECRET}
            allowed_domains: ${MY_EMAIL##*@}
          users:
            auto_assign_org_role: Admin
        ingress:
          enabled: false
        service:
          type: ClusterIP
          port: 80
          targetPort: 3000
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

Wait for monitoring ArgoCD Applications to be healthy:

```bash
kubectl wait --for=condition=Healthy application/victoria-metrics-k8s-stack application/victoria-logs-single application/grafana -n argocd --timeout=600s
```

Configure an [HTTPRoute](https://gateway-api.sigs.k8s.io/concepts/api-overview/#httproute)
to expose Grafana via the Envoy Gateway:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-grafana-httproute.yml" << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: eg
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - grafana.${CLUSTER_FQDN}
  rules:
    - backendRefs:
        - name: grafana
          port: 80
EOF
```

Access Grafana through your browser:

```shell
echo "https://grafana.${CLUSTER_FQDN}"
```

### Envoy Gateway SecurityPolicy

Envoy Gateway's
[SecurityPolicy](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
handles the full OIDC authorization code flow with Google — redirect,
consent, callback, and cookie-based session management — plus JWT-based
authorization to restrict access to a specific email address. No
separate proxy pod is needed.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-envoy-gateway-security-policy.yml" << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: google-oidc-client-secret
  namespace: envoy-gateway-system
type: Opaque
stringData:
  client-secret: "${GOOGLE_CLIENT_SECRET}"
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: google-oidc
  namespace: envoy-gateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: eg
  oidc:
    provider:
      issuer: "https://accounts.google.com"
    clientID: "${GOOGLE_CLIENT_ID}"
    clientSecret:
      name: google-oidc-client-secret
    redirectURL: "https://grafana.${CLUSTER_FQDN}/oauth2/callback"
    scopes:
      - openid
      - email
      - profile
    cookieNames:
      accessToken: oidc-access-token
      idToken: oidc-id-token
    cookieDomain: ".${CLUSTER_FQDN}"
    logoutPath: "/logout"
  jwt:
    providers:
      - name: google
        issuer: "https://accounts.google.com"
        remoteJWKS:
          uri: "https://www.googleapis.com/oauth2/v3/certs"
        extractFrom:
          cookies:
            - oidc-id-token
  authorization:
    defaultAction: Deny
    rules:
      - name: allow-specific-email
        action: Allow
        principal:
          jwt:
            provider: google
            claims:
              - name: email
                values:
                  - "${MY_EMAIL}"
              - name: email_verified
                values:
                  - "true"
EOF
```

```shell
echo "All routes through the Envoy Gateway now require Google authentication"
echo "Only ${MY_EMAIL} is allowed to access the services"
```

### Homepage

![Homepage](https://raw.githubusercontent.com/gethomepage/homepage/e56dccc7f17144a53b97a315c2e4f622fa07e58d/images/banner_light%402x.png){:width="400"}

Install [Homepage](https://gethomepage.dev/) as a unified dashboard for
cluster services:

```bash
# renovate: datasource=helm depName=homepage registryUrl=http://jameswynn.github.io/helm-charts
HOMEPAGE_HELM_CHART_VERSION="2.1.0"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-homepage.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homepage
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  destination:
    namespace: homepage
    server: https://kubernetes.default.svc
  source:
    chart: homepage
    repoURL: http://jameswynn.github.io/helm-charts
    targetRevision: ${HOMEPAGE_HELM_CHART_VERSION}
    helm:
      values: |
        enableRbac: true
        serviceAccount:
          create: true
        ingress:
          main:
            enabled: false
        config:
          bookmarks:
          services:
            - Observability:
                - Grafana:
                    icon: grafana.svg
                    href: https://grafana.${CLUSTER_FQDN}
                    description: Visualization Platform
                    siteMonitor: http://grafana.monitoring.svc:80
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
              Observability:
                icon: mdi-chart-bell-curve-cumulative
              Cluster Management:
                icon: mdi-tools
        env:
          - name: HOMEPAGE_ALLOWED_HOSTS
            value: ${CLUSTER_FQDN}
          - name: LOG_TARGETS
            value: stdout
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
```

```bash
kubectl wait --for=condition=Healthy application/homepage -n argocd --timeout=300s
```

Configure an [HTTPRoute](https://gateway-api.sigs.k8s.io/concepts/api-overview/#httproute)
to expose Homepage via the Envoy Gateway:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-homepage-httproute.yml" << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: homepage
  namespace: homepage
spec:
  parentRefs:
    - name: eg
      namespace: envoy-gateway-system
      sectionName: https-apex
  hostnames:
    - ${CLUSTER_FQDN}
  rules:
    - backendRefs:
        - name: homepage
          port: 3000
EOF
```

Access Homepage through your browser:

```shell
echo "https://${CLUSTER_FQDN}"
```

## Clean-up

![Clean-up](https://raw.githubusercontent.com/cubanpit/cleanupdate/7aaccaa36ab4888a0847b267ed24d079dfed7863/icons/cleanupdate.svg){:width="150"}

Back up the certificate before deleting the cluster (in case it was
renewed):

{% raw %}

```sh
if [[ "$(kubectl get --raw /api/v1/namespaces/cert-manager/services/cert-manager:9402/proxy/metrics | awk '/certmanager_http_acme_client_request_count.*acme-v02\.api.*finalize/ { print $2 }')" -gt 0 ]]; then
  velero backup create --labels letsencrypt=production --ttl 2160h --from-schedule velero-monthly-backup-cert-manager-production
fi
```

{% endraw %}

Remove Homepage HTTPRoute, Envoy Gateway SecurityPolicy, Envoy Gateway
resources, Grafana HTTPRoute, monitoring applications, and stop
Karpenter by deleting the ArgoCD Applications:

```sh
kubectl delete httproute -n homepage homepage || true
kubectl delete httproute -n monitoring grafana || true
kubectl delete securitypolicy -n envoy-gateway-system google-oidc || true
kubectl delete secret -n envoy-gateway-system google-oidc-client-secret || true
kubectl delete gateway -n envoy-gateway-system eg || true
kubectl delete envoyproxy -n envoy-gateway-system aws-nlb || true
kubectl delete application -n argocd homepage grafana victoria-logs-single victoria-metrics-k8s-stack || true
kubectl delete application -n argocd envoy-gateway gateway-api-crds || true
kubectl delete application -n argocd velero external-dns cert-manager aws-load-balancer-controller || true
kubectl delete application -n argocd karpenter || true
```

Remove any remaining EC2 instances provisioned by Karpenter (if they
still exist):

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=tag:karpenter.sh/nodepool,Values=*" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text); do
  echo "Removing Karpenter EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Disassociate a Route 53 Resolver query log configuration from an Amazon
VPC:

```sh
for RESOLVER_QUERY_LOG_CONFIGS_ID in $(aws route53resolver list-resolver-query-log-configs --query "ResolverQueryLogConfigs[?contains(DestinationArn, '/aws/eks/${CLUSTER_NAME}/cluster')].Id" --output text); do
  RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID=$(aws route53resolver list-resolver-query-log-config-associations --filters "Name=ResolverQueryLogConfigId,Values=${RESOLVER_QUERY_LOG_CONFIGS_ID}" --query 'ResolverQueryLogConfigAssociations[].ResourceId' --output text)
  if [[ -n "${RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID}" ]]; then
    aws route53resolver disassociate-resolver-query-log-config --resolver-query-log-config-id "${RESOLVER_QUERY_LOG_CONFIGS_ID}" --resource-id "${RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID}"
    sleep 5
  fi
done
```

Clean up AWS Route 53 Resolver query log configurations:

```sh
for AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID in $(aws route53resolver list-resolver-query-log-configs --query "ResolverQueryLogConfigs[?Name=='${CLUSTER_NAME}-vpc-dns-logs'].Id" --output text); do
  aws route53resolver delete-resolver-query-log-config --resolver-query-log-config-id "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}"
done
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

Remove the IAM Identity Center user (the instance is deleted with
the CloudFormation stack):

```sh
IDC_INSTANCE_ARN=$(
  aws sso-admin list-instances \
    --query "Instances[?Status=='ACTIVE'].InstanceArn | [0]" \
    --output text
)

if [[ -n "${IDC_INSTANCE_ARN}" && "${IDC_INSTANCE_ARN}" != "None" ]]; then
  IDC_IDENTITY_STORE_ID=$(
    aws sso-admin list-instances \
      --query "Instances[?InstanceArn=='${IDC_INSTANCE_ARN}'].IdentityStoreId | [0]" \
      --output text
  )

  IDC_USER_ID=$(
    aws identitystore list-users \
      --identity-store-id "${IDC_IDENTITY_STORE_ID}" \
      --filters "AttributePath=UserName,AttributeValue=argocd-admin" \
      --query "Users[0].UserId" \
      --output text
  )

  if [[ -n "${IDC_USER_ID}" && "${IDC_USER_ID}" != "None" ]]; then
    aws identitystore delete-user \
      --identity-store-id "${IDC_IDENTITY_STORE_ID}" \
      --user-id "${IDC_USER_ID}"
  fi
fi
```

Remove the CloudFormation stacks (this also deletes the IAM Identity
Center instance):

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
  echo "Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done

# Remove EBS snapshots associated with the cluster
for SNAPSHOT in $(aws ec2 describe-snapshots --owner-ids self --filter "Name=tag:Name,Values=${CLUSTER_NAME}-dynamic-snapshot*" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Snapshots[].SnapshotId' --output text); do
  echo "Removing Snapshot: ${SNAPSHOT}"
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
  for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{kubeconfig-${CLUSTER_NAME}.conf,{aws-cf-route53-kms,cloudformation-karpenter,eksctl-${CLUSTER_NAME},k8s-argocd-{aws-load-balancer-controller,cert-manager,external-dns,gateway-api-crds,grafana,homepage,envoy-gateway,karpenter,velero,victoria-logs-single,victoria-metrics-k8s-stack},k8s-{cert-manager-clusterissuer,envoy-gateway-gateway,envoy-gateway-security-policy,grafana-httproute,homepage-httproute,karpenter-nodepool,scheduling-priorityclass,storage-snapshot-storageclass-volumesnapshotclass}}.yml}; do
    if [[ -f "${FILE}" ]]; then
      rm -v "${FILE}"
    else
      echo "File not found: ${FILE}"
    fi
  done
  rmdir "${TMP_DIR}/${CLUSTER_FQDN}"
fi
```

Enjoy ... 😉
