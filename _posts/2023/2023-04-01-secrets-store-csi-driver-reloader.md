---
title: Secrets Store CSI Driver and Reloader
author: Petr Ruzicka
date: 2023-04-01
description: Deploy Trivy Operator and Grafana Dashboard
categories: [Kubernetes, Amazon EKS, secrets-store-csi-driver, Reloader, AWS Secrets Manager]
tags: [Amazon EKS, k8s, kubernetes, secrets-store-csi-driver, reloader, AWS Secrets Manager]
image:
  path: https://raw.githubusercontent.com/kubernetes/community/487f994c013ea61d92cf9a341af7620037abbce3/icons/svg/resources/unlabeled/secret.svg
---

Sometimes it is necessary to store the secrets in the [HashiCorp Vault](https://www.vaultproject.io/),
[AWS Secrets Manager](https://aws.amazon.com/secrets-manager/), [Azure Key Vault](https://azure.microsoft.com/en-us/products/key-vault/)
or others and use them in Kubernetes.

In this post I would like to look at the way how to store secrets in
[AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) retrieve them
using [Kubernetes Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
with [AWS Secrets and Configuration Provider (ASCP)](https://github.com/aws/secrets-store-csi-driver-provider-aws)
and use them as Kubernetes Secret and also mount them directly into the pod as
files.

When the Secret is rotated and [defined](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)
as environment variable in the Pod specification (using `secretKeyRef`) it is
necessary to refresh/restart the pod using tools like [Reloader](https://github.com/stakater/Reloader).

![secrets-store-csi-driver](https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/2002e15ac974b15cd0bb89de689f924afbae9bdd/docs/book/src/images/diagram.png)
_secrets-store-csi-driver architecture_

Links:

* [Use AWS Secrets Manager secrets in Amazon Elastic Kubernetes Service](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html)
* [How to use AWS Secrets & Configuration Provider with your Kubernetes Secrets Store CSI driver](https://aws.amazon.com/blogs/security/how-to-use-aws-secrets-configuration-provider-with-kubernetes-secrets-store-csi-driver/)
* [Stakater Reloader docs](https://github.com/stakater/Reloader/tree/master/docs)

## Requirements

* Amazon EKS cluster (described in
  [Cheapest Amazon EKS]({% post_url /2022/2022-11-27-cheapest-amazon-eks %}))
* [Helm](https://helm.sh/)

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
cat > "${TMP_DIR}/${CLUSTER_FQDN}/aws-secretmanager-secret.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Secret Manager and policy
Parameters:
  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: kube1.k8s.mylabs.dev"
    Type: String

Resources:
  SecretsManagerKuardSecretPolicy:
    Type: AWS::IAM::ManagedPolicy
    Properties:
      ManagedPolicyName: !Sub "${ClusterFQDN}-SecretsManagerKuardSecret"
      Description: !Sub "Policy required by SecretsManager to access to Secrets Manager ${ClusterFQDN}-KuardSecret"
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Sid: SecretActions
            Effect: Allow
            Action:
              - "secretsmanager:GetSecretValue"
              - "secretsmanager:DescribeSecret"
            Resource: !Ref SecretsManagerKuardSecret
  SecretsManagerKuardSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub "${ClusterFQDN}-KuardSecret"
      Description: My Secret
      GenerateSecretString:
        SecretStringTemplate: "{\"username\": \"admin123\"}"
        GenerateStringKey: password
        PasswordLength: 16
        ExcludePunctuation: true

Outputs:
  SecretsManagerKuardSecretArn:
    Description: The ARN of the created Amazon SecretsManagerKuardSecret Secret
    Value: !Ref SecretsManagerKuardSecret
  SecretsManagerKuardSecretPolicyArn:
    Description: The ARN of the created SecretsManagerKuardSecret Policy
    Value: !Ref SecretsManagerKuardSecretPolicy
EOF

aws cloudformation deploy --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterFQDN=${CLUSTER_FQDN}" \
  --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret" --template-file "${TMP_DIR}/${CLUSTER_FQDN}/aws-secretmanager-secret.yml"
```

Screenshot from AWS Secrets Manager:

![aws-secrets-manager-01-secrets-kuardsecret](/assets/img/posts/2023/2023-04-01-secrets-store-csi-driver-reloader/aws-secrets-manager-01-secrets-kuardsecret.avif
"AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret")
_AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret_

## Install Secrets Store CSI Driver and AWS Provider

Install `secrets-store-csi-driver`
[helm chart](https://github.com/kubernetes-sigs/secrets-store-csi-driver/tree/main/charts/secrets-store-csi-driver)
and modify the
[default values](https://github.com/kubernetes-sigs/secrets-store-csi-driver/blob/main/charts/secrets-store-csi-driver/values.yaml).

```bash
# renovate: datasource=helm depName=secrets-store-csi-driver registryUrl=https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
SECRETS_STORE_CSI_DRIVER_HELM_CHART_VERSION="1.3.4"

helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-secrets-store-csi-driver.yml" << EOF
syncSecret:
  enabled: true
enableSecretRotation: true
EOF
helm upgrade --install --version "${SECRETS_STORE_CSI_DRIVER_HELM_CHART_VERSION}" --namespace secrets-store-csi-driver --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-secrets-store-csi-driver.yml" secrets-store-csi-driver secrets-store-csi-driver/secrets-store-csi-driver
```

Install `secrets-store-csi-driver-provider-aws`
[helm chart](https://github.com/aws/secrets-store-csi-driver-provider-aws/tree/main/charts/secrets-store-csi-driver-provider-aws).

```bash
# renovate: datasource=helm depName=secrets-store-csi-driver-provider-aws registryUrl=https://aws.github.io/secrets-store-csi-driver-provider-aws
SECRETS_STORE_CSI_DRIVER_PROVIDER_AWS_HELM_CHART_VERSION="0.3.5"

helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm upgrade --install --version "${SECRETS_STORE_CSI_DRIVER_PROVIDER_AWS_HELM_CHART_VERSION}" --namespace secrets-store-csi-driver --create-namespace --wait secrets-store-csi-driver-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws
```

The necessary components are ready...

## Install kuard

[kuard](https://github.com/kubernetes-up-and-running/kuard) is a simple app
which can be used to display various pod details created for the
[Kubernetes: Up and Running](https://hello-tanzu.vmware.com/kubernetes-up-and-running-3/)
book.

Install [kuard](https://github.com/kubernetes-up-and-running/kuard) which will
use the secrets from [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
as mountpoint and also as K8s `Secret`.

```bash
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret")
SECRETS_MANAGER_KUARDSECRET_POLICY_ARN=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".Stacks[0].Outputs[] | select(.OutputKey==\"SecretsManagerKuardSecretPolicyArn\") .OutputValue")
eksctl create iamserviceaccount --cluster="${CLUSTER_NAME}" --name=kuard --namespace=kuard --attach-policy-arn="${SECRETS_MANAGER_KUARDSECRET_POLICY_ARN}" --role-name="eksctl-${CLUSTER_NAME}-irsa-kuard" --approve
```

Create the `SecretProviderClass` which tells the AWS provider which secrets will
be mounted in the pod. It will also create `Secret` called "kuard-secret" which will
be synchronized with the data stored in AWS Secrets Manager.

```bash
kubectl apply -f - << EOF
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: kuard-deployment-aws-secrets
  namespace: kuard
spec:
  provider: aws
  parameters:
    objects: |
        - objectName: "${CLUSTER_FQDN}-KuardSecret"
          objectType: "secretsmanager"
          objectAlias: KuardSecret
  secretObjects:
  - secretName: kuard-secret
    type: Opaque
    data:
    - objectName: KuardSecret
      key: username
EOF
```

Install [kuard](https://github.com/kubernetes-up-and-running/kuard) and use the
previously created `SecretProviderClass`:

```bash
kubectl apply -f - << EOF
kind: Service
apiVersion: v1
metadata:
  name: kuard
  namespace: kuard
  labels:
    app: kuard
spec:
  selector:
    app: kuard
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kuard-deployment
  namespace: kuard
  labels:
    app: kuard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kuard
  template:
    metadata:
      labels:
        app: kuard
    spec:
      serviceAccountName: kuard
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: "kubernetes.io/hostname"
              labelSelector:
                matchLabels:
                  app: kuard
      volumes:
        - name: secrets-store-inline
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "kuard-deployment-aws-secrets"
      containers:
        - name: kuard-deployment
          # renovate: datasource=docker depName=gcr.io/kuar-demo/kuard-arm64 extractVersion=^(?<version>.+)$
          image: gcr.io/kuar-demo/kuard-arm64:v0.9-green
          resources:
            requests:
              cpu: 10m
              memory: "32Mi"
            limits:
              cpu: 20m
              memory: "64Mi"
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: secrets-store-inline
              mountPath: "/mnt/secrets-store"
              readOnly: true
          env:
            - name: KUARDSECRET
              valueFrom:
                secretKeyRef:
                  name: kuard-secret
                  key: username
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kuard
  namespace: kuard
  annotations:
    forecastle.stakater.com/expose: "true"
    forecastle.stakater.com/icon: https://raw.githubusercontent.com/kubernetes/kubernetes/d9a58a39b69a0eaec5797e0f7a0f9472b4829ab0/logo/logo_with_border.svg
    forecastle.stakater.com/appName: Kuard
    nginx.ingress.kubernetes.io/auth-url: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/auth
    nginx.ingress.kubernetes.io/auth-signin: https://oauth2-proxy.${CLUSTER_FQDN}/oauth2/start?rd=\$scheme://\$host\$request_uri
  labels:
    app: kuard
spec:
  rules:
    - host: kuard.${CLUSTER_FQDN}
      http:
        paths:
          - path: /
            pathType: ImplementationSpecific
            backend:
              service:
                name: kuard
                port:
                  number: 8080
  tls:
    - hosts:
        - kuard.${CLUSTER_FQDN}
EOF
```

After the successful deployment of the "kuard" you should see the credentials
in the `kuard-secret`:

{% raw %}

```bash
kubectl wait --namespace kuard --for condition=available deployment kuard-deployment
kubectl get secrets -n kuard kuard-secret --template="{{.data.username}}" | base64 -d | jq
```

{% endraw %}

```json
{
  "password": "rxxxxxxxxxxxxxxH",
  "username": "admin123"
}
```

There should be similar log messages in the `secrets-store-csi-driver` pods:

```bash
kubectl logs -n secrets-store-csi-driver daemonsets/secrets-store-csi-driver
```

```console
Found 2 pods, using pod/secrets-store-csi-driver-2k9jv
I0416 12:17:32.553991       1 exporter.go:35] "initializing metrics backend" backend="prometheus"
I0416 12:17:32.555766       1 main.go:190] "starting manager\n"
I0416 12:17:32.656785       1 secrets-store.go:46] "Initializing Secrets Store CSI Driver" driver="secrets-store.csi.k8s.io" version="v1.3.2" buildTime="2023-03-20-21:09"
I0416 12:17:32.656834       1 reconciler.go:130] "starting rotation reconciler" rotationPollInterval="2m0s"
I0416 12:17:32.660649       1 server.go:121] "Listening for connections" address="//csi/csi.sock"
I0416 12:17:34.082277       1 nodeserver.go:365] "node: getting default node info\n"
I0416 12:18:54.990977       1 nodeserver.go:359] "Using gRPC client" provider="aws" pod="kuard-deployment-756f6cd885-6mzrq"
I0416 12:18:56.015817       1 nodeserver.go:254] "node publish volume complete" targetPath="/var/lib/kubelet/pods/ba66d6a4-1def-4636-b67a-99ca929e9293/volumes/kubernetes.io~csi/secrets-store-inline/mount" pod="kuard/kuard-deployment-756f6cd885-6mzrq" time="1.128414837s"
I0416 12:18:56.016290       1 secretproviderclasspodstatus_controller.go:222] "reconcile started" spcps="kuard/kuard-deployment-756f6cd885-6mzrq-kuard-kuard-deployment-aws-secrets"
I0416 12:18:56.220255       1 secretproviderclasspodstatus_controller.go:366] "reconcile complete" spc="kuard/kuard-deployment-aws-secrets" pod="kuard/kuard-deployment-756f6cd885-6mzrq" spcps="kuard/kuard-deployment-756f6cd885-6mzrq-kuard-kuard-deployment-aws-secrets"
```

Go to these URLs and check the credentials synced from AWS Secrets Manager:

* [https://kuard.k01.k8s.mylabs.dev/fs/mnt/secrets-store/](https://kuard.k01.k8s.mylabs.dev/fs/mnt/secrets-store/)
  ![kuard-fs-mnt-secrets-store-KuardSecret](/assets/img/posts/2023/2023-04-01-secrets-store-csi-driver-reloader/kuard-fs-mnt-secrets-store-KuardSecret.avif
  "kuard-fs-mnt-secrets-store-KuardSecret")

  ```bash
  kubectl exec -i -n kuard deployments/kuard-deployment -- cat /mnt/secrets-store/KuardSecret
  ```

  ```json
  {"password":"rxxxxxxxxxxxxxxH","username":"admin123"}
  ```

* [https://kuard.k01.k8s.mylabs.dev/-/env](https://kuard.k01.k8s.mylabs.dev/-/env)
  ![kuard-env](/assets/img/posts/2023/2023-04-01-secrets-store-csi-driver-reloader/kuard-env.avif
  "kuard-env")

  ```bash
  kubectl exec -i -n kuard deployments/kuard-deployment -- sh -c "echo \${KUARDSECRET}"
  ```

  ```json
  {"password":"rxxxxxxxxxxxxxxH","username":"admin123"}
  ```

After the commands executed above the secret from the AWS secret manager
are copied to Kubernetes Secret (`kuard-secret`) and it is also present as file
(`/mnt/secrets-store/KuardSecret`) and environment variable (`KUARDSECRET`)
inside the pod.

## Rotate AWS Secret

Let's change/rotate credentials inside AWS Secret to see if the change will be
reflected also in the Kubernetes objects:

```bash
aws secretsmanager update-secret --secret-id "k01.k8s.mylabs.dev-KuardSecret" \
  --secret-string "{\"user\":\"admin123\",\"password\":\"EXAMPLE-PASSWORD\"}"
