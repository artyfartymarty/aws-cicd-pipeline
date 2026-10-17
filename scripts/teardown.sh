#!/usr/bin/env bash
# Remove everything this project created, in reverse order. Run from your laptop
# with your own admin AWS CLI profile. Asks before doing anything.
set -euo pipefail

PROJECT="${PROJECT:-cicd-lab}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
ART_BUCKET="${PROJECT}-artifacts-${ACCOUNT_ID}"
DUMMY_SHA=0000000000000000000000000000000000000000
cd "$(dirname "$0")/.."

TFV_PROJECT="$(sed -n 's/^[[:space:]]*project[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' infra/platform/terraform.tfvars 2>/dev/null | head -1)"
if [ -n "$TFV_PROJECT" ] && [ "$TFV_PROJECT" != "$PROJECT" ]; then
  echo "terraform.tfvars says project = \"$TFV_PROJECT\" but PROJECT=$PROJECT. Re-run with PROJECT=$TFV_PROJECT." >&2
  exit 1
fi

echo "This destroys dev + prod apps, the runner, VPC, artifacts and ALL state in account $ACCOUNT_ID ($REGION)."
read -r -p "Type the project name ($PROJECT) to continue: " ok
[ "$ok" = "$PROJECT" ] || { echo "Aborted."; exit 1; }

for ENV in prod dev; do
  echo "== Destroying app ($ENV)"
  aws dynamodb update-table --region "$REGION" --table-name "${PROJECT}-${ENV}-items" \
    --no-deletion-protection-enabled >/dev/null 2>&1 || true
  tofu -chdir=infra/app init -input=false -reconfigure \
    -backend-config="bucket=$STATE_BUCKET" -backend-config="key=app/$ENV.tfstate" -backend-config="region=$REGION" >/dev/null
  # Deletion protection was switched off above, so the destroy can delete prod's table.
  tofu -chdir=infra/app destroy -auto-approve -input=false \
    -var "env=$ENV" -var "build_sha=$DUMMY_SHA" -var "region=$REGION" -var "project=$PROJECT" \
    -var "artifact_bucket=$ART_BUCKET" -var "app_boundary_arn=arn:aws:iam::${ACCOUNT_ID}:policy/${PROJECT}-${ENV}-app-boundary"
done

echo "== Destroying platform (runner, VPC, IAM, artifacts bucket)"
tofu -chdir=infra/platform init -input=false -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$REGION" >/dev/null
tofu -chdir=infra/platform destroy -auto-approve -input=false -var "region=$REGION" -var "project=$PROJECT" \
  -var "github_repo=unused/unused"

echo "== Deleting GitHub token from SSM"
aws ssm delete-parameter --region "$REGION" --name "/$PROJECT/github-pat" 2>/dev/null || true

echo "== Emptying and deleting state bucket"
python3 - "$STATE_BUCKET" "$REGION" <<'PY'
import json, subprocess, sys
bucket, region = sys.argv[1], sys.argv[2]
while True:
    out = subprocess.run(["aws", "s3api", "list-object-versions", "--bucket", bucket, "--region", region,
                          "--max-items", "500", "--output", "json"], capture_output=True, text=True, check=True).stdout
    data = json.loads(out or "{}")
    objs = [{"Key": o["Key"], "VersionId": o["VersionId"]} for o in data.get("Versions", []) + data.get("DeleteMarkers", [])]
    if not objs:
        break
    subprocess.run(["aws", "s3api", "delete-objects", "--bucket", bucket, "--region", region,
                    "--delete", json.dumps({"Objects": objs, "Quiet": True})], check=True)
PY
aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$REGION"

echo
echo "All gone. Last step by hand: remove the offline runner under GitHub repo Settings > Actions > Runners,"
echo "and revoke the fine-grained token you created for it."
