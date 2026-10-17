# Offline tests: `tofu test` with a mocked AWS provider. No AWS calls, no cost.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/cicd-lab-dev-app" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/lambda/cicd-lab-dev-api" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { arn = "arn:aws:dynamodb:us-east-1:111111111111:table/cicd-lab-dev-items" }
  }
}

variables {
  env              = "dev"
  build_sha        = "0123456789abcdef0123456789abcdef01234567"
  artifact_bucket  = "cicd-lab-artifacts-111111111111"
  app_boundary_arn = "arn:aws:iam::111111111111:policy/cicd-lab-dev-app-boundary"
}

run "dev_plan_uses_the_build_artifact" {
  command = plan

  assert {
    condition     = module.app.s3_key == "builds/${var.build_sha}/app.zip"
    error_message = "Lambda must deploy the exact build artifact."
  }
  assert {
    condition     = module.app.function_name == "cicd-lab-dev-api"
    error_message = "Names must carry the project prefix the runner role is scoped to."
  }
  assert {
    condition     = module.app.permissions_boundary == var.app_boundary_arn
    error_message = "App role must carry the permissions boundary or the runner cannot create it."
  }
  assert {
    condition     = module.app.deletion_protection == false
    error_message = "Dev table should be disposable."
  }
}

run "prod_protects_its_table" {
  command = plan
  variables {
    env = "prod"
  }
  assert {
    condition     = module.app.deletion_protection
    error_message = "Prod table must have deletion protection."
  }
}

run "rejects_unknown_env" {
  command = plan
  variables {
    env = "qa"
  }
  expect_failures = [var.env]
}

run "rejects_short_sha" {
  command = plan
  variables {
    build_sha = "abc123"
  }
  expect_failures = [var.build_sha]
}

run "sandbox_lambda_runs_in_private_subnets" {
  command = plan
  variables {
    lambda_subnet_ids         = ["subnet-aaa", "subnet-bbb"]
    lambda_security_group_ids = ["sg-123"]
  }
  assert {
    condition     = module.app.in_vpc
    error_message = "Lambda must be attached to the private subnets when they are given."
  }
}

run "pins_the_artifact_version" {
  command = plan
  variables {
    artifact_version = "3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY"
  }
  assert {
    condition     = module.app.s3_object_version == "3HL4kqtJlcpXroDTDmJ.rmSpXd3dIbrHY"
    error_message = "Lambda must deploy the pinned object version."
  }
}
