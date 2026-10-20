# Everything you run from your laptop. `make help` lists targets.
# Uses your normal AWS CLI profile (export AWS_PROFILE=... first if needed).
SHELL := /bin/bash

PROJECT    ?= cicd-lab
AWS_REGION ?= us-east-1
ENV        ?= dev
export PROJECT AWS_REGION

ACCOUNT_ID    = $(shell aws sts get-caller-identity --query Account --output text)
STATE_BUCKET  = $(PROJECT)-tfstate-$(ACCOUNT_ID)
TOFU_PLATFORM = tofu -chdir=infra/platform

.PHONY: help test test-py test-iac lock bootstrap-state pat platform-init platform-plan platform-apply \
        gh-vars bb-vars runner-start runner-stop runner-status runner-shell invoke teardown

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

## --- Free, local, no AWS ---------------------------------------------------
test: test-py test-iac ## Run every local check (same as CI)

test-py: ## Python unit tests + release script tests
	python3 -m pytest -q app/tests scripts/ci/tests sandbox-guardrails/tests

test-iac: ## tofu fmt + validate + mocked tests for every stack
	scripts/ci/test-iac.sh

lock: ## Refresh provider lock files for mac, Linux and the arm64 runner
	@for s in infra/modules/lambda-app infra/platform infra/app; do \
	  tofu -chdir=$$s init -backend=false -input=false >/dev/null && \
	  tofu -chdir=$$s providers lock -platform=darwin_arm64 -platform=darwin_amd64 \
	    -platform=linux_amd64 -platform=linux_arm64 || exit 1; done

## --- One-time setup in your AWS account ------------------------------------
bootstrap-state: ## Create the S3 state bucket
	scripts/bootstrap-state.sh

pat: ## Store the GitHub runner token in SSM (prompts, never echoes)
	@read -r -s -p "Paste GitHub fine-grained token: " T; echo; \
	aws ssm put-parameter --region $(AWS_REGION) --name /$(PROJECT)/github-pat \
	  --type SecureString --overwrite --value "$$T" >/dev/null && echo "Saved /$(PROJECT)/github-pat"

platform-init:
	$(TOFU_PLATFORM) init -input=false -reconfigure \
	  -backend-config="bucket=$(STATE_BUCKET)" -backend-config="region=$(AWS_REGION)"

platform-plan: platform-init ## Plan the runner, VPC, IAM, artifacts bucket
	$(TOFU_PLATFORM) plan -var region=$(AWS_REGION) -var project=$(PROJECT)

platform-apply: platform-init ## Create/update them (asks for confirmation)
	$(TOFU_PLATFORM) apply -var region=$(AWS_REGION) -var project=$(PROJECT)

gh-vars: ## Set the repo variables the workflows read (needs gh CLI, run inside the repo)
	@$(TOFU_PLATFORM) output -json ci_variables | \
	  python3 -c 'import json,sys;[print(k,v) for k,v in json.load(sys.stdin).items() if v]' | \
	  while read -r k v; do gh variable set "$$k" --body "$$v"; done

bb-vars: ## Print the Bitbucket repository variables to add (work pattern)
	@echo "Add these in Bitbucket: Repository settings > Pipelines > Repository variables"
	@$(TOFU_PLATFORM) output -json ci_variables | \
	  python3 -c 'import json,sys;[print(f"  {k} = {v}") for k,v in json.load(sys.stdin).items() if v]'

## --- Day to day -------------------------------------------------------------
runner-start: ## Start the runner (do this before you push)
	scripts/runner-power.sh start
runner-stop: ## Stop the runner when you're done (saves ~90% of its cost)
	scripts/runner-power.sh stop
runner-status:
	scripts/runner-power.sh status
runner-shell: ## Open a shell on the runner via SSM (no SSH, no open ports)
	aws ssm start-session --region $(AWS_REGION) --target "$$($(TOFU_PLATFORM) output -raw runner_instance_id)"

invoke: ## Call the deployed Lambda in ENV (default dev)
	aws lambda invoke --region $(AWS_REGION) --function-name $(PROJECT)-$(ENV)-api \
	  --cli-binary-format raw-in-base64-out --payload '{"action":"health"}' /dev/stdout

teardown: ## Destroy EVERYTHING (asks first)
	scripts/teardown.sh
