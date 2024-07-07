---
title: Detect the hacker attacks on Amazon EKS, Amazon ECS and EC2 instances
author: Petr Ruzicka
date: 2024-07-07
description: Use the security tools to detect the hacker attacks on Amazon EKS, Amazon ECS and EC2 instances
categories: [Kubernetes, Amazon EKS, Security, Exploit, Vulnerability, Kali Linux, EC2, Docker, Amazon ECS]
tags:
  [
    Amazon ECS,
    Amazon EKS,
    container,
    docker,
    EC2,
    eksctl,
    exploit,
    k8s,
    Kali Linux,
    kubernetes,
    plugin,
    security,
    SQLi,
    vulnerability,
    WordPress,
  ]
image: https://user-images.githubusercontent.com/45159366/128566095-253303e2-25d8-42f1-a06d-0b38ca079a1a.png
---

In previous posts [1]({%post_url /2024/2024-04-27-exploit-vulnerability-wordpress-plugin-kali-linux-1%})
and [2]({%post_url /2024/2024-05-09-exploit-vulnerability-wordpress-plugin-kali-linux-2%})
I've shown how to exploit a vulnerability in a WordPress plugin running on
Amazon EKS, Amazon ECS and EC2 instances using Kali Linux and Metasploit.

In this post, I would like to look at the way to detect the hacker attacks using
the security tools like [Wiz](https://wiz.io/), [MS Defender](https://www.microsoft.com/en-us/security/business/endpoint-security/microsoft-defender-business),
and [Amazon GuardDuty](https://aws.amazon.com/guardduty/).

I'm going to cover the following steps:

- Install vulnerable Wordpress Application + Plugin to Amazon EKS, ECS and EC2 instances
- Secure the Amazon EKS, ECS and EC2 instances using the security tools
- Exploit vulnerability in a WordPress plugin using Kali Linux and Metasploit

## Build the Amazon EKS, ECS and EC2 instances with Wordpress Application

This section contains the commands needed to build the Amazon EKS, ECS and EC2
instances with the vulnerable Wordpress Application.
I'm not going to cover all the details, because they were already described in
previous posts [1]({%post_url /2024/2024-04-27-exploit-vulnerability-wordpress-plugin-kali-linux-1%})
and [2]({%post_url /2024/2024-05-09-exploit-vulnerability-wordpress-plugin-kali-linux-2%}).

Requirements:

- [AWS CLI](https://aws.amazon.com/cli/)
- [Colima](https://github.com/abiosoft/colima) / [Docker](https://www.docker.com/)
  / [Rancher Desktop](https://rancherdesktop.io/) / ...
- [copilot](https://github.com/aws/copilot-cli)
- [eksctl](https://eksctl.io/)
- [kubectl](https://github.com/kubernetes/kubectl)
- [helm](https://github.com/helm/helm)

I'm going to cover only the necessary commands (without descriptions):

```bash
# export AWS_ACCESS_KEY_ID="xxxxxxxxxxxxxxxxxx"
# export AWS_SECRET_ACCESS_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export AWS_DEFAULT_REGION="eu-central-1"
AWS_EC2_KEY_PAIR_NAME="wordpress-test"
TMP_DIR="${TMP_DIR:-${PWD}}"
WORDPRESS_USERNAME="wordpress"
WORDPRESS_PASSWORD=$(openssl rand -base64 12)
MARIADB_WORDPRESS_DATABASE="wordpress"
MARIADB_WORDPRESS_DATABASE_USER="wordpress"
MARIADB_WORDPRESS_DATABASE_PASSWORD=$(openssl rand -base64 12)
MARIADB_ROOT_PASSWORD=$(openssl rand -base64 12)

## Download the CloudFormation templates
# renovate: currentValue=master
wget --continue -q -P "${TMP_DIR}" https://raw.githubusercontent.com/aws-samples/aws-codebuild-samples/00284b828a360aa89ac635a44d84c5a748af03d3/ci_tools/vpc_cloudformation_template.yml
# renovate:
wget --continue -q -P "${TMP_DIR}" https://raw.githubusercontent.com/aws-samples/amazon-ec2-nice-dcv-samples/720bbefbf14a5391d4762edba13120a2e7a35f66/cfn/KaliLinux-NICE-DCV.yaml
# renovate:
wget --continue -q -P "${TMP_DIR}" https://raw.githubusercontent.com/aws-samples/ec2-lamp-server/c0ec2481d4995771422304b05b7b90bd701052f2/UbuntuLinux-2204-LAMP-server.yaml
# renovate:
wget --continue -q -P "${TMP_DIR}" https://raw.githubusercontent.com/aws-samples/ec2-lamp-server/c0ec2481d4995771422304b05b7b90bd701052f2/AmazonLinux-2023-LAMP-server.yaml

## Create a new AWS EC2 Key Pair to be used for the EC2 instances
aws ec2 create-key-pair --key-name "${AWS_EC2_KEY_PAIR_NAME}" --key-type ed25519 --query "KeyMaterial" --output text > "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem"
chmod 600 "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem"

## Create AWS EC2 instance with [Kali Linux](https://www.kali.org/) using the CloudFormation template
export SOLUTION_KALI="KaliLinux-NICE-DCV"

aws cloudformation deploy --capabilities CAPABILITY_IAM \
  --parameter-overrides "EnvironmentName=${SOLUTION_KALI}" \
  --stack-name "${SOLUTION_KALI}-VPC" --template-file "${TMP_DIR}/vpc_cloudformation_template.yml" \
  --tags "Owner=${USER} Environment=dev Solution=${SOLUTION_KALI}"

# shellcheck disable=SC2016
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${SOLUTION_KALI}-VPC" --query 'Stacks[0].Outputs[? OutputKey==`PublicSubnet1` || OutputKey==`VPC`].{OutputKey:OutputKey,OutputValue:OutputValue}')
AWS_VPC_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"VPC\") .OutputValue")
AWS_SUBNET_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"PublicSubnet1\") .OutputValue")

eval aws cloudformation create-stack --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_IAM --on-failure DO_NOTHING \
  --parameters "ParameterKey=ec2KeyPair,ParameterValue=${AWS_EC2_KEY_PAIR_NAME} ParameterKey=vpcID,ParameterValue=${AWS_VPC_ID} ParameterKey=subnetID,ParameterValue=${AWS_SUBNET_ID} ParameterKey=allowWebServerPorts,ParameterValue=HTTP-and-HTTPS" \
  --stack-name "${SOLUTION_KALI}" --template-body "file://${TMP_DIR}/KaliLinux-NICE-DCV.yaml" \
  --tags "Key=Owner,Value=${USER} Key=Environment,Value=dev Key=Solution,Value=${SOLUTION_KALI}"

## Install the Amazon EKS cluster using the "eksctl":
export CLUSTER_NAME="Amazon-EKS"
export KUBECONFIG="${TMP_DIR}/kubeconfig-${CLUSTER_NAME}.conf"

eksctl create cluster \
  --name "${CLUSTER_NAME}" --tags "Owner=${USER},Solution=${CLUSTER_NAME},Cluster=${CLUSTER_NAME}" \
  --node-type t3a.medium --node-volume-size 20 --node-private-networking \
  --kubeconfig "${KUBECONFIG}"

## Install vulnerable Wordpress Application to the Amazon EKS cluster using the Helm chart and modify the default values
WORDPRESS_HELM_CHART_VERSION="22.1.3"

tee "${TMP_DIR}/helm_values-wordpress.yml" << EOF
wordpressUsername: wordpress
wordpressPassword: $(openssl rand -base64 12)
customPostInitScripts:
  install_plugins.sh: |
    wp plugin install backup-backup --version=1.3.7 --activate
    wp plugin install loginizer --version=1.6.3 --activate
persistence:
  enabled: false
mariadb:
  primary:
    persistence:
      enabled: false
EOF
helm upgrade --install --version "${WORDPRESS_HELM_CHART_VERSION}" --namespace wordpress --create-namespace --wait --values "${TMP_DIR}/helm_values-wordpress.yml" wordpress oci://registry-1.docker.io/bitnamicharts/wordpress

K8S_WORDPRESS_SERVICE=$(kubectl get services --namespace wordpress wordpress --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')

## Build new Ubuntu Linux 22.04 EC2 instance
export SOLUTION_EC2_CONTAINER="Amazon-EC2-Container"

aws cloudformation deploy \
  --parameter-overrides "EnvironmentName=${SOLUTION_EC2_CONTAINER}" \
  --stack-name "${SOLUTION_EC2_CONTAINER}-VPC" --template-file "${TMP_DIR}/vpc_cloudformation_template.yml" \
  --tags "Owner=${USER} Environment=dev Solution=${SOLUTION_EC2_CONTAINER}"

# shellcheck disable=SC2016
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${SOLUTION_EC2_CONTAINER}-VPC" --query 'Stacks[0].Outputs[? OutputKey==`PublicSubnet1` || OutputKey==`VPC`].{OutputKey:OutputKey,OutputValue:OutputValue}')
AWS_VPC_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"VPC\") .OutputValue")
AWS_SUBNET_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"PublicSubnet1\") .OutputValue")

eval aws cloudformation deploy --capabilities CAPABILITY_IAM \
  --parameter-overrides "instanceType=t4g.medium ec2Name=${SOLUTION_EC2_CONTAINER} ec2KeyPair=${AWS_EC2_KEY_PAIR_NAME} vpcID=${AWS_VPC_ID} subnetID=${AWS_SUBNET_ID} webOption=none databaseOption=none phpVersion=none" \
  --stack-name "${SOLUTION_EC2_CONTAINER}" --template-file "${TMP_DIR}/AmazonLinux-2023-LAMP-server.yaml" \
  --tags "Owner=${USER} Environment=dev Solution=${SOLUTION_EC2_CONTAINER}"

AWS_EC2_CONTAINER_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Solution,Values=${SOLUTION_EC2_CONTAINER}" --query "Reservations[].Instances[].PublicIpAddress" --output text)
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_CONTAINER_PUBLIC_IP}" 'curl -Ls https://github.com/ruzickap.keys >> ~/.ssh/authorized_keys'

## Install Docker and Docker Compose
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_CONTAINER_PUBLIC_IP}" << \EOF
set -euxo pipefail
sudo dnf install -qy docker
sudo usermod -aG docker ec2-user
sudo systemctl enable --now docker
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -sL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chown root:root /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
EOF

## Install Wordpress in the container with vulnerable WordPress Backup Migration Plugin and Loginizer plugins
# shellcheck disable=SC2087
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_CONTAINER_PUBLIC_IP}" << EOF2
set -euxo pipefail
mkdir -p docker-entrypoint-init.d
cat > docker-entrypoint-init.d/wordpress_plugin_install.sh << EOF
wp plugin install backup-backup --version=1.3.7 --activate
wp plugin install loginizer --version=1.6.3 --activate
EOF
chmod a+x docker-entrypoint-init.d/wordpress_plugin_install.sh

cat > docker-compose.yml << EOF
services:
  mariadb:
    # renovate: datasource=docker depName=bitnami/mariadb
    image: docker.io/bitnami/mariadb:11.2
    volumes:
      - 'mariadb_data:/bitnami/mariadb'
    environment:
      - ALLOW_EMPTY_PASSWORD=no
      - MARIADB_USER=${MARIADB_WORDPRESS_DATABASE_USER}
      - MARIADB_DATABASE=${MARIADB_WORDPRESS_DATABASE}
      - MARIADB_PASSWORD=${MARIADB_WORDPRESS_DATABASE_PASSWORD}
      - MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
  wordpress:
    image: docker.io/bitnami/wordpress:6
    ports:
      - '80:8080'
      - '443:8443'
    volumes:
      - 'wordpress_data:/bitnami/wordpress'
      - '\${PWD}/docker-entrypoint-init.d:/docker-entrypoint-init.d'
    depends_on:
      - mariadb
    environment:
      - ALLOW_EMPTY_PASSWORD=no
      - WORDPRESS_USERNAME=${WORDPRESS_USERNAME}
      - WORDPRESS_PASSWORD=${WORDPRESS_PASSWORD}
      - WORDPRESS_DATABASE_HOST=mariadb
      - WORDPRESS_DATABASE_PORT_NUMBER=3306
      - WORDPRESS_DATABASE_USER=${MARIADB_WORDPRESS_DATABASE_USER}
      - WORDPRESS_DATABASE_PASSWORD=${MARIADB_WORDPRESS_DATABASE_PASSWORD}
      - WORDPRESS_DATABASE_NAME=${MARIADB_WORDPRESS_DATABASE}
volumes:
  mariadb_data:
    driver: local
  wordpress_data:
    driver: local
EOF

docker compose up --quiet-pull -d
EOF2

## Build new Ubuntu Linux 22.04 EC2 instance
export SOLUTION_EC2="Amazon-EC2"

aws cloudformation deploy \
  --parameter-overrides "EnvironmentName=${SOLUTION_EC2}" \
  --stack-name "${SOLUTION_EC2}-VPC" --template-file "${TMP_DIR}/vpc_cloudformation_template.yml" \
  --tags "Owner=${USER} Environment=dev Solution=${SOLUTION_EC2}"

# shellcheck disable=SC2016
AWS_CLOUDFORMATION_DETAILS=$(aws cloudformation describe-stacks --stack-name "${SOLUTION_EC2}-VPC" --query 'Stacks[0].Outputs[? OutputKey==`PublicSubnet1` || OutputKey==`VPC`].{OutputKey:OutputKey,OutputValue:OutputValue}')
AWS_VPC_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"VPC\") .OutputValue")
AWS_SUBNET_ID=$(echo "${AWS_CLOUDFORMATION_DETAILS}" | jq -r ".[] | select(.OutputKey==\"PublicSubnet1\") .OutputValue")

eval aws cloudformation deploy --capabilities CAPABILITY_IAM \
  --parameter-overrides "instanceType=t4g.medium ec2Name=${SOLUTION_EC2} ec2KeyPair=${AWS_EC2_KEY_PAIR_NAME} vpcID=${AWS_VPC_ID} subnetID=${AWS_SUBNET_ID}" \
  --stack-name "${SOLUTION_EC2}" --template-file "${TMP_DIR}/AmazonLinux-2023-LAMP-server.yaml" \
  --tags "Owner=${USER} Environment=dev Solution=${SOLUTION_EC2}"

AWS_EC2_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Solution,Values=${SOLUTION_EC2}" --query "Reservations[].Instances[].PublicIpAddress" --output text)
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_PUBLIC_IP}" 'curl -Ls https://github.com/ruzickap.keys >> ~/.ssh/authorized_keys'

## Configure MariaDB and add "wordpress" user with password
# shellcheck disable=SC2087
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_PUBLIC_IP}" << EOF2
sudo mysql --user=root << \EOF
UPDATE mysql.global_priv SET priv=json_set(priv, '$.plugin', 'mysql_native_password', '$.authentication_string', PASSWORD('${MARIADB_ROOT_PASSWORD}')) WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER '${MARIADB_WORDPRESS_DATABASE_USER}'@'localhost' IDENTIFIED BY '${MARIADB_WORDPRESS_DATABASE_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MARIADB_WORDPRESS_DATABASE}.* TO '${MARIADB_WORDPRESS_DATABASE_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
EOF2

## Install Wordpress with vulnerable WordPress Backup Migration Plugin and Loginizer plugins
# shellcheck disable=SC2087
ssh -i "${TMP_DIR}/${AWS_EC2_KEY_PAIR_NAME}.pem" -o StrictHostKeyChecking=no "ec2-user@${AWS_EC2_PUBLIC_IP}" << EOF
set -euxo pipefail
wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
cd /var/www/html/
wp core download --version=6.5.3
wp config create --dbname="${MARIADB_WORDPRESS_DATABASE}" --dbuser="${MARIADB_WORDPRESS_DATABASE_USER}" --dbpass="${MARIADB_WORDPRESS_DATABASE_PASSWORD}"
wp db create
wp core install --url="${AWS_EC2_PUBLIC_IP}" --title="My Blog" --admin_user="${WORDPRESS_USERNAME}" --admin_password="${WORDPRESS_PASSWORD}" --skip-email --admin_email="info@example.com"
wp plugin install backup-backup --version=1.3.7 --activate
wp plugin install loginizer --version=1.6.3 --activate
EOF

## Prepare the "wordpress_plugin_install.sh" startup script, which will be used to install the WordPress Backup Migration Plugin and Loginizer plugins during the container startup
cd "${TMP_DIR}" || exit
cat > wordpress_plugin_install.sh << EOF
wp plugin install backup-backup --version=1.3.7 --activate
wp plugin install loginizer --version=1.6.3 --activate
EOF
chmod a+x wordpress_plugin_install.sh

## Create the "startup.sh" script, which will be used to populate the environment variables for bitnami/wordpress based on the WORDPRESSCLUSTER_SECRET produced by copilot
cat > startup.sh << \EOF
#!/bin/sh

# Exit if the secret wasn't populated by the ECS agent
if [ -z "${WORDPRESSCLUSTER_SECRET}" ]; then
  echo "Environment variable "WORDPRESSCLUSTER_SECRET" with secrets is not populated in environment !!!"
  echo 'It should look like: {"host":"mariadb","port":3306,"dbname":"wordpress","username":"wordpress","password":"password"}'
  exit 1
fi

export WORDPRESS_DATABASE_HOST=$(echo "${WORDPRESSCLUSTER_SECRET}" | jq -r '.host')
export WORDPRESS_DATABASE_PORT_NUMBER=$(echo "${WORDPRESSCLUSTER_SECRET}" | jq -r '.port')
export WORDPRESS_DATABASE_NAME=$(echo "${WORDPRESSCLUSTER_SECRET}" | jq -r '.dbname')
export WORDPRESS_DATABASE_USER=$(echo "${WORDPRESSCLUSTER_SECRET}" | jq -r '.username')
export WORDPRESS_DATABASE_PASSWORD=$(echo "${WORDPRESSCLUSTER_SECRET}" | jq -r '.password')

/opt/bitnami/scripts/wordpress/entrypoint.sh /opt/bitnami/scripts/apache/run.sh
EOF
chmod a+x startup.sh

## Prepare the "Dockerfile" which installs jq into the Bitnami Wordpress image and uses the "startup.sh" script to start the container
cat > Dockerfile << \EOF
FROM docker.io/bitnami/minideb:bookworm as installer
RUN set -eux && \
    apt-get update -q && \
    apt-get install curl -y -q && \
    curl -sLo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 && \
    chmod a+x /usr/local/bin/jq

FROM docker.io/bitnami/wordpress:latest as app
COPY --from=installer /usr/local/bin/jq /usr/bin/jq
COPY startup.sh /opt/copilot/scripts/startup.sh
COPY wordpress_plugin_install.sh /docker-entrypoint-init.d/

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/opt/copilot/scripts/startup.sh"]
EXPOSE 8080
EOF

## Create ECS cluster with Wordpress
copilot app init wordpress --resource-tags "Owner=${USER},Environment=dev,Solution=Amazon-ECS"
copilot env init --name dev --default-config
copilot env deploy --name dev
copilot secret init --name WORDPRESS_USERNAME --values "dev=${WORDPRESS_USERNAME}" --overwrite
copilot secret init --name WORDPRESS_PASSWORD --values "dev=${WORDPRESS_PASSWORD}" --overwrite
copilot svc init --dockerfile Dockerfile --name wordpress --port 8080 --svc-type 'Load Balanced Web Service'
cat >> copilot/wordpress/manifest.yml << EOF

secrets:
  WORDPRESS_USERNAME: /copilot/wordpress/dev/secrets/WORDPRESS_USERNAME
  WORDPRESS_PASSWORD: /copilot/wordpress/dev/secrets/WORDPRESS_PASSWORD
EOF
copilot storage init --name wordpress-cluster --lifecycle=workload --storage-type Aurora --engine MySQL --initial-db "${MARIADB_WORDPRESS_DATABASE}"
copilot svc deploy --resource-tags "Owner=${USER},Environment=dev,Solution=Amazon-ECS"
```

## Cleanup

Delete the Amazon EKS cluster, Kali Linux EC2 instance, and EC2 Key Pair:

```sh
export AWS_DEFAULT_REGION="eu-central-1"
export AWS_EC2_KEY_PAIR_NAME="wordpress-test"
export SOLUTION_KALI="KaliLinux-NICE-DCV"
export SOLUTION_EC2_CONTAINER="Amazon-EC2-Container"
export SOLUTION_EC2="Amazon-EC2"
export CLUSTER_NAME="Amazon-EKS"

eksctl delete cluster --name "${CLUSTER_NAME}"
aws cloudformation delete-stack --stack-name "${SOLUTION_KALI}"
aws cloudformation delete-stack --stack-name "${SOLUTION_EC2_CONTAINER}"
aws cloudformation delete-stack --stack-name "${SOLUTION_EC2}"
aws cloudformation delete-stack --stack-name "${SOLUTION_KALI}-VPC"
aws cloudformation delete-stack --stack-name "${SOLUTION_EC2_CONTAINER}-VPC"
aws cloudformation delete-stack --stack-name "${SOLUTION_EC2}-VPC"
aws ec2 delete-key-pair --key-name "${AWS_EC2_KEY_PAIR_NAME}"
copilot app delete --name wordpress --yes
aws ssm delete-parameter --name /copilot/wordpress/dev/secrets/WORDPRESS_USERNAME
aws ssm delete-parameter --name /copilot/wordpress/dev/secrets/WORDPRESS_PASSWORD
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/wordpress-dev-wordpress --query 'logGroups[*].logGroupName' | jq -r '.[]' | xargs -I {} aws logs delete-log-group --log-group-name {}
aws rds describe-db-cluster-snapshots --query 'DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, `wordpress-dev-wordpress`) == `true`].DBClusterSnapshotIdentifier' | jq -r '.[]' | xargs -I {} aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier {}
```

Enjoy ... 😉
