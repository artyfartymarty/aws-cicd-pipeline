#!/usr/bin/env bash
# Package the app once and store it as builds/<sha>/app.zip (work: publish to
# JFrog). A build that already exists is never overwritten. Shared by GitHub
# (_build.yml) and Bitbucket (bitbucket-pipelines.yml).
# Env: BUILD_SHA ARTIFACT_BUCKET, optional BRANCH RUN_ID ACTOR SUMMARY_FILE
set -euo pipefail
: "${BUILD_SHA:?}" "${ARTIFACT_BUCKET:?}"
SUMMARY="${SUMMARY_FILE:-/dev/null}"
KEY="builds/$BUILD_SHA/app.zip"

if aws s3api head-object --bucket "$ARTIFACT_BUCKET" --key "$KEY" >/dev/null 2>&1; then
  echo "Build $BUILD_SHA already exists, reusing it."
  exit 0
fi
mkdir -p dist
(cd app/src && zip -qr -X ../../dist/app.zip . -x '__pycache__/*')
aws s3api put-object --bucket "$ARTIFACT_BUCKET" --key "$KEY" --body dist/app.zip \
  --metadata "branch=${BRANCH:-unknown},run=${RUN_ID:-unknown},actor=${ACTOR:-unknown}" >/dev/null
{ echo "### Build \`$BUILD_SHA\`"; echo "Uploaded s3://$ARTIFACT_BUCKET/$KEY from \`${BRANCH:-unknown}\`"; } >>"$SUMMARY"
echo "Uploaded s3://$ARTIFACT_BUCKET/$KEY"
