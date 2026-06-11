#!/usr/bin/env bash

set -euo pipefail

# Save all output (stdout + stderr) to a log file while still displaying on terminal
exec > >(tee "/tmp/${MISE_TASK_NAME//[:|]/_}.log") 2>&1

export TMP_DIR="${TMP_DIR:-${PWD}/tmp}"

# Try a simple AWS STS call to validate credentials
if aws sts get-caller-identity > /dev/null 2>&1; then
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
    for ((idx = ${#POSTS[@]} - 1; idx >= 0; idx--)); do
      POST_FILES_ARRAY+=("$(find _posts -type f -name "*${POSTS[idx]}*.md")")
    done
    mq 'select(.code.lang == "bash" || .code.lang == "terraform" || .code.lang == "javascript" || .code.lang == "json" || .code.lang == "python") | to_text()' "${POST_FILES_ARRAY[@]}" >> "${RUN_FILE}"
    ;;
  delete)
    for POST_FILE in "${POSTS[@]}"; do
      POST_FILES_ARRAY+=("$(find _posts -type f -name "*${POST_FILE}*.md")")
    done
    mq 'select(.code.lang == "sh") | to_text()' "${POST_FILES_ARRAY[@]}" >> "${RUN_FILE}"
    ;;
  *)
    echo "Unknown action: ${1%:*}. Expected 'create' or 'delete'."
    exit 1
    ;;
esac

chmod a+x "${RUN_FILE}"
echo "⏰ *** $(date)"
# shellcheck source=/dev/null
source "${RUN_FILE}"
echo "⏰ *** $(date)"

if grep -Eq 'CLUSTER_FQDN' "${RUN_FILE}"; then
  (
    echo "😇 <https://${CLUSTER_FQDN}>"
    echo '```'
    echo "export AWS_REGION=\"${AWS_REGION}\" CLUSTER_FQDN=\"${CLUSTER_FQDN}\""
    echo "eval \"\$(mise run a)\""
    echo '```'
  ) | tee "${GITHUB_STEP_SUMMARY}"
fi

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
