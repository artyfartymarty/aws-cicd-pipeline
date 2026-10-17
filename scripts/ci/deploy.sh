#!/usr/bin/env bash
# Layer 2 deploy logic, shared by both CI systems:
#   GitHub Actions     .github/workflows/_deploy.yml   (my account)
#   Bitbucket Pipelines bitbucket-pipelines.yml        (work)
# The CI file signs in to the base role and decides who may run this. Every
# step after that is here, so the two pipelines cannot drift apart.
#
# Needs: aws, jq, tofu on PATH, and base-role credentials in the environment.
# Env:   PROJECT ENV_NAME BUILD_SHA AWS_REGION ARTIFACT_BUCKET TF_STATE_BUCKET
#        APPLY=true|false (false = plan only)  SUMMARY_FILE (optional, markdown)
set -euo pipefail

: "${PROJECT:?}" "${ENV_NAME:?}" "${BUILD_SHA:?}" "${AWS_REGION:?}" "${ARTIFACT_BUCKET:?}" "${TF_STATE_BUCKET:?}"
APPLY="${APPLY:-true}"
SUMMARY="${SUMMARY_FILE:-/dev/null}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" TF_IN_AUTOMATION=1
export TF_VAR_env="$ENV_NAME" TF_VAR_build_sha="$BUILD_SHA" TF_VAR_region="$AWS_REGION" \
  TF_VAR_project="$PROJECT" TF_VAR_artifact_bucket="$ARTIFACT_BUCKET"
STACK=infra/app

# 1. Per-env settings live outside the repo (work: Config Graph infraConfig).
CFG="$(aws ssm get-parameter --name "/$PROJECT/env/$ENV_NAME/config" --query Parameter.Value --output text)"
DEPLOY_ROLE_ARN="$(jq -r .deploy_role_arn <<<"$CFG")"
TF_VAR_app_boundary_arn="$(jq -r .app_boundary_arn <<<"$CFG")"
TF_VAR_lambda_subnet_ids="$(jq -c .lambda_subnet_ids <<<"$CFG")"
TF_VAR_lambda_security_group_ids="$(jq -c .lambda_security_group_ids <<<"$CFG")"
export TF_VAR_app_boundary_arn TF_VAR_lambda_subnet_ids TF_VAR_lambda_security_group_ids

# 2. Base role -> this env's deploy role (work: OIDC base -> provisioner role).
SESSION="ci-$ENV_NAME-${GITHUB_RUN_ID:-${BITBUCKET_BUILD_NUMBER:-local}}"
CREDS="$(aws sts assume-role --role-arn "$DEPLOY_ROLE_ARN" --role-session-name "$SESSION" \
  --duration-seconds 3600 --query Credentials --output json)"
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  for k in AccessKeyId SecretAccessKey SessionToken; do echo "::add-mask::$(jq -r ".$k" <<<"$CREDS")"; done
fi
AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"$CREDS")"
AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$CREDS")"
AWS_SESSION_TOKEN="$(jq -r .SessionToken <<<"$CREDS")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset CREDS AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE AWS_PROFILE
echo "Deploying as $(aws sts get-caller-identity --query Arn --output text)"

# 3. Deploy the FIRST version ever uploaded for this build. A later upload to
#    the same key (by anyone) is ignored, so prod gets what dev tested.
KEY="builds/$BUILD_SHA/app.zip"
VID="$(aws s3api list-object-versions --bucket "$ARTIFACT_BUCKET" --prefix "$KEY" \
  --query "sort_by(Versions[?Key=='$KEY'], &LastModified)[0].VersionId" --output text)"
if [ -z "$VID" ] || [ "$VID" = "None" ]; then
  echo "No build at s3://$ARTIFACT_BUCKET/$KEY" >&2; exit 1
fi
export TF_VAR_artifact_version="$VID"
echo "Deploying $KEY version $VID"

# 4. init -> plan -> apply (work: Harness IACM workspace per env).
tofu -chdir="$STACK" init -input=false \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=app/$ENV_NAME.tfstate" \
  -backend-config="region=$AWS_REGION"
tofu -chdir="$STACK" plan -input=false -no-color -out=tfplan | tee plan.txt
{
  echo "### Plan for $ENV_NAME (build \`$BUILD_SHA\`)"
  echo '```'; grep -E '^(Plan:|No changes)|will be|must be' plan.txt || true; echo '```'
} >>"$SUMMARY"
[ "$APPLY" = "true" ] || { echo "Plan only, nothing applied."; exit 0; }
tofu -chdir="$STACK" apply -input=false tfplan

# 5. Smoke test: the running Lambda must report this build and env.
FN="$(tofu -chdir="$STACK" output -raw function_name)"
aws lambda invoke --function-name "$FN" --cli-binary-format raw-in-base64-out \
  --payload '{"action":"health"}' out.json >/dev/null
cat out.json; echo
test "$(jq -r .build out.json)" = "$BUILD_SHA"
test "$(jq -r .env out.json)" = "$ENV_NAME"
echo "### $ENV_NAME is running build \`$BUILD_SHA\`" >>"$SUMMARY"
