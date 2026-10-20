# Offline tests: `tofu test` with a mocked AWS provider. No AWS calls, no cost.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/mock-boundary" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
}

variables {
  github_repo = "artyfartymarty/aws-cicd-pipeline"
}

run "runner_is_locked_down_and_cheap" {
  command = plan

  assert {
    condition     = length(aws_security_group.runner[0].ingress) == 0
    error_message = "Runner must accept no inbound traffic."
  }
  assert {
    condition     = aws_instance.runner[0].metadata_options[0].http_tokens == "required"
    error_message = "Runner must use IMDSv2."
  }
  assert {
    condition     = aws_instance.runner[0].instance_type == "t4g.micro"
    error_message = "Default runner size changed; check the cost estimate in the README."
  }
  assert {
    condition     = aws_instance.runner[0].instance_market_options[0].market_type == "spot"
    error_message = "Runner should default to Spot."
  }
  assert {
    condition     = strcontains(aws_instance.runner[0].user_data, "artyfartymarty/aws-cicd-pipeline")
    error_message = "User data must register to the configured repo."
  }
  assert {
    condition     = aws_s3_bucket.artifacts.bucket == "cicd-lab-artifacts-111111111111"
    error_message = "Artifact bucket name must be deterministic."
  }
}

run "dev_qa_and_prod_get_separate_deploy_roles" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.deploy)) == toset(["dev", "qa", "prod"])
    error_message = "Expected one deploy role per environment."
  }
  assert {
    condition     = aws_iam_role.deploy["prod"].name == "cicd-lab-deploy-prod"
    error_message = "Prod deploy role name must match what the runner is allowed to assume."
  }
  assert {
    condition     = aws_iam_policy.app_boundary["dev"].name == "cicd-lab-dev-app-boundary"
    error_message = "Each env needs its own app boundary."
  }
}

run "on_demand_when_spot_disabled" {
  command = plan
  variables {
    use_spot = false
  }
  assert {
    condition     = length(aws_instance.runner[0].instance_market_options) == 0
    error_message = "No market options expected for on-demand."
  }
}

run "sandbox_mode_has_no_internet_path" {
  command = plan
  variables {
    runner_mode                  = "github-oidc"
    lambda_in_vpc                = true
    org_permissions_boundary_arn = "arn:aws:iam::111111111111:policy/yield-boundary"
    org_env_boundary_arns = {
      dev  = "arn:aws:iam::111111111111:policy/yield-dev-boundary"
      prod = "arn:aws:iam::111111111111:policy/yield-prod-boundary"
    }
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_instance.runner) == 0
    error_message = "Sandbox mode must not create an internet gateway or a runner."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch != true])
    error_message = "Private subnets must not hand out public IPs."
  }
  assert {
    condition     = length(aws_iam_role.ci) == 1 && aws_iam_role.ci[0].permissions_boundary == var.org_permissions_boundary_arn
    error_message = "The OIDC role must exist and carry the org boundary."
  }
  assert {
    condition     = aws_iam_role.deploy["dev"].permissions_boundary == "arn:aws:iam::111111111111:policy/yield-dev-boundary"
    error_message = "The dev deploy role must carry the dev boundary IT supplies."
  }
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_vpc_endpoint.dynamodb.route_table_ids) == 1
    error_message = "Expected two private subnets with a DynamoDB endpoint on their route table."
  }
}

run "oidc_trusts_only_this_repo" {
  command = plan
  variables {
    runner_mode = "github-oidc"
  }
  assert {
    condition     = output.ci_variables.RUNS_ON == "\"ubuntu-latest\""
    error_message = "OIDC mode should run on GitHub-hosted runners."
  }
}

