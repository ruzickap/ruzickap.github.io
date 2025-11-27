# ruzickap.github.io

[![GitHub Actions status - Lint Code Base](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml/badge.svg)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml)
[![Build and Deploy](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml/badge.svg?branch=main)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ruzickap/ruzickap.github.io/badge)](https://scorecard.dev/viewer/?uri=github.com/ruzickap/ruzickap.github.io)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/9800/badge)](https://www.bestpractices.dev/projects/9800)

## Overview

Personal blog and website built with Jekyll using the Chirpy theme.

[**ruzickap.github.io**](https://ruzickap.github.io/)

- Main Page: <https://ruzickap.github.io>
- Dev Page: <https://ruzickap-github-io.pages.dev>

## Theme Source

Chirpy:

- [GitHub](https://github.com/cotes2020/jekyll-theme-chirpy)
- [Example and tips/best practices](https://chirpy.cotes.page/)

## Building / Testing Locally

On Ubuntu / Intel-based Mac:

```bash
bundle install
bundle exec jekyll s
```

Using Docker:

```bash
# Build the site
docker run --rm -it \
  --volume="${PWD}:/srv/jekyll" \
  -e JEKYLL_UID="${UID}" \
  -e JEKYLL_GID="${GID}" \
  jekyll/jekyll -- bash -c 'chown -R jekyll /usr/gem/ && jekyll build --destination "public"'

# Serve the site locally
docker run --rm -it \
  --volume="${PWD}:/srv/jekyll" \
  -e JEKYLL_UID="${UID}" \
  -e JEKYLL_GID="${GID}" \
  --publish 4000:4000 \
  jekyll/jekyll -- bash -c 'chown -R jekyll /usr/gem/ && jekyll serve'
```

Megalinter:

```bash
mega-linter-runner --remove-container \
  --container-name="mega-linter" \
  --debug \
  --env VALIDATE_ALL_CODEBASE=true
```

## Tests

```bash
docker run --rm -it -v "$PWD:/mnt" -v "/var/run/docker.sock:/var/run/docker.sock" \
  --env AWS_ACCESS_KEY_ID --env AWS_SECRET_ACCESS_KEY --env AWS_ROLE_TO_ASSUME \
  --env GOOGLE_CLIENT_ID --env GOOGLE_CLIENT_SECRET --env FORCE_COLOR=1 --env USER \
  --workdir /mnt \
  ubuntu bash -c 'set -euo pipefail && \
    apt update -qq && apt install -qqy bsdextrautils curl docker.io jq unzip wget && \
    curl -sL https://mise.run -o - | bash && \
    eval "$(~/.local/bin/mise activate bash)" && \
    mise run "create-delete:posts:all" \
  '
```

## Notes

- Use ` ```bash ` to run commands during the [post_tests](./.github/workflows/post_tests.yml)
  "create" execution:

  ````md
  ```bash
  ### <some create commands...>
  ```
  ````

- Use ` ```shell ` not to run commands during the [post_tests](./.github/workflows/post_tests.yml)
  execution (they will be only displayed on the web pages):

  ````md
  ```shell
  ### some commands...
  ```
  ````

- Use ` ```sh ` to run commands during the [post_tests](./.github/workflows/post_tests.yml)
  "destroy" execution:

  ````md
  ```sh
  ### <some clean-up/destroy commands...>
  ```
  ````

## Star History

<!-- markdownlint-disable -->
<a href="https://www.star-history.com/#ruzickap/ruzickap.github.io&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=ruzickap/ruzickap.github.io&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=ruzickap/ruzickap.github.io&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=ruzickap/ruzickap.github.io&type=date&legend=top-left" />
 </picture>
</a>
<!-- markdownlint-restore -->
