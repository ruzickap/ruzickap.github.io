---
title: Argo CD Vault Plugin with AWS Secret Manager
author: Petr Ruzicka
date: 2023-05-23
description: Intrgrate Argo CD Vault Plugin with AWS Secret Manager and use the secrets inside Application installing Helm Chart
categories: [Kubernetes, Amazon EKS, AWS Secrets Manager, argocd-vault-plugin, argocd]
tags: [Amazon EKS, k8s, kubernetes, AWS Secrets Manager, argocd-vault-plugin, argocd]
image:
  path: https://raw.githubusercontent.com/cncf/artwork/fb84e337e4234b14c770d2dc2dafefe2b25b2881/projects/argo/horizontal/color/argo-horizontal-color.svg
---

I desired to delve a bit deeper into the [Argo CD Vault Plugin](https://argocd-vault-plugin.readthedocs.io/en/stable/)
and explore the process of integrating it with [AWS Secret Manager](https://aws.amazon.com/secrets-manager/).

## Requirements

* Amazon EKS cluster (described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}))
* [Helm](https://helm.sh/)
* [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

Variables which are being used in the next steps:

```bash
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

## Create secret in AWS Secrets Manager

Use CloudFormation to create Policy and Secrets in [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/):

```bash
cat > "${TMP_DIR}/${CLUSTER_FQDN}/aws-secretmanager-secret-podinfo.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Secret Manager and policy
Parameters:
  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: kube1.k8s.mylabs.dev"
    Type: String

Resources:
  SecretsManagerPodinfoSecretPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-SecretsManagerPodinfoSecret"
      Description: !Sub "Policy required by SecretsManager to access to Secrets Manager ${ClusterFQDN}-PodinfoSecret"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Sid: SecretActions
            Effect: Allow
            Action:
              - "secretsmanager:GetSecretValue"
              - "secretsmanager:DescribeSecret"
            Resource: !Ref SecretsManagerPodinfoSecret
  SecretsManagerPodinfoSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ClusterFQDN}-PodinfoSecret"
      Description: My Secret
      SecretString: "{\"podinfo_secret_message\": \"Secret Message form AWS Secrets Manager\"}"

Outputs:
  SecretsManagerPodinfoSecretArn:
    Description: The ARN of the created Amazon SecretsManagerPodinfoSecret Secret
    Value: !Ref SecretsManagerPodinfoSecret
  SecretsManagerPodinfoSecretPolicyArn:
    Description: The ARN of the created SecretsManagerPodinfoSecret Policy
    Value: !Ref SecretsManagerPodinfoSecretPolicy
EOF

aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterFQDN=${CLUSTER_FQDN}" \
  --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret-podinfo" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-secretmanager-secret-podinfo.yml"
```

Screenshot from AWS Secrets Manager:

![aws-secrets-manager-01-secrets-PodinfoSecret](/assets/img/posts/2023/2023-05-23-argocd-vault-plugin-and-aws-secret-manager/aws-secrets-manager-01-secrets-podinfosecret.avif
"AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-PodinfoSecret")
_AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-PodinfoSecret_

## Install ArgoCD with Argo CD Vault Plugin

Create ServiceAccount (`argocd-repo-server`) in `argocd` namespace - [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).

```bash
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret-podinfo")
SECRETS_MANAGER_PODINFOSECRET_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"SecretsManagerPodinfoSecretPolicyArn\") .OutputValue")
eksctl create iamserviceaccount --cluster="${CLUSTER_NAME}" --name=argocd-repo-server --namespace=argocd --attach-policy-arn="${SECRETS_MANAGER_PODINFOSECRET_POLICY_ARN}" --role-name="eksctl-${CLUSTER_NAME}-irsa-argocd" --approve
```

Install `argo-cd`
[helm chart](https://artifacthub.io/packages/helm/argo/argo-cd)
and modify the
[default values](https://github.com/argoproj/argo-helm/blob/master/charts/argo-cd/values.yaml).

```bash
# renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
ARGOCD_HELM_CHART_VERSION="5.46.2"

