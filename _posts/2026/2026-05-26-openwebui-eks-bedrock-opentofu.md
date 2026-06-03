---
title: Amazon Q Business with S3 RAG managed by OpenTofu
author: Petr Ruzicka
date: 2026-05-26
description: Deploy Amazon Q Business with S3 data source for RAG, provisioned entirely with OpenTofu
categories: [Cloud, AI]
tags: [amazon-q-business, aws-bedrock, iam-identity-center, kms, opentofu, rag, s3]
image: https://raw.githubusercontent.com/open-webui/open-webui/14a6c1f4963892c163821765efcc10c5c4394fe9965/static/static/favicon.svg
---

I will outline the steps for setting up
[Amazon Q Business](https://aws.amazon.com/q/business/) — a fully managed
generative AI assistant that can answer questions, generate content, and
complete tasks based on your company's data. All infrastructure is provisioned
by [OpenTofu](https://opentofu.org/) using the
[`hashicorp/aws`](https://registry.terraform.io/providers/hashicorp/aws/latest)
and [`hashicorp/awscc`](https://registry.terraform.io/providers/hashicorp/awscc/latest)
providers.

The setup should align with the following criteria:

- Less expensive region - `us-east-1`
- [Amazon Q Business](https://aws.amazon.com/q/business/) as the fully managed
  AI assistant with a built-in web experience
- [IAM Identity Center](https://aws.amazon.com/iam/identity-center/) for user
  authentication and access control
- [Amazon S3](https://aws.amazon.com/s3/) as the document data source for RAG
  (Retrieval-Augmented Generation)
- [AWS KMS](https://aws.amazon.com/kms/) for encryption at rest of all data
- [OpenTofu](https://opentofu.org/) drives the full stack via the
  `hashicorp/aws` and `hashicorp/awscc` providers

## Build Amazon Q Business

### Requirements

You will need to configure the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and set up other necessary secrets and variables:

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
```

<!-- prettier-ignore-start -->
> [IAM Identity Center](https://aws.amazon.com/iam/identity-center/) must
> already be enabled in your AWS account/organization. This is a one-time
> operation done via the AWS Console or Organizations.
{: .prompt-warning }
<!-- prettier-ignore-end -->

If you plan to follow this document and its tasks, you will need to set up
a few environment variables, such as:

```bash
# AWS Region
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k02.k8s.mylabs.dev}"
# OpenTofu variables
export TF_VAR_cluster_fqdn="${CLUSTER_FQDN}"
export TF_VAR_my_email="${TF_VAR_my_email:-petr.ruzicka@gmail.com}"
# Derived shell variables
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
cd "${TMP_DIR}/${CLUSTER_FQDN}"
```

Install the required tools:

<!-- prettier-ignore-start -->
> You can bypass these procedures if you already have all the essential
> software installed.
{: .prompt-tip }
<!-- prettier-ignore-end -->

- [OpenTofu](https://opentofu.org/)
- [AWS CLI](https://aws.amazon.com/cli/)

### Create S3 bucket for OpenTofu state

Create an S3 bucket to store OpenTofu remote state using CloudFormation. The
bucket uses KMS encryption, lifecycle policies, and blocks all public access:

```bash
if ! aws s3api head-bucket --bucket "${CLUSTER_FQDN}" 2>/dev/null; then
  tee "${TMP_DIR}/${CLUSTER_FQDN}/s3.yaml" << \EOF
AWSTemplateFormatVersion: "2010-09-09"
Description: S3 bucket for OpenTofu state files
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
    --tags "Owner=${TF_VAR_my_email}" "Environment=dev" \
    --parameter-overrides "Name=${CLUSTER_FQDN}" \
    --template-file "${TMP_DIR}/${CLUSTER_FQDN}/s3.yaml"
fi
```

## OpenTofu Code

All resources from this point onwards are managed by [OpenTofu](https://opentofu.org/).
Create the working directory and the main configuration file with provider
versions, backend, and provider settings:

![OpenTofu](https://raw.githubusercontent.com/opentofu/brand-artifacts/45131c91b81dc05ac2b18de01d18e7be8c715137/full/transparent/SVG/on-light.svg){:width="400"}

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
    awscc = {
      source  = "hashicorp/awscc"
      # renovate: datasource=terraform-provider depName=hashicorp/awscc
      version = "1.40.0"
    }
    http = {
      source  = "hashicorp/http"
      # renovate: datasource=terraform-provider depName=hashicorp/http
      version = "3.6.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = local.tags
  }
}

provider "awscc" {
  region = "${AWS_REGION}"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
EOF
```

Define the input variables. Values are provided via `TF_VAR_` environment
variables:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/variables.tf" << \EOF
variable "cluster_fqdn" {
  description = "FQDN used as a naming prefix (e.g. k02.k8s.mylabs.dev)"
  type        = string
}

variable "my_email" {
  description = "Email address used for tagging"
  type        = string
}

locals {
  cluster_name = split(".", var.cluster_fqdn)[0]
  tags = {
    Owner       = var.my_email
    Environment = "dev"
    Managed-by  = "opentofu"
  }
  rag_documents = {
    "opentofu-README.md"  = "https://raw.githubusercontent.com/opentofu/opentofu/main/README.md"
    "karpenter-README.md" = "https://raw.githubusercontent.com/aws/karpenter-provider-aws/main/README.md"
    "amazon-q-FAQ.md"     = "https://raw.githubusercontent.com/aws/aws-cdk/main/README.md"
  }
}
EOF
```

### KMS key

Create a KMS key for encrypting Amazon Q Business data and the S3 RAG bucket:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/kms.tf" << \EOF
module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/kms/aws
  version = "4.2.0"

  description             = "KMS key for ${local.cluster_name} Amazon Q Business"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  aliases                 = ["qbusiness-${local.cluster_name}"]

  key_statements = [
    {
      sid = "AllowQBusinessEncryption"
      principals = [{ type = "Service", identifiers = ["qbusiness.amazonaws.com"] }]
      actions = [
        "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey",
        "kms:CreateGrant", "kms:RetireGrant",
      ]
      resources = ["*"]
      condition = [{
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }]
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

### IAM Identity Center

Look up the existing IAM Identity Center instance (must already be enabled in
your account). Amazon Q Business requires Identity Center for user
authentication:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/identity-center.tf" << \EOF
data "aws_ssoadmin_instances" "this" {}

locals {
  identity_center_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
}
EOF
```

### Amazon Q Business Application

Create the core Amazon Q Business application with KMS encryption, file
attachments enabled, and the web experience for end users:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/qbusiness.tf" << \EOF
data "aws_iam_policy_document" "qbusiness_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["qbusiness.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "qbusiness_service" {
  statement {
    sid = "AllowCloudWatchMetrics"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["AWS/QBusiness"]
    }
  }
  statement {
    sid = "AllowCloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/qbusiness/*"]
  }
}

resource "aws_iam_role" "qbusiness_service" {
  name               = "${local.cluster_name}-qbusiness-service"
  assume_role_policy = data.aws_iam_policy_document.qbusiness_trust.json
}

resource "aws_iam_role_policy" "qbusiness_service" {
  name   = "${local.cluster_name}-qbusiness-service"
  role   = aws_iam_role.qbusiness_service.id
  policy = data.aws_iam_policy_document.qbusiness_service.json
}

resource "aws_qbusiness_application" "this" {
  display_name                 = "${local.cluster_name}-q-business"
  description                  = "Amazon Q Business application for ${local.cluster_name}"
  iam_service_role_arn         = aws_iam_role.qbusiness_service.arn
  identity_center_instance_arn = local.identity_center_arn

  attachments_configuration {
    attachments_control_mode = "ENABLED"
  }

  encryption_configuration {
    kms_key_id = module.kms.key_arn
  }
}
EOF
```

### Q Business Index and Retriever

Create the Q Business index (the knowledge store) and a native retriever that
searches over the index. The `awscc` provider is used because these resources
are not yet available in the `hashicorp/aws` provider:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/qbusiness-index.tf" << \EOF
resource "awscc_qbusiness_index" "this" {
  application_id = aws_qbusiness_application.this.application_id
  display_name   = "${local.cluster_name}-index"
  description    = "Primary index for ${local.cluster_name} Q Business application"
  type           = "STARTER"

  capacity_configuration = {
    units = 1
  }

  tags = [{
    key   = "Managed-by"
    value = "opentofu"
  }]
}

resource "awscc_qbusiness_retriever" "this" {
  application_id = aws_qbusiness_application.this.application_id
  display_name   = "${local.cluster_name}-retriever"
  type           = "NATIVE_INDEX"

  configuration = {
    native_index_configuration = {
      index_id = awscc_qbusiness_index.this.index_id
    }
  }

  tags = [{
    key   = "Managed-by"
    value = "opentofu"
  }]
}
EOF
```

### Q Business Web Experience

Deploy the built-in web experience that provides a chat-style UI for users
authenticated via IAM Identity Center:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/qbusiness-web.tf" << \EOF
data "aws_iam_policy_document" "qbusiness_web_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:SetContext"]
    principals {
      type        = "Service"
      identifiers = ["application.qbusiness.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_qbusiness_application.this.arn]
    }
  }
}

data "aws_iam_policy_document" "qbusiness_web" {
  statement {
    sid = "QBusinessConversation"
    actions = [
      "qbusiness:Chat",
      "qbusiness:ChatSync",
      "qbusiness:ListMessages",
      "qbusiness:ListConversations",
      "qbusiness:DeleteConversation",
      "qbusiness:PutFeedback",
      "qbusiness:GetWebExperience",
      "qbusiness:GetApplication",
      "qbusiness:ListPlugins",
      "qbusiness:GetChatControlsConfiguration",
    ]
    resources = [aws_qbusiness_application.this.arn]
  }
}

resource "aws_iam_role" "qbusiness_web" {
  name               = "${local.cluster_name}-qbusiness-web"
  assume_role_policy = data.aws_iam_policy_document.qbusiness_web_trust.json
}

resource "aws_iam_role_policy" "qbusiness_web" {
  name   = "${local.cluster_name}-qbusiness-web"
  role   = aws_iam_role.qbusiness_web.id
  policy = data.aws_iam_policy_document.qbusiness_web.json
}

resource "awscc_qbusiness_web_experience" "this" {
  application_id              = aws_qbusiness_application.this.application_id
  role_arn                    = aws_iam_role.qbusiness_web.arn
  sample_prompts_control_mode = "ENABLED"
  title                       = "${local.cluster_name} Q Business"
  subtitle                    = "Ask questions about your documents"
  welcome_message             = "Welcome! Upload documents or ask questions about indexed content."

  tags = [{
    key   = "Managed-by"
    value = "opentofu"
  }]
}
EOF
```

### S3 Data Source for RAG

Create an encrypted S3 bucket for documents and configure it as a data source
for the Q Business index. The data source will crawl objects under the `docs/`
prefix:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/qbusiness-datasource.tf" << \EOF
module "s3_rag" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/s3-bucket/aws
  version = "5.14.0"

  bucket        = "${var.cluster_fqdn}-rag"
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = module.kms.key_arn
      }
    }
  }
}

data "aws_iam_policy_document" "qbusiness_datasource_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["qbusiness.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "qbusiness_datasource" {
  statement {
    sid     = "S3GetObject"
    actions = ["s3:GetObject"]
    resources = ["${module.s3_rag.s3_bucket_arn}/*"]
  }
  statement {
    sid     = "S3ListBucket"
    actions = ["s3:ListBucket"]
    resources = [module.s3_rag.s3_bucket_arn]
  }
  statement {
    sid = "QBusinessIndexing"
    actions = [
      "qbusiness:BatchPutDocument",
      "qbusiness:BatchDeleteDocument",
    ]
    resources = ["arn:aws:qbusiness:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application/${aws_qbusiness_application.this.application_id}/index/${awscc_qbusiness_index.this.index_id}"]
  }
  statement {
    sid = "QBusinessUserManagement"
    actions = [
      "qbusiness:PutGroup",
      "qbusiness:CreateUser",
      "qbusiness:DeleteGroup",
      "qbusiness:UpdateUser",
      "qbusiness:ListGroups",
    ]
    resources = [
      aws_qbusiness_application.this.arn,
      "arn:aws:qbusiness:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application/${aws_qbusiness_application.this.application_id}/index/${awscc_qbusiness_index.this.index_id}",
      "arn:aws:qbusiness:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:application/${aws_qbusiness_application.this.application_id}/index/${awscc_qbusiness_index.this.index_id}/data-source/*",
    ]
  }
  statement {
    sid     = "KMSDecrypt"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [module.kms.key_arn]
  }
}

resource "aws_iam_role" "qbusiness_datasource" {
  name               = "${local.cluster_name}-qbusiness-datasource"
  assume_role_policy = data.aws_iam_policy_document.qbusiness_datasource_trust.json
}

resource "aws_iam_role_policy" "qbusiness_datasource" {
  name   = "${local.cluster_name}-qbusiness-datasource"
  role   = aws_iam_role.qbusiness_datasource.id
  policy = data.aws_iam_policy_document.qbusiness_datasource.json
}

resource "awscc_qbusiness_data_source" "s3" {
  application_id = aws_qbusiness_application.this.application_id
  display_name   = "${local.cluster_name}-s3-datasource"
  index_id       = awscc_qbusiness_index.this.index_id
  role_arn       = aws_iam_role.qbusiness_datasource.arn

  configuration = jsonencode({
    type    = "S3"
    version = "1.0.0"
    connectionConfiguration = {
      repositoryEndpointMetadata = {
        BucketName = module.s3_rag.s3_bucket_id
      }
    }
    repositoryConfigurations = {
      document = {
        fieldMappings = [{
          dataSourceFieldName = "s3_document_id"
          indexFieldType      = "STRING"
          indexFieldName      = "s3_document_id"
        }]
      }
    }
    additionalProperties = {
      inclusionPrefixes = ["docs/"]
    }
    syncMode = "FORCED_FULL_CRAWL"
  })

  tags = [{
    key   = "Managed-by"
    value = "opentofu"
  }]
}

data "http" "rag_docs" {
  for_each = local.rag_documents
  url      = each.value
}

resource "aws_s3_object" "rag_docs" {
  for_each     = local.rag_documents
  bucket       = module.s3_rag.s3_bucket_id
  key          = "docs/${each.key}"
  content      = data.http.rag_docs[each.key].response_body
  content_type = "text/markdown"
}
EOF
```

### Outputs

Add outputs to display the web experience URL and application ID after
provisioning:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/outputs.tf" << \EOF
output "qbusiness_application_id" {
  description = "Amazon Q Business application ID"
  value       = aws_qbusiness_application.this.application_id
}

output "qbusiness_web_experience_url" {
  description = "URL of the Amazon Q Business web experience"
  value       = awscc_qbusiness_web_experience.this.default_endpoint
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

<!-- prettier-ignore-start -->
> After `apply` completes, use the `qbusiness_web_experience_url` output to
> access the Q Business chat interface. Users must be assigned to the
> application in IAM Identity Center before they can log in.
{: .prompt-info }
<!-- prettier-ignore-end -->

To sync the S3 data source and start indexing documents, trigger a sync from
the AWS Console or via the CLI:

```shell
APPLICATION_ID=$(tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" output -raw qbusiness_application_id)
INDEX_ID=$(aws qbusiness list-indices --application-id "${APPLICATION_ID}" --query "indices[0].indexId" --output text)
DATA_SOURCE_ID=$(aws qbusiness list-data-sources --application-id "${APPLICATION_ID}" --index-id "${INDEX_ID}" --query "dataSources[0].dataSourceId" --output text)
aws qbusiness start-data-source-sync-job --application-id "${APPLICATION_ID}" --index-id "${INDEX_ID}" --data-source-id "${DATA_SOURCE_ID}"
```

## Clean-up

Remove all resources with OpenTofu.

![Clean-up](https://raw.githubusercontent.com/cubanpit/cleanupdate/7aaccaa36ab4888a0847b267ed24d079dfed7863/icons/cleanupdate.svg){:width="150"}

Set environment variables:

```sh
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k02.k8s.mylabs.dev}"
export TF_VAR_cluster_fqdn="${CLUSTER_FQDN}"
export TF_VAR_my_email="${TF_VAR_my_email:-petr.ruzicka@gmail.com}"
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
mkdir -p "${TMP_DIR}/${CLUSTER_FQDN}"
```

Recreate the OpenTofu code files:

```sh
export MY_TASK="${MISE_TASK_NAME}"
mise run "create:${MISE_TASK_NAME##*:}"
```

Destroy all infrastructure with OpenTofu:

```sh
if tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" destroy -auto-approve; then
  aws s3api delete-objects --bucket "${CLUSTER_FQDN}" --no-cli-pager --delete "$(aws s3api list-object-versions --bucket "${CLUSTER_FQDN}" --prefix "terraform.tfstate" --output json --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
  rm -rf "${TMP_DIR}/${CLUSTER_FQDN}"
fi
```

Enjoy ... 😉
