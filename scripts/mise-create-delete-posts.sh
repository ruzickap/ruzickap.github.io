#!/usr/bin/env bash

set -euo pipefail

# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
# Cluster Name: k01
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-${PWD}}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

: "${AWS_ACCESS_KEY_ID:?Error: AWS_ACCESS_KEY_ID environment variable is not set!}"
: "${AWS_ROLE_TO_ASSUME:?Error: AWS_ROLE_TO_ASSUME environment variable is not set!}"
: "${AWS_SECRET_ACCESS_KEY:?Error: AWS_SECRET_ACCESS_KEY environment variable is not set!}"
: "${GITHUB_STEP_SUMMARY:="${TMP_DIR}/github_step_summary"}"
: "${RUN_FILE:="${TMP_DIR}/${1//[:|]/_}.sh"}"

eval "$(aws sts assume-role --role-arn "${AWS_ROLE_TO_ASSUME}" --role-session-name "$USER@${HOSTNAME}-$(date +%s)" --duration-seconds 7200 | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)\n"')"
[[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo -e "::add-mask::${AWS_ACCESS_KEY_ID}\n::add-mask::${AWS_SECRET_ACCESS_KEY}\n::add-mask::${AWS_SESSION_TOKEN}"

echo "💡 *** $*"

readarray -td\| POSTS <<< "${1##*:}|"
unset 'POSTS[-1]'

[[ ! -d "${TMP_DIR}" ]] && mkdir -v "${TMP_DIR}"
echo "set -euxo pipefail" > "${RUN_FILE}"

case "${1%:*}" in
  create)
    MQ_CODE_BLOCK="bash"
    for ((idx = ${#POSTS[@]} - 1; idx >= 0; idx--)); do
      POST_FILES_ARRAY+=("$(find "${PWD}/_posts" -type f -name "*${POSTS[idx]}*.md")")
    done
    ;;
  delete)
    MQ_CODE_BLOCK="sh"
    for POST_FILE in "${POSTS[@]}"; do
      POST_FILES_ARRAY+=("$(find "${PWD}/_posts" -type f -name "*${POST_FILE}*.md")")
    done
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    exit 1
    ;;
esac

mq "select(.code.lang == \"${MQ_CODE_BLOCK}\") | to_text()" "${POST_FILES_ARRAY[@]}" >> "${RUN_FILE}"

if grep -Eq '(^| )eksctl ' "${RUN_FILE}"; then
  if eksctl get clusters --name="${CLUSTER_NAME}" && [[ "${1%:*}" = "delete" ]]; then
    aws eks update-kubeconfig --region "${AWS_DEFAULT_REGION}" --name "${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}" || true
  fi
  (
    echo "😇 <https://${CLUSTER_FQDN}>"
    echo '```'
    echo "export CLUSTER_NAME=\"${CLUSTER_NAME}\""
    echo "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\""
    echo "eval \"\$(mise run a)\""
    echo '```'
  ) | tee "${GITHUB_STEP_SUMMARY}"
fi

chmod a+x "${RUN_FILE}"
echo "⏰ *** $(date)"
"${RUN_FILE}"
echo "⏰ *** $(date)"

rm -v "${RUN_FILE}"

if [[ "${GITHUB_STEP_SUMMARY}" =~ ${TMP_DIR} ]] && [[ -f "${GITHUB_STEP_SUMMARY}" ]]; then
  rm -v "${GITHUB_STEP_SUMMARY}"
fi

if [[ -z "$(ls -A "${TMP_DIR}")" ]]; then
  rmdir -v "${TMP_DIR}"
else
  if [[ "${1%:*}" = "delete" ]]; then
    find "${TMP_DIR}" -ls
    echo "💡 *** ${TMP_DIR} is not empty, please check it !!!"
    exit 2
  fi
fi
