# ruzickap.github.io

[![GitHub Actions status - Lint Code Base](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml/badge.svg)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml)
[![Build and Deploy](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml/badge.svg?branch=main)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ruzickap/ruzickap.github.io/badge)](https://scorecard.dev/viewer/?uri=github.com/ruzickap/ruzickap.github.io)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/9800/badge)](https://www.bestpractices.dev/projects/9800)

## Overview

My personal site and blog...

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
docker run --rm -it --volume="${PWD}:/srv/jekyll" -e JEKYLL_UID="${UID}" -e JEKYLL_GID="${GID}" jekyll/jekyll -- bash -c 'chown -R jekyll /usr/gem/ && jekyll build --destination "public"'
docker run --rm -it --volume="${PWD}:/srv/jekyll" -e JEKYLL_UID="${UID}" -e JEKYLL_GID="${GID}" --publish 4000:4000 jekyll/jekyll -- bash -c 'chown -R jekyll /usr/gem/ && jekyll serve'
```

Megalinter:

```bash
mega-linter-runner --remove-container --container-name="mega-linter" --debug --env VALIDATE_ALL_CODEBASE=true
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

## Customizations

(Taken from [kungfux/kungfux.github.io](https://github.com/kungfux/kungfux.github.io))

- Add progress bar to back to top
  `assets/js/progress.js`, `assets/css/jekyll-theme-chirpy.scss`, `_includes/metadata-hook.html`
- Trigger PWA update automatically
  `assets/js/auto-update.js`, `_includes/metadata-hook.html`