sleep 200
```

After changing the password in the AWS Secret Manager you should see also the
change in the K8s Secret and in the `/mnt/secrets-store/KuardSecret` file inside
the pod:

{% raw %}

```bash
kubectl get secrets -n kuard kuard-secret --template="{{.data.username}}" | base64 -d | jq
```

{% endraw %}

```json
{
  "user": "admin123",
  "password": "EXAMPLE-PASSWORD"
}
```

![aws-secrets-manager-02-secrets-kuardsecret](/assets/img/posts/2023/2023-04-01-secrets-store-csi-driver-reloader/aws-secrets-manager-02-secrets-kuardsecret.avif
"AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret"){: width="700" }
_AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret_

```bash
kubectl exec -i -n kuard deployments/kuard-deployment -- cat /mnt/secrets-store/KuardSecret
```

```json
{"user":"admin123","password":"EXAMPLE-PASSWORD"}
```

Environment variable inside the pod is not going to be changed:

```bash
kubectl exec -i -n kuard deployments/kuard-deployment -- sh -c "echo \${KUARDSECRET}"
```

```json
{"password":"rxxxxxxxxxxxxxxH","username":"admin123"}
```

The only way how to change the pre-defined environment variable inside the pod
is to restart the pod...

## Install Reloader to do rolling upgrades when Secrets get changed

In case of changes in the Secret (`kuard-secret`) the rolling upgrade should be
performed on Deployment (`kuard`) to "refresh" the environment variables.

It is time to use [Reloader](https://github.com/stakater/Reloader) which can do
it automatically.

![Reloader](https://raw.githubusercontent.com/stakater/Reloader/b73f14aef9d0ff24b91e4682223ecce485b8d21c/assets/web/reloader-round-100px.png)

Install `reloader`
[helm chart](https://github.com/stakater/Reloader/blob/master/deployments/kubernetes/chart/reloader/values.yaml).

```bash
# renovate: datasource=helm depName=reloader registryUrl=https://stakater.github.io/stakater-charts
RELOADER_HELM_CHART_VERSION="1.0.52"

