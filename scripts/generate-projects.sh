#!/usr/bin/env bash

set -euo pipefail

DESTINATION_FILE="${1:-projects.md}"

cat > "${DESTINATION_FILE}" << EOF
---
# https://www.w3schools.com/icons/icons_reference.asp
icon: fas fa-project-diagram
order: 4
---

- Legacy Blog: [linux.xvx.cz](https://linux.xvx.cz/)
- List of my GitHub projects: [https://github.com/ruzickap/](https://github.com/ruzickap/)
EOF

while read -r GITHUB_REPOSITORY_TITLE_TMP; do
  GITHUB_REPOSITORY_NAME=$(jq -r '.nameWithOwner' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  echo "*** ${GITHUB_REPOSITORY_NAME}"
  GITHUB_REPOSITORY_DESCRIPTION=$(jq -r '.description' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  GITHUB_REPOSITORY_URL=$(jq -r '.url' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  GITHUB_REPOSITORY_TOPICS=$(jq -r '[.repositoryTopics[].name] | join(", ")' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  GITHUB_REPOSITORY_HOMEPAGEURL=$(jq -r '.homepageUrl' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  GITHUB_REPOSITORY_DEFAULT_BRANCH=$(jq -r '.defaultBranchRef.name' <<< "${GITHUB_REPOSITORY_TITLE_TMP}")
  # Remove pages-build-deployment and any obsolete GitHub Actions which doesn't have path like "vuepress-build"
  GITHUB_REPOSITORY_CI_CD_STATUS=$(curl -s --header "authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${GITHUB_REPOSITORY_NAME}/actions/workflows" | jq -r 'del(.workflows[] | select((.path=="dynamic/pages/pages-build-deployment") or (.path==""))) | .workflows[] | "  [![GitHub Actions status - " + .name + "](" + .badge_url + ")](" + .html_url | gsub("/blob/.*/.github/"; "/actions/") + ")"' | sort --ignore-case)
  GITHUB_REPOSITORY_URL_STRING=$(if [[ -n "${GITHUB_REPOSITORY_HOMEPAGEURL}" ]]; then echo -e "\n- Website: <${GITHUB_REPOSITORY_HOMEPAGEURL}>"; fi)
  cat << EOF >> "${DESTINATION_FILE}"

## [${GITHUB_REPOSITORY_NAME##*/}](${GITHUB_REPOSITORY_URL})

- Description: ${GITHUB_REPOSITORY_DESCRIPTION}${GITHUB_REPOSITORY_URL_STRING}
- Topics: ${GITHUB_REPOSITORY_TOPICS}

[![GitHub release](https://img.shields.io/github/v/release/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/releases/latest)
[![GitHub license](https://img.shields.io/github/license/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/blob/${GITHUB_REPOSITORY_DEFAULT_BRANCH}/LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/${GITHUB_REPOSITORY_NAME}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY_NAME}/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/${GITHUB_REPOSITORY_NAME}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY_NAME}/network/members)
[![GitHub watchers](https://img.shields.io/github/watchers/${GITHUB_REPOSITORY_NAME}.svg?style=social)](https://github.com/${GITHUB_REPOSITORY_NAME})

- CI/CD status:

${GITHUB_REPOSITORY_CI_CD_STATUS}

- Issue tracking:

  [![GitHub issues](https://img.shields.io/github/issues/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/issues)
  [![GitHub pull requests](https://img.shields.io/github/issues-pr/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/pulls)

- Repository:

  [![GitHub release date](https://img.shields.io/github/release-date/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/releases)
  [![GitHub last commit](https://img.shields.io/github/last-commit/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/commits/)
  [![GitHub commits since latest release](https://img.shields.io/github/commits-since/${GITHUB_REPOSITORY_NAME}/latest)](https://github.com/${GITHUB_REPOSITORY_NAME}/commits/)
  [![GitHub commit activity](https://img.shields.io/github/commit-activity/y/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME}/commits/)
  [![GitHub repo size](https://img.shields.io/github/repo-size/${GITHUB_REPOSITORY_NAME}.svg)](https://github.com/${GITHUB_REPOSITORY_NAME})
EOF
done <<< "$(gh repo list --visibility public --json defaultBranchRef,description,homepageUrl,nameWithOwner,repositoryTopics,url --jq 'sort_by(.nameWithOwner).[]' awsugcz | jq -c && gh repo list --visibility public --topic public --limit 100 --json defaultBranchRef,description,homepageUrl,nameWithOwner,repositoryTopics,url --jq 'sort_by(.nameWithOwner).[]' ruzickap | jq -c)"

npx prettier -w --parser markdown --prose-wrap always --print-width 80 "${DESTINATION_FILE}"
