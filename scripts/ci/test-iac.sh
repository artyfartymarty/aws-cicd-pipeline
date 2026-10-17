#!/usr/bin/env bash
# tofu fmt + validate + mocked tests for every stack. Offline, no AWS, no cost.
# Used by `make test-iac`, GitHub ci.yml and bitbucket-pipelines.yml.
set -euo pipefail
tofu fmt -check -recursive infra
for stack in infra/modules/lambda-app infra/platform infra/app; do
  echo "--- $stack"
  tofu -chdir="$stack" init -backend=false -input=false >/dev/null
  tofu -chdir="$stack" validate
  tofu -chdir="$stack" test
done
