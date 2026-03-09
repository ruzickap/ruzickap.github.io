#!/usr/bin/env bash

set -euo pipefail

# AWS Region
export AWS_REGION="${AWS_REGION:-us-east-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-k01.k8s.mylabs.dev}"
# Cluster Name: k01
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"
export KUBECONFIG="${KUBECONFIG:-${TMP_DIR}/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf}"

# Try a simple AWS STS call to validate credentials
if aws sts get-caller-identity >/dev/null 2>&1; then
  echo "✅ AWS access verified."
else
  echo "❌ ERROR: Unable to access AWS. Check credentials or permissions."
  exit 1
fi

: "${GITHUB_STEP_SUMMARY:="${TMP_DIR}/github_step_summary"}"
: "${RUN_FILE:="${TMP_DIR}/${1//[:|]/_}.sh"}"

echo "💡 *** $*"

readarray -td\| POSTS <<< "${1#*:}|"
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
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}" || true
  fi
  (
    echo "😇 <https://${CLUSTER_FQDN}>"
    echo '```'
    echo "export CLUSTER_NAME=\"${CLUSTER_NAME}\""
    echo "export AWS_REGION=\"${AWS_REGION}\""
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
