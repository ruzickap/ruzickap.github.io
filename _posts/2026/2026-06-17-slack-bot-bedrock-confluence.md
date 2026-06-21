---
title: Slack bot for answering questions from Confluence using Amazon Bedrock
author: Petr Ruzicka
date: 2026-06-17
description: Slack bot that answers questions from your Confluence wiki using Amazon Bedrock Knowledge Base, OpenSearch Serverless, and LiteLLM on Amazon EKS, provisioned with OpenTofu.
categories: [Kubernetes, Cloud, AI]
tags: [amazon-eks, amazon-bedrock, amazon-bedrock-knowledge-base, opensearch-serverless, confluence, rag, collmbo, litellm, slack, opentofu]
mermaid: true
image: https://github.com/user-attachments/assets/b13da1c7-5d2f-4ad3-8c5b-9ef4e500deb8
---

<!-- rumdl-disable MD013 -->
This post builds directly on top of [Amazon EKS with Open WebUI and AWS Bedrock managed by OpenTofu]({% post_url /2026/2026-05-26-openwebui-eks-bedrock-opentofu %}),
<!-- rumdl-enable MD013 -->
which provisions an [Amazon EKS](https://aws.amazon.com/eks/) cluster with
[LiteLLM](https://github.com/BerriAI/litellm) (an OpenAI-compatible proxy in
front of [AWS Bedrock](https://aws.amazon.com/bedrock/)), [Envoy Gateway](https://gateway.envoyproxy.io/),
cert-manager, ExternalDNS and Karpenter - all driven by [OpenTofu](https://opentofu.org/).
That cluster is the foundation here; this post adds a
[Retrieval-Augmented Generation (RAG)](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
pipeline on top of it.

The goal is a [Slack](https://slack.com/) bot that answers **from your own
[Confluence](https://www.atlassian.com/software/confluence) wiki**. An
[Amazon Bedrock Knowledge Base](https://aws.amazon.com/bedrock/knowledge-bases/)
crawls a single Confluence space, embeds the pages with
[Amazon Titan](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
and stores the vectors in [Amazon OpenSearch Serverless](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html).
[LiteLLM](https://github.com/BerriAI/litellm) then retrieves the relevant chunks
on every question and feeds them to a Bedrock model, while
[Collmbo](https://github.com/iwamot/collmbo) - a small Slack bot - is the chat
front-end. Collmbo sends a plain chat request and all the RAG wiring lives in
LiteLLM and AWS.

The setup should align with the following criteria:

- An [Amazon Bedrock Knowledge Base](https://aws.amazon.com/bedrock/knowledge-bases/)
  indexes **one configurable [Confluence](https://www.atlassian.com/software/confluence)
  space** (the space key is an OpenTofu variable)
- [Confluence](https://www.atlassian.com/software/confluence) credentials are
  rendered by OpenTofu into an [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
  secret - the only credential store the Bedrock connector accepts
- [Amazon OpenSearch Serverless](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html)
  is the vector store backing the Knowledge Base (the only store the Confluence
  connector supports)
- [LiteLLM](https://github.com/BerriAI/litellm) performs RAG **server-side**
  through an [always-on vector store](https://docs.litellm.ai/docs/completion/knowledgebase)
  attached to a model - the bot passes no extra parameters
- [Collmbo](https://github.com/iwamot/collmbo) runs as a single container
  ([`ghcr.io/iwamot/collmbo`](https://github.com/iwamot/collmbo/pkgs/container/collmbo))
  deployed by [OpenTofu](https://opentofu.org/) into the existing EKS cluster
- Collmbo talks to a dedicated [LiteLLM](https://github.com/BerriAI/litellm)
  release inside the cluster through the [OpenAI-compatible API](https://docs.litellm.ai/docs/providers/openai_compatible)
  (`http://litellm-kb.litellm-kb.svc:4000/v1`) - no model credentials in the bot
- Slack connectivity uses [Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode),
  so the bot needs no public endpoint and no inbound load balancer

## Architecture

```mermaid
flowchart TD
  User(["fa:fa-user Slack User"])
  Slack["fa:fa-slack Slack"]
  Confluence["fa:fa-confluence Confluence Cloud"]

  User -- "message / @mention" --> Slack
  Slack <== "Socket Mode (outbound WebSocket)" ==> CO
  CO -- "OpenAI API" --> LL
  LL -- "Retrieve" --> KB
  KB -- "vectors" --> AOSS
  LL -- "Converse (+context)\nSigV4" --> BR
  BR --> GR
  KB -. "crawl + embed (ingestion job)" .-> Confluence

  subgraph AWS["fa:fa-cloud AWS us-east-1"]
    BR["fa:fa-brain Amazon Bedrock"]
    GR["fa:fa-lock Bedrock Guardrail"]
    KB["fa:fa-book Bedrock Knowledge Base"]
    AOSS["fa:fa-database OpenSearch Serverless"]
    SM["fa:fa-key Secrets Manager\n(Confluence creds)"]
    subgraph EKS["fa:fa-dharmachakra Amazon EKS"]
      CO["fa:fa-robot Collmbo"]
      LL["fa:fa-server LiteLLM (litellm-kb)"]
    end
  end

  KB -. "reads creds" .-> SM
```

The request flow:

1. A user sends a message in Slack (direct message or `@mention` in a channel).
2. Slack delivers the event to Collmbo over the existing Socket Mode WebSocket.
3. Collmbo builds an OpenAI-format chat request and sends it to the in-cluster
   `litellm-kb` service (`http://litellm-kb.litellm-kb.svc:4000/v1`), selecting
   the knowledge-base-attached model (`...-kb`).
4. Because that model has a vector store attached, LiteLLM calls the Bedrock
   Knowledge Base `Retrieve` API, which searches the Confluence vectors in
   OpenSearch Serverless and returns the most relevant chunks.
5. LiteLLM prepends the retrieved chunks to the conversation and calls Amazon
   Bedrock with SigV4 (via EKS Pod Identity), applying the Bedrock Guardrail
   configured in the base post.
6. The grounded answer travels back through LiteLLM to Collmbo, which posts it
   to the Slack thread.

Separately, on a schedule (or on demand), the Knowledge Base ingestion job
crawls the configured Confluence space, chunks and embeds every page with Titan,
and writes the vectors into OpenSearch Serverless - this is what populates the
store the `Retrieve` step reads.

## Requirements

This post assumes the cluster from
<!-- rumdl-disable MD013 -->
[Amazon EKS with Open WebUI and AWS Bedrock managed by OpenTofu]({% post_url /2026/2026-05-26-openwebui-eks-bedrock-opentofu %})
<!-- rumdl-enable MD013 -->
is already described - the same OpenTofu working directory
(`${TMP_DIR}/${CLUSTER_FQDN}`), S3 backend, providers (`helm`, `kubectl`) and
the `litellm` release are reused. You will need the
[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
configured exactly as in that post:

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
```

The environment variables (`AWS_REGION`, `CLUSTER_FQDN`, `TMP_DIR`,
`TF_VAR_cluster_fqdn`, `TF_VAR_tags`, the Google OIDC variables, ...) are the same
ones exported in the base post and are not repeated here.

<!-- prettier-ignore-start -->
> The [Amazon Titan Text Embeddings V2](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html)
> model must be enabled in the [Bedrock console](https://console.aws.amazon.com/bedrock)
> for the target region (one-time, per account) - the Knowledge Base uses it to
> embed Confluence pages.
{: .prompt-info }
<!-- prettier-ignore-end -->

You also need a [Confluence Cloud](https://www.atlassian.com/software/confluence)
site (a free `*.atlassian.net` instance works), at least one space with a few
pages, and an [Atlassian API token](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/)
for [basic authentication](https://docs.aws.amazon.com/bedrock/latest/userguide/confluence-data-source-connector.html).
Map them - together with the "space key" to index - to the `TF_VAR_*` names
the OpenTofu code expects (in CI these come from secrets):

```bash
export TF_VAR_confluence_url="${MY_CONFLUENCE_URL:-https://mylabsdev.atlassian.net}"
export TF_VAR_confluence_username="${MY_CONFLUENCE_EMAIL:-petr.ruzicka@gmail.com}"
export TF_VAR_confluence_api_token="${MY_CONFLUENCE_API_TOKEN:-${MY_ATLASSIAN_PERSONAL_TOKEN:-confluence-api-token-placeholder}}"
export TF_VAR_confluence_space_key="${MY_CONFLUENCE_SPACE_KEY:-myspace}"
```

<!-- prettier-ignore-start -->
> Amazon Bedrock only supports Confluence URLs ending in `.atlassian.net`
> (custom domains are not supported), and basic authentication uses the account
> email as the username with the API token in place of the password.
{: .prompt-info }
<!-- prettier-ignore-end -->

Install the required tools:

- [OpenTofu](https://opentofu.org/)
- [AWS CLI](https://builder.aws.com/build/tools)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)

```bash
mise use opentofu@1.12.1 aws@2.35.2 kubectl@1.36.1
```

## Create a Slack App

Creating the app, installing it to a workspace, and copying the **Bot User OAuth
Token** (`xoxb-...`) are the same steps described in
<!-- rumdl-disable MD013 -->
[Amazon Bedrock AgentCore Slack Bot deployed with OpenTofu]({% post_url /2026/2026-06-11-bedrock-agentcore-slack-opentofu %})
<!-- rumdl-enable MD013 -->
under **Create a Slack App** - follow that section, with two Collmbo-specific
differences:

- **Use a manifest.** When creating the app, choose **From an app manifest**
  (instead of _From scratch_) and paste Collmbo's
  [`manifest.yml`](https://github.com/iwamot/collmbo/blob/main/manifest.yml). It
  already enables Socket Mode and sets the required bot scopes.
- **Generate an App-Level Token.** Socket Mode needs an extra token: go to
  **Settings** > **Basic Information** > **App-Level Tokens**, choose **Generate
  Token and Scopes**, add the `connections:write` scope, and copy the
  **App-Level Token** (`xapp-1-...`).

### Slack permissions and events

The manifest is the source of truth for the bot's permissions, so creating the
app **From an app manifest** is strongly recommended. Collmbo's
[`manifest.yml`](https://github.com/iwamot/collmbo/blob/main/manifest.yml) sets
exactly the following.

**Bot token scopes** (`oauth_config.scopes.bot`):

| Scope               | Why Collmbo needs it                                      |
|---------------------|-----------------------------------------------------------|
| `channels:history`  | Read messages in public channels it is invited to         |
| `groups:history`    | Read messages in private channels                         |
| `im:history`        | Read direct messages                                      |
| `mpim:history`      | Read group direct messages                                |
| `im:write`          | Open direct-message conversations                         |
| `chat:write`        | Post replies                                              |
| `chat:write.public` | Post in public channels without being a member            |
| `files:read`        | Read uploaded images / PDFs for multimodal input          |
| `files:write`       | Upload files back to Slack                                |
| `users:read`        | Look up the sender's locale (the `set_locale` middleware) |

**Subscribed bot events** (`settings.event_subscriptions.bot_events`):

- `app_home_opened`
- `message.channels`
- `message.groups`
- `message.im`
- `message.mpim`

<!-- prettier-ignore-start -->
> Adding scopes or events to an **already-installed** app does nothing until you
> **reinstall** it to the workspace - the existing `xoxb-...` token keeps its old
> scopes. Reinstall, copy the new token, and roll the Deployment so the pod picks
> it up.
{: .prompt-info }
<!-- prettier-ignore-end -->

Map secrets to the `TF_VAR_*` names Collmbo's OpenTofu code expects:

```bash
export TF_VAR_slack_app_token="${MY_SLACK_APP_TOKEN:-xapp-placeholder}"
export TF_VAR_slack_bot_token="${MY_SLACK_BOT_TOKEN:-xoxb-placeholder}"
```

## OpenTofu Code

All resources below are added to the same OpenTofu working directory used by
the base post (`${TMP_DIR}/${CLUSTER_FQDN}`), so they share its state and
providers and can reference its resources directly (the EKS module, the Bedrock
guardrail `aws_bedrock_guardrail.ai_safety`, and the cluster add-ons).

![OpenTofu](https://raw.githubusercontent.com/opentofu/brand-artifacts/af744ad2e454fc47cc7d3c6399aaac15c5c0eeac/full/transparent/SVG/on-dark.svg){:width="300"}

<!-- prettier-ignore-start -->
> **Cost warning.** The Confluence connector requires
> [Amazon OpenSearch Serverless](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-overview.html),
> which bills for a minimum capacity (OCUs) even while idle - on the order of
> hundreds of USD per month.
{: .prompt-warning }
<!-- prettier-ignore-end -->

### Knowledge Base and Collmbo variables

Add the Slack token variables plus the Confluence connection variables. They are
all populated from the `TF_VAR_*` environment variables exported above:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/collmbo-variables.tf" << \EOF
variable "slack_app_token" {
  description = "Slack App-Level Token (xapp-1-...) used for Socket Mode"
  type        = string
  sensitive   = true
}

variable "slack_bot_token" {
  description = "Slack Bot User OAuth Token (xoxb-...)"
  type        = string
  sensitive   = true
}

variable "confluence_url" {
  description = "Confluence Cloud base URL (must end in .atlassian.net)"
  type        = string
}

variable "confluence_username" {
  description = "Atlassian account email used for basic authentication"
  type        = string
}

variable "confluence_api_token" {
  description = "Atlassian API token used in place of the password"
  type        = string
  sensitive   = true
}

variable "confluence_space_key" {
  description = "Key of the single Confluence space to index (e.g. DOCS)"
  type        = string
}
EOF
```

### Confluence credentials in Secrets Manager

The Bedrock Confluence connector reads its credentials only from
[AWS Secrets Manager](https://docs.aws.amazon.com/bedrock/latest/userguide/confluence-data-source-connector.html)
(Parameter Store is not accepted). For [basic authentication](https://docs.aws.amazon.com/bedrock/latest/userguide/kb-managed-confluence-basic-setup.html)
the secret must contain `username` (the account email), `password` (the API
token) and `hostUrl`. OpenTofu renders it from the variables above:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/kb-confluence-secret.tf" << \EOF
resource "aws_secretsmanager_secret" "confluence" {
  name                    = "${local.cluster_name}-confluence"
  description             = "Confluence basic-auth credentials for the Bedrock Knowledge Base"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "confluence" {
  secret_id = aws_secretsmanager_secret.confluence.id
  secret_string = jsonencode({
    username = var.confluence_username
    password = var.confluence_api_token
    hostUrl  = var.confluence_url
  })
}
EOF
```

### OpenSearch Serverless vector store

The Confluence connector is **only supported with an
[Amazon OpenSearch Serverless](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless-vector-search.html)
vector store** (S3 Vectors is not accepted for managed connectors), so the
Knowledge Base stores its embeddings in an OpenSearch Serverless collection of
type `VECTORSEARCH`. The collection needs three policies before it can be created
or used: an encryption policy (required before creation), a network policy, and
a data access policy granting both the OpenTofu caller (to create the index) and
the Knowledge Base role (to read/write vectors):

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/kb-opensearch.tf" << \EOF
locals {
  aoss_collection_name = "${local.cluster_name}-confluence"
  # Field names / dimensions shared by the index and the Knowledge Base mapping.
  aoss_index_name       = "bedrock-knowledge-base-index"
  aoss_vector_field     = "bedrock-knowledge-base-vector"
  aoss_text_field       = "AMAZON_BEDROCK_TEXT_CHUNK"
  aoss_metadata_field   = "AMAZON_BEDROCK_METADATA"
  aoss_vector_dimension = 1024
  aoss_caller_arn = replace(
    replace(data.aws_caller_identity.current.arn, "/:sts::(\\d+):assumed-role/([^/]+)/.*/", ":iam::$1:role/$2"),
    "/^(arn:aws:iam::\\d+:role/[^/]+)/.*/", "$1"
  )
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = local.aoss_collection_name
  type = "encryption"
  policy = jsonencode({
    Rules       = [{ Resource = ["collection/${local.aoss_collection_name}"], ResourceType = "collection" }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = local.aoss_collection_name
  type = "network"
  policy = jsonencode([{
    Rules = [
      { Resource = ["collection/${local.aoss_collection_name}"], ResourceType = "collection" },
      { Resource = ["collection/${local.aoss_collection_name}"], ResourceType = "dashboard" },
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_collection" "confluence" {
  name             = local.aoss_collection_name
  type             = "VECTORSEARCH"
  standby_replicas = "DISABLED"
  depends_on       = [aws_opensearchserverless_security_policy.encryption]
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = local.aoss_collection_name
  type = "data"
  policy = jsonencode([{
    Rules = [
      { Resource = ["collection/${local.aoss_collection_name}"], Permission = ["aoss:*"], ResourceType = "collection" },
      { Resource = ["index/${local.aoss_collection_name}/*"], Permission = ["aoss:*"], ResourceType = "index" },
    ]
    Principal = [
      local.aoss_caller_arn,
      aws_iam_role.bedrock_kb.arn,
    ]
  }])
}
EOF
```

### OpenSearch index (created out of band)

Bedrock expects the vector index to already exist in the collection, but
there is no Terraform, CloudFormation or CDK resource that creates an OpenSearch
Serverless index - only the AWS CLI can. A [`terraform_data`](https://developer.hashicorp.com/terraform/language/resources/terraform-data)
resource runs `aws opensearchserverless create-index` with the kNN schema and is
re-run whenever the collection is replaced:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/kb-index.tf" << \EOF
locals {
  aoss_index_schema = jsonencode({
    settings = { index = { knn = true } }
    mappings = {
      properties = {
        (local.aoss_vector_field) = {
          type      = "knn_vector"
          dimension = local.aoss_vector_dimension
          method    = { name = "hnsw", engine = "faiss", space_type = "l2" }
        }
        (local.aoss_text_field)     = { type = "text" }
        (local.aoss_metadata_field) = { type = "text", index = false }
      }
    }
  })
}

resource "terraform_data" "aoss_index" {
  triggers_replace = [aws_opensearchserverless_collection.confluence.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-CMD
      set -euo pipefail
      ID=${aws_opensearchserverless_collection.confluence.id}
      NAME=${local.aoss_index_name}
      # Retry create-index (the data access policy is eventually consistent) and
      # consider it done once get-index can read it back. This covers propagation
      # delay, an already-existing index, and the index becoming queryable.
      for i in $(seq 1 20); do
        aws opensearchserverless create-index --id "$ID" --index-name "$NAME" \
          --index-schema ${jsonencode(local.aoss_index_schema)} 2> /dev/null || true
        if aws opensearchserverless get-index --id "$ID" --index-name "$NAME" > /dev/null 2>&1; then
          echo "index ready"
          exit 0
        fi
        echo "waiting for index (attempt $i)..."
        sleep 15
      done
      echo "index did not become ready in time" >&2
      exit 1
    CMD
  }

  depends_on = [aws_opensearchserverless_access_policy.data]
}
EOF
```

<!-- prettier-ignore-start -->
> Provisioning the OpenSearch Serverless collection takes **~4-5 minutes**
> (`Still creating...`), and the index/Knowledge Base steps add a couple more.
> This is expected one-time setup time, not a hang.
{: .prompt-info }
<!-- prettier-ignore-end -->

### Bedrock Knowledge Base and Confluence data source

The Knowledge Base ties everything together: an IAM role Bedrock assumes (with
permission to read the Secrets Manager secret, embed with Titan, and access the
OpenSearch collection), the vector configuration, and a **Confluence data
source** restricted to the single space via a `Space` inclusion filter on the
space key:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/kb.tf" << \EOF
data "aws_iam_policy_document" "bedrock_kb_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "bedrock_kb" {
  statement {
    sid       = "ReadConfluenceSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.confluence.arn]
  }
  statement {
    sid       = "InvokeEmbeddingModel"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:*::foundation-model/amazon.titan-embed-text-v2:0"]
  }
  statement {
    sid       = "AccessOpenSearch"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.confluence.arn]
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${local.cluster_name}-bedrock-kb"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_assume.json
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "bedrock-kb"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb.json
}

resource "aws_bedrockagent_knowledge_base" "confluence" {
  name     = "${local.cluster_name}-confluence"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.confluence.arn
      vector_index_name = local.aoss_index_name
      field_mapping {
        vector_field   = local.aoss_vector_field
        text_field     = local.aoss_text_field
        metadata_field = local.aoss_metadata_field
      }
    }
  }

  depends_on = [terraform_data.aoss_index]
}

resource "aws_bedrockagent_data_source" "confluence" {
  name              = "confluence-${var.confluence_space_key}"
  knowledge_base_id = aws_bedrockagent_knowledge_base.confluence.id
  # RETAIN avoids Bedrock DELETE_UNSUCCESSFUL during `tofu destroy`: collection
  # teardown removes vectors anyway, so explicit per-vector purge is unnecessary.
  data_deletion_policy = "RETAIN"

  data_source_configuration {
    type = "CONFLUENCE"
    confluence_configuration {
      source_configuration {
        host_url               = var.confluence_url
        host_type              = "SAAS"
        auth_type              = "BASIC"
        credentials_secret_arn = aws_secretsmanager_secret.confluence.arn
      }
      crawler_configuration {
        filter_configuration {
          type = "PATTERN"
          pattern_object_filter {
            filters {
              object_type       = "Space"
              inclusion_filters = ["^${var.confluence_space_key}$"]
            }
          }
        }
      }
    }
  }
}

# Start a Bedrock ingestion job after the data source is created or changed.
# There is no native Terraform resource for StartIngestionJob, so a terraform_data
# resource shells out to the AWS CLI. The job runs asynchronously - we just kick
# it off and do not block the apply. It re-runs whenever the data source ID
# changes (i.e. when the space filter / data source is replaced).
resource "terraform_data" "confluence_ingestion" {
  triggers_replace = [aws_bedrockagent_data_source.confluence.data_source_id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-CMD
      set -euo pipefail
      aws bedrock-agent start-ingestion-job \
        --knowledge-base-id ${aws_bedrockagent_knowledge_base.confluence.id} \
        --data-source-id ${aws_bedrockagent_data_source.confluence.data_source_id} \
        --query 'ingestionJob.{id:ingestionJobId,status:status}'
    CMD
  }

  depends_on = [aws_bedrockagent_data_source.confluence]
}

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = aws_bedrockagent_knowledge_base.confluence.id
}

output "data_source_id" {
  description = "Confluence data source ID"
  value       = aws_bedrockagent_data_source.confluence.data_source_id
}
EOF
```

### Dedicated LiteLLM release for RAG

The base post owns the `litellm` Helm release and is left untouched. Rather than
mutating that release at runtime, this post deploys a second, dedicated LiteLLM
release (`litellm-kb`) whose `proxy_config` declares the Knowledge Base wiring
natively in the chart values: a
[`vector_store_registry`](https://docs.litellm.ai/docs/completion/knowledgebase)
entry for the Bedrock Knowledge Base and an [always-on](https://docs.litellm.ai/docs/completion/knowledgebase)
`...-kb` model that references it through `vector_store_ids`. Every request to
that model runs _retrieve → augment → generate_ server-side.

> Because this `litellm-kb` release is backed by a database, LiteLLM reads a
> `vector_store_id` from the `LiteLLM_ManagedVectorStores` table, not
> `vector_store_registry`
> ([BerriAI/litellm#25947](https://github.com/BerriAI/litellm/issues/25947)): an
> absent ID silently returns no context. A small idempotent `Job` therefore
> registers the Knowledge Base via the admin API, shipped through
> `extraResources` as a `post-install,post-upgrade` hook.

It is a self-contained copy of the base proxy (own namespace, Pod Identity,
PostgreSQL and master key), so the only thing it shares with the base post is the
Bedrock guardrail and Knowledge Base it points at. The dedicated pod role grants
the Bedrock invoke/guardrail permissions plus `bedrock:Retrieve` for the
Knowledge Base:

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/litellm-kb.tf" << \EOF
# Master key for the dedicated LiteLLM-KB release (independent from the base one).
resource "random_password" "litellm_kb_master_key" {
  length  = 32
  special = false
}

# IAM policy for the litellm-kb pod: Bedrock invoke with guardrail + KB Retrieve.
data "aws_iam_policy_document" "litellm_kb" {
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
  statement {
    sid       = "BedrockRetrieve"
    actions   = ["bedrock:Retrieve"]
    resources = [aws_bedrockagent_knowledge_base.confluence.arn]
  }
}

module "litellm_kb_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  # renovate: datasource=terraform-module depName=terraform-aws-modules/eks-pod-identity/aws
  version = "2.8.1"

  name                    = "${local.cluster_name}-litellm-kb"
  attach_custom_policy    = true
  source_policy_documents = [data.aws_iam_policy_document.litellm_kb.json]

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "litellm-kb"
      service_account = "litellm-kb"
    }
  }
}

resource "helm_release" "litellm_kb" {
  # renovate: datasource=docker depName=docker.litellm.ai/berriai/litellm-helm
  version          = "1.89.2"
  name             = "litellm-kb"
  chart            = "oci://docker.litellm.ai/berriai/litellm-helm"
  namespace        = "litellm-kb"
  create_namespace = true
  wait             = true

  values = [<<-YAML
    replicaCount: 1
    image:
      repository: ghcr.io/berriai/litellm-database
      pullPolicy: Always
    resources:
      requests:
        memory: 1Gi
    masterkey: sk-${random_password.litellm_kb_master_key.result}
    serviceAccount:
      create: true
      name: litellm-kb
    service:
      port: 4000
    db:
      deployStandalone: true
    postgresql:
      image:
        tag: latest
      auth:
        password: ${random_password.litellm_kb_master_key.result}
        postgres-password: ${random_password.litellm_kb_master_key.result}
    disableSchemaUpdate: false
    migrationJob:
      enabled: false
    proxy_config:
      model_list:
        # Always-on RAG model: every call queries the Bedrock Knowledge Base
        # (Retrieve) and prepends the context before invoking Bedrock.
        - model_name: us.anthropic.claude-haiku-4-5-20251001-v1:0-kb
          litellm_params:
            model: bedrock/us.anthropic.claude-haiku-4-5-20251001-v1:0
            aws_region_name: ${data.aws_region.current.region}
            vector_store_ids: ["${aws_bedrockagent_knowledge_base.confluence.id}"]
            # Claude on Bedrock rejects temperature+top_p together.
            # Collmbo sends temperature, so drop top_p.
            additional_drop_params: ["top_p"]
            guardrailConfig:
              guardrailIdentifier: ${aws_bedrock_guardrail.ai_safety.guardrail_arn}
              guardrailVersion: "DRAFT"
              trace: "disabled"
      vector_store_registry:
        - vector_store_name: confluence-knowledge-base
          litellm_params:
            vector_store_id: ${aws_bedrockagent_knowledge_base.confluence.id}
            custom_llm_provider: bedrock
            vector_store_description: Confluence pages indexed by Amazon Bedrock
      litellm_settings:
        drop_params: true
      general_settings:
        store_model_in_db: true
        store_prompts_in_spend_logs: true
    # With a database attached, LiteLLM reads vector stores from the
    # LiteLLM_ManagedVectorStores table, not "vector_store_registry"
    # an unregistered KB ID falls back to the OpenAI provider and silently
    # loses RAG context. This idempotent post-install,post-upgrade hook Job
    # writes the DB row via the admin API.
    extraResources:
      - apiVersion: batch/v1
        kind: Job
        metadata:
          name: litellm-kb-vector-store-register
          namespace: litellm-kb
          annotations:
            # Run after the release each install/upgrade, once the proxy exists,
            # and self-delete on success so the next upgrade re-runs it.
            helm.sh/hook: post-install,post-upgrade
            helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
          labels:
            app.kubernetes.io/name: litellm-kb-vector-store-register
        spec:
          # The script already waits for proxy readiness, so retries here only
          # cover genuine registration errors; keep the default backoff so real
          # failures surface instead of being retried many times.
          backoffLimit: 6
          ttlSecondsAfterFinished: 600
          template:
            metadata:
              labels:
                app.kubernetes.io/name: litellm-kb-vector-store-register
            spec:
              restartPolicy: OnFailure
              securityContext:
                runAsNonRoot: true
                runAsUser: 65534
                seccompProfile:
                  type: RuntimeDefault
              containers:
                - name: register
                  # renovate: datasource=docker depName=curlimages/curl
                  image: curlimages/curl:8.18.0
                  securityContext:
                    allowPrivilegeEscalation: false
                    readOnlyRootFilesystem: true
                    capabilities:
                      drop: ["ALL"]
                  env:
                    - name: MASTER_KEY
                      valueFrom:
                        secretKeyRef:
                          name: litellm-kb-masterkey
                          key: masterkey
                    - name: KB_ID
                      value: "${aws_bedrockagent_knowledge_base.confluence.id}"
                    - name: BASE_URL
                      value: http://litellm-kb.litellm-kb.svc:4000
                  command:
                    - /bin/sh
                    - -c
                    - |
                      set -eu
                      echo "Waiting for LiteLLM proxy to be ready..."
                      until curl -sf -m 5 "$${BASE_URL}/health/readiness" > /dev/null; do
                        sleep 5
                      done
                      # Register the Knowledge Base as a bedrock vector store.
                      # /vector_store/new returns 200 on success and an "already
                      # exists" error on re-runs, so the POST response alone is
                      # enough to be idempotent - no separate existence check.
                      echo "Registering vector store $${KB_ID} (provider: bedrock)..."
                      RESP="$(curl -s -m 30 -w '\n%%{http_code}' "$${BASE_URL}/vector_store/new" \
                        -H "Authorization: Bearer $${MASTER_KEY}" \
                        -H "Content-Type: application/json" \
                        -d "{\"vector_store_id\":\"$${KB_ID}\",\"custom_llm_provider\":\"bedrock\",\"vector_store_name\":\"confluence-knowledge-base\",\"vector_store_description\":\"Confluence pages indexed by Amazon Bedrock\"}")"
                      CODE="$(printf '%s' "$${RESP}" | tail -n1)"
                      echo "Response: $${RESP}"
                      if [ "$${CODE}" = "200" ]; then
                        echo "Registered successfully."
                      elif printf '%s' "$${RESP}" | grep -q "already exists"; then
                        echo "Already exists - treating as success."
                      else
                        echo "Registration failed." >&2
                        exit 1
                      fi
  YAML
  ]

  depends_on = [
    kubectl_manifest.nodepool_default,
    module.litellm_kb_pod_identity,
    helm_release.cert_manager,
    aws_bedrockagent_knowledge_base.confluence,
  ]
}

# HTTPRoute exposes the litellm-kb API through the Envoy Gateway at
# litellm-kb.${var.cluster_fqdn} (the base post owns the plain "litellm" host).
resource "kubectl_manifest" "litellm_kb_httproute" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: litellm-kb
      namespace: litellm-kb
    spec:
      parentRefs:
        - name: eg
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - litellm-kb.${var.cluster_fqdn}
      rules:
        - backendRefs:
            - name: litellm-kb
              port: 4000
  YAML
  depends_on = [
    helm_release.litellm_kb,
    kubectl_manifest.gateway,
  ]
}
EOF
```

### Collmbo Deployment

[Collmbo](https://github.com/iwamot/collmbo) is published only as a container
image (there is no Helm chart), so it is deployed with a plain Kubernetes
`Deployment` through the [`alekc/kubectl`](https://registry.terraform.io/providers/alekc/kubectl/latest/docs)
provider. The key wiring is in the environment variables:

- `LLM_MODEL` is set to the **knowledge-base-attached** model
  (`openai/us.anthropic.claude-haiku-4-5-...-kb`). The `openai/` prefix routes the
  call through LiteLLM's [OpenAI-compatible](https://docs.litellm.ai/docs/providers/openai_compatible)
  path; the `-kb` suffix selects the model that performs RAG server-side. This
  single value is the **only** Collmbo-side change needed for Confluence answers.
- `OPENAI_API_BASE` points at the in-cluster `litellm-kb` Service.
- `OPENAI_API_KEY` uses the `litellm-kb` master key
  (`random_password.litellm_kb_master_key`) so no extra secret is invented.
- `SYSTEM_PROMPT_TEMPLATE` overrides Collmbo's
  [default prompt](https://github.com/iwamot/collmbo/blob/main/app/env.py), which
  makes the bot prepend its own Slack mention (`<@U...>`) to every reply. The
  Bedrock guardrail's `PASSWORD` PII entity (`ANONYMIZE`) misreads that token as
  a credential and rewrites replies to `<{PASSWORD}>: ...` with a
  `content_filter` finish reason. The replacement prompt simply forbids emitting
  mention tokens, fixing the false positive without weakening the guardrail.

The image also ships a default [`config/mcp.yml`](https://github.com/iwamot/collmbo/blob/main/config/mcp.yml)
that enables the public [AWS Knowledge](https://awslabs.github.io/mcp/servers/aws-knowledge-mcp-server/)
MCP server. Collmbo loads those tools at startup and passes them to the model on
every request, and their AWS-centric descriptions nudge the bot into answering
as an _AWS assistant_ regardless of the question. A `ConfigMap` with an empty
`servers: []` list is mounted over that file to disable MCP - this also keeps the
tool list empty so it never competes with Knowledge Base retrieval.

![Collmbo](https://github.com/user-attachments/assets/b13da1c7-5d2f-4ad3-8c5b-9ef4e500deb8){:width="150"}

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/collmbo.tf" << \EOF
# Dedicated namespace for the bot.
resource "kubectl_manifest" "collmbo_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: collmbo
  YAML
}

# The image's default /app/config/mcp.yml enables the AWS Knowledge MCP server,
# whose tools bias every reply toward AWS. Mount an empty list to disable MCP.
resource "kubectl_manifest" "collmbo_mcp_config" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: collmbo-mcp
      namespace: collmbo
    data:
      mcp.yml: |
        servers: []
  YAML
  depends_on = [kubectl_manifest.collmbo_namespace]
}

# Secret holding the Slack Socket Mode tokens and the litellm-kb master key
# reused as the OpenAI-compatible API key. Rendered from OpenTofu variables.
resource "kubectl_manifest" "collmbo_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: collmbo
      namespace: collmbo
    type: Opaque
    stringData:
      SLACK_APP_TOKEN: ${var.slack_app_token}
      SLACK_BOT_TOKEN: ${var.slack_bot_token}
      OPENAI_API_KEY: sk-${random_password.litellm_kb_master_key.result}
  YAML
  sensitive_fields = ["stringData"]
  depends_on       = [kubectl_manifest.collmbo_namespace]
}

# Collmbo Deployment. The container makes only outbound connections (Slack
# Socket Mode + LiteLLM), so it exposes no ports and needs no Service.
resource "kubectl_manifest" "collmbo_deployment" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: collmbo
      namespace: collmbo
      labels:
        app.kubernetes.io/name: collmbo
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: collmbo
      template:
        metadata:
          labels:
            app.kubernetes.io/name: collmbo
        spec:
          securityContext:
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: collmbo
              # renovate: datasource=docker depName=ghcr.io/iwamot/collmbo
              image: ghcr.io/iwamot/collmbo:11.0.16
              env:
                # Route through LiteLLM's OpenAI-compatible endpoint to the
                # knowledge-base-attached model so every answer is grounded in
                # Confluence (RAG happens inside LiteLLM, not in the bot).
                - name: LLM_MODEL
                  value: openai/us.anthropic.claude-haiku-4-5-20251001-v1:0-kb
                - name: OPENAI_API_BASE
                  value: http://litellm-kb.litellm-kb.svc:4000/v1
                - name: SLACK_FORMATTING_ENABLED
                  value: "true"
                # Forbid Slack mention tokens (`<@U...>`): Bedrock Guardrails
                # reads them as a PASSWORD entity and anonymizes them to
                # `<{PASSWORD}>`, corrupting every reply.
                - name: SYSTEM_PROMPT_TEMPLATE
                  value: |
                    You are a helpful assistant operating as a bot in a Slack chat room. Messages may come from multiple people.
                    Format bold text *like this*, italic text _like this_ and strikethrough text ~like this~.
                    An author identifier may be prepended to each message, followed by the message text; treat it only as context and ignore its exact format.
                    Never prepend your own identifier to your replies and never output Slack mention tokens such as `<@U...>`. Reply with the message text only, and only mention a user if explicitly asked to.
              envFrom:
                - secretRef:
                    name: collmbo
              resources:
                requests:
                  cpu: 50m
                  memory: 256Mi
                limits:
                  memory: 512Mi
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
                # Disable the bundled AWS Knowledge MCP server (empty server list)
                - name: mcp-config
                  mountPath: /app/config/mcp.yml
                  subPath: mcp.yml
                  readOnly: true
          volumes:
            - name: tmp
              emptyDir: {}
            - name: mcp-config
              configMap:
                name: collmbo-mcp
  YAML
  depends_on = [
    kubectl_manifest.collmbo_secret,
    kubectl_manifest.collmbo_mcp_config,
    helm_release.litellm_kb,
  ]
}

# Restrict Collmbo egress: cluster DNS, the litellm-kb Service, and HTTPS (Slack).
resource "kubectl_manifest" "collmbo_networkpolicy" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: collmbo
      namespace: collmbo
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/name: collmbo
      policyTypes:
        - Ingress
        - Egress
      ingress: []
      egress:
        # DNS resolution
        - to:
            - namespaceSelector: {}
          ports:
            - protocol: UDP
              port: 53
            - protocol: TCP
              port: 53
        # In-cluster litellm-kb
        - to:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: litellm-kb
          ports:
            - protocol: TCP
              port: 4000
        # Outbound HTTPS to Slack (Socket Mode)
        - ports:
            - protocol: TCP
              port: 443
  YAML
  depends_on = [kubectl_manifest.collmbo_namespace]
}
EOF
```

## OpenTofu Code - apply

Initialise the OpenTofu working directory and apply. This is the same
idempotent apply used by the base post - re-running it simply adds the Knowledge
Base, OpenSearch Serverless collection, Confluence data source, the `litellm-kb`
release and Collmbo to the existing cluster:

```bash
if aws s3api head-bucket --bucket "${CLUSTER_FQDN}" 2> /dev/null; then
  tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" init
  if [[ ! ${MY_TASK:-} =~ delete: ]]; then
    tofu -chdir="${TMP_DIR}/${CLUSTER_FQDN}" apply -auto-approve
  fi
fi
```

## Test the integration

Invite the bot to a channel and ask it something that is documented "only"
in your Confluence space:

```shell
/invite @Slack Bot
@Slack Bot What is the recommended way to secure new Kubernetes clusters?
```

Collmbo replies in channels, threads, and DMs. Because `LLM_MODEL` points at the
`...-kb` model, LiteLLM retrieves the relevant Confluence chunks from the Knowledge
Base and the Bedrock model answers from them - so the reply reflects your wiki,
not the model's general knowledge.

<!-- prettier-ignore-start -->
> The ingestion job is started **asynchronously** by the apply (it is not waited
> on), so give it a few minutes to finish before testing - until the first job
> reaches `COMPLETE` the Knowledge Base is empty and answers fall back to the
> model's general knowledge. Track progress with the
> [`list-ingestion-jobs`](https://docs.aws.amazon.com/cli/latest/reference/bedrock-agent/list-ingestion-jobs.html)
> CLI command (or the Bedrock console).
{: .prompt-info }
<!-- prettier-ignore-end -->

## Clean-up

Collmbo, the dedicated `litellm-kb` release, the Knowledge Base, the OpenSearch
Serverless collection and the Confluence secret all live inside the base
cluster's OpenTofu state, so the standard clean-up from
<!-- rumdl-disable MD013 -->
[Amazon EKS with Open WebUI and AWS Bedrock managed by OpenTofu]({% post_url /2026/2026-05-26-openwebui-eks-bedrock-opentofu %})
<!-- rumdl-enable MD013 -->
removes them together with the rest of the cluster - there is nothing extra to
delete.

![Clean-up](https://raw.githubusercontent.com/cubanpit/cleanupdate/7aaccaa36ab4888a0847b267ed24d079dfed7863/icons/cleanupdate.svg){:width="100"}

The full teardown (`tofu destroy`, S3 state removal, Karpenter EC2 cleanup, ...)
is performed by the base post's clean-up steps, which recreate both OpenTofu
files and destroy the whole working directory at once:

```sh
export TF_VAR_slack_app_token="anything"
export TF_VAR_slack_bot_token="anything"
export TF_VAR_confluence_url="https://example.atlassian.net"
export TF_VAR_confluence_username="anything"
export TF_VAR_confluence_api_token="anything"
export TF_VAR_confluence_space_key="DOCS"
```

Enjoy ... 😉
