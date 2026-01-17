---
title: Check availability of external links in your web pages
author: Petr Ruzicka
date: 2020-02-02
description: Check availability of external links in your web pages
categories: [DevOps, linux.xvx.cz]
tags: [github-actions, automation]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2020/02/check-availability-of-external-links-in.html)
{: .prompt-info }

When you create your web pages in most cases you are using the images, external
links, videos which may not be a static part of the web page itself, but it's
stored externally.

At the time you wrote your shiny page you probably checked all these external
dependencies to be sure it's working to make your readers happy, because nobody
likes to see errors like this:

![YouTube missing video error message](/assets/img/posts/2020/2020-02-02-check-availability-of-external-links-in-your-web-pages/youtube_missing_video.avif)

Now the page is working fine with all external dependencies because I checked it
properly - but what about in a few months / years / ... ?

Web pages / images  / videos may disappear from the Internet especially when you
can not control them and then it's handy from time to time to check your web
pages if all the external links are still alive.

There are many tools which you may install to your PC and check the "validity"
of your web pages instead of manually clicking the links.

I would like to share how I'm periodically checking my documents / pages
using the [GitHub Actions](https://github.com/features/actions).

Here is the GitHub Action I wrote for this purpose: 
[My Broken Link Checker](https://github.com/ruzickap/action-my-broken-link-checker)

In short you can simply create a git repository in GitHub and store there the
file defining which URLs should be checked/verified:

```bash
git clone git@github.com:ruzickap/check_urls.git
cd check_urls || true
mkdir -p .github/workflows

cat > .github/workflows/periodic-broken-link-checks.yml << \EOF
name: periodic-broken-link-checks

on:
  schedule:
    - cron: '0 0 * * *'
  pull_request:
    types: [opened, synchronize]
    paths:
      - .github/workflows/periodic-broken-link-checks.yml
  push:
    branches:
      - master
    paths:
      - .github/workflows/periodic-broken-link-checks.yml

jobs:
  broken-link-checker:
    runs-on: ubuntu-latest
    steps:
      - name: Broken link checker
        env:
          INPUT_URL: https://google.com
          EXCLUDE: |
            linkedin.com
            localhost
            myexample.dev
            mylabs.dev
        run: |
          export INPUT_CMD_PARAMS="--one-page-only --verbose --buffer-size=8192 --concurrency=10 --exclude=($( echo ${EXCLUDE} | tr ' ' '|' ))"
          wget -qO- https://raw.githubusercontent.com/ruzickap/action-my-broken-link-checker/v1/entrypoint.sh | bash
EOF

git add .
git commit -m "Add periodic-broken-link-checks"
git push
```

The code above will store the GitHub Action Workflow file into the repository
and start checking the `https://google.com` every midnight (UTC).

This is the screencast where you can see it all in action:

{% include embed/youtube.html id='H6H523TMPXk' %}

This URL checker script is based on [muffet](https://github.com/raviqqe/muffet) 
and you can set its parameters by changing the `INPUT_CMD_PARAMS` variable.

Feel free to look at more details
here: [https://github.com/ruzickap/action-my-broken-link-checker](https://github.com/ruzickap/action-my-broken-link-checker)

I hope this may help you to keep the quality of the web pages by finding the
external link errors quickly.

Enjoy :-)
