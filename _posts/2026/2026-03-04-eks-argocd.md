---
title: Amazon EKS with Argo CD
author: Petr Ruzicka
date: 2026-03-04
description: Build Amazon EKS with ArgoCD
categories: [Kubernetes, Cloud, Monitoring]
tags: [amazon-eks, argocd, cert-manager, eks, eksctl, grafana, homepage, envoy-gateway, kubernetes, monitoring, velero, victorialogs, victoriametrics]
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
- [ArgoCD](https://argoproj.github.io/cd/) deployed via
  [Helm chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd),
  using Application CRDs for declarative deployments
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
```

If you plan to follow this document and its tasks, you will need to set up
a few environment variables, such as:

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
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"
# Tags used to tag the AWS resources
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev,Cluster=${CLUSTER_FQDN}}"
export AWS_PARTITION="aws"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) && export AWS_ACCOUNT_ID
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
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

### Create Route53 and KMS infrastructure

Generate a CloudFormation template that defines an [Amazon Route 53](https://aws.amazon.com/route53/)
zone and an [AWS Key Management Service (KMS)](https://aws.amazon.com/kms/) key.

Add the new domain `CLUSTER_FQDN` to Route 53, and set up DNS delegation from
the `BASE_DOMAIN`.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 and KMS key

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
EOF

# shellcheck disable=SC2001
eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "BaseDomain=${BASE_DOMAIN} ClusterFQDN=${CLUSTER_FQDN} ClusterName=${CLUSTER_NAME}" \
  --stack-name "${CLUSTER_NAME}-route53-kms" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-cf-route53-kms.yml" --tags "${TAGS//,/ }"

AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-route53-kms" --query "Stacks[0].Outputs[? OutputKey==\`KMSKeyArn\` || OutputKey==\`KMSKeyId\` || OutputKey==\`S3AccessPolicyArn\`].{OutputKey:OutputKey,OutputValue:OutputValue}")
AWS_KMS_KEY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyArn\") .OutputValue")
AWS_KMS_KEY_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"KMSKeyId\") .OutputValue")
AWS_S3_ACCESS_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"S3AccessPolicyArn\") .OutputValue")
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
  region: ${AWS_REGION}
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
    $(echo "${TAGS}" | sed "s/,/\\n    /g; s/=/: /g")
availabilityZones:
  - ${AWS_REGION}a
  - ${AWS_REGION}b
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
iamIdentityMappings:
  - arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
    username: system:node:{{EC2PrivateDNSName}}
    groups:
      - system:bootstrappers
      - system:nodes
addons:
  - name: eks-pod-identity-agent
  - name: snapshot-controller
  - name: aws-ebs-csi-driver
    useDefaultPodIdentityAssociations: true
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
      - ${AWS_REGION}a
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

### ArgoCD

[Argo CD](https://argoproj.github.io/cd/) is a declarative, GitOps
continuous delivery tool for Kubernetes.

![Argo CD](https://raw.githubusercontent.com/argoproj/argo-cd/master/docs/assets/argo.png){:width="200"}

Install the `argo-cd` [Helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify its [default values](https://github.com/argoproj/argo-helm/blob/argo-cd-9.4.12/charts/argo-cd/values.yaml).
The chart is first installed directly via Helm to bootstrap ArgoCD on
the cluster. After Envoy Gateway is deployed (providing the Gateway API
CRDs), ArgoCD takes over managing itself through an Application CRD
([Manage Argo CD Using Argo CD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#manage-argo-cd-using-argo-cd))
that also configures an
[HTTPRoute](https://gateway-api.sigs.k8s.io/concepts/api-overview/#httproute)
to expose the ArgoCD UI:

```bash
# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
ARGOCD_HELM_CHART_VERSION="9.5.13"

helm repo add --force-update argo https://argoproj.github.io/argo-helm
helm upgrade --install --version "${ARGOCD_HELM_CHART_VERSION}" --namespace argocd --create-namespace --wait argo-cd argo/argo-cd
```

### Prometheus Operator CRDs

[Prometheus Operator CRDs](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds)
provides the Custom Resource Definitions (CRDs) that define the Prometheus
operator resources. These CRDs are required before installing ServiceMonitor
resources.

Install the `prometheus-operator-crds`
[Helm chart](https://github.com/prometheus-community/helm-charts/tree/prometheus-operator-crds-28.0.0/charts/prometheus-operator-crds)
to set up the necessary CRDs:

```bash
# renovate: datasource=docker depName=prometheus-community/charts/prometheus-operator-crds registryUrl=https://ghcr.io
PROMETHEUS_OPERATOR_CRDS_HELM_CHART_VERSION="28.0.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-prometheus-operator-crds.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-operator-crds
  namespace: argocd
spec:
  project: default
  destination:
    namespace: kube-system
    server: https://kubernetes.default.svc
  source:
    chart: prometheus-operator-crds
    repoURL: ghcr.io/prometheus-community/charts
    targetRevision: ${PROMETHEUS_OPERATOR_CRDS_HELM_CHART_VERSION}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - Replace=true
EOF
```

Wait for the Prometheus Operator CRDs ArgoCD Application
to be healthy and synced:

```bash
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/prometheus-operator-crds -n argocd --timeout=300s
```

### Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) is an implementation of
the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) built on
[Envoy Proxy](https://www.envoyproxy.io/) that provides advanced traffic
management, OIDC authentication, and JWT-based authorization.

![Envoy Gateway](https://raw.githubusercontent.com/cncf/artwork/main/projects/envoy/envoy-gateway/icon/color/envoy-gateway-icon-color.svg){:width="250"}

Install Envoy Gateway using an ArgoCD
[Application](https://gateway.envoyproxy.io/docs/install/install-argocd/)
CRD. `ServerSideApply` avoids the 262,144-byte annotation size
limit, and `CreateNamespace` ensures the target namespace exists:

```bash
# renovate: datasource=docker depName=envoyproxy/gateway-helm registryUrl=https://docker.io
ENVOY_GATEWAY_HELM_CHART_VERSION="1.7.3"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-envoy-gateway.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: envoy-gateway
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: gateway-helm
    repoURL: docker.io/envoyproxy
    targetRevision: ${ENVOY_GATEWAY_HELM_CHART_VERSION}
    helm:
      values: |
        deployment:
          priorityClassName: critical-priority
  destination:
    namespace: envoy-gateway-system
    server: https://kubernetes.default.svc
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    automated:
      prune: true
      selfHeal: true
EOF
```

Wait for the Envoy Gateway ArgoCD Application to be healthy:

```bash
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/envoy-gateway -n argocd --timeout=300s
```

The Helm chart creates the
[GatewayClass](https://gateway-api.sigs.k8s.io/concepts/api-overview/#gatewayclass)
via a `certgen` pre-install hook, but ArgoCD's auto-prune can
remove hook-created resources that are not part of the tracked
manifests. Following the [official guide](https://gateway.envoyproxy.io/docs/install/install-argocd/),
apply the GatewayClass explicitly alongside the [EnvoyProxy](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/),
[Gateway](https://gateway-api.sigs.k8s.io/concepts/api-overview/#gateway),
and [SecurityPolicy](https://gateway.envoyproxy.io/docs/tasks/security/oidc/)
resources. The SecurityPolicy handles the full OIDC authorization
code flow with Google — redirect, consent, callback, and cookie-based session
management — plus JWT-based authorization to restrict access to a specific email
address. No separate proxy pod is needed.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-envoy-gateway-gateway.yml" << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
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
          - name: cert-production
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
          - name: cert-production
            namespace: cert-manager
      allowedRoutes:
        namespaces:
          from: All
---
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
    cookieDomain: "${CLUSTER_FQDN}"
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

All routes through the Envoy Gateway now require Google authentication.
Only `${MY_EMAIL}` is allowed to access the services.

Now that the Gateway API CRDs are available, create an ArgoCD
Application to let ArgoCD manage itself. The `server.httproute`
section configures an
[HTTPRoute](https://gateway-api.sigs.k8s.io/concepts/api-overview/#httproute)
to expose the ArgoCD UI via the Envoy Gateway:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-argo-cd.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-cd
  namespace: argocd
spec:
  project: default
  destination:
    namespace: argocd
    server: https://kubernetes.default.svc
  source:
    chart: argo-cd
    repoURL: https://argoproj.github.io/argo-helm
    targetRevision: ${ARGOCD_HELM_CHART_VERSION}
    helm:
      values: |
        global:
          priorityClassName: critical-priority
        configs:
          params:
            server.insecure: true
        controller:
          metrics:
            enabled: true
            serviceMonitor:
              enabled: true
        server:
          httproute:
            enabled: true
            parentRefs:
              - name: eg
                namespace: envoy-gateway-system
                sectionName: https
            hostnames:
              - argocd.${CLUSTER_FQDN}
          metrics:
            enabled: true
            serviceMonitor:
              enabled: true
        repoServer:
          metrics:
            enabled: true
            serviceMonitor:
              enabled: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF
```

Remove the initial Helm release secret so that only ArgoCD manages
itself going forward (the bootstrap release is no longer needed):

```bash
kubectl delete secret -n argocd -l owner=helm,name=argo-cd
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
KARPENTER_HELM_CHART_VERSION="1.12.0"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-karpenter.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: karpenter
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
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
        serviceMonitor:
          enabled: true
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
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/karpenter -n argocd --timeout=300s
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
          values: ["${AWS_REGION}a"]
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

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters and simplifies the process of
obtaining, renewing, and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="150"}

Install the `cert-manager` [Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
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
        prometheus:
          enabled: true
          servicemonitor:
            enabled: true
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
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/cert-manager -n argocd --timeout=300s
```

### Generate a Let's Encrypt production certificate

<!-- prettier-ignore-start -->
> These steps only need to be performed once.
{: .prompt-info }
<!-- prettier-ignore-end -->

Production-ready Let's Encrypt certificates should generally be generated only
once. The goal is to back up the certificate and then restore it whenever
needed for a new cluster.

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

Create a new certificate and have it signed by Let's Encrypt for validation:

```bash
if ! aws s3 ls "s3://${CLUSTER_FQDN}/velero/backups/" | grep -q velero-monthly-backup-cert-manager-production; then
  tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-cert-manager-certificate-production.yml" << EOF | kubectl apply -f -
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: cert-production
    namespace: cert-manager
    labels:
      letsencrypt: production
  spec:
    secretName: cert-production
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
  kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate cert-production
fi
```

### Create S3 bucket

<!-- prettier-ignore-start -->
> The following step needs to be performed only once.
{: .prompt-info }
<!-- prettier-ignore-end -->

Use CloudFormation to create an S3 bucket that will be used for storing Velero
backups.

```bash
if ! aws s3 ls "s3://${CLUSTER_FQDN}"; then
  cat > "${TMP_DIR}/${CLUSTER_FQDN}/aws-s3.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09

Parameters:
  S3BucketName:
    Description: Name of the S3 bucket
    Type: String
  EmailToSubscribe:
    Description: Confirm subscription over email to receive a copy of S3 events
    Type: String

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref S3BucketName
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      LifecycleConfiguration:
        Rules:
          # Transitions objects to the ONEZONE_IA storage class after 30 days
          - Id: TransitionToOneZoneIA
            Status: Enabled
            Transitions:
              - TransitionInDays: 30
                StorageClass: STANDARD_IA
          - Id: DeleteOldObjects
            Status: Enabled
            ExpirationInDays: 120
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: alias/aws/s3
  S3BucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref S3Bucket
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          # S3 Bucket policy force HTTPs requests
          - Sid: ForceSSLOnlyAccess
            Effect: Deny
            Principal: "*"
            Action: s3:*
            Resource:
              - !GetAtt S3Bucket.Arn
              - !Sub ${S3Bucket.Arn}/*
            Condition:
              Bool:
                aws:SecureTransport: "false"
  S3Policy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${S3BucketName}-s3"
      Description: !Sub "Policy required by Velero to write to S3 bucket ${S3BucketName}"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
        - Effect: Allow
          Action:
          - s3:ListBucket
          - s3:GetBucketLocation
          - s3:ListBucketMultipartUploads
          Resource: !GetAtt S3Bucket.Arn
        - Effect: Allow
          Action:
          - s3:PutObject
          - s3:GetObject
          - s3:DeleteObject
          - s3:ListMultipartUploadParts
          - s3:AbortMultipartUpload
          Resource: !Sub "arn:aws:s3:::${S3BucketName}/*"
        # S3 Bucket policy does not deny HTTP requests
        - Sid: ForceSSLOnlyAccess
          Effect: Deny
          Action: "s3:*"
          Resource:
            - !Sub "arn:${AWS::Partition}:s3:::${S3Bucket}"
            - !Sub "arn:${AWS::Partition}:s3:::${S3Bucket}/*"
          Condition:
            Bool:
              aws:SecureTransport: "false"
Outputs:
  S3PolicyArn:
    Description: The ARN of the created Amazon S3 policy
    Value: !Ref S3Policy
  S3Bucket:
    Description: The name of the created Amazon S3 bucket
    Value: !Ref S3Bucket
EOF

  eval aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides S3BucketName="${CLUSTER_FQDN}" EmailToSubscribe="${MY_EMAIL}" \
    --stack-name "${CLUSTER_NAME}-s3" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-s3.yml" --tags "${TAGS//,/ }"
fi
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
VELERO_HELM_CHART_VERSION="12.0.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-velero.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: velero
  namespace: argocd
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
            image: velero/velero-plugin-for-aws:v1.14.0
            volumeMounts:
              - mountPath: /target
                name: plugins
        priorityClassName: high-priority
        metrics:
          serviceMonitor:
            enabled: true
        configuration:
          backupStorageLocation:
            - name:
              provider: aws
              bucket: ${CLUSTER_FQDN}
              prefix: velero
              config:
                region: ${AWS_REGION}
          volumeSnapshotLocation:
            - name:
              provider: aws
              config:
                region: ${AWS_REGION}
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
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/velero -n argocd --timeout=300s
```

Wait for Velero to sync with the S3 bucket and be ready for backup and restore
operations:

```bash
while [ -z "$(kubectl -n velero get backupstoragelocations default -o jsonpath='{.status.lastSyncedTime}')" ]; do sleep 5; done
```

Initiate the restore process for the cert-manager objects if the backup exists
in the S3 bucket:

```bash
if aws s3 ls "s3://${CLUSTER_FQDN}/velero/backups/" | grep -q velero-monthly-backup-cert-manager-production; then
  velero restore create --from-schedule velero-monthly-backup-cert-manager-production --labels letsencrypt=production --wait --existing-resource-policy=update
fi
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
EXTERNAL_DNS_HELM_CHART_VERSION="1.21.1"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-external-dns.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-dns
  namespace: argocd
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
        serviceMonitor:
          enabled: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

### victoria-metrics-k8s-stack

[![victoria-metrics-k8s-stack](https://raw.githubusercontent.com/VictoriaMetrics/VictoriaMetrics/master/docs/victoriametrics/logo.webp){:width="200"}](https://victoriametrics.com/)

Install [victoria-metrics-k8s-stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/)
which provides a full monitoring stack with [VictoriaMetrics](https://victoriametrics.com/)
components: VMSingle for metrics storage, VMAgent for scraping,
VMAlert for alerting rules, the VictoriaMetrics Operator with
CRDs (VMServiceScrape, VMPodScrape, VMRule, etc.), and
[Grafana](https://grafana.com/) with preconfigured
[VictoriaMetrics](https://victoriametrics.com/) and
[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/)
datasources. The
[victoriametrics-metrics-datasource](https://grafana.com/grafana/plugins/victoriametrics-metrics-datasource/)
and
[victoriametrics-logs-datasource](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/)
Grafana plugins are required for the native VictoriaMetrics
and VictoriaLogs datasource types:

```bash
# renovate: datasource=helm depName=victoria-metrics-k8s-stack registryUrl=https://victoriametrics.github.io/helm-charts
VICTORIA_METRICS_K8S_STACK_HELM_CHART_VERSION="0.77.0"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-victoria-metrics-k8s-stack.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-metrics-k8s-stack
  namespace: argocd
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
          enabled: true
          # Disable Grafana's secret leak detection for values
          # with Google OIDC client_secret set explicitly
          assertNoLeakedSecrets: false
          plugins:
            - victoriametrics-logs-datasource
            - victoriametrics-metrics-datasource
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
              enabled: false
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
          serviceMonitor:
            enabled: true
          ingress:
            enabled: false
          service:
            type: ClusterIP
            port: 80
            targetPort: 3000
        defaultDatasources:
          victoriametrics:
            datasources:
              - name: VictoriaMetrics
                type: prometheus
                access: proxy
                isDefault: true
                uid: victoriametrics
                jsonData:
                  httpMethod: POST
                  timeInterval: "30s"
              - name: VictoriaMetrics (DS)
                isDefault: false
                access: proxy
                type: victoriametrics-metrics-datasource
          extra:
            - name: VictoriaLogs
              type: victoriametrics-logs-datasource
              uid: victorialogs
              access: proxy
              url: http://victoria-logs-single-server.monitoring.svc:9428
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
VICTORIA_LOGS_SINGLE_HELM_CHART_VERSION="0.12.4"

tee "${TMP_DIR}/${CLUSTER_FQDN}/k8s-argocd-victoria-logs-single.yml" << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-logs-single
  namespace: argocd
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

Wait for monitoring ArgoCD Applications to be healthy:

```bash
kubectl wait --for='jsonpath={.status.health.status}=Healthy' --for='jsonpath={.status.sync.status}=Synced' application/victoria-metrics-k8s-stack application/victoria-logs-single -n argocd --timeout=600s
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
        - name: victoria-metrics-k8s-stack-grafana
          port: 80
EOF
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
                    siteMonitor: http://victoria-metrics-k8s-stack-grafana.monitoring.svc:80
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

## Clean-up

![Clean-up](https://raw.githubusercontent.com/cubanpit/cleanupdate/7aaccaa36ab4888a0847b267ed24d079dfed7863/icons/cleanupdate.svg){:width="150"}

Stop Karpenter from launching additional nodes and remove
Envoy Gateway to release the AWS Load Balancer:

```sh
kubectl delete application -n argocd karpenter envoy-gateway || true
kubectl wait --for=delete application/karpenter application/envoy-gateway -n argocd --timeout=300s 2>/dev/null || true
kubectl get pods -n karpenter || true
```

Back up the certificate before deleting the cluster (in case it was
renewed):

{% raw %}

```sh
if [[ "$(kubectl get --raw /api/v1/namespaces/cert-manager/services/cert-manager:9402/proxy/metrics | awk '/certmanager_http_acme_client_request_count.*acme-v02\.api.*finalize/ { print $2 }')" -gt 0 ]]; then
  velero backup create --labels letsencrypt=production --ttl 2160h --from-schedule velero-monthly-backup-cert-manager-production
fi
```

{% endraw %}

Disassociate a Route 53 Resolver query log configuration from an Amazon
VPC:

```sh
for RESOLVER_QUERY_LOG_CONFIGS_ID in $(aws route53resolver list-resolver-query-log-configs --query "ResolverQueryLogConfigs[?contains(DestinationArn, '/aws/eks/${CLUSTER_NAME}/cluster')].Id" --output text); do
  RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID=$(aws route53resolver list-resolver-query-log-config-associations --filters "Name=ResolverQueryLogConfigId,Values=${RESOLVER_QUERY_LOG_CONFIGS_ID}" --query 'ResolverQueryLogConfigAssociations[].ResourceId' --output text)
  if [[ -n "${RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID}" ]]; then
    echo "*** Disassociating Resolver query log config: ${RESOLVER_QUERY_LOG_CONFIGS_ID} from resource: ${RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID}"
    aws route53resolver disassociate-resolver-query-log-config --resolver-query-log-config-id "${RESOLVER_QUERY_LOG_CONFIGS_ID}" --resource-id "${RESOLVER_QUERY_LOG_CONFIG_ASSOCIATIONS_RESOURCEID}"
    sleep 5
  fi
done
```

Clean up AWS Route 53 Resolver query log configurations:

```sh
for AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID in $(aws route53resolver list-resolver-query-log-configs --query "ResolverQueryLogConfigs[?Name=='${CLUSTER_NAME}-vpc-dns-logs'].Id" --output text); do
  echo "*** Removing Route 53 Resolver query log config: ${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}"
  aws route53resolver delete-resolver-query-log-config --resolver-query-log-config-id "${AWS_CLUSTER_ROUTE53_RESOLVER_QUERY_LOG_CONFIG_ID}"
done
```

Remove any remaining EC2 instances provisioned by Karpenter (if they
still exist):

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=tag:karpenter.sh/nodepool,Values=*" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text); do
  echo "*** Removing Karpenter EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
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
  echo "*** Removing Route 53 DNS records from zone: ${CLUSTER_FQDN_ZONE_ID}"
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
    echo "*** Removing instance profile: ${AWS_INSTANCE_PROFILES_FOR_ROLE} from role: KarpenterNodeRole-${CLUSTER_NAME}"
    aws iam remove-role-from-instance-profile --instance-profile-name "${AWS_INSTANCE_PROFILES_FOR_ROLE}" --role-name "KarpenterNodeRole-${CLUSTER_NAME}"
    aws iam delete-instance-profile --instance-profile-name "${AWS_INSTANCE_PROFILES_FOR_ROLE}"
  fi
fi
```

Remove the CloudFormation stacks:

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
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done

# Remove EBS snapshots associated with the cluster
for SNAPSHOT in $(aws ec2 describe-snapshots --owner-ids self --filter "Name=tag:Name,Values=${CLUSTER_NAME}-dynamic-snapshot*" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Snapshots[].SnapshotId' --output text); do
  echo "*** Removing Snapshot: ${SNAPSHOT}"
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
done
```

Remove the CloudWatch log group:

```sh
if [[ "$(aws logs describe-log-groups --query "logGroups[?logGroupName==\`/aws/eks/${CLUSTER_NAME}/cluster\`] | [0].logGroupName" --output text)" = "/aws/eks/${CLUSTER_NAME}/cluster" ]]; then
  echo "*** Removing CloudWatch log group: /aws/eks/${CLUSTER_NAME}/cluster"
  aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
fi
```

Remove the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
if [[ -d "${TMP_DIR}/${CLUSTER_FQDN}" ]]; then
  for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{kubeconfig-${CLUSTER_NAME}.conf,{aws-cf-route53-kms,aws-s3,cloudformation-karpenter,eksctl-${CLUSTER_NAME},k8s-argocd-{argo-cd,cert-manager,external-dns,homepage,envoy-gateway,karpenter,prometheus-operator-crds,velero,victoria-logs-single,victoria-metrics-k8s-stack},k8s-{cert-manager-certificate-production,cert-manager-clusterissuer-production,envoy-gateway-gateway,grafana-httproute,homepage-httproute,karpenter-nodepool,scheduling-priorityclass,storage-snapshot-storageclass-volumesnapshotclass}}.yml}; do
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
