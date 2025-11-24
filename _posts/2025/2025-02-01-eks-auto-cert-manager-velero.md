---
title: Amazon EKS Auto Mode with cert-manager and Velero
author: Petr Ruzicka
date: 2025-02-01
description:
categories: [Kubernetes, Amazon EKS Auto Mode, Velero, cert-manager]
tags:
  [
    amaozn eks auto mode,
    amazon eks,
    cert-manager,
    certificates,
    eksctl,
    k8s,
    kubernetes,
    security,
    velero,
  ]
image: https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/heroes/velero.svg
---

<!-- markdownlint-disable MD013 MD033 -->
In the previous post,
"[Build secure and cheap Amazon EKS Auto Mode]({% post_url /2024/2024-12-14-secure-cheap-amazon-eks-auto %})",
I used [cert-manager](https://cert-manager.io/) to obtain a
[wildcard certificate](https://en.wikipedia.org/wiki/Public_key_certificate#Wildcard_certificate)
for the [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/).
<!-- markdownlint-enable MD013 MD033 -->

When using Let's Encrypt [production](https://letsencrypt.org/about/)
certificates, it is useful to back them up and restore them when recreating
the cluster.

Here are a few steps to install [Velero](https://velero.io/) and perform the
[backup and restore](https://cert-manager.io/docs/tutorials/backup/) procedure
for cert-manager objects.

Links:

- [Backup and Restore Resources](https://cert-manager.io/v1.16-docs/devops-tips/backup/)

## Requirements

<!-- markdownlint-disable MD013 MD033 -->
- An Amazon EKS Auto Mode cluster (as described in
  "[Build secure and cheap Amazon EKS Auto Mode]({% post_url /2024/2024-12-14-secure-cheap-amazon-eks-auto %})")
- [AWS CLI](https://aws.amazon.com/cli/)
- [eksctl](https://eksctl.io/)
- [Helm](https://helm.sh)
- [kubectl](https://github.com/kubernetes/kubectl)
<!-- markdownlint-enable MD013 MD033 -->

The following variables are used in the subsequent steps:

```bash
export AWS_REGION="${AWS_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"
# Tags applied to identify AWS resources
export TAGS="${TAGS:-Owner=${MY_EMAIL},Environment=dev,Cluster=${CLUSTER_FQDN}}"
mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
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
  kubectl wait --namespace cert-manager --for=condition=Ready --timeout=10m certificate ingress-cert-production
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

## Install Velero

Before installing Velero, you must create a Pod Identity Association to grant
Velero the [necessary permissions](https://github.com/vmware-tanzu/velero-plugin-for-aws/blob/644e43f9ca39dc951b6fafa596311fe5659e8dc6/README.md?plain=1#L89-L141)
to access S3 and EC2 resources. The created `velero` ServiceAccount will be
specified in the Velero Helm chart later.

```bash
tee "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}-iam-podidentityassociations.yml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
iam:
  podIdentityAssociations:
    - namespace: velero
      serviceAccountName: velero
      roleName: eksctl-${CLUSTER_NAME}-pia-velero
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
EOF
eksctl create podidentityassociation --config-file "${TMP_DIR}/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}-iam-podidentityassociations.yml"
```

```console
2025-02-06 06:13:57 [ℹ]  1 task: {
    2 sequential sub-tasks: {
        create IAM role for pod identity association for service account "velero/velero",
        create pod identity association for service account "velero/velero",
    } }2025-02-06 06:13:58 [ℹ]  deploying stack "eksctl-k01-podidentityrole-velero-velero"
2025-02-06 06:13:58 [ℹ]  waiting for CloudFormation stack "eksctl-k01-podidentityrole-velero-velero"
2025-02-06 06:14:28 [ℹ]  waiting for CloudFormation stack "eksctl-k01-podidentityrole-velero-velero"
2025-02-06 06:15:26 [ℹ]  waiting for CloudFormation stack "eksctl-k01-podidentityrole-velero-velero"
2025-02-06 06:15:27 [ℹ]  created pod identity association for service account "velero" in namespace "velero"
2025-02-06 06:15:27 [ℹ]  all tasks were completed successfully
```

![velero](https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/heroes/velero.svg){:width="600"}

Install the `velero` [Helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify its [default values](https://github.com/vmware-tanzu/helm-charts/blob/velero-8.3.0/charts/velero/values.yaml):

{% raw %}

```bash
# renovate: datasource=helm depName=velero registryUrl=https://vmware-tanzu.github.io/helm-charts
VELERO_HELM_CHART_VERSION="11.1.1"

helm repo add --force-update vmware-tanzu https://vmware-tanzu.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-velero.yml" << EOF
initContainers:
  - name: velero-plugin-for-aws
    # renovate: datasource=docker depName=velero/velero-plugin-for-aws extractVersion=^(?<version>.+)$
    image: velero/velero-plugin-for-aws:v1.13.0
    volumeMounts:
      - mountPath: /target
        name: plugins
metrics:
  serviceMonitor:
    enabled: true
  prometheusRule:
    enabled: true
    spec:
      - alert: VeleroBackupPartialFailures
        annotations:
          message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} partially failed backups.
        expr: velero_backup_partial_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
        for: 15m
        labels:
          severity: warning
      - alert: VeleroBackupFailures
        annotations:
          message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed backups.
        expr: velero_backup_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
        for: 15m
        labels:
          severity: warning
      - alert: VeleroBackupSnapshotFailures
        annotations:
          message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed snapshot backups.
        expr: increase(velero_volume_snapshot_failure_total{schedule!=""}[1h]) > 0
        for: 15m
        labels:
          severity: warning
      - alert: VeleroRestorePartialFailures
        annotations:
          message: Velero restore {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} partially failed restores.
        expr: increase(velero_restore_partial_failure_total{schedule!=""}[1h]) > 0
        for: 15m
        labels:
          severity: warning
      - alert: VeleroRestoreFailures
        annotations:
          message: Velero restore {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed restores.
        expr: increase(velero_restore_failure_total{schedule!=""}[1h]) > 0
        for: 15m
        labels:
          severity: warning
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
      includeClusterResources: true
      includedNamespaces:
        - cert-manager
      includedResources:
        - certificates.cert-manager.io
        - clusterissuers.cert-manager.io
        - secrets
      labelSelector:
        matchLabels:
          letsencrypt: production
EOF
helm upgrade --install --version "${VELERO_HELM_CHART_VERSION}" --namespace velero --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-velero.yml" velero vmware-tanzu/velero
```

{% endraw %}

Add the Velero Grafana dashboard for enhanced monitoring and visualization:

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="67.9.0"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-velero-cert-manager.yml" << EOF
grafana:
  dashboards:
    default:
      15469-kubernetes-addons-velero-stats:
        # renovate: depName="Velero Exporter Overview"
        gnetId: 15469
        revision: 1
        datasource: Prometheus
EOF
helm upgrade --install --version "${KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION}" --namespace kube-prometheus-stack --reuse-values --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-kube-prometheus-stack-velero-cert-manager.yml" kube-prometheus-stack prometheus-community/kube-prometheus-stack
```

## Backup cert-manager objects

<!-- prettier-ignore-start -->
> These steps should be done only once.
{: .prompt-info }
<!-- prettier-ignore-end -->

Verify that the `backup-location` is set properly to AWS S3 and is available:

```bash
velero get backup-location
```

```console
NAME      PROVIDER   BUCKET/PREFIX               PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
default   aws        k01.k8s.mylabs.dev/velero   Available   2025-02-06 06:21:59 +0100 CET   ReadWrite     true
```

Initiate the backup process and store the required cert-manager objects in S3.

```bash
if ! aws s3 ls "s3://${CLUSTER_FQDN}/velero/backups/" | grep -q velero-monthly-backup-cert-manager-production; then
  velero backup create --labels letsencrypt=production --ttl 2160h --from-schedule velero-monthly-backup-cert-manager-production --wait
fi
```

Check the backup details:

```bash
velero backup describe --selector letsencrypt=production --details
```

```console
Name:         velero-monthly-backup-cert-manager-production-20250206052506
Namespace:    velero
Labels:       app.kubernetes.io/instance=velero
              app.kubernetes.io/managed-by=Helm
              app.kubernetes.io/name=velero
              helm.sh/chart=velero-8.3.0
              letsencrypt=production
              velero.io/schedule-name=velero-monthly-backup-cert-manager-production
              velero.io/storage-location=default
Annotations:  meta.helm.sh/release-name=velero
              meta.helm.sh/release-namespace=velero
              velero.io/resource-timeout=10m0s
              velero.io/source-cluster-k8s-gitversion=v1.30.9-eks-8cce635
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=30+

Phase:  Completed


Namespaces:
  Included:  cert-manager
  Excluded:  <none>

Resources:
  Included:        certificates.cert-manager.io, secrets
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  letsencrypt=production

Or label selector:  <none>

Storage Location:  default

Velero-Native Snapshot PVs:  auto
Snapshot Move Data:          false
Data Mover:                  velero

TTL:  2160h0m0s

CSISnapshotTimeout:    10m0s
ItemOperationTimeout:  4h0m0s

Hooks:  <none>

Backup Format Version:  1.1.0

Started:    2025-02-06 06:25:06 +0100 CET
Completed:  2025-02-06 06:25:08 +0100 CET

Expiration:  2025-05-07 07:25:06 +0200 CEST

Total items to be backed up:  6
Items backed up:              6

Resource List:
  apiextensions.k8s.io/v1/CustomResourceDefinition:
    - certificates.cert-manager.io
    - clusterissuers.cert-manager.io
  cert-manager.io/v1/Certificate:
    - cert-manager/ingress-cert-production
  cert-manager.io/v1/ClusterIssuer:
    - letsencrypt-production-dns
  v1/Secret:
    - cert-manager/ingress-cert-production
    - cert-manager/letsencrypt-production-dns

Backup Volumes:
  Velero-Native Snapshots: <none included>

  CSI Snapshots: <none included>

  Pod Volume Backups: <none included>

HooksAttempted:  0
HooksFailed:     0
```

List the files in the S3 bucket:

```bash
aws s3 ls --recursive "s3://${CLUSTER_FQDN}/velero/backups"
```

```console
2025-02-06 06:25:09       4276 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-backup.json
2025-02-06 06:25:08         29 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-csi-volumesnapshotclasses.json.gz
2025-02-06 06:25:08         29 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-csi-volumesnapshotcontents.json.gz
2025-02-06 06:25:08         29 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-csi-volumesnapshots.json.gz
2025-02-06 06:25:08         27 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-itemoperations.json.gz
2025-02-06 06:25:08       3049 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-logs.gz
2025-02-06 06:25:08         29 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-podvolumebackups.json.gz
2025-02-06 06:25:08        121 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-resource-list.json.gz
2025-02-06 06:25:08         49 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-results.gz
2025-02-06 06:25:08         27 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-volumeinfo.json.gz
2025-02-06 06:25:08         29 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506-volumesnapshots.json.gz
2025-02-06 06:25:08       8379 velero/backups/velero-monthly-backup-cert-manager-production-20250206052506/velero-monthly-backup-cert-manager-production-20250206052506.tar.gz
```

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
Name:         velero-monthly-backup-cert-manager-production-20250206055911
Namespace:    velero
Labels:       letsencrypt=production
Annotations:  <none>

Phase:                       Completed
Total items to be restored:  6
Items restored:              6

Started:    2025-02-06 06:59:12 +0100 CET
Completed:  2025-02-06 06:59:13 +0100 CET

Backup:  velero-monthly-backup-cert-manager-production-20250206052506

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
  apiextensions.k8s.io/v1/CustomResourceDefinition:
    - certificates.cert-manager.io(updated)
    - clusterissuers.cert-manager.io(updated)
  cert-manager.io/v1/Certificate:
    - cert-manager/ingress-cert-production(created)
  cert-manager.io/v1/ClusterIssuer:
    - letsencrypt-production-dns(updated)
  v1/Secret:
    - cert-manager/ingress-cert-production(created)
    - cert-manager/letsencrypt-production-dns(updated)
```

Verify that the certificate was restored properly:

```bash
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
Name:         ingress-cert-production
Namespace:    cert-manager
Labels:       letsencrypt=production
              velero.io/backup-name=velero-monthly-backup-cert-manager-production-20250206052506
              velero.io/restore-name=velero-monthly-backup-cert-manager-production-20250206055911
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2025-02-06T05:59:13Z
  Generation:          1
  Resource Version:    7903
  UID:                 a7adee5e-82b7-4849-aac6-aa33298a9268
Spec:
  Common Name:  *.k01.k8s.mylabs.dev
  Dns Names:
    *.k01.k8s.mylabs.dev
    k01.k8s.mylabs.dev
  Issuer Ref:
    Kind:       ClusterIssuer
    Name:       letsencrypt-production-dns
  Secret Name:  ingress-cert-production
  Secret Template:
    Labels:
      Letsencrypt:  production
Status:
  Conditions:
    Last Transition Time:  2025-02-06T05:59:13Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2025-05-07T04:13:10Z
  Not Before:              2025-02-06T04:13:11Z
  Renewal Time:            2025-04-07T04:13:10Z
Events:                    <none>
```

## Reconfigure ingress-nginx

The previous steps restored the Let's Encrypt production certificate (`cert-manager/ingress-cert-production`).
Now, let's configure `ingress-nginx` to use this certificate.

First, check the current "staging" certificate; this will be replaced by the
production certificate:

```bash
while ! curl -sk "https://${CLUSTER_FQDN}" > /dev/null; do
  date
  sleep 5
done
openssl s_client -connect "${CLUSTER_FQDN}:443" < /dev/null
```

```console
depth=1 C=US, O=(STAGING) Let's Encrypt, CN=(STAGING) Wannabe Watercress R11
verify error:num=20:unable to get local issuer certificate
verify return:1
depth=0 CN=*.k01.k8s.mylabs.dev
verify return:1
---
Certificate chain
 0 s:CN=*.k01.k8s.mylabs.dev
   i:C=US, O=(STAGING) Let's Encrypt, CN=(STAGING) Wannabe Watercress R11
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Feb  6 04:56:23 2025 GMT; NotAfter: May  7 04:56:22 2025 GMT
 1 s:C=US, O=(STAGING) Let's Encrypt, CN=(STAGING) Wannabe Watercress R11
   i:C=US, O=(STAGING) Internet Security Research Group, CN=(STAGING) Pretend Pear X1
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Mar 13 00:00:00 2024 GMT; NotAfter: Mar 12 23:59:59 2027 GMT
---
Server certificate
-----BEGIN CERTIFICATE-----
...
...
...
-----END CERTIFICATE-----
subject=CN=*.k01.k8s.mylabs.dev
issuer=C=US, O=(STAGING) Let's Encrypt, CN=(STAGING) Wannabe Watercress R11
---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 3270 bytes and written 409 bytes
Verification error: unable to get local issuer certificate
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol: TLSv1.3
Server public key is 2048 bit
This TLS version forbids renegotiation.
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 20 (unable to get local issuer certificate)
---
DONE
```

Configure `ingress-nginx` to use the production Let's Encrypt certificate.

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.12.3"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx-production-certs.yml" << EOF
controller:
  extraArgs:
    default-ssl-certificate: cert-manager/ingress-cert-production
EOF
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --reuse-values --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx-production-certs.yml" ingress-nginx ingress-nginx/ingress-nginx
```

The production certificate should now be active and in use.

```bash
while ! curl -sk "https://${CLUSTER_FQDN}" > /dev/null; do
  date
  sleep 5
done
openssl s_client -connect "${CLUSTER_FQDN}:443" < /dev/null
```

```console
depth=2 C=US, O=Internet Security Research Group, CN=ISRG Root X1
verify return:1
depth=1 C=US, O=Let's Encrypt, CN=R10
verify return:1
depth=0 CN=*.k01.k8s.mylabs.dev
verify return:1
---
Certificate chain
 0 s:CN=*.k01.k8s.mylabs.dev
   i:C=US, O=Let's Encrypt, CN=R10
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Feb  6 04:13:11 2025 GMT; NotAfter: May  7 04:13:10 2025 GMT
 1 s:C=US, O=Let's Encrypt, CN=R10
   i:C=US, O=Internet Security Research Group, CN=ISRG Root X1
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA256
   v:NotBefore: Mar 13 00:00:00 2024 GMT; NotAfter: Mar 12 23:59:59 2027 GMT
---
Server certificate
-----BEGIN CERTIFICATE-----
...
...
...
-----END CERTIFICATE-----
subject=CN=*.k01.k8s.mylabs.dev
issuer=C=US, O=Let's Encrypt, CN=R10
---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 3149 bytes and written 409 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol: TLSv1.3
Server public key is 2048 bit
This TLS version forbids renegotiation.
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
---
DONE
```

Here is the report from [SSL Labs](https://www.ssllabs.com):

![ssl-labs-report](/assets/img/posts/2023/2023-03-20-velero-and-cert-manager/ssl-labs-report.avif)

Examine the certificate details:

```bash
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
Name:         ingress-cert-production
Namespace:    cert-manager
Labels:       letsencrypt=production
              velero.io/backup-name=velero-monthly-backup-cert-manager-production-20250206052506
              velero.io/restore-name=velero-monthly-backup-cert-manager-production-20250206055911
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
Metadata:
  Creation Timestamp:  2025-02-06T05:59:13Z
  Generation:          1
  Resource Version:    7903
  UID:                 a7adee5e-82b7-4849-aac6-aa33298a9268
Spec:
  Common Name:  *.k01.k8s.mylabs.dev
  Dns Names:
    *.k01.k8s.mylabs.dev
    k01.k8s.mylabs.dev
  Issuer Ref:
    Kind:       ClusterIssuer
    Name:       letsencrypt-production-dns
  Secret Name:  ingress-cert-production
  Secret Template:
    Labels:
      Letsencrypt:  production
Status:
  Conditions:
    Last Transition Time:  2025-02-06T05:59:13Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2025-05-07T04:13:10Z
  Not Before:              2025-02-06T04:13:11Z
  Renewal Time:            2025-04-07T04:13:10Z
Events:                    <none>
```

## Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg){:width="300"}

Back up the certificate before deleting the cluster (in case it was renewed):

{% raw %}

```sh
if [[ "$(kubectl get --raw /api/v1/namespaces/cert-manager/services/cert-manager:9402/proxy/metrics | awk '/certmanager_http_acme_client_request_count.*acme-v02\.api.*finalize/ { print $2 }')" -gt 0 ]] && [[ -n "$(velero get backups -o json | jq -e --arg today "$(date +%Y-%m-%d)" '.items[] | select(.status.startTimestamp | startswith($today))')" ]]; then
  velero backup create --labels letsencrypt=production --ttl 2160h --from-schedule velero-monthly-backup-cert-manager-production
fi
```

{% endraw %}

Remove files from the `${TMP_DIR}/${CLUSTER_FQDN}` directory:

```sh
for FILE in "${TMP_DIR}/${CLUSTER_FQDN}"/{aws-s3,eksctl-${CLUSTER_NAME}-iam-podidentityassociations,helm_values-{ingress-nginx-production-certs,kube-prometheus-stack-velero-cert-manager,velero},k8s-cert-manager-{clusterissuer,certificate}-production}.yml; do
  if [[ -f "${FILE}" ]]; then
    rm -v "${FILE}"
  else
    echo "*** File not found: ${FILE}"
  fi
done
```

Enjoy ... 😉