run "runner_can_never_reach_prod" {
  command = plan

  override_resource {
    target = aws_iam_role.ci_prod
    values = { arn = "arn:aws:iam::111111111111:role/cicd-lab-ci-prod" }
  }
  override_resource {
    target = aws_iam_role.runner
    values = { arn = "arn:aws:iam::111111111111:role/cicd-lab-runner" }
  }

  assert {
    condition     = one(one(data.aws_iam_policy_document.deploy_assume["prod"].statement).principals).identifiers == toset(["arn:aws:iam::111111111111:role/cicd-lab-ci-prod"])
    error_message = "Prod deploy role must trust only the main-only OIDC role."
  }
  assert {
    condition     = one(one(data.aws_iam_policy_document.deploy_assume["dev"].statement).principals).identifiers == toset(["arn:aws:iam::111111111111:role/cicd-lab-runner"])
    error_message = "Dev deploy role should trust the runner in ec2 mode."
  }
  assert {
    condition     = one(one(data.aws_iam_policy_document.deploy_assume["qa"].statement).principals).identifiers == toset(["arn:aws:iam::111111111111:role/cicd-lab-runner"])
    error_message = "QA is non-prod: its deploy role should trust the runner, never the prod role."
  }
  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.nonprod_base.statement :
      alltrue([for r in st.resources : !strcontains(r, "prod")])
    ])
    error_message = "The runner / non-prod base role must not reference any prod resource."
  }
  assert {
    condition = one([
      for c in one(data.aws_iam_policy_document.ci_prod_only.statement).condition : c.values if c.variable == "token.actions.githubusercontent.com:sub"
    ]) == tolist(["repo:artyfartymarty/aws-cicd-pipeline:ref:refs/heads/main"])
    error_message = "Prod OIDC role must be limited to the main branch."
  }
  assert {
    condition     = aws_ssm_parameter.env_config["prod"].name == "/cicd-lab/env/prod/config"
    error_message = "Per-env config must be in SSM."
  }
}

# Work pattern: Bitbucket Pipelines OIDC instead of GitHub.
run "bitbucket_mode_trusts_only_this_repo_and_prod_environment" {
  command = plan
  variables {
    github_repo             = ""
    runner_mode             = "bitbucket-oidc"
    lambda_in_vpc           = true
    bitbucket_oidc_url      = "https://api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc"
    bitbucket_oidc_audience = "ari:cloud:bitbucket::workspace/11111111-2222-3333-4444-555555555555"
    bitbucket_repo_uuid     = "{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
    bitbucket_deployment_uuids = {
      dev  = "{00000000-0000-0000-0000-00000000000d}"
      prod = "{00000000-0000-0000-0000-00000000000f}"
    }
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_instance.runner) == 0
    error_message = "Bitbucket mode must not create an internet gateway or a runner."
  }
  assert {
    condition     = aws_iam_openid_connect_provider.ci[0].url == "https://api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc"
    error_message = "The OIDC provider must be the workspace's Bitbucket issuer."
  }
  assert {
    condition = one([
      for c in one(data.aws_iam_policy_document.ci_prod_only.statement).condition : c.values
      if c.variable == "api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc:sub"
    ]) == tolist(["{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}:{00000000-0000-0000-0000-00000000000f}:*"])
    error_message = "Prod role must trust only steps in the prod deployment environment of this repo."
  }
  assert {
    condition = one([
      for c in one(data.aws_iam_policy_document.ci_any_ref.statement).condition : c.values
      if c.variable == "api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc:sub"
    ]) == tolist(["{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}:*"])
    error_message = "Non-prod role must trust only this repo."
  }
  assert {
    condition     = output.ci_variables.RUNS_ON == ""
    error_message = "RUNS_ON is a GitHub-only variable."
  }
}

run "bitbucket_mode_refuses_missing_prod_environment" {
  command = plan
  variables {
    github_repo             = ""
    runner_mode             = "bitbucket-oidc"
    bitbucket_oidc_url      = "https://api.bitbucket.org/2.0/workspaces/acme/pipelines-config/identity/oidc"
    bitbucket_oidc_audience = "ari:cloud:bitbucket::workspace/11111111-2222-3333-4444-555555555555"
    bitbucket_repo_uuid     = "{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
  }
  expect_failures = [aws_iam_role.ci_prod]
}
