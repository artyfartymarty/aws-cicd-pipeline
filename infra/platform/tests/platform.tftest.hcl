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
    condition     = length(aws_security_group.runner.ingress) == 0
    error_message = "Runner must accept no inbound traffic."
  }
  assert {
    condition     = aws_instance.runner.metadata_options[0].http_tokens == "required"
    error_message = "Runner must use IMDSv2."
  }
  assert {
    condition     = aws_instance.runner.instance_type == "t4g.micro"
    error_message = "Default runner size changed; check the cost estimate in the README."
  }
  assert {
    condition     = aws_instance.runner.instance_market_options[0].market_type == "spot"
    error_message = "Runner should default to Spot."
  }
  assert {
    condition     = strcontains(aws_instance.runner.user_data, "artyfartymarty/aws-cicd-pipeline")
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
    condition     = length(aws_instance.runner.instance_market_options) == 0
    error_message = "No market options expected for on-demand."
  }
}
