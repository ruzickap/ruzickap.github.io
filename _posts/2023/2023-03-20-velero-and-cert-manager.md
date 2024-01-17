---
title: Velero and cert-manager
author: Petr Ruzicka
date: 2023-03-20
description: Deploy Trivy Operator and Grafana Dashboard
categories: [Kubernetes, Amazon EKS, Velero, cert-manager]
tags: [Amazon EKS, k8s, kubernetes, velero, cert-manager, certificates]
image:
  path: https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/heroes/velero.svg
---

In the previous post related to
[Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %})
I'm using the [cert-manager](https://cert-manager.io/) to get the wildcard
certificate for the ingress.

When the Let's Encrypt [production](https://letsencrypt.org/about/) certificates
are used, it may be handy to backup and restore them when the cluster is
recreated.

Here are few steps how to install [Velero](https://velero.io/) and
[backup + restore](https://cert-manager.io/docs/tutorials/backup/) procedure
for the cert-manager objects.

Links:

- [Backup and Restore Resources](https://cert-manager.io/v1.11-docs/tutorials/backup/#order-of-restore)

## Requirements

- Amazon EKS cluster (described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}))
- [Helm](https://helm.sh/)

Variables which are being used in the next steps:

```bash
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export MY_EMAIL="petr.ruzicka@gmail.com"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

mkdir -pv "${TMP_DIR}/${CLUSTER_FQDN}"
```

### Create Let's Encrypt production certificate

<!-- prettier-ignore-start -->
> These steps should be done only once
{: .prompt-info }
<!-- prettier-ignore-end -->

Generating the production ready Let's Encrypt certificates should be done only
once. The goal is to backup the certificate and then restore it whenever is it
needed to "new" cluster.

Create Let's Encrupt production `ClusterIssuer`:

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
          route53:
            region: ${AWS_DEFAULT_REGION}
EOF
kubectl wait --namespace cert-manager --timeout=15m --for=condition=Ready clusterissuer --all
```

Create new certificate and let it sign by Let's Encrypt to validate it:

```shell
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
```

### Create S3 bucket

<!-- prettier-ignore-start -->
> The following step should be done only once
{: .prompt-info }
<!-- prettier-ignore-end -->

Use CloudFormation to create S3 bucket which will be used to store backups from
Velero.

```shell
cat > "${TMP_DIR}/${CLUSTER_FQDN}/aws-s3.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09

Parameters:
  S3BucketName:
    Description: Name of the S3 bucket
    Type: String
    Default: s3bucket.myexample.com

Resources:
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
        # S3 Bucket policy does not deny TLS version lower than 1.2
        - Sid: EnforceTLSv12orHigher
          Effect: Deny
          Action: "s3:*"
          Resource:
            - !Sub "arn:${AWS::Partition}:s3:::${S3Bucket}"
            - !Sub "arn:${AWS::Partition}:s3:::${S3Bucket}/*"
          Condition:
            NumericLessThan:
              s3:TlsVersion: 1.2
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      AccessControl: Private
      BucketName: !Sub "${S3BucketName}"
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      VersioningConfiguration:
        Status: Suspended
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: alias/aws/s3
Outputs:
  S3PolicyArn:
    Description: The ARN of the created Amazon S3 policy
    Value: !Ref S3Policy
  S3Bucket:
    Description: The ARN of the created Amazon S3 bucket
    Value: !Ref S3Bucket
EOF

aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "S3BucketName=${CLUSTER_FQDN}" \
  --stack-name "${CLUSTER_NAME}-s3" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-s3.yml"
```

## Install Velero

Before installing Velero it is necessary to create IRSA with S3 policy. The
created ServiceAccount `velero` will be specified in velero helm chart later.

```bash
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-s3")
S3_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"S3PolicyArn\") .OutputValue")
eksctl create iamserviceaccount --cluster="${CLUSTER_NAME}" --name=velero --namespace=velero --attach-policy-arn="${S3_POLICY_ARN}" --role-name="eksctl-${CLUSTER_NAME}-irsa-velero" --approve
```

```console
2023-03-23 20:13:12 [ℹ]  3 existing iamserviceaccount(s) (cert-manager/cert-manager,external-dns/external-dns,karpenter/karpenter) will be excluded
2023-03-23 20:13:12 [ℹ]  1 iamserviceaccount (velero/velero) was included (based on the include/exclude rules)
2023-03-23 20:13:12 [!]  serviceaccounts that exist in Kubernetes will be excluded, use --override-existing-serviceaccounts to override
2023-03-23 20:13:12 [ℹ]  1 task: {
    2 sequential sub-tasks: {
        create IAM role for serviceaccount "velero/velero",
        create serviceaccount "velero/velero",
    } }2023-03-23 20:13:12 [ℹ]  building iamserviceaccount stack "eksctl-k01-addon-iamserviceaccount-velero-velero"
2023-03-23 20:13:13 [ℹ]  deploying stack "eksctl-k01-addon-iamserviceaccount-velero-velero"
2023-03-23 20:13:13 [ℹ]  waiting for CloudFormation stack "eksctl-k01-addon-iamserviceaccount-velero-velero"
2023-03-23 20:13:43 [ℹ]  waiting for CloudFormation stack "eksctl-k01-addon-iamserviceaccount-velero-velero"
2023-03-23 20:14:34 [ℹ]  waiting for CloudFormation stack "eksctl-k01-addon-iamserviceaccount-velero-velero"
2023-03-23 20:14:34 [ℹ]  created namespace "velero"
2023-03-23 20:14:35 [ℹ]  created serviceaccount "velero/velero"
```

Install `velero`
[helm chart](https://artifacthub.io/packages/helm/vmware-tanzu/velero)
and modify the
[default values](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/values.yaml).

![velero](https://raw.githubusercontent.com/vmware-tanzu/velero/c663ce15ab468b21a19336dcc38acf3280853361/site/static/img/heroes/velero.svg){:width="600"}

{% raw %}

```bash
# renovate: datasource=helm depName=velero registryUrl=https://vmware-tanzu.github.io/helm-charts
VELERO_HELM_CHART_VERSION="5.2.2"

helm repo add --force-update vmware-tanzu https://vmware-tanzu.github.io/helm-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-velero.yml" << EOF
initContainers:
  - name: velero-plugin-for-aws
    # renovate: datasource=docker depName=velero/velero-plugin-for-aws extractVersion=^(?<version>.+)$
    image: velero/velero-plugin-for-aws:v1.8.2
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
        expr: |-
          velero_backup_partial_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
        for: 15m
        labels:
          severity: warning
      - alert: VeleroBackupFailures
        annotations:
          message: Velero backup {{ \$labels.schedule }} has {{ \$value | humanizePercentage }} failed backups.
        expr: |-
          velero_backup_failure_total{schedule!=""} / velero_backup_attempt_total{schedule!=""} > 0.25
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
    # Use exiting IRSA service account
    create: false
    name: velero
credentials:
  useSecret: false
# Create scheduled backup to periodically backup the "production" certificate in the "cert-manager" namespace every night:
schedules:
  weekly-backup-cert-manager:
    labels:
      letsencrypt: production
    schedule: "@weekly"
    template:
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

Add Velero Grafana Dashboard:

```bash
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_HELM_CHART_VERSION="55.8.3"

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
> These steps should be done only once
{: .prompt-info }
<!-- prettier-ignore-end -->

Verify if the `backup-location` is set properly to AWS S3 and is available:

```bash
velero get backup-location
```

```console
NAME      PROVIDER   BUCKET/PREFIX               PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
default   aws        k01.k8s.mylabs.dev/velero   Available   2023-03-23 20:16:20 +0100 CET   ReadWrite     true
```

Initiate backup process and save the necessary cert-manager object to S3:

```shell
velero backup create --labels letsencrypt=production --ttl 2160h0m0s --from-schedule velero-weekly-backup-cert-manager
```

Check the backup details:

```bash
velero backup describe --selector letsencrypt=production --details
```

```console
Name:         velero-weekly-backup-cert-manager-20230323191755
Namespace:    velero
Labels:       letsencrypt=production
              velero.io/schedule-name=velero-weekly-backup-cert-manager
              velero.io/storage-location=default
Annotations:  velero.io/source-cluster-k8s-gitversion=v1.25.6-eks-48e63af
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=25+

Phase:  Completed

Errors:    0
Warnings:  0

Namespaces:
  Included:  cert-manager
  Excluded:  <none>

Resources:
  Included:        certificates.cert-manager.io, clusterissuers.cert-manager.io, secrets
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  letsencrypt=production

Storage Location:  default

Velero-Native Snapshot PVs:  auto

TTL:  720h0m0s

CSISnapshotTimeout:  10m0s

Hooks:  <none>

Backup Format Version:  1.1.0

Started:    2023-03-23 20:17:55 +0100 CET
Completed:  2023-03-23 20:17:56 +0100 CET

Expiration:  2023-04-22 21:17:55 +0200 CEST

Total items to be backed up:  2
Items backed up:              2

Resource List:
  cert-manager.io/v1/Certificate:
    - cert-manager/ingress-cert-production
  v1/Secret:
    - cert-manager/ingress-cert-production

Velero-Native Snapshots: <none included>
```

See the files in S3 bucket:

```bash
aws s3 ls --recursive "s3://${CLUSTER_FQDN}/velero/backups"
```

```console
2023-03-23 20:17:57       3388 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-backup.json
2023-03-23 20:17:57         29 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-csi-volumesnapshotclasses.json.gz
2023-03-23 20:17:57         29 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-csi-volumesnapshotcontents.json.gz
2023-03-23 20:17:57         29 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-csi-volumesnapshots.json.gz
2023-03-23 20:17:57       2545 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-logs.gz
2023-03-23 20:17:57         29 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-podvolumebackups.json.gz
2023-03-23 20:17:57         99 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-resource-list.json.gz
2023-03-23 20:17:57         49 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-results.gz
2023-03-23 20:17:57         29 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755-volumesnapshots.json.gz
2023-03-23 20:17:57       8369 velero/backups/velero-weekly-backup-cert-manager-20230323191755/velero-weekly-backup-cert-manager-20230323191755.tar.gz
```

## Restore cert-manager objects

The next steps will show the way to restore Let's Encrypt production certificate
(previously backed up by Veleto to S3) to new cluster.

Start the restore procedure of the cert-manager objects:

```bash
velero restore create --from-schedule velero-weekly-backup-cert-manager --labels letsencrypt=production --wait
```

Details about the restore process:

```bash
velero restore describe --selector letsencrypt=production --details
```

```console
Name:         velero-weekly-backup-cert-manager-20230323202248
Namespace:    velero
Labels:       letsencrypt=production
Annotations:  <none>

Phase:                       Completed
Total items to be restored:  2
Items restored:              2

Started:    2023-03-23 20:22:51 +0100 CET
Completed:  2023-03-23 20:22:52 +0100 CET

Backup:  velero-weekly-backup-cert-manager-20230323191755

Namespaces:
  Included:  all namespaces found in the backup
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        nodes, events, events.events.k8s.io, backups.velero.io, restores.velero.io, resticrepositories.velero.io, csinodes.storage.k8s.io, volumeattachments.storage.k8s.io, backuprepositories.velero.io
  Cluster-scoped:  auto

Namespace mappings:  <none>

Label selector:  <none>

Restore PVs:  auto

Existing Resource Policy:   <none>

Preserve Service NodePorts:  auto
```

Verify if the certificate was restored properly:

```bash
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
Name:         ingress-cert-production
Namespace:    cert-manager
Labels:       letsencrypt=production
              velero.io/backup-name=velero-weekly-backup-cert-manager-20230323194540
              velero.io/restore-name=velero-weekly-backup-cert-manager-20230324051646
Annotations:  <none>
API Version:  cert-manager.io/v1
Kind:         Certificate
...
...
...
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
    Last Transition Time:  2023-03-24T05:16:48Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2023-06-21T18:10:31Z
  Not Before:              2023-03-23T18:10:32Z
  Renewal Time:            2023-05-22T18:10:31Z
Events:                    <none>
```

## Reconfigure ingress-nginx

Previous steps restored the Let's Encrypt production certificate
`cert-manager/ingress-cert-production`. Let's use this cert by `ingress-nginx`.

Check the current "staging" certificate - this will be replaced by the
"production" one:

```bash
while ! curl -sk "https://${CLUSTER_FQDN}" > /dev/null; do
  date
  sleep 5
done
openssl s_client -connect "${CLUSTER_FQDN}:443" < /dev/null
```

```console
depth=2 C = US, O = (STAGING) Internet Security Research Group, CN = (STAGING) Pretend Pear X1
verify error:num=20:unable to get local issuer certificate
verify return:0
...
---
Server certificate
subject=/CN=*.k01.k8s.mylabs.dev
issuer=/C=US/O=(STAGING) Let's Encrypt/CN=(STAGING) Artificial Apricot R3
---
...
```

Use production Let's Encrypt certificate by `ingress-nginx`:

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.9.0"

cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx-production-certs.yml" << EOF
controller:
  extraArgs:
    default-ssl-certificate: cert-manager/ingress-cert-production
EOF
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --reuse-values --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-ingress-nginx-production-certs.yml" ingress-nginx ingress-nginx/ingress-nginx
```

The production certificate should be ready:

```bash
openssl s_client -connect "${CLUSTER_FQDN}:443" < /dev/null
```

```console
depth=2 C = US, O = Internet Security Research Group, CN = ISRG Root X1
verify return:1
depth=1 C = US, O = Let's Encrypt, CN = R3
verify return:1
depth=0 CN = *.k01.k8s.mylabs.dev
...
---
Server certificate
subject=/CN=*.k01.k8s.mylabs.dev
issuer=/C=US/O=Let's Encrypt/CN=R3
---
...
```

Here is the report form [SSL Labs](https://www.ssllabs.com):

![ssl-labs-report](/assets/img/posts/2023/2023-03-20-velero-and-cert-manager/ssl-labs-report.avif)

## Rotation of the "production" certificate

The Let's Encrypt certificates are valid for 90 days. It is necessary to renew
them before they expire.

Few commands showing the details after cert-manager renewed the certificate.

Examine the certificate:

```shell
kubectl describe certificates -n cert-manager ingress-cert-production
```

```console
...
Status:
  Conditions:
    Last Transition Time:  2023-09-13T04:50:19Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2023-12-12T03:53:45Z
  Not Before:              2023-09-13T03:53:46Z
  Renewal Time:            2023-11-12T03:53:45Z
  Revision:                1
Events:
  Type    Reason     Age   From                                       Message
  ----    ------     ----  ----                                       -------
  Normal  Issuing    58m   cert-manager-certificates-trigger          Renewing certificate as renewal was scheduled at 2023-09-09 13:39:16 +0000 UTC
  Normal  Reused     58m   cert-manager-certificates-key-manager      Reusing private key stored in existing Secret resource "ingress-cert-production"
  Normal  Requested  58m   cert-manager-certificates-request-manager  Created new CertificateRequest resource "ingress-cert-production-1"
  Normal  Issuing    55m   cert-manager-certificates-issuing          The certificate has been successfully issued
```

Look at the `CertificateRequest`:

```shell
kubectl describe certificaterequests -n cert-manager ingress-cert-production-1
```

```console
Name:         ingress-cert-production-1
Namespace:    cert-manager
Labels:       letsencrypt=production
              velero.io/backup-name=velero-weekly-backup-cert-manager-20230711144135
              velero.io/restore-name=velero-weekly-backup-cert-manager-20230913045017
Annotations:  cert-manager.io/certificate-name: ingress-cert-production
              cert-manager.io/certificate-revision: 1
              cert-manager.io/private-key-secret-name: ingress-cert-production-kxk5s
API Version:  cert-manager.io/v1
Kind:         CertificateRequest
Metadata:
  Creation Timestamp:  2023-09-13T04:50:19Z
  Generation:          1
  Owner References:
    API Version:           cert-manager.io/v1
    Block Owner Deletion:  true
    Controller:            true
    Kind:                  Certificate
    Name:                  ingress-cert-production
    UID:                   b04e1186-e6c5-42d0-8d61-34810644b386
  Resource Version:        8653
  UID:                     b9c209b3-0bac-440d-a62f-91800c6c458b
Spec:
  Extra:
    authentication.kubernetes.io/pod-name:
      cert-manager-f9f87498d-nvggh
    authentication.kubernetes.io/pod-uid:
      3b1a2731-0e75-4cf2-bdbd-7278ac364498
  Groups:
    system:serviceaccounts
    system:serviceaccounts:cert-manager
    system:authenticated
  Issuer Ref:
    Kind:    ClusterIssuer
    Name:    letsencrypt-production-dns
  Request:   LS0xxxxxxxS0K
  UID:       8704d6db-816e-4c93-bcc8-8801060b05d0
  Username:  system:serviceaccount:cert-manager:cert-manager
Status:
  Certificate:  LSxxxxxxCg==
  Conditions:
    Last Transition Time:  2023-09-13T04:50:19Z
    Message:               Certificate request has been approved by cert-manager.io
    Reason:                cert-manager.io
    Status:                True
    Type:                  Approved
    Last Transition Time:  2023-09-13T04:53:46Z
    Message:               Certificate fetched from issuer successfully
    Reason:                Issued
    Status:                True
    Type:                  Ready
Events:
  Type    Reason              Age   From                                                Message
  ----    ------              ----  ----                                                -------
  Normal  WaitingForApproval  54m   cert-manager-certificaterequests-issuer-ca          Not signing CertificateRequest until it is Approved
  Normal  WaitingForApproval  54m   cert-manager-certificaterequests-issuer-acme        Not signing CertificateRequest until it is Approved
  Normal  WaitingForApproval  54m   cert-manager-certificaterequests-issuer-vault       Not signing CertificateRequest until it is Approved
  Normal  WaitingForApproval  54m   cert-manager-certificaterequests-issuer-selfsigned  Not signing CertificateRequest until it is Approved
  Normal  WaitingForApproval  54m   cert-manager-certificaterequests-issuer-venafi      Not signing CertificateRequest until it is Approved
  Normal  cert-manager.io     54m   cert-manager-certificaterequests-approver           Certificate request has been approved by cert-manager.io
  Normal  OrderCreated        54m   cert-manager-certificaterequests-issuer-acme        Created Order resource cert-manager/ingress-cert-production-1-3932937138
  Normal  OrderPending        54m   cert-manager-certificaterequests-issuer-acme        Waiting on certificate issuance from order cert-manager/ingress-cert-production-1-3932937138: ""
  Normal  CertificateIssued   50m   cert-manager-certificaterequests-issuer-acme        Certificate fetched from issuer successfully
```

Check the `cert-manager` logs:

```shell
kubectl logs -n cert-manager cert-manager-f9f87498d-nvggh
```

```console
...
I0913 04:50:18.960223       1 conditions.go:203] Setting lastTransitionTime for Certificate "ingress-cert-production" condition "Ready" to 2023-09-13 04:50:18.960211036 +0000 UTC m=+451.003679107
I0913 04:50:18.962295       1 trigger_controller.go:194] "cert-manager/certificates-trigger: Certificate must be re-issued" key="cert-manager/ingress-cert-production" reason="Renewing" message="Renewing certificate as renewal was scheduled at <nil>"
I0913 04:50:18.962464       1 conditions.go:203] Setting lastTransitionTime for Certificate "ingress-cert-production" condition "Issuing" to 2023-09-13 04:50:18.962457264 +0000 UTC m=+451.005925351
I0913 04:50:19.011897       1 conditions.go:203] Setting lastTransitionTime for Certificate "ingress-cert-production" condition "Ready" to 2023-09-13 04:50:19.011889134 +0000 UTC m=+451.055357214
I0913 04:50:19.020026       1 trigger_controller.go:194] "cert-manager/certificates-trigger: Certificate must be re-issued" key="cert-manager/ingress-cert-production" reason="Renewing" message="Renewing certificate as renewal was scheduled at <nil>"
I0913 04:50:19.020061       1 conditions.go:203] Setting lastTransitionTime for Certificate "ingress-cert-production" condition "Issuing" to 2023-09-13 04:50:19.020054522 +0000 UTC m=+451.063522609
I0913 04:50:19.046907       1 trigger_controller.go:194] "cert-manager/certificates-trigger: Certificate must be re-issued" key="cert-manager/ingress-cert-production" reason="Renewing" message="Renewing certificate as renewal was scheduled at 2023-09-09 13:39:16 +0000 UTC"
I0913 04:50:19.046942       1 conditions.go:203] Setting lastTransitionTime for Certificate "ingress-cert-production" condition "Issuing" to 2023-09-13 04:50:19.046937063 +0000 UTC m=+451.090405134
I0913 04:50:19.134032       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "ingress-cert-production-1" condition "Approved" to 2023-09-13 04:50:19.134023095 +0000 UTC m=+451.177491158
I0913 04:50:19.175761       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "ingress-cert-production-1" condition "Ready" to 2023-09-13 04:50:19.175750564 +0000 UTC m=+451.219218635
I0913 04:50:19.210564       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "ingress-cert-production-1" condition "Ready" to 2023-09-13 04:50:19.210549558 +0000 UTC m=+451.254017629
I0913 04:53:46.526286       1 acme.go:233] "cert-manager/certificaterequests-issuer-acme/sign: certificate issued" resource_name="ingress-cert-production-1" resource_namespace="cert-manager" resource_kind="CertificateRequest" resource_version="v1" related_resource_name="ingress-cert-production-1-3932937138" related_resource_namespace="cert-manager" related_resource_kind="Order" related_resource_version="v1"
I0913 04:53:46.526563       1 conditions.go:252] Found status change for CertificateRequest "ingress-cert-production-1" condition "Ready": "False" -> "True"; setting lastTransitionTime to 2023-09-13 04:53:46.526554494 +0000 UTC m=+658.570022573
```

---

Backup certificate before deleting the cluster (in case it was renewed):

{% raw %}

```sh
if ! kubectl get certificaterequests.cert-manager.io -n cert-manager --selector letsencrypt=production -o go-template='{{.items | len}}' | grep -qxF 0; then
  velero backup create --labels letsencrypt=production --ttl 2160h0m0s --from-schedule velero-weekly-backup-cert-manager
fi
```

{% endraw %}

Enjoy ... 😉
