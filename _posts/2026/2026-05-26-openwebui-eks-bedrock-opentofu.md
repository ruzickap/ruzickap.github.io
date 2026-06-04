---
title: Amazon EKS with Open WebUI and AWS Bedrock managed by OpenTofu
author: Petr Ruzicka
date: 2026-05-26
description: Deploy Open WebUI on Amazon EKS with AWS Bedrock as the LLM backend, provisioned with OpenTofu
categories: [Kubernetes, Cloud, Monitoring]
tags: [amazon-eks, amazon-bedrock, litellm, cert-manager, envoy-gateway, kubernetes, open-webui, opentofu, velero]
image: https://raw.githubusercontent.com/open-webui/open-webui/14a6c1f4963892c163821765efcc10c5c4578454/static/static/favicon.svg
---

I will outline the steps for setting up an [Amazon EKS](https://aws.amazon.com/eks/)
environment that hosts [Open WebUI](https://openwebui.com/) backed by
[AWS Bedrock](https://aws.amazon.com/bedrock/) as the LLM provider. All
infrastructure - from the VPC up to the Helm releases - is provisioned by
[OpenTofu](https://opentofu.org/) using widely adopted community modules
([terraform-aws-modules](https://github.com/terraform-aws-modules)) and the
official [`hashicorp/helm`](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
provider for chart installations.

The setup should align with the following criteria:

- Utilize two Availability Zones (AZs) to reduce cross-AZ traffic costs
- Spot instances
- Less expensive region - `us-east-1`
- Most price-efficient EC2 instance type `t4g.medium` (2 x CPU, 4GB RAM) using
  [AWS Graviton](https://aws.amazon.com/ec2/graviton/) based on ARM
- [Bottlerocket OS](https://github.com/bottlerocket-os/bottlerocket) for the
  worker nodes
- [Network Load Balancer (NLB)](https://aws.amazon.com/elasticloadbalancing/network-load-balancer/)
  for highly cost-effective and optimized load balancing
- [Karpenter](https://karpenter.sh/) for automatic node scaling
- The Amazon EKS control plane must be [encrypted using KMS](https://docs.aws.amazon.com/eks/latest/userguide/enable-kms.html)
- Worker node [EBS volumes must be encrypted](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-encryption.html)
- [EKS cluster logging](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)
  to [CloudWatch](https://aws.amazon.com/cloudwatch/) must be configured
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
  should be enabled
- [EKS Pod Identities](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
  for AWS API access (including [AWS Bedrock](https://aws.amazon.com/bedrock/))
- [OpenTofu](https://opentofu.org/) drives the full stack via the
  [`terraform-aws-modules`](https://github.com/terraform-aws-modules) collection
  and [`helm_release`](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release)
  for every chart installation
- [Envoy Gateway](https://gateway.envoyproxy.io/) as the Gateway API
  implementation with OIDC authentication and JWT-based authorization
  via Google for protecting web endpoints
- [LiteLLM](https://github.com/BerriAI/litellm) providing an
  OpenAI-compatible API over [AWS Bedrock](https://aws.amazon.com/bedrock/)
  with inline guardrail enforcement and SigV4
  credential injection via EKS Pod Identity
- [Open WebUI](https://openwebui.com/) as the chat front-end consuming the
  Envoy AI Gateway endpoint

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
# Google OIDC credentials used by Envoy Gateway for authentication
export TF_VAR_google_client_id="${GOOGLE_CLIENT_ID}"
export TF_VAR_google_client_secret="${GOOGLE_CLIENT_SECRET}"

# AWS Region
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k02.k8s.mylabs.dev}"
# OpenTofu variables
export TF_VAR_cluster_fqdn="${CLUSTER_FQDN}"
export TF_VAR_my_email="${TF_VAR_my_email:-petr.ruzicka@gmail.com}"
# Derived shell variables
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
cd "${TMP_DIR}/${CLUSTER_FQDN}" || exit
```

Install the required tools:

<!-- prettier-ignore-start -->
> You can bypass these procedures if you already have all the essential
> software installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [OpenTofu](https://opentofu.org/)
- [AWS CLI](https://builder.aws.com/build/tools)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)

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

Utilize your domain registrar to update the nameservers for your zone
(e.g., `mylabs.dev`) to point to Amazon Route 53 nameservers. Discover the
required Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Establish the NS record in `k8s.mylabs.dev` (your `BASE_DOMAIN`) for proper
zone delegation. I use Cloudflare and employ Ansible for automation:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

Create the EC2 Spot service-linked role if it does not yet exist in this account
(it is a one-time, account-wide resource):

```shell
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2> /dev/null || true
```

### Create S3 bucket for Amazon EKS backups and Tofu state

Create an S3 bucket to store Amazon EKS backups and OpenTofu remote state
using CloudFormation. The bucket uses KMS encryption, lifecycle policies, and
blocks all public access:

```bash
if ! aws s3api head-bucket --bucket "${CLUSTER_FQDN}" 2> /dev/null; then
  tee "${TMP_DIR}/${CLUSTER_FQDN}/s3.yaml" << \EOF
AWSTemplateFormatVersion: "2010-09-09"
Description: S3 bucket for Amazon EKS backups and OpenTofu state files
Parameters:
  Name:
    Description: Name of the S3 bucket
    Type: String
Resources:
  ClusterS3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref Name
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      LifecycleConfiguration:
        Rules:
          - Id: MultipartUploadLifecycleRule
            Status: Enabled
            AbortIncompleteMultipartUpload:
              DaysAfterInitiation: 1
          - Id: VeleroExpiration
            Status: Enabled
            Prefix: velero/
            ExpirationInDays: 120
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: alias/aws/s3
  ClusterS3BucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref ClusterS3Bucket
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Sid: ForceSSLOnlyAccess
            Effect: Deny
            Principal: "*"
            Action: s3:*
            Resource:
              - !GetAtt ClusterS3Bucket.Arn
              - !Sub ${ClusterS3Bucket.Arn}/*
            Condition:
              Bool:
                aws:SecureTransport: "false"
Outputs:
  ClusterS3Bucket:
    Value: !Ref ClusterS3Bucket
EOF

  aws cloudformation deploy --region "${AWS_REGION}" \
    --stack-name "${CLUSTER_FQDN//./-}-s3" \
    --tags "Owner=${TF_VAR_my_email}" "Environment=dev" "Cluster=${CLUSTER_FQDN}" \
    --parameter-overrides "Name=${CLUSTER_FQDN}" \
    --template-file "${TMP_DIR}/${CLUSTER_FQDN}/s3.yaml"
fi
```

## OpenTofu Code

All resources from this point onwards are managed by [OpenTofu](https://opentofu.org/).
Create the working directory and the main configuration file with provider
versions, backend, and provider settings:

![OpenTofu](https://raw.githubusercontent.com/opentofu/brand-artifacts/af744ad2e454fc47cc7d3c6399aaac15c5c0eeac/full/transparent/SVG/on-dark.svg){:width="400"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/main.tf" << EOF
terraform {
  required_version = ">= 1.12.0"

  backend "s3" {
    bucket       = "${CLUSTER_FQDN}"
    key          = "terraform.tfstate"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # renovate: datasource=terraform-provider depName=hashicorp/aws
      version = "6.47.0"
    }
    helm = {
      source  = "hashicorp/helm"
      # renovate: datasource=terraform-provider depName=hashicorp/helm
      version = "3.1.2"
    }
    kubectl = {
      source  = "alekc/kubectl"
      # renovate: datasource=terraform-provider depName=alekc/kubectl
      version = "2.4.1"
    }
    random = {
      source  = "hashicorp/random"
      # renovate: datasource=terraform-provider depName=hashicorp/random
      version = "3.7.2"
    }
  }
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  lazy_load              = true
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  cluster_name = split(".", var.cluster_fqdn)[0]
  base_domain  = join(".", slice(split(".", var.cluster_fqdn), 1, length(split(".", var.cluster_fqdn))))
  tags = {
    Owner       = var.my_email
    Environment = "dev"
    Cluster     = var.cluster_fqdn
    Managed-by  = "opentofu"
  }
}
EOF
```

Define the input variables. Values are provided via `TF_VAR_` environment
variables — no defaults are baked into the configuration:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/variables.tf" << \EOF
variable "cluster_fqdn" {
  description = "FQDN of the EKS cluster (e.g. k01.k8s.mylabs.dev)"
  type        = string
}

variable "my_email" {
  description = "Email address used for tagging and Let's Encrypt registration"
  type        = string
}

variable "google_client_id" {
  description = "Google OAuth Client ID for OIDC authentication"
  type        = string
}

variable "google_client_secret" {
  description = "Google OAuth Client Secret for OIDC authentication"
  type        = string
  sensitive   = true
}
EOF
```

### Route53 and KMS key

Use the [`terraform-aws-modules`](https://github.com/terraform-aws-modules)
collection to provision the Route 53 hosted zone for `${CLUSTER_FQDN}`,
delegate it from the parent zone, and create the KMS key for EKS secrets and
EBS volume encryption:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/infra-aws.tf" << \EOF
data "aws_route53_zone" "base" {
  name         = "${local.base_domain}."
  private_zone = false
}

data "aws_s3_objects" "velero_backup" {
  bucket   = var.cluster_fqdn
  prefix   = "velero/backups/cert-manager-production"
  max_keys = 1
}

module "route53_zone" {
  source        = "terraform-aws-modules/route53/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/route53/aws
  version       = "6.5.0"
  name          = var.cluster_fqdn
  force_destroy = true
}

resource "aws_route53_record" "ns_delegation" {
  zone_id = data.aws_route53_zone.base.zone_id
  name    = var.cluster_fqdn
  type    = "NS"
  ttl     = 60
  records = module.route53_zone.name_servers
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/kms/aws
  version = "4.2.0"

  description             = "KMS key for ${local.cluster_name} Amazon EKS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  aliases                 = ["eks-${local.cluster_name}"]

  key_statements = [
    {
      sid = "AllowEBSEncryptionViaEC2Service"
      principals = [{ type = "AWS", identifiers = ["*"] }]
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey",
      ]
      resources = ["*"]
      condition = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["ec2.${data.aws_region.current.region}.amazonaws.com"]
        },
        {
          test     = "StringEquals"
          variable = "kms:CallerAccount"
          values   = [data.aws_caller_identity.current.account_id]
        },
      ]
    },
    {
      sid = "AllowCloudWatchLogs"
      principals = [{ type = "Service", identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"] }]
      actions = [
        "kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:Describe*",
      ]
      resources = ["*"]
      condition = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
      }]
    },
  ]
}
EOF
```

### Amazon Bedrock

<!-- prettier-ignore-start -->
> Enabling Bedrock foundation models is a one-time operation per account/region.
> Use the [Bedrock console](https://console.aws.amazon.com/bedrock) to opt in
> to the models you intend to use (Anthropic Claude, Meta Llama, Mistral, …).
{: .prompt-info }
<!-- prettier-ignore-end -->

![Amazon Bedrock](https://raw.githubusercontent.com/aws-samples/generative-ai-demo-on-miro/c9ee08f37aea1fd0f2f48e46f4ae1a21e3bae2a7/frontend/src/assets/bedrocklogo.svg){:width="200"}

Enable model invocation logging so every Bedrock request is captured in
CloudWatch, and define a guardrail that the IAM policy will reference to
enforce guardrail usage. An IAM role is required to allow Bedrock to write
log events to the log group:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/bedrock.tf" << \EOF
# resource "aws_cloudwatch_log_group" "bedrock" {
#   name              = "/aws/bedrock/${local.cluster_name}"
#   retention_in_days = 1
#   kms_key_id        = module.kms.key_arn
# }
#
# data "aws_iam_policy_document" "bedrock_logging_trust" {
#   statement {
#     principals {
#       type        = "Service"
#       identifiers = ["bedrock.amazonaws.com"]
#     }
#     actions = ["sts:AssumeRole"]
#     condition {
#       test     = "StringEquals"
#       variable = "aws:SourceAccount"
#       values   = [data.aws_caller_identity.current.account_id]
#     }
#   }
# }
#
# data "aws_iam_policy_document" "bedrock_logging" {
#   statement {
#     actions = [
#       "logs:CreateLogStream",
#       "logs:PutLogEvents",
#     ]
#     resources = ["${aws_cloudwatch_log_group.bedrock.arn}:*"]
#   }
# }
#
# resource "aws_iam_role" "bedrock_logging" {
#   name               = "${local.cluster_name}-bedrock-logging"
#   assume_role_policy = data.aws_iam_policy_document.bedrock_logging_trust.json
# }
#
# resource "aws_iam_role_policy" "bedrock_logging" {
#   name   = "${local.cluster_name}-bedrock-logging"
#   role   = aws_iam_role.bedrock_logging.id
#   policy = data.aws_iam_policy_document.bedrock_logging.json
# }
#
# resource "aws_bedrock_model_invocation_logging_configuration" "this" {
#   logging_config {
#     cloudwatch_config {
#       log_group_name = aws_cloudwatch_log_group.bedrock.name
#       role_arn       = aws_iam_role.bedrock_logging.arn
#     }
#     embedding_data_delivery_enabled = true
#     image_data_delivery_enabled     = true
#     text_data_delivery_enabled      = true
#   }
# }
#
resource "aws_bedrock_guardrail" "ai_safety" {
  name                      = "${local.cluster_name}-ai-safety"
  description               = "Guardrail for AI model safety and compliance"
  blocked_input_messaging   = "Your request contains content that violates our AI usage policy."
  blocked_outputs_messaging = "The AI response was blocked due to policy violations."

  content_policy_config {
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }
}
EOF
```

### Amazon EKS

Provision the cluster with
[`terraform-aws-modules/eks/aws`](https://github.com/terraform-aws-modules/terraform-aws-eks).
The module wires up the OIDC provider, addons, EKS managed node group (with
Bottlerocket on Graviton), and the Pod Identity associations consumed by the
addons further down the page.

![terraform-aws-modules/eks](https://raw.githubusercontent.com/terraform-aws-modules/terraform-aws-eks/7cd3be3fbbb695105a447b37c4653a00b0b51b94/docs/assets/logo.png){:width="150"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eks.tf" << \EOF
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/vpc/aws
  version = "6.6.1"

  name = local.cluster_name
  cidr = "192.168.0.0/16"

  azs             = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}b"]
  private_subnets = ["192.168.0.0/19", "192.168.32.0/19"]
  public_subnets  = ["192.168.64.0/19", "192.168.96.0/19"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  manage_default_network_acl = true
  default_network_acl_ingress = [
    {
      rule_no    = 89
      action     = "deny"
      from_port  = 22
      to_port    = 22
      protocol   = "tcp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 90
      action     = "deny"
      from_port  = 3389
      to_port    = 3389
      protocol   = "tcp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 443
      to_port    = 443
      protocol   = "tcp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 110
      action     = "allow"
      from_port  = 1024
      to_port    = 65535
      protocol   = "tcp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 120
      action     = "allow"
      from_port  = 53
      to_port    = 53
      protocol   = "udp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 130
      action     = "allow"
      from_port  = 123
      to_port    = 123
      protocol   = "udp"
      cidr_block = "0.0.0.0/0"
    },
    {
      rule_no    = 140
      action     = "allow"
      from_port  = 1024
      to_port    = 65535
      protocol   = "udp"
      cidr_block = "0.0.0.0/0"
    },
  ]

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.cluster_name
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks/aws
  version = "21.23.0"

  name                   = local.cluster_name
  kubernetes_version     = "1.35"
  endpoint_public_access = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  create_kms_key    = false
  encryption_config = {
    provider_key_arn = module.kms.key_arn
    resources        = ["secrets"]
  }

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
    snapshot-controller    = {}
    aws-ebs-csi-driver = {
      configuration_values = jsonencode({
        defaultStorageClass = { enabled = false }
        controller          = { loggingFormat = "json" }
      })
    }
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env                 = { ENABLE_PREFIX_DELEGATION = "true" }
      })
    }
  }

  eks_managed_node_groups = {
    mng01 = {
      name           = "${local.cluster_name}-mng01"
      ami_type       = "BOTTLEROCKET_ARM_64"
      instance_types = ["t4g.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      subnet_ids     = [module.vpc.private_subnets[0]]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 2
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = module.kms.key_arn
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = module.kms.key_arn
            delete_on_termination = true
          }
        }
      }

      labels = { "node.kubernetes.io/lifecycle" = "on-demand" }
    }
  }

  cloudwatch_log_group_retention_in_days = 1
  cloudwatch_log_group_kms_key_id        = module.kms.key_arn
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  node_security_group_additional_rules = {
    ingress_self_443 = {
      description = "Node to node HTTPS (webhooks, metrics-server, etc.)"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      self        = true
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                      = "${local.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = [module.kms.key_arn]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

# Custom gp3 StorageClass with KMS encryption replaces the default gp2 class. The EBS CSI addon has defaultStorageClass disabled so this takes precedence.
resource "kubectl_manifest" "gp3" {
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: "true"
    provisioner: ebs.csi.aws.com
    reclaimPolicy: Delete
    allowVolumeExpansion: true
    volumeBindingMode: WaitForFirstConsumer
    parameters:
      type: gp3
      encrypted: "true"
      kmsKeyId: ${module.kms.key_arn}
  YAML
  depends_on = [module.eks]
}

# Default VolumeSnapshotClass for the EBS CSI driver, required by Velero to create EBS snapshots when backing up PersistentVolumes.
resource "kubectl_manifest" "vsc_ebs" {
  yaml_body = <<-YAML
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: ebs-vsc
      annotations:
        snapshot.storage.kubernetes.io/is-default-class: "true"
    driver: ebs.csi.aws.com
    deletionPolicy: Delete
  YAML
  depends_on = [module.eks]
}
EOF
```

#### AWS Load Balancer Controller

[AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
provisions ELBv2 resources (ALB/NLB) for Services and Ingresses.

![AWS Load Balancer Controller](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/05071ecd0f2c240c7e6b815c0fdf731df799005a/docs/assets/images/aws_load_balancer_icon.svg){:width="150"}

Install the `aws-load-balancer-controller`
[Helm chart](https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/main/helm/aws-load-balancer-controller)
and customize its
[default values](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v2.14.0/helm/aws-load-balancer-controller/values.yaml):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/aws-load-balancer-controller.tf" << \EOF
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                            = "${local.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "aws-load-balancer-controller"
      service_account = "aws-load-balancer-controller"
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  # renovate: datasource=helm depName=aws-load-balancer-controller registryUrl=https://aws.github.io/eks-charts
  version          = "3.3.0"
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "aws-load-balancer-controller"
  create_namespace = true
  wait = true

  values = [<<-YAML
    clusterName: ${local.cluster_name}
    vpcId: ${module.vpc.vpc_id}
    serviceAccount:
      name: aws-load-balancer-controller
  YAML
  ]

  depends_on = [
    module.aws_lb_controller_pod_identity,
    module.eks,
  ]
}
EOF
```

#### cert-manager

[cert-manager](https://cert-manager.io/) adds certificates and certificate
issuers as resource types in Kubernetes clusters and simplifies the process of
obtaining, renewing, and using those certificates.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg){:width="150"}

Install the `cert-manager`
[Helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and customize its
[default values](https://github.com/cert-manager/cert-manager/blob/v1.20.2/deploy/charts/cert-manager/values.yaml).
Provision the Pod Identity role granted to the `cert-manager` ServiceAccount
(scoped to the `${CLUSTER_FQDN}` hosted zone):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/cert-manager.tf" << \EOF
module "cert_manager_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                       = "${local.cluster_name}-cert-manager"
  attach_cert_manager_policy = true
  cert_manager_hosted_zone_arns = [
    module.route53_zone.arn,
  ]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "cert-manager"
      service_account = "cert-manager"
    }
  }
}

resource "helm_release" "cert_manager" {
  # renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io extractVersion=^(?<version>.+)$
  version          = "v1.20.2"
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  values = [<<-YAML
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
  YAML
  ]

  depends_on = [
    module.eks,
    module.cert_manager_pod_identity,
    # Ensure AWS LB Controller webhook is ready before creating Services
    # otherwise the mutating webhook "mservice.elbv2.k8s.aws" rejects requests
    # with "no endpoints available" if the controller pod is not yet running
    helm_release.aws_load_balancer_controller,
  ]
}
EOF
```

Create the `ClusterIssuer` and `Certificate` resources through OpenTofu using the
[`alekc/kubectl`](https://registry.terraform.io/providers/alekc/kubectl/latest/docs)
provider.

- ClusterIssuer configuring Let's Encrypt production ACME with DNS-01 challenges
  solved via Route 53 (using cert-manager's Pod Identity for AWS API access).

- Wildcard TLS certificate for `*.cluster_fqdn` issued by Let's Encrypt.
  Only created when no Velero backup exists (count condition) — on subsequent
  runs the certificate+secret are restored from the Velero backup instead,
  avoiding unnecessary ACME rate-limit consumption.
  wait_for blocks until cert-manager reports the certificate as Ready so that
  downstream resources (Gateway TLS listeners) can reference the secret.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/cert-manager-letsencrypt.tf" << \EOF
resource "kubectl_manifest" "letsencrypt_production_dns" {
  yaml_body = <<-YAML
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
        email: ${var.my_email}
        privateKeySecretRef:
          name: letsencrypt-production-dns
        solvers:
          - selector:
              dnsZones:
                - ${var.cluster_fqdn}
            dns01:
              route53: {}
  YAML

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "cert_production" {
  count = length(data.aws_s3_objects.velero_backup.keys) == 0 ? 1 : 0

  yaml_body = <<-YAML
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
      commonName: "*.${var.cluster_fqdn}"
      dnsNames:
        - "*.${var.cluster_fqdn}"
        - "${var.cluster_fqdn}"
  YAML

  wait_for {
    field {
      key   = "status.conditions.[0].status"
      value = "True"
    }
  }

  depends_on = [kubectl_manifest.letsencrypt_production_dns]
}
EOF
```

#### Velero

[Velero](https://velero.io/) is an open-source tool for backing up and
restoring Kubernetes cluster resources and persistent volumes.

![Velero](https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/Velero.svg){:width="400"}

Install the `velero`
[Helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and customize its
[default values](https://github.com/vmware-tanzu/helm-charts/blob/velero-12.0.2/charts/velero/values.yaml):

##### S3 bucket for Velero backups (if not already exists)

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/velero.tf" << \EOF
data "aws_iam_policy_document" "velero" {
  statement {
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = ["arn:aws:s3:::${var.cluster_fqdn}"]
  }
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListMultipartUploadParts", "s3:AbortMultipartUpload"]
    resources = ["arn:aws:s3:::${var.cluster_fqdn}/*"]
  }
}

module "velero_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                    = "${local.cluster_name}-velero"
  attach_custom_policy    = true
  source_policy_documents = [data.aws_iam_policy_document.velero.json]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "velero"
      service_account = "velero"
    }
  }
}

resource "helm_release" "velero" {
  # renovate: datasource=helm depName=velero registryUrl=https://vmware-tanzu.github.io/helm-charts
  version          = "12.0.2"
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true
  wait             = true

  values = [<<-YAML
    initContainers:
      - name: velero-plugin-for-aws
        # renovate: datasource=github-tags depName=vmware-tanzu/velero-plugin-for-aws extractVersion=^(?<version>.+)$
        image: velero/velero-plugin-for-aws:v1.14.1
        volumeMounts:
          - mountPath: /target
            name: plugins
    configuration:
      backupStorageLocation: []
      volumeSnapshotLocation:
        - provider: aws
          config:
            region: ${data.aws_region.current.region}
    serviceAccount:
      server:
        name: velero
    credentials:
      useSecret: false
  YAML
  ]

  depends_on = [
    module.eks,
    module.velero_pod_identity,
  ]
}

# Create BSL separately so we can use wait_for to confirm Velero has completed at least one backup sync cycle (status.lastSyncedTime is set).
resource "kubectl_manifest" "velero_bsl" {
  yaml_body = <<-YAML
    apiVersion: velero.io/v1
    kind: BackupStorageLocation
    metadata:
      name: default
      namespace: velero
    spec:
      provider: aws
      default: true
      objectStorage:
        bucket: ${var.cluster_fqdn}
        prefix: velero
      config:
        region: ${data.aws_region.current.region}
  YAML

  wait_for {
    field {
      key        = "status.lastSyncedTime"
      value      = ".+"
      value_type = "regex"
    }
  }

  depends_on = [helm_release.velero]
}

resource "kubectl_manifest" "velero_restore_cert" {
  count = length(data.aws_s3_objects.velero_backup.keys) > 0 ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: velero.io/v1
    kind: Restore
    metadata:
      name: restore-cert-manager-production
      namespace: velero
      labels:
        letsencrypt: production
    spec:
      backupName: cert-manager-production
      existingResourcePolicy: update
  YAML

  wait_for {
    field {
      key   = "status.phase"
      value = "Completed"
    }
  }

  depends_on = [
    kubectl_manifest.velero_bsl,
  ]
}
EOF
```

#### Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) is an implementation of the
[Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) built on Envoy
Proxy. It will terminate TLS, run the OIDC flow against Google, and forward
authenticated requests to Open WebUI and other services.

![Envoy Gateway](https://raw.githubusercontent.com/cncf/artwork/85a8328ca85a355e93e843ffe42d060d8992318d/projects/envoy/envoy-gateway/horizontal/color/envoy-gateway-horizontal-color.svg){:width="300"}

Install the `gateway-helm`
[Helm chart](https://github.com/envoyproxy/gateway/tree/main/charts/gateway-helm)
and customize its
[default values](https://github.com/envoyproxy/gateway/blob/v1.8.0/charts/gateway-helm/values.tmpl.yaml):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/envoy-gateway.tf" << \EOF
resource "helm_release" "envoy_gateway" {
  # renovate: datasource=docker depName=envoyproxy/gateway-helm registryUrl=https://docker.io
  version          = "1.8.0"
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  namespace        = "envoy-gateway-system"
  create_namespace = true
  wait             = true

  depends_on = [
    helm_release.aws_load_balancer_controller,
  ]
}

# Kubernetes Secret holding the Google OAuth client secret, referenced by the SecurityPolicy OIDC configuration to authenticate users via Google.
resource "kubectl_manifest" "google_oidc_client_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: google-oidc-client-secret
      namespace: envoy-gateway-system
    type: Opaque
    stringData:
      client-secret: ${var.google_client_secret}
  YAML
  sensitive_fields = ["stringData"]
  depends_on       = [helm_release.envoy_gateway]
}

# GatewayClass registers Envoy Gateway as the controller for Gateway API resources. All Gateway objects referencing the "eg" class are reconciled by the Envoy Gateway controller.
resource "kubectl_manifest" "gatewayclass" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: eg
    spec:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
  YAML
  depends_on = [helm_release.envoy_gateway]
}

# EnvoyProxy customizes the data-plane Service created by the Gateway. Annotations instruct the AWS Load Balancer Controller to provision an internet-facing NLB with IP-mode targets.
resource "kubectl_manifest" "envoy_proxy_nlb" {
  yaml_body = <<-YAML
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
              service.beta.kubernetes.io/aws-load-balancer-name: eks-${local.cluster_name}
  YAML
  depends_on = [helm_release.envoy_gateway]
}

# ReferenceGrant allows the Gateway in envoy-gateway-system to reference the "cert-production" TLS Secret in the cert-manager namespace. Without this, cross-namespace Secret references are rejected by the Gateway API.
resource "kubectl_manifest" "ref_grant_cert_secret" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-eg-to-cert-manager-secrets
      namespace: cert-manager
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: Gateway
          namespace: envoy-gateway-system
      to:
        - group: ""
          kind: Secret
          name: cert-production
  YAML
  depends_on = [helm_release.envoy_gateway]
}

# Central Gateway resource that terminates TLS for both the wildcard (*.cluster_fqdn) and apex (cluster_fqdn) hostnames. It references the NLB-backed EnvoyProxy for infrastructure and the Let's Encrypt certificate from cert-manager for TLS. All HTTPRoutes in any namespace can attach to this Gateway.
resource "kubectl_manifest" "gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: eg
      namespace: envoy-gateway-system
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
          hostname: "*.${var.cluster_fqdn}"
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
          hostname: "${var.cluster_fqdn}"
          tls:
            mode: Terminate
            certificateRefs:
              - name: cert-production
                namespace: cert-manager
          allowedRoutes:
            namespaces:
              from: All
  YAML
  depends_on = [
    kubectl_manifest.ref_grant_cert_secret,
    kubectl_manifest.envoy_proxy_nlb,
    kubectl_manifest.gatewayclass,
  ]
}

# SecurityPolicy attached to both Gateway listeners that enforces Google OIDC authentication and JWT-based authorization. Only the email specified in var.my_email is allowed access. Authenticated user identity is forwarded to backends via X-Forwarded-Email and X-Forwarded-User headers.
resource "kubectl_manifest" "security_policy_oidc" {
  yaml_body = <<-YAML
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
          sectionName: https
        - group: gateway.networking.k8s.io
          kind: Gateway
          name: eg
          sectionName: https-apex
      oidc:
        provider:
          issuer: "https://accounts.google.com"
        clientID: "${var.google_client_id}"
        clientSecret:
          name: google-oidc-client-secret
        redirectURL: "https://${var.cluster_fqdn}/oauth2/callback"
        scopes: [openid, email, profile]
        cookieNames:
          accessToken: oidc-access-token
          idToken: oidc-id-token
        cookieDomain: "${var.cluster_fqdn}"
        logoutPath: "/logout"
      jwt:
        providers:
          - name: google
            issuer: "https://accounts.google.com"
            remoteJWKS:
              uri: "https://www.googleapis.com/oauth2/v3/certs"
            extractFrom:
              cookies: [oidc-id-token]
            claimToHeaders:
              - { header: X-Forwarded-Email, claim: email }
              - { header: X-Forwarded-User,  claim: name  }
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
                    values: ["${var.my_email}"]
  YAML
  depends_on = [
    kubectl_manifest.gateway,
    kubectl_manifest.google_oidc_client_secret,
  ]
}

# HTTPRoute for the apex domain (cluster_fqdn) that redirects all traffic to the chat subdomain (chat.cluster_fqdn) with a 302 status code, providing a convenient entry point.
resource "kubectl_manifest" "apex_httproute" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: apex
      namespace: envoy-gateway-system
    spec:
      parentRefs:
        - name: eg
          namespace: envoy-gateway-system
          sectionName: https-apex
      hostnames:
        - ${var.cluster_fqdn}
      rules:
        - filters:
            - type: RequestRedirect
              requestRedirect:
                hostname: chat.${var.cluster_fqdn}
                statusCode: 302
  YAML
  depends_on = [kubectl_manifest.gateway]
}
EOF
```

#### Karpenter

[Karpenter](https://karpenter.sh/) automatically scales the node pool based on
pending pod requirements. The EKS module provisions the IAM roles via the
[`karpenter`](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/modules/karpenter)
sub-module.

![Karpenter](https://raw.githubusercontent.com/aws/karpenter-provider-aws/41b115a0b85677641e387635496176c4cc30d4c6/website/static/full_logo.svg){:width="400"}

Install the `karpenter`
[Helm chart](https://github.com/aws/karpenter-provider-aws/tree/main/charts/karpenter)
and customize its
[default values](https://github.com/aws/karpenter-provider-aws/blob/v1.12.1/charts/karpenter/values.yaml):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/karpenter.tf" << \EOF
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks/aws
  version = "21.23.0"

  cluster_name = module.eks.cluster_name

  namespace       = "karpenter"
  service_account = "karpenter"

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "KarpenterNodeRole-${local.cluster_name}"

  queue_managed_sse_enabled = false
  queue_kms_master_key_id   = module.kms.key_id
}

resource "helm_release" "karpenter" {
  # renovate: datasource=github-tags depName=aws/karpenter-provider-aws
  version          = "1.12.1"
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  namespace        = "karpenter"
  create_namespace = true
  wait             = true

  values = [<<-YAML
    settings:
      clusterName: ${module.eks.cluster_name}
      eksControlPlane: true
      interruptionQueue: ${module.karpenter.queue_name}
      featureGates:
        spotToSpotConsolidation: true
    serviceAccount:
      name: karpenter
  YAML
  ]

  depends_on = [
    module.karpenter,
  ]
}

# EC2NodeClass defines the AWS-specific node configuration for Karpenter-provisioned instances: Bottlerocket AMI, VPC subnets/security groups discovered via tags, the Karpenter IAM role, and KMS-encrypted gp3 EBS volumes.
resource "kubectl_manifest" "ec2_nodeclass_default" {
  yaml_body = <<-YAML
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
            karpenter.sh/discovery: "${local.cluster_name}"
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${local.cluster_name}"
      role: "KarpenterNodeRole-${local.cluster_name}"
      tags:
        Name: "${local.cluster_name}-karpenter"
        Cluster: "${var.cluster_fqdn}"
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 2Gi
            volumeType: gp3
            encrypted: true
            kmsKeyID: ${module.kms.key_arn}
        - deviceName: /dev/xvdb
          ebs:
            volumeSize: 20Gi
            volumeType: gp3
            encrypted: true
            kmsKeyID: ${module.kms.key_arn}
  YAML
  depends_on = [helm_release.karpenter]
}

# NodePool defines the scheduling constraints for Karpenter: instances must have >4 GiB RAM, run in a single AZ to minimize cross-AZ costs, use cost-efficient t4g/t3a families, and prefer spot capacity with on-demand fallback.
resource "kubectl_manifest" "nodepool_default" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          requirements:
            - key: "karpenter.k8s.aws/instance-memory"
              operator: Gt
              values: ["8191"]
            - key: "topology.kubernetes.io/zone"
              operator: In
              values: ["${data.aws_region.current.region}a"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: In
              values: ["t4g", "t3a"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64", "amd64"]
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
  YAML
  depends_on = [kubectl_manifest.ec2_nodeclass_default]
}
EOF
```

#### ExternalDNS

[ExternalDNS](https://github.com/kubernetes-sigs/external-dns) synchronises
Kubernetes Services, Ingresses, and Gateway API routes with Route 53.

![ExternalDNS](https://raw.githubusercontent.com/kubernetes-sigs/external-dns/afe3b09f45a241750ec3ddceef59ceaf84c096d0/docs/img/external-dns.png){:width="200"}

Install the `external-dns`
[Helm chart](https://artifacthub.io/packages/helm/external-dns/external-dns)
and customize its
[default values](https://github.com/kubernetes-sigs/external-dns/blob/external-dns-helm-chart-1.21.1/charts/external-dns/values.yaml):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/external-dns.tf" << \EOF
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                       = "${local.cluster_name}-external-dns"
  attach_external_dns_policy = true
  external_dns_hosted_zone_arns = [
    module.route53_zone.arn,
  ]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
}

resource "helm_release" "external_dns" {
  # renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
  version          = "1.21.1"
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true

  values = [<<-YAML
    serviceAccount:
      name: external-dns
    interval: 20s
    policy: sync
    domainFilters:
      - ${var.cluster_fqdn}
    sources:
      - service
      - ingress
      - gateway-httproute
      - gateway-grpcroute
  YAML
  ]

  depends_on = [
    module.external_dns_pod_identity,
    kubectl_manifest.nodepool_default,
  ]
}
EOF
```

### LiteLLM

[LiteLLM](https://github.com/BerriAI/litellm) is an OpenAI-compatible proxy
that supports 100+ LLM providers including
[Amazon Bedrock](https://aws.amazon.com/bedrock/). It passes `guardrailConfig`
inline in the Bedrock Converse API call, satisfying the IAM
`bedrock:GuardrailIdentifier` condition. It uses
[EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
for authentication — no IAM users or long-term credentials are needed.
No database is required — models are configured via a static YAML file.

![LiteLLM](https://raw.githubusercontent.com/BerriAI/litellm/main/docs/my-website/img/litellm_logo.png){:width="300"}

Install `litellm` using
[Helm](https://github.com/BerriAI/litellm/tree/main/deploy/charts/litellm-helm)
and customize its
[default values](https://github.com/BerriAI/litellm/blob/main/deploy/charts/litellm-helm/values.yaml).
Create a dedicated IAM role granting the LiteLLM pod permission to call the
Bedrock Converse/InvokeModel APIs with guardrail enforcement, and associate it
with the `litellm` ServiceAccount through EKS Pod Identity:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/litellm.tf" << \EOF
data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid = "BedrockInvoke"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "bedrock:GuardrailIdentifier"
      values   = [aws_bedrock_guardrail.ai_safety.guardrail_arn]
    }
  }
  statement {
    sid       = "BedrockApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.ai_safety.guardrail_arn]
  }
  statement {
    sid = "BedrockListAndGet"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
      "bedrock:ListInferenceProfiles",
      "bedrock:GetInferenceProfile",
    ]
    resources = ["*"]
  }
}

module "litellm_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                    = "${local.cluster_name}-litellm"
  attach_custom_policy    = true
  source_policy_documents = [data.aws_iam_policy_document.bedrock_invoke.json]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "litellm"
      service_account = "litellm"
    }
  }
}

# Pre-create the master key secret with a known value so both LiteLLM and
# Open WebUI can reference the same API key deterministically.
resource "random_password" "litellm_master_key" {
  length  = 32
  special = false
}

resource "kubectl_manifest" "litellm_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: litellm
  YAML
}

resource "kubectl_manifest" "litellm_masterkey" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: litellm-masterkey
      namespace: litellm
    stringData:
      masterkey: sk-${random_password.litellm_master_key.result}
  YAML
  depends_on = [kubectl_manifest.litellm_namespace]
}

resource "helm_release" "litellm" {
  # renovate: datasource=docker depName=docker.litellm.ai/berriai/litellm-helm
  version          = "1.87.0"
  name             = "litellm"
  chart            = "oci://docker.litellm.ai/berriai/litellm-helm"
  namespace        = "litellm"
  create_namespace = false
  wait             = true

  values = [<<-YAML
    replicaCount: 1
    image:
      repository: ghcr.io/berriai/litellm-database
      pullPolicy: Always
    resources:
      requests:
        memory: 1Gi
    masterkeySecretName: litellm-masterkey
    masterkeySecretKey: masterkey
    serviceAccount:
      create: true
      name: litellm
    service:
      port: 4000
    db:
      deployStandalone: true
    postgresql:
      image:
        tag: latest
      auth:
        password: litellm-pg-pass
        postgres-password: litellm-pg-pass
    migrationJob:
      enabled: true
      resources:
        requests:
          memory: 512Mi
        limits:
          memory: 512Mi
    proxy_config:
      model_list:
        - model_name: us.anthropic.claude-haiku-4-5-20251001-v1:0
          litellm_params:
            model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
            aws_region_name: ${data.aws_region.current.region}
            guardrailConfig:
              guardrailIdentifier: ${aws_bedrock_guardrail.ai_safety.guardrail_arn}
              guardrailVersion: "DRAFT"
              trace: "disabled"
      litellm_settings:
        drop_params: true
  YAML
  ]

  depends_on = [
    kubectl_manifest.litellm_masterkey,
    kubectl_manifest.nodepool_default,
    module.litellm_pod_identity,
  ]
}

# HTTPRoute exposes LiteLLM API through the Envoy Gateway at litellm.${cluster_fqdn}
resource "kubectl_manifest" "litellm_httproute" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: litellm
      namespace: litellm
    spec:
      parentRefs:
        - name: eg
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - litellm.${var.cluster_fqdn}
      rules:
        - backendRefs:
            - name: litellm
              port: 4000
  YAML
  depends_on = [
    helm_release.litellm,
    kubectl_manifest.gateway,
  ]
}
EOF
```

### Open WebUI

[Open WebUI](https://openwebui.com/) is a user-friendly web interface for
chat-style interactions with LLMs. Install the `open-webui`
[Helm chart](https://github.com/open-webui/helm-charts/tree/main/charts/open-webui)
and customize its
[default values](https://github.com/open-webui/helm-charts/blob/open-webui-14.8.0/charts/open-webui/values.yaml).
Point it at LiteLLM's in-cluster OpenAI-compatible endpoint and expose it
through the Envoy Gateway:

![Open WebUI](https://raw.githubusercontent.com/open-webui/docs/763ec157507501e64253a1a857d3ab9810a078f0/static/images/favicon.png){:width="150"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/open-webui.tf" << \EOF
resource "helm_release" "open_webui" {
  # renovate: datasource=helm depName=open-webui registryUrl=https://helm.openwebui.com
  version          = "14.8.0"
  name             = "open-webui"
  repository       = "https://helm.openwebui.com"
  chart            = "open-webui"
  namespace        = "open-webui"
  create_namespace = true

  values = [<<-YAML
    ollama:
      enabled: false
    pipelines:
      enabled: false
    persistence:
      enabled: false
    resources:
      requests:
        memory: 1Gi
      limits:
        memory: 2Gi
    openaiBaseApiUrl: http://litellm.litellm.svc:4000/v1
    extraEnvVars:
      - name: OPENAI_API_KEY
        value: sk-${random_password.litellm_master_key.result}
      - name: WEBUI_AUTH
        value: "false"
      - name: ENABLE_SIGNUP
        value: "false"
      - name: ENABLE_EVALUATION_ARENA_MODELS
        value: "false"
      - name: DEFAULT_MODELS
        value: us.anthropic.claude-haiku-4-5-20251001-v1:0
      - name: WEBUI_AUTH_TRUSTED_EMAIL_HEADER
        value: X-Forwarded-Email
      - name: WEBUI_AUTH_TRUSTED_NAME_HEADER
        value: X-Forwarded-User
  YAML
  ]

  depends_on = [helm_release.litellm]
}

# HTTPRoute exposing Open WebUI at chat.<cluster_fqdn>, the primary user-facing endpoint. Traffic passes through OIDC authentication enforced by the SecurityPolicy on the Gateway before reaching the Open WebUI Service.
resource "kubectl_manifest" "openwebui_httproute" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: open-webui
      namespace: open-webui
    spec:
      parentRefs:
        - name: eg
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - chat.${var.cluster_fqdn}
      rules:
        - backendRefs:
            - name: open-webui
              port: 80
  YAML
  depends_on = [
    helm_release.open_webui,
    kubectl_manifest.gateway,
  ]
}
EOF
```

## OpenTofu Code - apply

Initialise the OpenTofu working directory and apply the entire configuration
in a single run:

```bash
tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" init
if [[ ! ${MY_TASK:-} =~ delete: ]]; then
  tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" apply -auto-approve
fi
```

Visit `https://chat.${CLUSTER_FQDN}` — you should be redirected through the
Google OIDC flow by Envoy Gateway, and then land in Open WebUI with the
Bedrock-backed Claude, Llama, and Mistral models available in the model picker:

## Clean-up

Remove the cluster and all related resources with OpenTofu.

![Clean-up](https://raw.githubusercontent.com/cubanpit/cleanupdate/7aaccaa36ab4888a0847b267ed24d079dfed7863/icons/cleanupdate.svg){:width="150"}

Set environment variables:

```sh
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k02.k8s.mylabs.dev}"
export TF_VAR_cluster_fqdn="${CLUSTER_FQDN}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TF_VAR_my_email="${TF_VAR_my_email:-petr.ruzicka@gmail.com}"
export TF_VAR_google_client_id="${GOOGLE_CLIENT_ID}"
export TF_VAR_google_client_secret="${GOOGLE_CLIENT_SECRET}"
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
mkdir -p "${TMP_DIR}/${CLUSTER_FQDN}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig.conf}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}" || true
```

Back up the cert-manager certificate before tearing the cluster down (only if
it was issued/renewed during this cluster's lifetime — a completed
CertificateRequest with the `letsencrypt: production` label only exists when
cert-manager performed the ACME flow, not after a Velero restore):

{% raw %}

```sh
if kubectl get certificaterequest -n cert-manager -l letsencrypt=production -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
  kubectl apply -f - << EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: cert-manager-production
  namespace: velero
spec:
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
fi
```

{% endraw %}

Recreate the OpenTofu code files:

```sh
export MY_TASK="${MISE_TASK_NAME}"
mise run "create:${MISE_TASK_NAME##*:}"
```

Stop Karpenter from launching additional nodes and remove the Envoy Gateway /
AWS LB Controller so the NLB is released before OpenTofu tries to destroy the
VPC:

```sh
tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" destroy -target=helm_release.karpenter -target=helm_release.envoy_gateway -target=helm_release.aws_load_balancer_controller -auto-approve || true
```

Remove any remaining EC2 instances provisioned by Karpenter:

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=tag:karpenter.sh/nodepool,Values=*" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text); do
  echo "*** Removing Karpenter EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Destroy the remaining infrastructure with OpenTofu:

```sh
if tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" destroy -auto-approve; then
  aws s3api delete-objects --bucket "${CLUSTER_FQDN}" --no-cli-pager --delete "$(aws s3api list-object-versions --bucket "${CLUSTER_FQDN}" --prefix "terraform.tfstate" --output json --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
  rm -rf "${TMP_DIR:?}/${CLUSTER_FQDN:?}"
fi
```

Remove EBS volumes and snapshots related to the cluster (as a precaution):

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text); do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done

for SNAPSHOT in $(aws ec2 describe-snapshots --owner-ids self --filter "Name=tag:Name,Values=${CLUSTER_NAME}-dynamic-snapshot*" "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Snapshots[].SnapshotId' --output text); do
  echo "*** Removing Snapshot: ${SNAPSHOT}"
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
done
```

Remove the CloudWatch log group:

```sh
if [[ "$(aws logs describe-log-groups --query "logGroups[?logGroupName==\`/aws/eks/${CLUSTER_NAME}/cluster\`] | [0].logGroupName" --output text)" = "/aws/eks/${CLUSTER_NAME}/cluster" ]]; then
  aws logs delete-log-group --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster"
fi
```

Enjoy ... 😉