helm repo add stakater https://stakater.github.io/stakater-charts
cat > "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-reloader.yml" << EOF
reloader:
  readOnlyRootFileSystem: true
  podMonitor:
    enabled: true
EOF
helm upgrade --install --version "${RELOADER_HELM_CHART_VERSION}" --namespace reloader --create-namespace --wait --values "${TMP_DIR}/${CLUSTER_FQDN}/helm_values-reloader.yml" reloader stakater/reloader
```

You need to annotate the `kuard` deployment to enable Pod rolling upgrades:

```bash
kubectl annotate -n kuard deployment kuard-deployment 'reloader.stakater.com/auto=true'
```

Let's do credential change one more time:

```bash
aws secretsmanager update-secret --secret-id "k01.k8s.mylabs.dev-KuardSecret" \
  --secret-string "{\"user\":\"admin123\",\"password\":\"EXAMPLE-PASSWORD-2\"}"
sleep 400
```

Screenshot from AWS Secrets Manager:

![aws-secrets-manager-03-secrets-kuardsecret](/assets/img/posts/2023/2023-04-01-secrets-store-csi-driver-reloader/aws-secrets-manager-03-secrets-kuardsecret.avif
"AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret"){: width="500" }
_AWS Secrets Manager - Secrets - k01.k8s.mylabs.dev-KuardSecret_

After some time changes are detected in `kuard-secret` secret and pods are
restarted:

```bash
kubectl logs -n reloader deployments/reloader-reloader reloader-reloader
```

```console
time="2023-04-17T18:08:57Z" level=info msg="Environment: Kubernetes"
time="2023-04-17T18:08:57Z" level=info msg="Starting Reloader"
time="2023-04-17T18:08:57Z" level=warning msg="KUBERNETES_NAMESPACE is unset, will detect changes in all namespaces."
time="2023-04-17T18:08:57Z" level=info msg="created controller for: configMaps"
time="2023-04-17T18:08:57Z" level=info msg="Starting Controller to watch resource type: configMaps"
time="2023-04-17T18:08:57Z" level=info msg="created controller for: secrets"
time="2023-04-17T18:08:57Z" level=info msg="Starting Controller to watch resource type: secrets"
time="2023-04-17T18:12:17Z" level=info msg="Changes detected in 'kuard-secret' of type 'SECRET' in namespace 'kuard', Updated 'kuard-deployment' of type 'Deployment' in namespace 'kuard'"
```

After the pod reload the environment variable `KUARDSECRET` should contain the
proper value:

```bash
kubectl exec -i -n kuard deployments/kuard-deployment -- sh -c "echo \${KUARDSECRET}"
```

```json
{"user":"admin123","password":"EXAMPLE-PASSWORD-2"}
```

It is possible to use/synchronize credentials form the AWS Secret Manager to:

* File inside the pod
* Kubernetes Secret
* Environment variable inside the pod

---

To clean up the environment - delete IRSA, remove CloudFormation stack
and namespace:

```sh
eksctl delete iamserviceaccount --cluster="${CLUSTER_NAME}" --name=kuard --namespace=kuard
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-aws-secretmanager-secret"
```

Enjoy ... 😉
