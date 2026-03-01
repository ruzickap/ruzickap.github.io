# AI Agent Guidelines

## Overview

Jekyll blog (Chirpy theme) deployed to GitHub Pages / Cloudflare Pages.
Primary content: Markdown blog posts with executable shell code blocks
tested as E2E integration tests against AWS EKS clusters.

## Build / Lint / Test Commands

```bash
# Install Ruby dependencies
bundle install

# Build the Jekyll site
bundle exec jekyll build --destination public

# Test built site (HTML validation, internal links)
bundle exec htmlproofer public \
  --disable-external \
  --ignore-urls "/127.0.0.1/,/0.0.0.0/,/localhost/,/.local/"

# Run MegaLinter (shellcheck, shfmt, rumdl, lychee, checkov, etc.)
mega-linter-runner --remove-container \
  --container-name="mega-linter" \
  --env VALIDATE_ALL_CODEBASE=true

# Run a single post E2E test (requires AWS credentials + mise)
mise run "create:<post-date-slug>"
mise run "delete:<post-date-slug>"

# Run all post E2E tests
mise run "create-delete:posts:all"

# Individual linters
actionlint                                              # GH Actions
rumdl <file.md>                                         # Markdown
shellcheck <script.sh>                                  # Shell lint
shfmt --case-indent --indent 2 --space-redirects <file> # Shell fmt
lychee --root-dir . --verbose <file.md>                 # Links
```

## Repository Structure

- `_posts/YYYY/` -- Blog posts (Markdown with YAML front matter)
- `_tabs/` -- Navigation pages (about, archives, categories, tags)
- `_data/` -- Site data (authors, contact, share config)
- `_plugins/` -- Jekyll Ruby plugins
- `assets/img/` -- Images (favicons, per-post `.avif` files)
- `scripts/` -- Shell scripts for testing and project generation
- `mise.toml` -- Tool versions and E2E test task definitions
- `.github/workflows/` -- CI/CD workflow files

## Blog Post Conventions

Every post requires YAML front matter with: `title`, `author`, `date`,
`description`, `categories` (array), `tags` (array), `image`.
File naming: `_posts/YYYY/YYYY-MM-DD-slug-title.md`

### Code Block Language Tags (Critical)

Code blocks in posts drive the E2E test system:

- `` ```bash `` -- Executed during **create** (provisioning)
- `` ```shell `` -- **Display only**, never executed
- `` ```sh `` -- Executed during **delete** (cleanup/teardown)

## Shell Scripts

- **Shebang**: `#!/usr/bin/env bash`
- **Strict mode**: `set -euo pipefail` (or `set -euxo pipefail`)
- **Variables**: UPPERCASE with braces: `${MY_VARIABLE}`
- **Required var checks**: `: "${VAR:?Error: VAR is not set!}"`
- **Defaults**: `${VAR:-default_value}`
- **Linting**: Must pass `shellcheck` (SC2317 excluded)
- **Formatting**: `shfmt --case-indent --indent 2 --space-redirects`
- **Indentation**: 2 spaces, no tabs

## Markdown Files

- Must pass `rumdl` checks (MD036 and MD041 disabled globally)
- Wrap lines at 72 characters
- Use proper heading hierarchy (no skipped levels)
- Include language identifiers in all code fences
- Shell code blocks inside Markdown are extracted and validated
  by `shellcheck` and `shfmt` during CI
- Use Chirpy admonitions: `{: .prompt-info }`, `{: .prompt-tip }`,
  `{: .prompt-warning }`, `{: .prompt-danger }`

## JSON Files

- Must pass `jsonlint --comments` validation
- `.devcontainer/devcontainer.json` is excluded from linting

## Terraform Files

- Must pass `tflint`, `checkov`, `kics`, and `trivy` scans
- Only HIGH/CRITICAL severity issues fail the build

## GitHub Actions

- **Pin actions** to full SHA commits, not tags
- **Permissions**: `permissions: read-all` default; grant only
  what is needed per job
- **Validate** every workflow change with `actionlint`
- **Runner**: Prefer `ubuntu-24.04-arm` for cost efficiency

## Security and Link Scanning

CI runs: Checkov (`CKV_GHA_7` skipped), DevSkim (DS162092/DS137138
ignored), KICS (HIGH only), Trivy (HIGH/CRITICAL, ignores unfixed),
Gitleaks, Secretlint. Link checking via `lychee` (config in
`lychee.toml`); accepts 200/429; caching enabled; excludes template
variables, shell variables, private IPs, `CHANGELOG.md`.

## Version Control

### Commit Messages

- **Format**: `<type>: <description>` (conventional commits)
- **Types**: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`,
  `style`, `perf`, `ci`, `build`, `revert`
- **Subject**: imperative mood, lowercase, no period, max 72 chars
- **Body**: wrap at 72 chars, explain what and why
- **References**: use `Fixes`, `Closes`, or `Resolves` keywords

### Branching

[Conventional Branch](https://conventional-branch.github.io/) format:
`feature/`, `feat/`, `bugfix/`, `fix/`, `hotfix/`, `release/`,
`chore/`. Lowercase, hyphens only, no consecutive/leading/trailing
hyphens.

### Pull Requests

- Always create as **draft** initially
- Title must follow conventional commit format
- Include clear description and link related issues

## Quality Checklist

- [ ] Two spaces for indentation (no tabs)
- [ ] Shell code blocks pass `shellcheck` and `shfmt`
- [ ] Markdown passes `rumdl`
- [ ] Links are valid (`lychee`)
- [ ] Actions pinned to SHA; validated with `actionlint`
- [ ] Atomic, focused commits with conventional messages
