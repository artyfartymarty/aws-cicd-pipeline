# shellcheck shell=bash
# Source this in a Bitbucket step that has `oidc: true`:
#   source scripts/ci/bitbucket-aws-login.sh "$AWS_CI_ROLE_ARN"
# It hands the step's OIDC token to the AWS CLI and SDKs (and so to OpenTofu),
# which then call AssumeRoleWithWebIdentity themselves. With no role ARN it
# does nothing, so a self-hosted runner's own role (work: EKS pod role) is used.
# The GitHub equivalent is aws-actions/configure-aws-credentials.
if [ -n "${1:-}" ]; then
  : "${BITBUCKET_STEP_OIDC_TOKEN:?This step needs oidc: true}"
  AWS_WEB_IDENTITY_TOKEN_FILE="$(mktemp)"
  printf '%s' "$BITBUCKET_STEP_OIDC_TOKEN" >"$AWS_WEB_IDENTITY_TOKEN_FILE"
  export AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN="$1" AWS_ROLE_SESSION_NAME="bb-${BITBUCKET_BUILD_NUMBER:-0}"
  : "${AWS_REGION:?}"
  export AWS_DEFAULT_REGION="$AWS_REGION"
  aws sts get-caller-identity --query Arn --output text
fi
