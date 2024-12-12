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
considered a good practice, not just in Terraform/OpenTofu code.

I want to explore how to sort Terraform/OpenTofu resources, outputs, lists, and
more.

I'll explain how to use [keep-sorted](https://github.com/google/keep-sorted)
from Google to maintain well-organized, properly sorted Terraform/OpenTofu code.

Rather than diving into a lengthy description of [keep-sorted](https://github.com/google/keep-sorted)
features, let's explore some examples.

Install `keep-sorted`:

```bash
brew install keep-sorted
```

Let's have some example `data.tf` file:

```bash
tee data.tf << EOF
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

Let's check the output after using [keep-sorted](https://github.com/google/keep-sorted):

```bash
keep-sorted data.tf && cat data.tf
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

As you can see above:

* The data resources were sorted
* The comments were preserved with the data sources

One more example - `main.tf`:

```bash
tee main.tf << EOF
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

...and the output is:

```bash
keep-sorted main.tf && cat main.tf
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

`keep-sorted` has few more features documented in the [README.md](https://github.com/google/keep-sorted/blob/main/README.md#options)
and as I mentioned before - it's not only for Terraform / OpenTofu.

Enjoy ... 😉
