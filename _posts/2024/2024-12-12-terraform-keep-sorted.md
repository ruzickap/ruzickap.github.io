---
title: Using keep-sorted to organize Terraform objects
author: Petr Ruzicka
date: 2024-12-12
description: Use keep-sorted to organize your Terraform objects in sorted order within your code
categories: [Terraform, OpenTofu, keep-sorted, sort, iac, code]
tags:
  [
    Terraform,
    OpenTofu,
    keep-sorted,
    sort,
    iac,
    code,
  ]
image: https://opengraph.githubassets.com/main/google/keep-sorted
---

Alphabetically sorting variables, sets, arrays, and other strings has long been
considered good practice, not just in Terraform/OpenTofu code.

I want to explore how to sort Terraform/OpenTofu resources, outputs, lists, and
more using a dedicated tool.

I will explain how to use [keep-sorted](https://github.com/google/keep-sorted)
from Google to maintain well-organized and properly sorted Terraform/OpenTofu
code.

Rather than diving into a lengthy description of [keep-sorted](https://github.com/google/keep-sorted)'s
features, let's explore some examples.

Install `keep-sorted` by following these steps:

```bash
TMP_DIR="${TMP_DIR:-${PWD}}"
mkdir -pv "${TMP_DIR}"
wget -q "https://github.com/google/keep-sorted/releases/download/v0.6.1/keep-sorted_$(uname | tr '[:upper:]' '[:lower:]')" -O "${TMP_DIR}/keep-sorted"
chmod +x "${TMP_DIR}/keep-sorted"
```

Let's consider an example `data.tf` file:

```bash
tee "${TMP_DIR}/data.tf" << EOF
# keep-sorted start block=yes newline_separated=yes
# [APIGateway-007] REST API Gateway 7
data "wiz_cloud_configuration_rules" "apigateway-007" {
  search = "APIGateway-007"
}

# [APIGateway-001] REST API Gateway 1
data "wiz_cloud_configuration_rules" "apigateway-001" {
  search = "APIGateway-001"
}

# [APIGateway-009] REST API Gateway 9
data "wiz_cloud_configuration_rules" "apigateway-009" {
  search = "APIGateway-009"
}

# [APIGateway-002] REST API Gateway 2
data "wiz_cloud_configuration_rules" "apigateway-002" {
  search = "APIGateway-002"
}
# keep-sorted end
EOF
```

Let's check the output after applying [keep-sorted](https://github.com/google/keep-sorted):

```bash
"${TMP_DIR}/keep-sorted" "${TMP_DIR}/data.tf" && cat "${TMP_DIR}/data.tf"
```

```hcl
# keep-sorted start block=yes newline_separated=yes
# [APIGateway-001] REST API Gateway 1
data "wiz_cloud_configuration_rules" "apigateway-001" {
  search = "APIGateway-001"
}

# [APIGateway-002] REST API Gateway 2
data "wiz_cloud_configuration_rules" "apigateway-002" {
  search = "APIGateway-002"
}

# [APIGateway-007] REST API Gateway 7
data "wiz_cloud_configuration_rules" "apigateway-007" {
  search = "APIGateway-007"
}

# [APIGateway-009] REST API Gateway 9
data "wiz_cloud_configuration_rules" "apigateway-009" {
  search = "APIGateway-009"
}
# keep-sorted end
```

Diff:

![keep-sorted data.tf diff](/assets/img/posts/2024/2024-12-12-terraform-keep-sorted/data-diff.avif)
_keep-sorted data.tf diff_

As you can see in the output above:

* The data resources were sorted alphabetically by their names
* The comments associated with each data source were preserved and moved along
  with their respective blocks

Here's one more example, this time with a `main.tf` file:

```bash
tee "${TMP_DIR}/main.tf" << EOF
locals {
  # keep-sorted start block=yes numeric=yes
  wiz_cloud_configuration_rules_20 = [
    # keep-sorted start
    data.wiz_cloud_configuration_rules.apigateway-02.id,
    data.wiz_cloud_configuration_rules.apigateway-01.id,
    data.wiz_cloud_configuration_rules.apigateway-09.id,
    data.wiz_cloud_configuration_rules.apigateway-07.id,
    # keep-sorted end
  ]
  wiz_cloud_configuration_rules_5 = [
    # keep-sorted start
    data.wiz_cloud_configuration_rules.apigateway-10.id,
    data.wiz_cloud_configuration_rules.apigateway-2.id,
    data.wiz_cloud_configuration_rules.apigateway-27.id,
    data.wiz_cloud_configuration_rules.apigateway-1.id,
    # keep-sorted end
  ]
  # keep-sorted end
}
EOF
```

...and the resulting output is:

```bash
"${TMP_DIR}/keep-sorted" "${TMP_DIR}/main.tf" && cat "${TMP_DIR}/main.tf"
```

```hcl
locals {
  # keep-sorted start block=yes numeric=yes
  wiz_cloud_configuration_rules_5 = [
    # keep-sorted start
    data.wiz_cloud_configuration_rules.apigateway-1.id,
    data.wiz_cloud_configuration_rules.apigateway-10.id,
    data.wiz_cloud_configuration_rules.apigateway-2.id,
    data.wiz_cloud_configuration_rules.apigateway-27.id,
    # keep-sorted end
  ]
  wiz_cloud_configuration_rules_20 = [
    # keep-sorted start
    data.wiz_cloud_configuration_rules.apigateway-01.id,
    data.wiz_cloud_configuration_rules.apigateway-02.id,
    data.wiz_cloud_configuration_rules.apigateway-07.id,
    data.wiz_cloud_configuration_rules.apigateway-09.id,
    # keep-sorted end
  ]
  # keep-sorted end
}
```

Diff:

![keep-sorted main.tf diff](/assets/img/posts/2024/2024-12-12-terraform-keep-sorted/main-diff.avif)
_keep-sorted main.tf diff_

`keep-sorted` has several other features documented in its [README.md](https://github.com/google/keep-sorted/blob/main/README.md#options).
As I mentioned before, it's not limited to use with only Terraform/OpenTofu.

## Cleanup

Delete all created files using the following command:

```sh
rm -v "${TMP_DIR}"/{data,main}.tf "${TMP_DIR}/keep-sorted"
```

Enjoy ... 😉