helm repo add argo https://argoproj.github.io/argo-helm
tee "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-argocd.yml" << EOF
global:
  logging:
    level: debug
configs:
  cm:
    admin.enabled: false
    users.anonymous.enabled: false
  params:
    server.insecure: true
  rbac:
    policy.default: role:admin
  cmp:
    create: true
    plugins:
      avp-kustomize:
        allowConcurrency: true
        discover:
          find:
            command:
              - find
              - "."
              - "-name"
              - kustomization.yaml
        generate:
          command:
            - sh
            - "-c"
            - "kustomize build . | argocd-vault-plugin generate --verbose-sensitive-output -"
        lockRepo: false
      avp-helm:
        allowConcurrency: true
        discover:
          find:
            command:
              - sh
              - "-c"
              - "find . -name 'Chart.yaml' && find . -name 'values.yaml'"
        generate:
          command:
            - sh
            - "-c"
            - |
              helm template \$ARGOCD_APP_NAME -n \$ARGOCD_APP_NAMESPACE -f <(echo "\$ARGOCD_ENV_helm_values") . |
              argocd-vault-plugin generate --verbose-sensitive-output -
        lockRepo: false
      avp:
        allowConcurrency: true
        discover:
          find:
            command:
              - sh
              - "-c"
              - "find . -name '*.yaml' | xargs -I {} grep \\"<path\\\\|avp\\\\.kubernetes\\\\.io\\" {} | grep ."
        generate:
          command:
            - argocd-vault-plugin
            - generate
            - "--verbose-sensitive-output"
            - "."
        lockRepo: false
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
    rules:
      enabled: true
      namespace: kube-prometheus-stack
      spec:
      - alert: ArgoAppMissing
        expr: |
          absent(argocd_app_info) == 1
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "[Argo CD] No reported applications"
          description: >
            Argo CD has not reported any applications data for the past 15 minutes which
            means that it must be down or not functioning properly.  This needs to be
            resolved for this cloud to continue to maintain state.
      - alert: ArgoAppNotSynced
        expr: |
          argocd_app_info{sync_status!="Synced"} == 1
        for: 12h
        labels:
          severity: warning
        annotations:
          summary: "[{{\`{{\$labels.name}}\`}}] Application not synchronized"
          description: >
            The application [{{\`{{\$labels.name}}\`}} has not been synchronized for over
            12 hours which means that the state of this cloud has drifted away from the
            state inside Git.
dex:
  enabled: false
redis:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
server:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      forecastle.stakater.com/expose: "true"
      forecastle.stakater.com/icon: https://raw.githubusercontent.com/cncf/artwork/master/projects/argo/icon/color/argo-icon-color.svg
      forecastle.stakater.com/appName: Argo CD
      nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
      nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
    hosts:
      - argocd.${CLUSTER_FQDN}
    tls:
      - hosts:
          - argocd.${CLUSTER_FQDN}
repoServer:
  env:
    - name: AVP_TYPE
      value: awssecretsmanager
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  serviceAccount:
    create: false
    name: argocd-repo-server
  initContainers:
  - name: download-tools
    image: alpine:latest
    command: [sh, -c]
    env:
    - name: AVP_VERSION
      # renovate: datasource=github-tags depName=argoproj-labs/argocd-vault-plugin extractVersion=^(?<version>.*)$
      value: 1.14.0
    - name: AVP_ARCHITECTURE
      value: arm64
    args:
    - >-
      wget -O argocd-vault-plugin
      https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v\${AVP_VERSION}/argocd-vault-plugin_\${AVP_VERSION}_linux_\${AVP_ARCHITECTURE} &&
      chmod +x argocd-vault-plugin &&
      mv argocd-vault-plugin /custom-tools/
    volumeMounts:
    - mountPath: /custom-tools
      name: custom-tools
  extraContainers:
    - name: avp
      command: [/var/run/argocd/argocd-cmp-server]
      # renovate: datasource=docker depName=quay.io/argoproj/argocd extractVersion=^(?<version>.+)$
      image: quay.io/argoproj/argocd:v2.7.14
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: avp.yaml
          name: argocd-cmp-cm
        - name: custom-tools
          subPath: argocd-vault-plugin
          mountPath: /usr/local/bin/argocd-vault-plugin
    - name: avp-helm
      command: [/var/run/argocd/argocd-cmp-server]
      # renovate: datasource=docker depName=quay.io/argoproj/argocd extractVersion=^(?<version>.+)$
      image: quay.io/argoproj/argocd:v2.7.14
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: avp-helm.yaml
          name: argocd-cmp-cm
        - name: custom-tools
          subPath: argocd-vault-plugin
          mountPath: /usr/local/bin/argocd-vault-plugin
    - name: avp-kustomize
      command: [/var/run/argocd/argocd-cmp-server]
      # renovate: datasource=docker depName=quay.io/argoproj/argocd extractVersion=^(?<version>.+)$
      image: quay.io/argoproj/argocd:v2.7.14
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
      volumeMounts:
        - mountPath: /var/run/argocd
          name: var-files
        - mountPath: /home/argocd/cmp-server/plugins
          name: plugins
        - mountPath: /tmp
          name: tmp
        - mountPath: /home/argocd/cmp-server/config/plugin.yaml
          subPath: avp-kustomize.yaml
          name: argocd-cmp-cm
        - name: custom-tools
          subPath: argocd-vault-plugin
          mountPath: /usr/local/bin/argocd-vault-plugin
  volumes:
    - configMap:
        name: argocd-cmp-cm
      name: argocd-cmp-cm
    - name: custom-tools
      emptyDir: {}
applicationSet:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
notifications:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  notifiers:
    service.email: |
      host: mailhog.mailhog.svc.cluster.local
      port: 1025
      from: argocd@${CLUSTER_FQDN}
  subscriptions:
    - recipients:
      - email:notification@${CLUSTER_FQDN}
      triggers:
        - on-sync-status-unknown
        - on-sync-failed
        - on-sync-running
        - on-sync-succeeded
  templates:
    template.app-deployed: |
      email:
        subject: New version of an application {{.app.metadata.name}} is up and running
      message: |
        Application {{.app.metadata.name}} is now running new version of deployments manifests.
    template.app-health-degraded: |
      email:
        subject: Application {{.app.metadata.name}} has degraded
      message: |
        Application {{.app.metadata.name}} has degraded.
        Application details: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}.
    template.app-sync-failed: |
      email:
        subject: Failed to sync application {{.app.metadata.name}}
      message: |
        The sync operation of application {{.app.metadata.name}} has failed at {{.app.status.operationState.finishedAt}} with the following error: {{.app.status.operationState.message}}
        Sync operation details are available at: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true .
    template.app-sync-running: |
      email:
        subject: Start syncing application {{.app.metadata.name}}
      message: |
        The sync operation of application {{.app.metadata.name}} has started at {{.app.status.operationState.startedAt}}.
        Sync operation details are available at: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true .
    template.app-sync-status-unknown: |
      email:
        subject: Application {{.app.metadata.name}} sync status is 'Unknown'
      message: |
        Application {{.app.metadata.name}} sync is 'Unknown'.
        Application details: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}.
    template.app-sync-succeeded: |
      email:
        subject: Application {{.app.metadata.name}} has been successfully synced
      message: |
        Application {{.app.metadata.name}} has been successfully synced at {{.app.status.operationState.finishedAt}}.
        Sync operation details are available at: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true .
  triggers:
    trigger.on-deployed: |
      - description: Application is synced and healthy. Triggered once per commit.
        oncePer: app.status.sync.revision
        send:
        - app-deployed
        when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
    trigger.on-health-degraded: |
      - description: Application has degraded
        send:
        - app-health-degraded
        when: app.status.health.status == 'Degraded'
    trigger.on-sync-failed: |
      - description: Application syncing has failed
        send:
        - app-sync-failed
        when: app.status.operationState.phase in ['Error', 'Failed']
    trigger.on-sync-running: |
      - description: Application is being synced
        send:
        - app-sync-running
        when: app.status.operationState.phase in ['Running']
    trigger.on-sync-status-unknown: |
      - description: Application status is 'Unknown'
        send:
        - app-sync-status-unknown
        when: app.status.sync.status == 'Unknown'
    trigger.on-sync-succeeded: |
      - description: Application syncing has succeeded
        send:
        - app-sync-succeeded
        when: app.status.operationState.phase in ['Succeeded']
    defaultTriggers: |
      - on-sync-status-unknown
EOF
helm upgrade --install --version "${ARGOCD_HELM_CHART_VERSION}" --namespace argocd --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-argocd.yml" argo-cd argo/argo-cd
```

Add [ArgoCD Grafana Dashboard](https://grafana.com/grafana/dashboards/14584-argocd/)
and [Argo CD Notifications Grafana Dashboard](https://argocd-notifications.readthedocs.io/en/stable/services/grafana/):

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="50.3.1"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-argocd.yml" << EOF
grafana:
  dashboards:
    default:
      argocd:
        # renovate: depName="ArgoCD"
        gnetId: 14584
        revision: 1
        datasource: Prometheus
      argocd-notifications:
        url: https://argocd-notifications.readthedocs.io/en/stable/grafana-dashboard.json
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --reuse-values --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-argocd.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

Login to ArgoCD talking directly to Kubernetes instead of talking to Argo CD API
server:

```bash
argocd login --core --name "${CLUSTER_FQDN}"
kubectl config set-context --current --namespace=argocd
```

Install [podinfo](https://github.com/stefanprodan/podinfo) where I used `<path:`
with secret which should be taken from the AWS Secret Manager:

* First is using the secret as a helm parameter - the secret should be injected
  into the installed helm chart

* Second is using kustomize and should inject the secret into the annotation

![podinfo](https://raw.githubusercontent.com/stefanprodan/podinfo/a7be119f20369b97f209d220535506af7c49b4ea/screens/podinfo-ui-v3.png
"podinfo"){: width="500" }

```bash
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-podinfo.yml" << EOF
ui:
  message: "<path:${CLUSTER_FQDN}-PodinfoSecret#podinfo_secret_message>"
ingress:
  enabled: true
  className: nginx
  annotations:
    forecastle.stakater.com/expose: "true"
    forecastle.stakater.com/icon: https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/cuddle_bunny.gif
    forecastle.stakater.com/appName: Podinfo
  hosts:
    - host: podinfo.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - hosts:
        - podinfo.${CLUSTER_FQDN}
EOF

argocd app create podinfo \
  --repo https://stefanprodan.github.io/podinfo --helm-chart podinfo --revision 6.4.1 \
  --dest-namespace podinfo --dest-server https://kubernetes.default.svc \
  --auto-prune \
  --sync-option CreateNamespace=true \
  --sync-policy auto \
  --values-literal-file "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-podinfo.yml"

argocd app create podinfo2 \
  --repo https://github.com/stefanprodan/podinfo.git --path kustomize \
  --dest-namespace podinfo2 --dest-server https://kubernetes.default.svc \
  --kustomize-common-annotation "secret-test=<path:${CLUSTER_FQDN}-PodinfoSecret#podinfo_secret_message>" \
  --auto-prune \
  --sync-option CreateNamespace=true \
  --sync-policy auto
```

---

To clean up the environment - delete IRSA and remove CloudFormation stack:

```sh
eksctl delete iamserviceaccount --cluster="${CLUSTER_NAME}" --name=argocd-repo-server --namespace=argocd
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret-podinfo"
```

Enjoy ... 😉
