#!/usr/bin/env bash

set -eu

GITHUB_REPOSITORIES=(
  "ruzickap/blog-test.ruzicka.dev"
  "ruzickap/cheatsheet-macos"
  "ruzickap/container-build"
  "ruzickap/k8s-eks-rancher"
  "ruzickap/k8s-tf-eks-gitops"
  "ruzickap/malware-cryptominer-container"
  "ruzickap/myteam-adr"
  "ruzickap/popular-containers-vulnerability-checks"
  "ruzickap/raw-photo-tools-container"
  "ruzickap/ruzickap.github.io"
  "ruzickap/action-my-broken-link-checker"
  "ruzickap/action-my-markdown-link-checker"
  "ruzickap/action-my-markdown-linter"
  "ruzickap/packer-templates"
  "ruzickap/packer-virt-sysprep"
  "ruzickap/darktable_video_tutorials_list"
  "ruzickap/test_usb_stick_for_tv"
  "ruzickap/ansible-role-my_common_defaults"
  "ruzickap/ansible-role-proxy_settings"
  "ruzickap/ansible-role-virtio-win"
  "ruzickap/ansible-role-vmwaretools"
  "ruzickap/ansible-my_workstation"
  "ruzickap/ansible-openwrt"
  "ruzickap/ansible-raspbian"
  "awsugcz/awsug.cz"
  "ruzickap/petr.ruzicka.dev"
  "ruzickap/xvx.cz"
  "ruzickap/k8s-eks-bottlerocket-fargate"
  "ruzickap/k8s-flagger-istio-flux"
  "ruzickap/k8s-flux-istio-gitlab-harbor"
  "ruzickap/k8s-harbor"
  "ruzickap/k8s-harbor-presentation"
  "ruzickap/k8s-istio-demo"
  "ruzickap/k8s-istio-webinar"
  "ruzickap/k8s-istio-workshop"
  "ruzickap/k8s-jenkins-x"
  "ruzickap/k8s-knative-gitlab-harbor"
  "ruzickap/k8s-postgresql"
  "ruzickap/k8s-sockshop"
  "ruzickap/cheatsheet-atom"
  "ruzickap/cheatsheet-systemd"
)

for GITHUB_REPOSITORY in "${GITHUB_REPOSITORIES[@]}"; do
  curl -s -u "${GITHUB_TOKEN}:x-oauth-basic" "https://api.github.com/repos/${GITHUB_REPOSITORY}" > /tmp/add_project.json
  GITHUB_REPOSITORY_DESCRIPTION=$(jq -r '.description' /tmp/add_project.json)
  GITHUB_REPOSITORY_HTML_URL=$(jq -r '.html_url' /tmp/add_project.json)
  GITHUB_REPOSITORY_DEFAULT_BRANCH=$(jq -r '.default_branch' /tmp/add_project.json)
  cat << EOF

## [GitHub Actions: ${GITHUB_REPOSITORY##*/}](${GITHUB_REPOSITORY_HTML_URL})

Description: ${GITHUB_REPOSITORY_DESCRIPTION}

[![GitHub release](https://img.shields.io/github/v/release/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/releases/latest)
[![GitHub license](https://img.shields.io/github/license/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/blob/${GITHUB_REPOSITORY_DEFAULT_BRANCH}/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY}/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY}/network/members)
[![GitHub watchers](https://img.shields.io/github/watchers/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY})

* CI/CD status:

$(curl -s -u "${GITHUB_TOKEN}:x-oauth-basic" "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows" | jq -r '.workflows[] | "  [![GitHub Actions status - " + .name + "](" + .badge_url + ")](" + ( if .html_url | contains("/dynamic/pages/pages-build-deployment") then .html_url | gsub("/blob/.*/dynamic/"; "/actions/workflows/") else .html_url | gsub("/blob/.*/.github/"; "/actions/") end ) + ")"' | sort --ignore-case)

* Issue tracking:

  [![GitHub issues](https://img.shields.io/github/issues/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/issues)
  [![GitHub pull requests](https://img.shields.io/github/issues-pr/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/pulls)

* Repository:

  [![GitHub release date](https://img.shields.io/github/release-date/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/releases)
  [![GitHub last commit](https://img.shields.io/github/last-commit/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub commits since latest release](https://img.shields.io/github/commits-since/${GITHUB_REPOSITORY}/latest)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub repo size](https://img.shields.io/github/repo-size/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY})
EOF
done
