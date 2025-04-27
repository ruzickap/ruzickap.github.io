#!/usr/bin/env bash

set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?Error: AWS_ACCESS_KEY_ID environment variable is not set!}"
: "${AWS_DEFAULT_REGION:?Error: AWS_DEFAULT_REGION environment variable is not set!}"
: "${AWS_ROLE_TO_ASSUME:?Error: AWS_ROLE_TO_ASSUME environment variable is not set!}"
: "${AWS_SECRET_ACCESS_KEY:?Error: AWS_SECRET_ACCESS_KEY environment variable is not set!}"
: "${CLUSTER_FQDN:?Error: CLUSTER_FQDN environment variable is not set!}"
: "${CLUSTER_NAME:?Error: CLUSTER_NAME environment variable is not set!}"
: "${GITHUB_STEP_SUMMARY:="${TMP_DIR}/github_step_summary"}"
: "${TMP_DIR:="${PWD}"}"
: "${RUN_FILE:="${TMP_DIR}/${1//[:|]/_}.sh"}"

eval "$(aws sts assume-role --role-arn "${AWS_ROLE_TO_ASSUME}" --role-session-name "$USER@$(hostname -f)-k8s-$(date +%s)" --duration-seconds 36000 | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)\n"')"

echo "💡 *** $*"

readarray -td\| POSTS <<< "${1##*:}|"
unset 'POSTS[-1]'

[[ ! -d "${TMP_DIR}" ]] && mkdir -v "${TMP_DIR}"
echo "set -euxo pipefail" > "${RUN_FILE}"

case "${1%:*}" in
  create)
    MDQ_CODE_BLOCK='```^bash$'
    for ((idx = ${#POSTS[@]} - 1; idx >= 0; idx--)); do
      POST_FILES_ARRAY+=("$(find "${PWD}/_posts" -type f -name "*${POSTS[idx]}*.md")")
    done
    ;;
  delete)
    MDQ_CODE_BLOCK='```^sh$'
    for POST_FILE in "${POSTS[@]}"; do
      POST_FILES_ARRAY+=("$(find "${PWD}/_posts" -type f -name "*${POST_FILE}*.md")")
    done
    ;;
  *)
    echo "Unknown action: ${ACTION}"
    exit 1
    ;;
esac

mdq "${MDQ_CODE_BLOCK}" --br -o plain "${POST_FILES_ARRAY[@]}" >> "${RUN_FILE}"

if grep -Eq '(^| )eksctl ' "${RUN_FILE}"; then
  (
    echo "😇 <https://${CLUSTER_FQDN}>"
    echo '```'
    echo "export AWS_DEFAULT_REGION=\"${AWS_DEFAULT_REGION}\""
    # shellcheck disable=SC2028
    echo "eval \"\$(aws sts assume-role --role-arn \"\${AWS_ROLE_TO_ASSUME}\" --role-session-name \"\$USER@\$(hostname -f)-k8s-\$(date +%s)\" --duration-seconds 36000 | jq -r '.Credentials | \"export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\\nexport AWS_SESSION_TOKEN=\(.SessionToken)\\n\"')\""
    echo "export KUBECONFIG=\"/tmp/kubeconfig-${CLUSTER_NAME}.conf\""
    echo "aws eks update-kubeconfig --region \"${AWS_DEFAULT_REGION}\" --name \"${CLUSTER_NAME}\" --kubeconfig \"\$KUBECONFIG\""
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
