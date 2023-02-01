# ruzickap.github.io

[![GitHub Actions status - Lint Code Base](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml/badge.svg)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/mega-linter.yml)

## Overview

My personal site and blog...

[**ruzickap.github.io →**](https://ruzickap.github.io/)

- Main Page: <https://blog.ruzicka.dev>, <https://ruzickap.github.io>
- Dev Page: <https://ruzickap-github-io.pages.dev>

[![Build and Deploy](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml/badge.svg?branch=main)](https://github.com/ruzickap/ruzickap.github.io/actions/workflows/gh-pages-build.yml)

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
docker run --rm -it --volume="${PWD}:/srv/jekyll:Z" --publish 4000:4000 jekyll/jekyll jekyll serve
```
