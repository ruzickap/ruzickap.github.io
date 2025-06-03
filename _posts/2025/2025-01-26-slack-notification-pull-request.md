---
title: Slack notification for GitHub Pull Requests with status updates
author: Petr Ruzicka
date: 2025-01-26
description: Use GitHub Actions for Slack notifications of your Pull Requests including the PR status updates
categories: [GitHub, GitHub Actions, Slack, notification, Pull Request]
tags:
  [
    GitHub,
    notifications,
    GitHub Actions,
    Pull Request,
  ]
image: https://raw.githubusercontent.com/kubevela/kube-trigger/cfa3e2e367b2886cf80735de795dbe45c94fb8bf/docs/img/overview/slack-logo.svg
---

When working on code and collaborating with teammates, setting up Slack
notifications for new GitHub Pull Requests can be helpful. This is a widely
recognized best practice, and many people use the [slack-github-action](https://github.com/slackapi/slack-github-action)
to implement it. However, using Slack reactions for Pull Request updates is less
common.

Here's a screencast demonstrating what the Slack notification with status
updates looks like:

![Slack notification for GitHub Pull Requests with status updates](/assets/img/posts/2025/2025-01-26-slack-notification-pull-request/pr-update-slack-notification-status-update.avif)

In this article, I will walk you through setting up Slack notifications for
GitHub Pull Requests, including status updates, using GitHub Actions.

## Requirements

- First, create GitHub Action secrets named `MY_SLACK_BOT_TOKEN` and
  `MY_SLACK_CHANNEL_ID`. Detailed instructions for this can be found in the
  [slack-github-action](https://github.com/slackapi/slack-github-action)
  repository.
- Next, create a new GitHub Action workflow file named
  `.github/workflows/pr-slack-notification.yml` with the following content.

{% raw %}

```yaml
name: pr-slack-notification

# Based on: https://github.com/slackapi/slack-github-action/issues/269
# Description: https://ruzickap.github.io/posts/slack-notification-pull-request/

on:
  workflow_dispatch:
  pull_request:
    types:
      - opened
      - ready_for_review
      - review_requested
      - closed
  issue_comment:
    types:
      - created
  pull_request_review:
    types:
      - submitted

permissions: read-all

defaults:
  run:
    shell: bash -euxo pipefail {0}

jobs:
  debug:
    runs-on: ubuntu-latest
    steps:
      - name: Debug
        env:
          GITHUB_CONTEXT: ${{ toJson(github) }}
        run: |
          echo "${GITHUB_CONTEXT}"

  pr-slack-notification:
    runs-on: ubuntu-latest
    name: Sends a message to Slack when a PR is opened
    if: (github.event.action == 'opened' && github.event.pull_request.draft == false) || github.event.action == 'ready_for_review'
    steps:
      - name: Post PR summary message to slack
        id: message
        uses: slackapi/slack-github-action@485a9d42d3a73031f12ec201c457e2162c45d02d # v2.0.0
        with:
          method: chat.postMessage
          token: ${{ secrets.MY_SLACK_BOT_TOKEN }}
          payload: |
            channel: ${{ secrets.MY_SLACK_CHANNEL_ID }}
            text: "💡 *${{ github.event.pull_request.user.login }}*: <${{ github.event.pull_request.html_url }}|#${{ github.event.pull_request.number }} - ${{ github.event.pull_request.title }}> (+${{ github.event.pull_request.additions }}, -${{ github.event.pull_request.deletions }})"

      - name: Create file with slack message timestamp
        run: |
          echo "${{ steps.message.outputs.ts }}" > slack-message-timestamp.txt

      - name: Cache slack message timestamp
        uses: actions/cache/save@1bd1e32a3bdc45362d1e726936510720a7c30a57 # v4.2.0
        with:
          path: slack-message-timestamp.txt
          key: slack-message-timestamp-${{ github.event.pull_request.html_url }}-${{ steps.message.outputs.ts }}

  slack-emoji-react:
    runs-on: ubuntu-latest
    name: Adds emoji reaction to slack message when a PR is closed or reviewed
    if: ${{ startsWith(github.event.pull_request.html_url, 'https') || startsWith(github.event.issue.pull_request.html_url, 'https') }}
    steps:
      # gh commands needs to be executed in the repository
      - name: Checkout Code
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      # https://stackoverflow.com/questions/74640750/github-actions-not-finding-cache
      # I can not use the cache action in this job because the cache is not shared between runs
      - name: Save slack timestamp as an environment variable
        id: slack-timestamp
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          SLACK_TIMESTAMP=$(gh cache list --json key --jq '.[].key|capture("${{ github.event.pull_request.html_url || github.event.issue.pull_request.html_url }}-(?<x>.+)").x')
          echo "SLACK_TIMESTAMP=${SLACK_TIMESTAMP}" | tee -a "${GITHUB_ENV}"
          if [[ "${SLACK_TIMESTAMP}" != '' ]]; then
            echo "github_event_pull_request_html_url=true" >> "${GITHUB_OUTPUT}"
          fi

      - name: Decide which emoji to add
        if: ${{ steps.slack-timestamp.outputs.github_event_pull_request_html_url == 'true' }}
        run: |
          case "${{ github.event.action }}" in
            created)
              if [[ "${{ github.event_name }}" == 'issue_comment' ]]; then
                echo "EMOJI=speech_balloon" >> "${GITHUB_ENV}" # 💬
              fi
              ;;
            submitted)
              case "${{ github.event.review.state }}" in
                changes_requested)
                  echo "EMOJI=repeat" >> "${GITHUB_ENV}" # 🔁
                  ;;
                approved)
                  echo "EMOJI=ok" >> "${GITHUB_ENV}" # 🆗
                  ;;
                commented)
                  echo "EMOJI=speech_balloon" >> "${GITHUB_ENV}" # 💬
                  ;;
              esac
              ;;
            review_requested)
              echo "EMOJI=eyes" >> "${GITHUB_ENV}" # 👀
              ;;
            *)
              echo "EMOJI=false" >> "${GITHUB_ENV}"
              ;;
          esac

      - name: React to PR summary message in slack with emoji
        if: ${{ steps.slack-timestamp.outputs.github_event_pull_request_html_url == 'true' && env.EMOJI != 'false' }}
        uses: slackapi/slack-github-action@485a9d42d3a73031f12ec201c457e2162c45d02d # v2.0.0
        with:
          method: reactions.add
          token: ${{ secrets.MY_SLACK_BOT_TOKEN }}
          payload: |
            channel: ${{ secrets.MY_SLACK_CHANNEL_ID }}
            timestamp: "${{ env.SLACK_TIMESTAMP }}"
            name: ${{ env.EMOJI }}

      - name: Update the original message with success
        if: ${{ github.event.pull_request.merged && steps.slack-timestamp.outputs.github_event_pull_request_html_url == 'true' }}
        uses: slackapi/slack-github-action@v2.0.0
        with:
          method: chat.update
          token: ${{ secrets.MY_SLACK_BOT_TOKEN }}
          payload: |
            channel: ${{ secrets.MY_SLACK_CHANNEL_ID }}
            ts: "${{ env.SLACK_TIMESTAMP }}"
            text: "✅ *${{ github.event.pull_request.user.login }}*: <${{ github.event.pull_request.html_url }}|#${{ github.event.pull_request.number }} - ${{ github.event.pull_request.title }}> (+${{ github.event.pull_request.additions }}, -${{ github.event.pull_request.deletions }})"
            attachments:
              - color: "28a745"
                fields:
                  - title: "Status"
                    short: true
                    value: "Merged ✅"
```

{% endraw %}

## Description

The workflow file defines two jobs: `pr-slack-notification` and
`slack-emoji-react`.

- The `pr-slack-notification` job sends a message to Slack when a Pull Request
  is opened or marked as ready for review.
- The `slack-emoji-react` job adds an emoji reaction to the Slack message when
  a Pull Request is closed or reviewed. This job also updates the original
  message with a success indicator when the Pull Request is merged.

The Slack message "emoji" updates cover the following scenarios:

- 💬 - a new comment is added to the pull request through either a "Pull Request
  Comment" or a "Review Changes Comment"
- 🔁 - the reviewer has requested changes
- 🆗 - the reviewer has approved the Pull Request
- 👀 - The Pull Request owner has requested the reviewer to review the Pull
  Request
- ✅ - The Pull Request has been merged

The screencast above showcases some of these actions.

> The GitHub Action workflow code and its description may change in the future.
> The latest version of the code can be found here: [pr-slack-notification.yml](https://github.com/ruzickap/malware-cryptominer-container/blob/main/.github/workflows/pr-slack-notification.yml)

Enjoy ... 😉
