output "runner_instance_id" {
  value = local.use_runner ? aws_instance.runner[0].id : null
}

output "base_role_arn" {
  value = local.base_role_arn
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "state_bucket" {
  value = local.state_bkt
}

output "github_variables" {
  description = "Repository-level variables the workflows read. `make gh-vars` sets them."
  value = {
    AWS_REGION      = var.region
    PROJECT         = var.project
    TF_STATE_BUCKET = local.state_bkt
    ARTIFACT_BUCKET = aws_s3_bucket.artifacts.bucket
    # Empty in ec2 mode: the runner already has AWS credentials.
    AWS_CI_ROLE_ARN = local.use_oidc ? aws_iam_role.ci[0].arn : ""
    RUNS_ON         = local.use_runner ? jsonencode(["self-hosted", "aws"]) : jsonencode("ubuntu-latest")
  }
}

output "github_environment_variables" {
  description = "Per-environment variables (GitHub Environments dev/prod). Plays the role of Config Graph infraConfig: env settings live outside the repo."
  value = {
    for e in local.envs : e => {
      DEPLOY_ROLE_ARN           = aws_iam_role.deploy[e].arn
      APP_BOUNDARY_ARN          = local.app_boundary_arn[e]
      TF_VAR_lambda_subnet_ids  = jsonencode(var.lambda_in_vpc ? aws_subnet.private[*].id : [])
      LAMBDA_SECURITY_GROUP_IDS = jsonencode(var.lambda_in_vpc ? [aws_security_group.lambda.id] : [])
    }
  }
}
