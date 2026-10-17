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

run "dev_and_prod_get_separate_deploy_roles" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.deploy)) == toset(["dev", "prod"])
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
    condition     = alltrue([for r in aws_iam_role.deploy : r.permissions_boundary == var.org_permissions_boundary_arn])
    error_message = "Deploy roles must carry the org boundary."
  }
  assert {
    condition     = length(aws_iam_policy.app_boundary) == 0
    error_message = "Per-env app boundaries are replaced by the org boundary."
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
    condition     = output.github_variables.RUNS_ON == "\"ubuntu-latest\""
    error_message = "OIDC mode should run on GitHub-hosted runners."
  }
}
