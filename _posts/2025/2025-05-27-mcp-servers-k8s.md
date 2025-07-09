---
title: MCP Servers running on Kubernetes
author: Petr Ruzicka
date: 2025-05-27
description:
categories: [Kubernetes, Amazon EKS Auto Mode, MCP]
tags:
  [
    amazon eks auto mode,
    amazon eks,
    k8s,
    kubernetes,
    mcp,
  ]
image: https://raw.githubusercontent.com/lobehub/lobe-icons/2889d303d4d0a3a7082fd9ff56e3df80b0b0c7d3/packages/static-png/light/mcp.png
---

<!-- markdownlint-disable MD013 -->
In the previous post, [Build secure and cheap Amazon EKS Auto Mode]({% post_url /2024/2024-12-14-secure-cheap-amazon-eks-auto %})
<!-- markdownlint-enable MD013 -->
I used [cert-manager](https://cert-manager.io/) to obtain a [wildcard certificate](https://en.wikipedia.org/wiki/Public_key_certificate#Wildcard_certificate)
for the [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/).
This post will explore running various MCP servers in Kubernetes, aiming to
power a web chat application like ChatGPT for data queries.

![MCP Architecture](https://raw.githubusercontent.com/Otman404/Otman404.github.io/656fb0030812c6061b0b6fc7abfc7f2cdc36995b/assets/mcp/mcp_architecture.png)

This post will guide you through the following steps:

- **ToolHive Installation**: Setting up ToolHive, a secure manager for MCP
  servers in Kubernetes.
- **MCP Server Deployment**: Deploying `fetch`, `github`, and `mkp` MCP servers.
- **LibreChat Installation**: Installing and configuring LibreChat,
  a self-hosted web chat application.
- **Open WebUI Installation**: Setting up Open WebUI, a user-friendly interface
  for chat interactions.

By the end of this tutorial, you'll have a fully functional chat application
powered by MCP servers running on your EKS cluster.

## Requirements

<!-- markdownlint-disable MD013 -->
- Amazon EKS Auto Mode cluster (described in
  [Build secure and cheap Amazon EKS Auto Mode]({% post_url /2024/2024-12-14-secure-cheap-amazon-eks-auto %}))
<!-- markdownlint-enable MD013 -->
- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [Helm](https://helm.sh)
- [kubectl](https://github.com/kubernetes/kubectl)

You will need the following environment variables. Replace the placeholder
values with your actual credentials:

```shell
LIBRECHAT_CREDS_KEY="$(openssl rand -hex 32)"
LIBRECHAT_CREDS_IV="$(openssl rand -hex 16)"
LIBRECHAT_JWT_SECRET="$(openssl rand -hex 32)"
LIBRECHAT_JWT_REFRESH_SECRET="$(openssl rand -hex 32)"
LIBRECHAT_GITHUB_PERSONAL_ACCESS_TOKEN="github_pat_11AAxxxxxxxxxxxxxxxDW"
LIBRECHAT_OPENAI_API_KEY="eyJ...TqQ"
LIBRECHAT_OPENAI_BASE_URL="https://openai....com/b8...82/v1"
export LIBRECHAT_CREDS_KEY LIBRECHAT_CREDS_IV LIBRECHAT_JWT_SECRET LIBRECHAT_JWT_REFRESH_SECRET
```

Variables used in the following steps:

```bash
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev,Cluster=${CLUSTER_FQDN}}"
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

Verify if all the necessary variables were set:

```bash
: "${LIBRECHAT_GITHUB_PERSONAL_ACCESS_TOKEN?}"
: "${LIBRECHAT_CREDS_KEY?}"
: "${LIBRECHAT_CREDS_IV?}"
: "${LIBRECHAT_JWT_SECRET?}"
: "${LIBRECHAT_JWT_REFRESH_SECRET?}"
: "${LIBRECHAT_OPENAI_API_KEY?}"
: "${LIBRECHAT_OPENAI_BASE_URL?}"
```

## Install ToolHive

[ToolHive](https://github.com/stacklok/toolhive) is an open-source, lightweight,
and secure manager for MCP (Model Context Protocol) servers, designed to
simplify the deployment and management of AI model servers in Kubernetes
environments.

![ToolHive](https://raw.githubusercontent.com/stacklok/toolhive/c0984e2f1d31ffb9aa215e48df60477e38249aa9/docs/images/toolhive.png){:width="400"}

Install [toolhive-operator-crds](https://github.com/stacklok/toolhive/tree/v0.1.0/deploy/charts/operator)
and [toolhive-operator](https://github.com/stacklok/toolhive/tree/v0.1.0/deploy/charts/operator-crds)
helm charts.

Install the `toolhive-operator-crds` and `toolhive-operator` Helm charts:

```bash
# renovate: datasource=github-tags depName=stacklok/toolhive extractVersion=^toolhive-operator-crds-(?<version>.*)$
TOOLHIVE_OPERATOR_CRDS_HELM_CHART_VERSION="0.0.9"
helm upgrade --install --version="${TOOLHIVE_OPERATOR_CRDS_HELM_CHART_VERSION}" toolhive-operator-crds oci://ghcr.io/stacklok/toolhive/toolhive-operator-crds
# renovate: datasource=github-tags depName=stacklok/toolhive extractVersion=^toolhive-operator-(?<version>.*)$
TOOLHIVE_OPERATOR_HELM_CHART_VERSION="0.1.0"
helm upgrade --install --version="${TOOLHIVE_OPERATOR_HELM_CHART_VERSION}" --namespace toolhive-system --create-namespace toolhive-operator oci://ghcr.io/stacklok/toolhive/toolhive-operator
```

### Deploy MCP Servers

Create a secret with your GitHub token and deploy the `fetch`, `github`,
and `mkp` MCP servers:

```bash
kubectl create secret generic github-token --namespace=toolhive-system --from-literal=token="${LIBRECHAT_GITHUB_PERSONAL_ACCESS_TOKEN}"
# renovate: datasource=github-tags depName=stacklok/toolhive
TOOLHIVE_VERSION="0.1.3"
kubectl apply -f https://raw.githubusercontent.com/stacklok/toolhive/refs/tags/v${TOOLHIVE_VERSION}/examples/operator/mcp-servers/mcpserver_fetch.yaml
kubectl apply -f https://raw.githubusercontent.com/stacklok/toolhive/refs/tags/v${TOOLHIVE_VERSION}/examples/operator/mcp-servers/mcpserver_github.yaml
kubectl apply -f https://raw.githubusercontent.com/stacklok/toolhive/refs/tags/v${TOOLHIVE_VERSION}/examples/operator/mcp-servers/mcpserver_mkp.yaml
```

## Install Librechat

[LibreChat](https://github.com/danny-avila/LibreChat) is an open-source,
self-hosted web chat application designed as an enhanced alternative to ChatGPT.
It supports multiple AI providers (including OpenAI, Azure, Google, and more),
offers a user-friendly interface, conversation management, plugin support, and
advanced features like prompt templates and file uploads.

![LibreChat](https://raw.githubusercontent.com/danny-avila/LibreChat/8f20fb28e549949b05e8b164d8a504bc14c0951a/client/public/assets/logo.svg){:width="300"}

Create `librechat` namespace and secrets with environment variables:

```bash
kubectl create namespace librechat
kubectl create secret generic --namespace librechat librechat-credentials-env \
  --from-literal=CREDS_KEY="${LIBRECHAT_CREDS_KEY}" \
  --from-literal=CREDS_IV="${LIBRECHAT_CREDS_IV}" \
  --from-literal=JWT_SECRET="${LIBRECHAT_JWT_SECRET}" \
  --from-literal=JWT_REFRESH_SECRET="${LIBRECHAT_JWT_REFRESH_SECRET}"
```

Install `librechat` [helm chart](https://github.com/danny-avila/LibreChat/tree/main/helm/librechat)
and modify the [default values](https://github.com/danny-avila/LibreChat/blob/main/helm/librechat/values.yaml).

```bash
# renovate: datasource=helm depName=librechat registryUrl=https://charts.blue-atlas.de
LIBRECHAT_HELM_CHART_VERSION="1.8.10"

helm repo add librechat https://charts.blue-atlas.de
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-librechat.yml" << EOF
librechat:
  # https://www.librechat.ai/docs/configuration/dotenv
  configEnv:
    ALLOW_EMAIL_LOGIN: "true"
    ALLOW_REGISTRATION: "true"
    DEBUG_CONSOLE: "true"
    ENDPOINTS: agents,custom
    existingSecretName: librechat-credentials-env
  # https://github.com/danny-avila/LibreChat/blob/main/librechat.example.yaml
  configYamlContent:
    version: 1.2.1
    cache: true
    endpoints:
      custom:
        - name: My OpenAI Gateway
          apiKey: ${LIBRECHAT_OPENAI_API_KEY}
          baseURL: ${LIBRECHAT_OPENAI_BASE_URL}
          models:
            default: ["gpt-4"]
    mcpServers:
      fetch:
        url: http://mcp-fetch-proxy.toolhive-system.svc.cluster.local:8080/sse
      github:
        url: http://mcp-github-proxy.toolhive-system.svc.cluster.local:8080/sse
      mkp:
        url: http://mcp-mkp-proxy.toolhive-system.svc.cluster.local:8080/sse
  imageVolume:
    enabled: false
ingress:
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/description: LibreChat is an open-source, self-hosted web chat application designed as an enhanced alternative to ChatGPT
    gethomepage.dev/group: Apps
    gethomepage.dev/icon: https://raw.githubusercontent.com/danny-avila/LibreChat/8f20fb28e549949b05e8b164d8a504bc14c0951a/client/public/assets/logo.svg
    gethomepage.dev/name: Librechat
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  hosts:
    - host: librechat.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
        - librechat.${CLUSTER_FQDN}
# https://github.com/bitnami/charts/blob/main/bitnami/mongodb/values.yaml
mongodb:
  image:
    repository: dlavrenuek/bitnami-mongodb-arm
    tag: 8.0.4
  containerSecurityContext:
    seLinuxOptions:
      type: "container_t"
meilisearch:
  enabled: false
EOF
helm upgrade --install --version "${LIBRECHAT_HELM_CHART_VERSION}" --namespace librechat --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-librechat.yml" librechat librechat/librechat
```

## Install Open WebUI

[Open WebUI](https://openwebui.com/) is a user-friendly web interface for chat interactions.

Install `open-webui` [helm chart](https://github.com/open-webui/helm-charts/tree/main/charts/open-webui)
and modify the [default values](https://github.com/open-webui/helm-charts/blob/main/charts/open-webui/values.yaml).

```bash
kubectl create namespace open-webui
# kubectl create secret generic --namespace open-webui open-webui-env-vars \
#   --from-literal="openai_api_key=${LIBRECHAT_OPENAI_API_KEY}" \
#   --from-literal="openai_api_base_url=${LIBRECHAT_OPENAI_BASE_URL}"

# renovate: datasource=helm depName=open-webui registryUrl=https://helm.openwebui.com
OPEN_WEBUI_HELM_CHART_VERSION="6.19.0"

helm repo add open-webui https://helm.openwebui.com/
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-open-webui.yml" << EOF
ollama:
  persistentVolume:
    enabled: true
pipelines:
  enabled: false
ingress:
  enabled: true
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/description: Open WebUI is a user friendly web interface for chat interactions.
    gethomepage.dev/group: Apps
    gethomepage.dev/icon: https://raw.githubusercontent.com/open-webui/open-webui/14a6c1f4963892c163821765efcc10c5c4578454/static/static/favicon.svg
    gethomepage.dev/name: Open WebUI
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  host: open-webui.${CLUSTER_FQDN}
# openaiBaseApiUrl: ${LIBRECHAT_OPENAI_BASE_URL}
extraEnvVars:
  # - name: OPENAI_API_BASE_URL
  #   valueFrom:
  #     secretKeyRef:
  #       name: open-webui-env-vars
  #       key: openai_api_base_url
  # - name: OPENAI_API_KEY
  #   valueFrom:
  #     secretKeyRef:
  #       name: open-webui-env-vars
  #       key: openai_api_key
  - name: ADMIN_EMAIL
    value: ${MY_EMAIL}
  - name: ENV
    value: dev
  - name: WEBUI_URL
    value: https://open-webui.${CLUSTER_FQDN}
  # - name: OLLAMA_BASE_URL
  #   value: http://open-webui-ollama.open-webui.svc.cluster.local:11434
EOF
helm upgrade --install --version "${OPEN_WEBUI_HELM_CHART_VERSION}" --namespace open-webui --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-open-webui.yml" open-webui open-webui/open-webui
```

Enjoy ... 😉
