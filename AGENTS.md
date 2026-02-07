# AI Agent Guidelines

Personal blog built with Jekyll and Chirpy theme. This guide helps AI agents
work effectively with blog posts, infrastructure testing, and code quality.

## Quick Reference

```bash
# Build Jekyll site
bundle install && bundle exec jekyll build --destination public

# Test a single blog post (creates AWS resources)
mise run create:2026-01-13-amazon-eks-grafana-stack

# Clean up test resources
mise run delete:2026-01-13-amazon-eks-grafana-stack

# Get EKS cluster access (run once per session)
eval "$(mise run a)"

# Run all linters locally
mega-linter-runner --remove-container --env VALIDATE_ALL_CODEBASE=true

# Run pre-commit hooks
pre-commit run --all-files
```

## Build & Development

### Local Jekyll Build

```bash
# Install dependencies
bundle install

# Build site
bundle exec jekyll build --destination public

# Validate HTML
bundle exec htmlproofer public --disable-external
```

### Docker Build

```bash
docker run --rm -it --volume="${PWD}:/mnt" --workdir /mnt ubuntu bash -c '
  apt update && apt install build-essential git ruby-bundler ruby-dev -y &&
  git config --global --add safe.directory /mnt &&
  bundle install && jekyll build --destination public
'
```

### Environment Requirements

- Ruby 3.4.8
- Jekyll theme: `jekyll-theme-chirpy ~> 7.4`
- Dependencies: See `Gemfile`

## Testing

### Single Post Testing

Blog posts contain executable code blocks. Use `mise` to test them:

```bash
# Test individual post
mise run create:YYYY-MM-DD-post-title

# Test with dependencies (runs prerequisites first)
mise run create:2023-04-01-post|2022-11-27-prerequisite

# Clean up resources
mise run delete:YYYY-MM-DD-post-title
```

### Code Block Conventions (CRITICAL)

Code block language identifiers determine test execution:

- **`bash`** - Commands executed during resource **creation** (GitHub Actions)
- **`sh`** - Commands executed during resource **deletion/cleanup**
- **`shell`** - Display-only commands, **NOT executed** in tests

Example:

````markdown
```bash
# This RUNS during create tests
export CLUSTER_NAME="test-cluster"
```

```shell
# This is SHOWN but NOT executed
kubectl get pods
```

```sh
# This RUNS during delete tests
eksctl delete cluster --name="${CLUSTER_NAME}"
```
````

### EKS Access

When testing EKS-related posts, get cluster access once per session:

```bash
eval "$(mise run a)"
```

This assumes AWS IAM role and configures `KUBECONFIG`.

## Linting & Quality

### Pre-commit Hooks

All commits must pass (enforced with `fail_fast: true`):

- **Markdown**: `rumdl` (Rust-based, MD041 disabled for frontmatter)
- **Shell**: `shellcheck` (SC2317 excluded), `shfmt` (2-space indent)
- **YAML**: `yamllint` (relaxed mode, no line-length limit)
- **Security**: `gitleaks`, `wizcli-scan-dir-secrets`
- **Formatting**: `prettier` (excludes `.md`, `_config.yml`)
- **Commits**: `commitizen`, `gitlint` (conventional commits, 80 char limit)

### MegaLinter

Runs comprehensive validation:

```bash
mega-linter-runner --remove-container \
  --container-name="mega-linter" \
  --env VALIDATE_ALL_CODEBASE=true
```

**Enabled**: shellcheck, shfmt, rumdl, yamllint, jsonlint, prettier, lychee
**Disabled**: markdownlint (using rumdl), cspell, jscpd, terrascan

**Excluded files**: `CHANGELOG.md`

## Code Style Guidelines

### Blog Post Structure

**Filename**: `_posts/YYYY/YYYY-MM-DD-kebab-case-title.md`

**Required frontmatter**:

```yaml
---
title: Post Title Here
author: Petr Ruzicka
date: YYYY-MM-DD
description: SEO-friendly description
categories: [Category1, Category2]
tags: [lowercase-tag, another-tag]
image: https://example.com/image.png  # Optional
---
```

**Categories**: Title Case, broad domains (Kubernetes, Cloud, Security, Linux)
**Tags**: lowercase, hyphen-separated (amazon-eks, cert-manager, bash)

### Markdown Formatting

- **Line length**: 80 characters max (prose wrapped with `--prose-wrap always`)
- **Headings**: Proper hierarchy, no skipped levels, no trailing periods
- **Code fences**: Always include language identifier
- **Links**: Line breaks allowed in long URLs for readability

### Shell Scripts

**Header**:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Formatting** (enforced by `shfmt`):

- 2-space indentation (`--indent 2`)
- Space before redirects (`--space-redirects`)
- Case indentation enabled (`--case-indent`)

**Variable conventions**:

```bash
# Environment variables: UPPER_CASE
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Required variables
: "${AWS_ACCESS_KEY_ID:?Error: AWS_ACCESS_KEY_ID not set!}"

# Parameter expansion for defaults
TMP_DIR="${TMP_DIR:-${PWD}}"
```

**Error handling**:

```bash
# Exit on error (set -e)
# Fail on undefined variables (set -u)
# Fail on pipe errors (set -o pipefail)

# Conditional execution
[[ "${CONDITION}" == "true" ]] && command

# Directory checks
[[ ! -d "${TMP_DIR}" ]] && mkdir -v "${TMP_DIR}"
```

## Version Control

### Commit Messages

Format: `<type>: <description>` (max 80 chars, imperative mood, lowercase)

**Types**: feat, fix, docs, chore, refactor, test, style, perf, ci, build

**Example**:

```markdown
feat: add eks auto mode testing guide

- Implement automated cluster creation
- Add cleanup procedures
- Include cost optimization tips
```

### Branching

Follow [Conventional Branch](https://conventional-branch.github.io/) spec:

- `feat/123-add-feature-name`
- `fix/456-resolve-bug`
- Use kebab-case, include issue number when applicable

### Pull Requests

- Create as **draft** initially
- Title: conventional commit format
- Link issues: `Fixes #123`, `Closes #456`
