---
title: Run the cheapest Amazon EKS
author: Petr Ruzicka
date: 2022-11-27
description: Start cheapest Amazon EKS using eksctl
categories: [Kubernetes, Amazon EKS]
tags: [Amazon EKS, k8s, kubernetes, karpenter, eksctl, cert-manager, external-dns, podinfo]
image:
  path: https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/icon-aws-amazon-eks.svg
  width: 20%
  height: 20%
  alt: Amazon EKS
---

Sometimes it is necessary to save costs and run the [Amazon EKS](https://aws.amazon.com/eks/)
the "cheapest way".

The following notes are about running [Amazon EKS](https://aws.amazon.com/eks/)
with lowest price.

Requirements:

- Single AZ only - no payments for cross availability zones traffic
- [Not done] Spot instances "everywhere"
- Less expensive region - `us-east-1`
- Most price efficient EC2 instance type - ARM Graviton based `t4g.medium`
  (2 x CPU, 4GB RAM)
- Use ARM based EC2 instances
- Use Bottlerocket - small operation system / CPU / Memory footprint
- Use Network Load Balancer (NLB) as a most cost efficient + cost optimized LB
- [Not done] Allow as many pods as needed on worker nodes `max-pods-per-node`
  - <https://stackoverflow.com/questions/57970896/pod-limit-on-node-aws-eks>
  - <https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/>

## Build Amazon EKS cluster

<!---
Run all commands using:
sed -n "/^\`\`\`bash$/,/^\`\`\`$/p" 2022-11-27-cheapest-amazon-eks.md | sed "/^\`\`\`*/d" | bash -euxo pipefail
sed -n "/^\`\`\`sh$/,/^\`\`\`$/p"   2022-11-27-cheapest-amazon-eks.md | sed "/^\`\`\`*/d" | bash -euxo pipefail
-->

### Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables.

`BASE_DOMAIN` (`k8s.mylabs.dev`) contains DNS records for all your Kubernetes
clusters. The cluster names will look like `CLUSTER_NAME`.`BASE_DOMAIN`
(`kube1.k8s.mylabs.dev`).

```bash
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export KUBECONFIG="${PWD}/tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"
export LETSENCRYPT_ENVIRONMENT="staging" # production
export MY_EMAIL="petr.ruzicka@gmail.com"
# Tags used to tag the AWS resources
export TAGS="Owner=${MY_EMAIL} Environment=dev"
```

You will need to configure [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and other secrets/variables.

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_SESSION_TOKEN="xxxxxxxx"
```

Verify if all the necessary variables were set:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${KUBECONFIG?}"
: "${LETSENCRYPT_ENVIRONMENT?}"
: "${MY_EMAIL?}"
: "${TAGS?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

### Prepare the local working environment

> You can skip these steps if you have all the required software already
> installed.
{: .prompt-tip }

Required:

- [AWS CLI](https://aws.amazon.com/cli/)
- [Helm](https://helm.sh/)
- [kubectl](https://github.com/kubernetes/kubectl)

Install [eksctl](https://eksctl.io/):

```bash
if ! command -v eksctl &> /dev/null; then
  # renovate: datasource=github-tags depName=weaveworks/eksctl
  EKSCTL_VERSION="0.118.0"
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

## Configure AWS Route 53 Domain delegation

> DNS delegation should be done only once.
{: .prompt-info }

Create DNS zone for EKS clusters:

```shell
export CLOUDFLARE_EMAIL="petr.ruzicka@gmail.com"
export CLOUDFLARE_API_KEY="1xxxxxxxxx0"

aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
`mylabs.dev`) to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.mylabs.dev` (`BASE_DOMAIN`) for
proper zone delegation. This step depends on your domain registrar - I'm using
CloudFlare and using Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

Output:

```text
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

### Create Route53

Create CloudFormation template containing policies for Route53 and Domain.

Put new domain `CLUSTER_FQDN` to the Route 53 and configure the DNS delegation
from the `BASE_DOMAIN`.

Create temporary directory for files used for creating/configuring EKS Cluster
and it's components:

```bash
mkdir -p "tmp/${CLUSTER_FQDN}"
```

Create Route53 zone:

```bash
cat > "tmp/${CLUSTER_FQDN}/cf-route53.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries

Parameters:

  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String

  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: kube1.k8s.mylabs.dev"
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
EOF

if [[ $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query "StackSummaries[?starts_with(StackName, \`${CLUSTER_NAME}-route53\`) == \`true\`].StackName" --output text) == "" ]]; then
  # shellcheck disable=SC2001
  eval aws cloudformation "create-stack" \
    --parameters "ParameterKey=BaseDomain,ParameterValue=${BASE_DOMAIN} ParameterKey=ClusterFQDN,ParameterValue=${CLUSTER_FQDN}" \
    --stack-name "${CLUSTER_NAME}-route53" \
    --template-body "file://tmp/${CLUSTER_FQDN}/cf-route53.yml" \
    --tags "$(echo "${TAGS}" | sed -e 's/\([^ =]*\)=\([^ ]*\)/Key=\1,Value=\2/g')" || true
fi
```

## Create Amazon EKS

I'm going to use [eksctl](https://eksctl.io/) to create the Amazon EKS cluster.

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl"){: width="700" }{: .shadow }

Create [Amazon EKS](https://aws.amazon.com/eks/) using [eksctl](https://eksctl.io/):

```bash
cat > "tmp/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.24"
  tags: &tags
    karpenter.sh/discovery: ${CLUSTER_NAME}
$(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/    /g; s/=/: /g")
availabilityZones:
  - ${AWS_DEFAULT_REGION}a
  - ${AWS_DEFAULT_REGION}b
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
    - metadata:
        name: external-dns
        namespace: external-dns
      wellKnownPolicies:
        externalDNS: true
karpenter:
  # Bug: version 0.20.0 is not supported yet: https://github.com/weaveworks/eksctl/issues/6033
  version: v0.18.1
  createServiceAccount: true
addons:
  - name: vpc-cni
  - name: kube-proxy
  - name: coredns
  - name: aws-ebs-csi-driver
managedNodeGroups:
  - name: mng01
    amiFamily: Bottlerocket
    # Minimal instance type for running add-ons + karpenter - ARM t4g.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    # Minimal instance type for running add-ons + karpenter - X86 t3a.medium: 4.0 GiB, 2 vCPUs - 0.0336 hourly
    instanceType: t4g.medium
    # Due to karpenter we need 2 instances
    desiredCapacity: 2
    availabilityZones:
      - ${AWS_DEFAULT_REGION}a
    minSize: 2
    maxSize: 5
    volumeSize: 20
    volumeType: gp3
    volumeEncrypted: true
    disableIMDSv1: true
EOF
```

Get the kubeconfig to access the cluster:

```bash
if [[ ! -s "${KUBECONFIG}" ]]; then
  if ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null; then
    eksctl create cluster --config-file "tmp/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" --kubeconfig "${KUBECONFIG}"
  else
    eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  fi
fi

aws eks update-kubeconfig --name="${CLUSTER_NAME}"
echo -e "***************\n export KUBECONFIG=${KUBECONFIG} \n***************"
```

Configure [Karpenter](https://karpenter.sh/)

![Karpenter](https://raw.githubusercontent.com/aws/karpenter/efa141bc7276db421980bf6e6483d9856929c1e9/website/static/banner.png
"Karpenter"){: width="600" }{: .shadow }

```bash
cat << EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  namespace: karpenter
  name: default
spec:
  # Bug: version 0.20.0 is not supported yet: https://github.com/weaveworks/eksctl/issues/6033
  # https://youtu.be/OB7IZolZk78?t=2629
  # consolidation:
  #   enabled: true
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      # Not working due to bug: https://github.com/weaveworks/eksctl/issues/6064
      # values: ["on-demand","spot"]
      values: ["on-demand"]
    - key: kubernetes.io/arch
      operator: In
      values: ["amd64","arm64"]
    - key: "topology.kubernetes.io/zone"
      operator: In
      values: ["${AWS_DEFAULT_REGION}a"]
    - key: karpenter.k8s.aws/instance-family
      operator: In
      values: [t3a, t4g]
  limits:
    resources:
      cpu: 1000
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30
---
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  namespace: karpenter
  name: default
spec:
  amiFamily: Bottlerocket
  subnetSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  securityGroupSelector:
    karpenter.sh/discovery: ${CLUSTER_NAME}
  tags:
    KarpenerProvisionerName: "default"
    Name: ${CLUSTER_NAME}-karpenter
EOF
```

---

## DNS, Ingress, Certificates

Install the basic tools, before running some applications like DNS integration
([external-dns](https://github.com/kubernetes-sigs/external-dns)), Ingress ([ingress-nginx](https://kubernetes.github.io/ingress-nginx/)),
certificate management ([cert-manager](https://cert-manager.io/)), ...

### cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
and modify the
[default values](https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

![cert-manager](https://raw.githubusercontent.com/cert-manager/cert-manager/7f15787f0f146149d656b6877a6fbf4394fe9965/logo/logo.svg
"cert-manager"){: width="200" }{: .shadow }

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.10.1"

helm repo add --force-update jetstack https://charts.jetstack.io
helm upgrade --install --version "${CERT_MANAGER_HELM_CHART_VERSION}" --namespace cert-manager --create-namespace --wait --values - cert-manager jetstack/cert-manager << EOF
installCRDs: true
serviceAccount:
  create: false
  name: cert-manager
extraArgs:
  - --enable-certificate-owner-ref=true
EOF
```

Add ClusterIssuers for Let's Encrypt staging and production:

```bash
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns
  namespace: cert-manager
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: ${AWS_DEFAULT_REGION}
---
# Create ClusterIssuer for production to get real signed certificates
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns
  namespace: cert-manager
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

kubectl wait --namespace cert-manager --timeout=10m --for=condition=Ready clusterissuer --all
```

### metrics-server

Install `metrics-server`
[helm chart](https://artifacthub.io/packages/helm/metrics-server/metrics-server)
and modify the
[default values](https://github.com/kubernetes-sigs/metrics-server/blob/master/charts/metrics-server/values.yaml):

```bash
# renovate: datasource=helm depName=metrics-server registryUrl=https://kubernetes-sigs.github.io/metrics-server/
METRICS_SERVER_HELM_CHART_VERSION="3.8.2"

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install --version "${METRICS_SERVER_HELM_CHART_VERSION}" --namespace kube-system metrics-server metrics-server/metrics-server
```

### external-dns

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/bitnami/external-dns)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://kubernetes-sigs.github.io/external-dns/
EXTERNAL_DNS_HELM_CHART_VERSION="1.11.0"

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm upgrade --install --version "${EXTERNAL_DNS_HELM_CHART_VERSION}" --namespace external-dns --values - external-dns external-dns/external-dns << EOF
serviceAccount:
  create: false
  name: external-dns
interval: 20s
policy: sync
domainFilters:
  - ${CLUSTER_FQDN}
EOF
```

### ingress-nginx

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.4.0"

helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --create-namespace --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
controller:
  replicaCount: 2
  watchIngressWithoutClass: true
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "$(echo "${TAGS}" | tr " " ,)"
EOF
```

## Workloads

Run some workload on the K8s...

Start the amd64 only container:

```bash
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 1
            memory: 16Mi
      nodeSelector:
        kubernetes.io/arch: amd64
EOF
```

Install `podinfo`
[helm chart](https://artifacthub.io/packages/helm/podinfo/podinfo)
and modify the
[default values](https://github.com/stefanprodan/podinfo/blob/master/charts/podinfo/values.yaml).

![podinfo](https://raw.githubusercontent.com/stefanprodan/podinfo/a7be119f20369b97f209d220535506af7c49b4ea/screens/podinfo-ui-v3.png
"podinfo"){: width="500" }{: .shadow }

```bash
# renovate: datasource=helm depName=podinfo registryUrl=https://stefanprodan.github.io/podinfo
PODINFO_HELM_CHART_VERSION="6.2.3"

helm repo add --force-update sp https://stefanprodan.github.io/podinfo
helm upgrade --install --version "${PODINFO_HELM_CHART_VERSION}" --namespace podinfo --create-namespace --wait --values - podinfo sp/podinfo << EOF
certificate:
  create: true
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-${LETSENCRYPT_ENVIRONMENT}-dns
  dnsNames:
    - podinfo.${CLUSTER_FQDN}
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: podinfo.${CLUSTER_FQDN}
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls:
    - secretName: podinfo-tls
      hosts:
        - podinfo.${CLUSTER_FQDN}
resources:
  requests:
    cpu: 1
    memory: 16Mi
EOF

kubectl scale deployment -n podinfo podinfo --replicas 1
```

Check cluster + node details:

```bash
kubectl get nodes -o wide
```

Output:

```text
NAME                             STATUS   ROLES    AGE     VERSION               INTERNAL-IP      EXTERNAL-IP     OS-IMAGE                                KERNEL-VERSION   CONTAINER-RUNTIME
ip-192-168-11-210.ec2.internal   Ready    <none>   21m     v1.24.6-eks-4360b32   192.168.11.210   54.89.253.185   Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-17-24.ec2.internal    Ready    <none>   21m     v1.24.6-eks-4360b32   192.168.17.24    3.88.130.104    Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-90-242.ec2.internal   Ready    <none>   9m10s   v1.24.6-eks-4360b32   192.168.90.242   <none>          Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
ip-192-168-91-66.ec2.internal    Ready    <none>   9m16s   v1.24.6-eks-4360b32   192.168.91.66    <none>          Bottlerocket OS 1.11.1 (aws-k8s-1.24)   5.15.59          containerd://1.6.8+bottlerocket
```

```bash
kubectl get pods -A -o wide --sort-by='.status.hostIP'
```

Output:

```text
NAMESPACE       NAME                                        READY   STATUS    RESTARTS   AGE     IP               NODE                             NOMINATED NODE   READINESS GATES
kube-system     aws-node-tckpq                              1/1     Running   0          21m     192.168.11.210   ip-192-168-11-210.ec2.internal   <none>           <none>
kube-system     ebs-csi-node-szg4l                          3/3     Running   0          17m     192.168.0.255    ip-192-168-11-210.ec2.internal   <none>           <none>
kube-system     metrics-server-7cd9d56884-54l69             1/1     Running   0          10m     192.168.25.190   ip-192-168-11-210.ec2.internal   <none>           <none>
kube-system     kube-proxy-rgb82                            1/1     Running   0          21m     192.168.11.210   ip-192-168-11-210.ec2.internal   <none>           <none>
cert-manager    cert-manager-cainjector-86f7f4749-4j49w     1/1     Running   0          11m     192.168.1.116    ip-192-168-11-210.ec2.internal   <none>           <none>
kube-system     ebs-csi-controller-6b894589bd-m64jn         6/6     Running   0          17m     192.168.23.73    ip-192-168-11-210.ec2.internal   <none>           <none>
ingress-nginx   ingress-nginx-controller-777c5c9d68-z29nc   1/1     Running   0          9m52s   192.168.14.14    ip-192-168-11-210.ec2.internal   <none>           <none>
karpenter       karpenter-57595c57c5-mtbcg                  2/2     Running   0          12m     192.168.12.13    ip-192-168-11-210.ec2.internal   <none>           <none>
cert-manager    cert-manager-webhook-66c85f8577-5c9kk       1/1     Running   0          11m     192.168.2.165    ip-192-168-11-210.ec2.internal   <none>           <none>
kube-system     coredns-79989457d9-r6f7d                    1/1     Running   0          32m     192.168.20.61    ip-192-168-17-24.ec2.internal    <none>           <none>
karpenter       karpenter-57595c57c5-vf6nt                  2/2     Running   0          12m     192.168.23.69    ip-192-168-17-24.ec2.internal    <none>           <none>
external-dns    external-dns-6df56bcbb5-2c6lh               1/1     Running   0          10m     192.168.17.251   ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     coredns-79989457d9-d2qh6                    1/1     Running   0          32m     192.168.15.109   ip-192-168-17-24.ec2.internal    <none>           <none>
cert-manager    cert-manager-7d57b6576b-slv5h               1/1     Running   0          11m     192.168.7.107    ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     ebs-csi-controller-6b894589bd-r9zkg         6/6     Running   0          17m     192.168.26.132   ip-192-168-17-24.ec2.internal    <none>           <none>
ingress-nginx   ingress-nginx-controller-777c5c9d68-qbqh8   1/1     Running   0          9m52s   192.168.6.199    ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     kube-proxy-cxmcx                            1/1     Running   0          21m     192.168.17.24    ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     ebs-csi-node-w5vkx                          3/3     Running   0          17m     192.168.8.186    ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     aws-node-mwrmh                              1/1     Running   0          21m     192.168.17.24    ip-192-168-17-24.ec2.internal    <none>           <none>
kube-system     kube-proxy-7vp5f                            1/1     Running   0          9m22s   192.168.90.242   ip-192-168-90-242.ec2.internal   <none>           <none>
kube-system     aws-node-dzm8h                              1/1     Running   0          9m22s   192.168.90.242   ip-192-168-90-242.ec2.internal   <none>           <none>
podinfo         podinfo-7d56b99d4-tpdck                     1/1     Running   0          9m26s   192.168.77.89    ip-192-168-90-242.ec2.internal   <none>           <none>
kube-system     ebs-csi-node-gzbwl                          3/3     Running   0          9m22s   192.168.81.188   ip-192-168-90-242.ec2.internal   <none>           <none>
kube-system     ebs-csi-node-6pmkx                          3/3     Running   0          9m28s   192.168.80.127   ip-192-168-91-66.ec2.internal    <none>           <none>
kube-system     aws-node-4bpvh                              1/1     Running   0          9m28s   192.168.91.66    ip-192-168-91-66.ec2.internal    <none>           <none>
kube-system     kube-proxy-crj2t                            1/1     Running   0          9m28s   192.168.91.66    ip-192-168-91-66.ec2.internal    <none>           <none>
default         nginx-deployment-5c7f597d98-xw9tw           1/1     Running   0          9m33s   192.168.89.194   ip-192-168-91-66.ec2.internal    <none>           <none>
```

```bash
kubectl get nodes -o json | jq -Cjr '.items[] | .metadata.name," ",.metadata.labels."node.kubernetes.io/instance-type"," ",.metadata.labels."kubernetes.io/arch", "\n"' | sort -k2 -r | column -t
```

Output:

```text
ip-192-168-90-242.ec2.internal  t4g.small   arm64
ip-192-168-17-24.ec2.internal   t4g.medium  arm64
ip-192-168-11-210.ec2.internal  t4g.medium  arm64
ip-192-168-91-66.ec2.internal   t3a.small   amd64
```

```bash
kubectl resource-capacity --sort cpu.util --util --pods --pod-count
```

Output:

```text
NODE                             NAMESPACE       POD                                         CPU REQUESTS   CPU LIMITS     CPU UTIL    MEMORY REQUESTS   MEMORY LIMITS   MEMORY UTIL    POD COUNT
*                                *               *                                           5540m (71%)    4800m (62%)    181m (2%)   3560Mi (37%)      8732Mi (92%)    2130Mi (22%)   27/53

ip-192-168-11-210.ec2.internal   *               *                                           1515m (78%)    2100m (108%)   55m (2%)    1574Mi (47%)      3428Mi (104%)   678Mi (20%)    9/17
ip-192-168-11-210.ec2.internal   karpenter       karpenter-57595c57c5-mtbcg                  1200m (62%)    1200m (62%)    3m (0%)     1124Mi (34%)      1124Mi (34%)    99Mi (3%)
ip-192-168-11-210.ec2.internal   kube-system     ebs-csi-controller-6b894589bd-m64jn         60m (3%)       600m (31%)     3m (0%)     240Mi (7%)        1536Mi (46%)    51Mi (1%)
ip-192-168-11-210.ec2.internal   kube-system     metrics-server-7cd9d56884-54l69             0Mi (0%)       0Mi (0%)       3m (0%)     0Mi (0%)          0Mi (0%)        18Mi (0%)
ip-192-168-11-210.ec2.internal   kube-system     aws-node-tckpq                              25m (1%)       0Mi (0%)       3m (0%)     0Mi (0%)          0Mi (0%)        28Mi (0%)
ip-192-168-11-210.ec2.internal   cert-manager    cert-manager-cainjector-86f7f4749-4j49w     0Mi (0%)       0Mi (0%)       2m (0%)     0Mi (0%)          0Mi (0%)        16Mi (0%)
ip-192-168-11-210.ec2.internal   kube-system     ebs-csi-node-szg4l                          30m (1%)       300m (15%)     1m (0%)     120Mi (3%)        768Mi (23%)     19Mi (0%)
ip-192-168-11-210.ec2.internal   kube-system     kube-proxy-rgb82                            100m (5%)      0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-11-210.ec2.internal   cert-manager    cert-manager-webhook-66c85f8577-5c9kk       0Mi (0%)       0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-11-210.ec2.internal   ingress-nginx   ingress-nginx-controller-777c5c9d68-z29nc   100m (5%)      0Mi (0%)       1m (0%)     90Mi (2%)         0Mi (0%)        64Mi (1%)

ip-192-168-17-24.ec2.internal    *               *                                           1715m (88%)    2100m (108%)   52m (2%)    1714Mi (52%)      3768Mi (114%)   623Mi (18%)    10/17
ip-192-168-17-24.ec2.internal    kube-system     aws-node-mwrmh                              25m (1%)       0Mi (0%)       3m (0%)     0Mi (0%)          0Mi (0%)        28Mi (0%)
ip-192-168-17-24.ec2.internal    kube-system     ebs-csi-controller-6b894589bd-r9zkg         60m (3%)       600m (31%)     2m (0%)     240Mi (7%)        1536Mi (46%)    51Mi (1%)
ip-192-168-17-24.ec2.internal    kube-system     coredns-79989457d9-r6f7d                    100m (5%)      0Mi (0%)       2m (0%)     70Mi (2%)         170Mi (5%)      12Mi (0%)
ip-192-168-17-24.ec2.internal    kube-system     ebs-csi-node-w5vkx                          30m (1%)       300m (15%)     1m (0%)     120Mi (3%)        768Mi (23%)     19Mi (0%)
ip-192-168-17-24.ec2.internal    kube-system     coredns-79989457d9-d2qh6                    100m (5%)      0Mi (0%)       1m (0%)     70Mi (2%)         170Mi (5%)      12Mi (0%)
ip-192-168-17-24.ec2.internal    karpenter       karpenter-57595c57c5-vf6nt                  1200m (62%)    1200m (62%)    1m (0%)     1124Mi (34%)      1124Mi (34%)    32Mi (0%)
ip-192-168-17-24.ec2.internal    kube-system     kube-proxy-cxmcx                            100m (5%)      0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-17-24.ec2.internal    cert-manager    cert-manager-7d57b6576b-slv5h               0Mi (0%)       0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        25Mi (0%)
ip-192-168-17-24.ec2.internal    external-dns    external-dns-6df56bcbb5-2c6lh               0Mi (0%)       0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        18Mi (0%)
ip-192-168-17-24.ec2.internal    ingress-nginx   ingress-nginx-controller-777c5c9d68-qbqh8   100m (5%)      0Mi (0%)       1m (0%)     90Mi (2%)         0Mi (0%)        65Mi (1%)

ip-192-168-91-66.ec2.internal    *               *                                           1155m (59%)    300m (15%)     42m (2%)    136Mi (9%)        768Mi (51%)     433Mi (29%)    4/8
ip-192-168-91-66.ec2.internal    kube-system     aws-node-4bpvh                              25m (1%)       0Mi (0%)       5m (0%)     0Mi (0%)          0Mi (0%)        29Mi (1%)
ip-192-168-91-66.ec2.internal    kube-system     ebs-csi-node-6pmkx                          30m (1%)       300m (15%)     1m (0%)     120Mi (8%)        768Mi (51%)     20Mi (1%)
ip-192-168-91-66.ec2.internal    kube-system     kube-proxy-crj2t                            100m (5%)      0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        10Mi (0%)
ip-192-168-91-66.ec2.internal    default         nginx-deployment-5c7f597d98-xw9tw           1000m (51%)    0Mi (0%)       0m (0%)     16Mi (1%)         0Mi (0%)        2Mi (0%)

ip-192-168-90-242.ec2.internal   *               *                                           1155m (59%)    300m (15%)     34m (1%)    136Mi (9%)        768Mi (56%)     399Mi (29%)    4/11
ip-192-168-90-242.ec2.internal   kube-system     aws-node-dzm8h                              25m (1%)       0Mi (0%)       4m (0%)     0Mi (0%)          0Mi (0%)        25Mi (1%)
ip-192-168-90-242.ec2.internal   podinfo         podinfo-7d56b99d4-tpdck                     1000m (51%)    0Mi (0%)       3m (0%)     16Mi (1%)         0Mi (0%)        15Mi (1%)
ip-192-168-90-242.ec2.internal   kube-system     kube-proxy-7vp5f                            100m (5%)      0Mi (0%)       1m (0%)     0Mi (0%)          0Mi (0%)        11Mi (0%)
ip-192-168-90-242.ec2.internal   kube-system     ebs-csi-node-gzbwl                          30m (1%)       300m (15%)     1m (0%)     120Mi (8%)        768Mi (56%)     19Mi (1%)
```

## Clean-up

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up"){: width="400" }

Set necessary variables and verify if all the necessary variables were set:

```sh
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export KUBECONFIG="${PWD}/tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"

: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${KUBECONFIG?}"
```

Remove EKS cluster and created components:

```sh
if eksctl get cluster --name="${CLUSTER_NAME}" 2> /dev/null; then
  eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  eksctl delete cluster --name="${CLUSTER_NAME}" --force
fi
```

Remove orphan EC2 created by Karpenter:

```sh
for EC2 in $(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text) ; do
  echo "Removing EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done
```

Remove orphan Remove Network ELBs (if exists):

```sh
for NETWORK_ELB_ARN in $(aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn" --output=text) ; do
  if [[ "$(aws elbv2 describe-tags --resource-arns "${NETWORK_ELB_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" =~ ${CLUSTER_NAME} ]]; then
    echo "*** Deleting Network ELB: ${NETWORK_ELB_ARN}"
    aws elbv2 delete-load-balancer --load-balancer-arn "${NETWORK_ELB_ARN}"
  fi
done
```

Remove orphan Target Groups (if exists):

```sh
for TARGET_GROUP_ARN in $(aws elbv2 describe-target-groups --region=eu-central-1 --query "TargetGroups[].TargetGroupArn" --output=text) ; do
  if [[ "$(aws elbv2 describe-tags --resource-arns "${TARGET_GROUP_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output
text)" =~ ${CLUSTER_NAME} ]]; then
    echo "*** Deleting Target Group: ${TARGET_GROUP_ARN}"
    aws elbv2 delete-target-group --target-group-arn "${TARGET_GROUP_ARN}"
  fi
done
```

Remove Route 53 DNS records from DNS Zone:

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

Remove CloudFormation stacks:

```sh
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53"
```

Wait for all CloudFormation stacks to be deleted:

```sh
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove Volumes and Snapshots related to the cluster:

```sh
for VOLUME in $(aws ec2 describe-volumes --filter "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" --query 'Volumes[].VolumeId' --output text) ; do
  echo "*** Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done
```

Remove `tmp/${CLUSTER_FQDN}` directory:

```sh
[[ -d "tmp/${CLUSTER_FQDN}" ]] && rm -rf "tmp/${CLUSTER_FQDN}" && [[ -d tmp ]] && rmdir tmp || true
```

Enjoy ... 😉
