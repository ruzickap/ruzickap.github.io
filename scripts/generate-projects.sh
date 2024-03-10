#!/usr/bin/env bash

set -euo pipefail

DESTINATION_FILE="${1:-projects.md}"
TMP_FILE="/tmp/generate_projects_md.json"

GITHUB_REPOSITORIES_DESCRIPTIONS=(
  "ruzickap/action-my-broken-link-checker|GitHub Actions: My Broken Link Checker ✔"
  "ruzickap/action-my-markdown-link-checker|GitHub Actions: My Markdown Link Checker ✔"
  "ruzickap/action-my-markdown-linter|GitHub Actions: My Markdown Linter ✔"
  "ruzickap/packer-templates|Packer templates"
  "ruzickap/packer-virt-sysprep|Packer-Virt-Sysprep"
  "ruzickap/container-build|container-build"
  "ruzickap/darktable_video_tutorials_list|Darktable Video Tutorials with screenshots"
  "ruzickap/test_usb_stick_for_tv|USB Stick for TV testing"
  "ruzickap/ansible-role-my_common_defaults|Ansible role my_common_defaults"
  "ruzickap/ansible-role-proxy_settings|Ansible role proxy_settings"
  "ruzickap/ansible-role-virtio-win|Ansible role virtio-win"
  "ruzickap/ansible-role-vmwaretools|Ansible role vmwaretools"
  "ruzickap/ansible-my_workstation|Ansible - My Workstation"
  "ruzickap/ansible-openwrt|Ansible - OpenWRT"
  "ruzickap/ansible-raspbian|Ansible - Raspbian"
  "ruzickap/popular-containers-vulnerability-checks|popular-containers-vulnerability-checks"
  "ruzickap/malware-cryptominer-container|malware-cryptominer-container"
  "ruzickap/raw-photo-tools-container|raw-photo-tools-container"
  "ruzickap/myteam-adr|myteam-adr"
  "awsugcz/awsug.cz|Prague AWS User Group Web Pages"
  "ruzickap/ruzickap.github.io|ruzickap.github.io"
  "ruzickap/petr.ruzicka.dev|petr.ruzicka.dev"
  "ruzickap/xvx.cz|xvx.cz"
  "ruzickap/k8s-tf-eks-gitops|k8s-tf-eks-gitops"
  "ruzickap/k8s-eks-rancher|k8s-eks-rancher"
  "ruzickap/k8s-eks-bottlerocket-fargate|k8s-eks-bottlerocket-fargate"
  "ruzickap/k8s-flagger-istio-flux|k8s-flagger-istio-flux"
  "ruzickap/k8s-flux-istio-gitlab-harbor|k8s-flux-istio-gitlab-harbor"
  "ruzickap/k8s-harbor|k8s-harbor"
  "ruzickap/k8s-harbor-presentation|k8s-harbor-presentation"
  "ruzickap/k8s-istio-demo|k8s-istio-demo"
  "ruzickap/k8s-istio-webinar|k8s-istio-webinar"
  "ruzickap/k8s-istio-workshop|k8s-istio-workshop"
  "ruzickap/k8s-jenkins-x|k8s-jenkins-x"
  "ruzickap/k8s-knative-gitlab-harbor|k8s-knative-gitlab-harbor"
  "ruzickap/k8s-postgresql|k8s-postgresql"
  "ruzickap/k8s-sockshop|k8s-sockshop"
  "ruzickap/cheatsheet-macos|cheatsheet-macos"
  "ruzickap/cheatsheet-atom|Cheatsheet - Atom"
  "ruzickap/cheatsheet-systemd|Cheatsheet - Systemd"
)

cat > "${DESTINATION_FILE}" << EOF
---
# https://www.w3schools.com/icons/icons_reference.asp
icon: fas fa-project-diagram
order: 4
---

List of my GitHub projects: [https://github.com/ruzickap/](https://github.com/ruzickap/)
EOF

for GITHUB_REPOSITORY_TITLE_TMP in "${GITHUB_REPOSITORIES_DESCRIPTIONS[@]}"; do
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY_TITLE_TMP%|*}"
  echo "*** ${GITHUB_REPOSITORY}"
  GITHUB_REPOSITORY_TITLE="${GITHUB_REPOSITORY_TITLE_TMP##*|}"
  curl -s --header "authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${GITHUB_REPOSITORY}" > "${TMP_FILE}"
  GITHUB_REPOSITORY_DESCRIPTION=$(jq -r '.description' "${TMP_FILE}")
  GITHUB_REPOSITORY_HTML_URL=$(jq -r '.html_url' "${TMP_FILE}")
  GITHUB_REPOSITORY_HOMEPAGE=$(jq -r '.homepage' "${TMP_FILE}")
  GITHUB_REPOSITORY_DEFAULT_BRANCH=$(jq -r '.default_branch' "${TMP_FILE}")
  # Remove pages-build-deployment and any obsolete GitHub Actions which doesn't have path like "vuepress-build"
  GITHUB_REPOSITORY_CI_CD_STATUS=$(curl -s --header "authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows" | jq -r 'del(.workflows[] | select((.path=="dynamic/pages/pages-build-deployment") or (.path==""))) | .workflows[] | "  [![GitHub Actions status - " + .name + "](" + .badge_url + ")](" + .html_url | gsub("/blob/.*/.github/"; "/actions/") + ")"' | sort --ignore-case)
  GITHUB_REPOSITORY_URL_STRING=$(if [[ -n "${GITHUB_REPOSITORY_HOMEPAGE}" ]]; then echo -e "\n- Website: <${GITHUB_REPOSITORY_HOMEPAGE}>"; fi)
  cat << EOF >> "${DESTINATION_FILE}"

## [${GITHUB_REPOSITORY_TITLE}](${GITHUB_REPOSITORY_HTML_URL})

- Description: ${GITHUB_REPOSITORY_DESCRIPTION}${GITHUB_REPOSITORY_URL_STRING}

[![GitHub release](https://img.shields.io/github/v/release/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/releases/latest)
[![GitHub license](https://img.shields.io/github/license/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/blob/${GITHUB_REPOSITORY_DEFAULT_BRANCH}/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY}/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY}/network/members)
[![GitHub watchers](https://img.shields.io/github/watchers/${GITHUB_REPOSITORY}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY})

- CI/CD status:

${GITHUB_REPOSITORY_CI_CD_STATUS}

- Issue tracking:

  [![GitHub issues](https://img.shields.io/github/issues/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/issues)
  [![GitHub pull requests](https://img.shields.io/github/issues-pr/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/pulls)

- Repository:

  [![GitHub release date](https://img.shields.io/github/release-date/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/releases)
  [![GitHub last commit](https://img.shields.io/github/last-commit/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub commits since latest release](https://img.shields.io/github/commits-since/${GITHUB_REPOSITORY}/latest)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY}/commits/)
  [![GitHub repo size](https://img.shields.io/github/repo-size/${GITHUB_REPOSITORY}.svg)](https://github.com/${GITHUB_REPOSITORY})
EOF
done

npx prettier -w --parser markdown --prose-wrap always --print-width 80 "${DESTINATION_FILE}"
