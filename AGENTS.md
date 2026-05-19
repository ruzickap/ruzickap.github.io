# AI Agent Guidelines

Jekyll blog (Chirpy theme) deployed to GitHub Pages / Cloudflare Pages.
Posts double as **executable E2E tests** against AWS EKS: shell code blocks
inside `_posts/**/*.md` are extracted by `mq` and run by `mise` tasks.

See `README.md` (long; high-level overview) and `NOTES` (scratch file, not
authoritative) for context. `_config.yml` is the Jekyll config.

## Critical conventions

### Code block language tags drive E2E execution

Inside posts under `_posts/`, fence language is **not cosmetic**:

- ` ```bash` -- extracted and executed by `create:*` tasks (provisioning)
- ` ```sh`    -- extracted and executed by `delete:*` tasks (teardown)
- ` ```shell` -- **display only**, never executed

Mechanism: `scripts/mise-create-delete-posts.sh` runs
`mq 'select(.code.lang == "bash" | "sh") | to_text()'` over the post files
and pipes the result into a generated script under `tmp/`.

### Mise task names use `|` to chain post dependencies

A task like
`create:2025-05-27-mcp-servers-k8s|2025-02-01-eks-auto-cert-manager-velero|2024-12-14-secure-cheap-amazon-eks-auto`
is **one task name** -- the `|`-separated slugs are prerequisite posts
whose `bash`/`sh` blocks are concatenated in order. Always quote the whole
task name and copy it verbatim from `mise tasks` or `mise.toml`. Do not
guess; many posts have no standalone task.

```bash
mise tasks                  # list real task names
mise run "<exact-task-name>"
```

### EKS session bootstrap

```bash
eval "$(mise run a)"   # alias for `eks-access`; run ONCE per shell session
```

This sources `bash` blocks from the EKS post defined in
`mise.toml` (`EKS_POST_FILE`, currently the 2026 Grafana post), then sets
`KUBECONFIG=/tmp/kubeconfig-<CLUSTER_NAME>-$$.conf` and runs
`aws eks update-kubeconfig`. Requires `CLUSTER_NAME` to already be in the
environment -- it is loaded from `.env.yaml` via the `fnox-env` mise plugin
(see `mise.toml` `[env]` section and `fnox.toml`). Without `.env.yaml` /
AWS creds the helper fails.

### tmp/ artifact directory

`scripts/mise-create-delete-posts.sh` writes generated scripts and
kubeconfigs under `./tmp/`. After a `delete:*` run, if `tmp/` is not empty
the script `exit 2`s -- treat leftover files as a real cleanup failure to
investigate, not as noise.

## Build, lint, test

```bash
bundle install
bundle exec jekyll build --destination public
bundle exec htmlproofer public \
  --disable-external \
  --ignore-urls "/127.0.0.1/,/0.0.0.0/,/localhost/,/.local/"

# Full lint suite (Docker) -- mirrors CI
mega-linter-runner --remove-container \
  --container-name="mega-linter" \
  --env VALIDATE_ALL_CODEBASE=true

# Individual linters used by CI (see .mega-linter.yml)
rumdl file.md                                           # Markdown
shellcheck script.sh                                    # excludes SC2317
shfmt --case-indent --indent 2 --space-redirects file
lychee --root-dir . --verbose file.md                   # config: lychee.toml
actionlint                                              # GH Actions
jsonlint --comments file.json
```

`CHANGELOG.md` is auto-generated and excluded from all linters
(`FILTER_REGEX_EXCLUDE` in `.mega-linter.yml`).
`.devcontainer/devcontainer.json` is excluded from `jsonlint`.

### Run all post E2E tests

```bash
mise run create-delete:posts:all
```

Walks every `create:*` / `delete:*` task in `mise.toml` (parsed with `sed`).
Expensive -- spins up real AWS infra.

## Repo layout (only the non-obvious bits)

- `_posts/YYYY/` -- blog posts; filename `YYYY-MM-DD-slug.md`
- `_plugins/` -- Jekyll Ruby plugins (custom)
- `_data/` -- site data (authors, contact, share config)
- `scripts/mise-create-delete-posts.sh` -- the E2E test runner
- `scripts/generate-projects.sh` -- regenerates `_tabs/projects.md` from GitHub
- `mise.toml` -- tool pins + task definitions (source of truth for E2E)
- `fnox.toml` + `.env.yaml` -- secret/env loading via `fnox` mise plugin
- `.pre-commit-config.yaml` -- **symlink** to `../my-git-projects/...`
  (shared across the author's repos; editing it touches another repo)

## Post front matter

Required: `title`, `author`, `date`, `description`, `categories` (array),
`tags` (array), `image`. Use Chirpy admonitions:
`{: .prompt-info }`, `{: .prompt-tip }`, `{: .prompt-warning }`,
`{: .prompt-danger }`.

## Shell scripts

- `#!/usr/bin/env bash`, `set -euo pipefail` (or `-euxo`)
- Variables UPPERCASE with braces: `${MY_VAR}`
- Required: `: "${VAR:?Error: VAR is not set!}"`
- Format: `shfmt --case-indent --indent 2 --space-redirects`; lint:
  `shellcheck` (SC2317 excluded)
- 2-space indent, no tabs

## Markdown

- Must pass `rumdl` (config `.rumdl.toml`; MD036, MD041 disabled globally)
- Wrap at 80 chars; always tag code fences with a language
- Shell blocks inside `.md` are extracted by CI and re-linted with
  `shellcheck` + `shfmt`
- See "Code block language tags" above before changing fence languages
  inside `_posts/`

## GitHub Actions

- Pin actions to full SHA, never tags
- Default `permissions: read-all`; widen only per-job as needed
- Prefer runner `ubuntu-24.04-arm`
- Validate every workflow change with `actionlint`
- Zizmor and lychee are allowed access to `GITHUB_TOKEN`
  (`*_UNSECURED_ENV_VARIABLES` in `.mega-linter.yml`)

## Security scanners (CI)

Checkov (`--quiet`; `CKV_GHA_7` skipped), DevSkim (DS162092, DS137138
ignored; CHANGELOG excluded), Trivy (HIGH/CRITICAL only, `--ignore-unfixed`),
Gitleaks, Secretlint. Disabled in `.mega-linter.yml`:
`COPYPASTE_JSCPD`, `MARKDOWN_MARKDOWNLINT` (rumdl is used instead),
`REPOSITORY_KINGFISHER`, `REPOSITORY_OSV_SCANNER` (no lockfiles),
`SPELL_CSPELL`, `TERRAFORM_TERRASCAN`.

## Terraform (when present)

Must pass `tflint`, `checkov`, `trivy`; only HIGH/CRITICAL fail the build.

## Version control

- Conventional commits: `<type>: <description>`; subject lowercase, no
  period, <=72 chars; body wrapped at 72; use `Fixes` / `Closes` / `Resolves`
- Branches per [Conventional Branch](https://conventional-branch.github.io/):
  `feature/`, `feat/`, `bugfix/`, `fix/`, `hotfix/`, `release/`, `chore/`
- PRs: **open as draft**, title in conventional-commit form
