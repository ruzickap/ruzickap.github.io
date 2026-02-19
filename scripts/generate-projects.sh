#!/usr/bin/env bash

set -euo pipefail

DESTINATION_FILE="${1:-projects.md}"
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token)}"

cat > "${DESTINATION_FILE}" << 'EOF'
---
# https://www.w3schools.com/icons/icons_reference.asp
icon: fas fa-project-diagram
order: 4
---

[![Homepage](https://img.shields.io/badge/Homepage-4285F4?style=plastic&logo=homeadvisor&logoColor=white)](https://ruzickap.github.io/)
[![Email](https://img.shields.io/badge/Email-005FF9?style=plastic&logo=maildotru&logoColor=white)](mailto:petr.ruzicka@gmail.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-%230077B5.svg?style=plastic&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/petrruzicka/)
[![Facebook](https://img.shields.io/badge/Facebook-%231877F2.svg?style=plastic&logo=Facebook&logoColor=white)](https://www.facebook.com/petr.ruzicka)
[![Instagram](https://img.shields.io/badge/Instagram-%23E4405F.svg?style=plastic&logo=Instagram&logoColor=white)](https://www.instagram.com/petr.ruzicka_cz/)
[![X](https://img.shields.io/badge/X-%23000000.svg?style=plastic&logo=X&logoColor=white)](https://x.com/Ruzicka_Petr)
[![Mastodon](https://img.shields.io/badge/Mastodon-%236364FF.svg?style=plastic&logo=mastodon&logoColor=white)](https://mastodon.social/@petr_ruzicka)
[![YouTube](https://img.shields.io/badge/YouTube-%23FF0000.svg?style=plastic&logo=YouTube&logoColor=white)](https://www.youtube.com/@PetrRuzicka)
[![Medium](https://img.shields.io/badge/Medium-12100E?style=plastic&logo=medium&logoColor=white)](https://medium.com/@petr.ruzicka)
[![Unsplash](https://img.shields.io/badge/Unsplash-000000?style=plastic&logo=unsplash&logoColor=white)](https://unsplash.com/@ruzickap/)
[![Pixabay](https://img.shields.io/badge/Pixabay-2EC66D?style=plastic&logo=pixabay&logoColor=white)](https://pixabay.com/users/ruzickap-7967890/)
[![Flickr](https://img.shields.io/badge/Flickr-0063DC?style=plastic&logo=flickr&logoColor=white)](https://www.flickr.com/photos/petrruzicka/)
[![500px](https://img.shields.io/badge/500px-0099E5?style=plastic&logo=500px&logoColor=white)](https://500px.com/p/petrruzicka)

## Websites

- [awsug.cz](https://awsug.cz/) - Prague AWS User Group community website
- [linux-old.xvx.cz](https://linux-old.xvx.cz/) - Old WordPress-based
  personal blog about Linux
- [linux.xvx.cz](https://linux.xvx.cz/) - Old Blogger-based personal blog
  about Linux
- [petr.ruzicka.dev](https://petr.ruzicka.dev/) - Personal homepage
- [ruzickap.github.io](https://ruzickap.github.io/) - Personal blog about
  Linux, CNCF  and cloud technologies
- [xvx.cz](https://xvx.cz/) - Personal domain landing page with links to
  all sites

## Vibe Coding Projects

- [brewwatch](https://brewwatch.lovable.app/) - A modern web app to discover
  and track newly added Homebrew packages and casks

## [GitHub Projects](https://github.com/ruzickap/)

[![Dashboard stats of @ruzickap](https://next.ossinsight.io/widgets/official/compose-user-dashboard-stats/thumbnail.png?user_id=1434387&image_size=auto&color_scheme=dark)](https://next.ossinsight.io/widgets/official/compose-user-dashboard-stats?user_id=1434387)
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

### [${GITHUB_REPOSITORY_NAME##*/}](${GITHUB_REPOSITORY_URL})

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
