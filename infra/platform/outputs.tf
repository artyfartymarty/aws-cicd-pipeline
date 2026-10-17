output "runner_instance_id" {
  value = local.use_runner ? aws_instance.runner[0].id : null
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "state_bucket" {
  value = local.state_bkt
}

output "deploy_role_arns" {
  value = { for e in local.envs : e => aws_iam_role.deploy[e].arn }
}

output "ci_variables" {
  description = "Repository variables the CI files read (GitHub: `make gh-vars`; Bitbucket: `make bb-vars` prints them). Per-env settings are in SSM, not CI."
  value = {
    AWS_REGION           = var.region
    PROJECT              = var.project
    TF_STATE_BUCKET      = local.state_bkt
    ARTIFACT_BUCKET      = aws_s3_bucket.artifacts.bucket
    AWS_CI_ROLE_ARN      = local.use_oidc ? aws_iam_role.ci[0].arn : "" # empty in ec2 mode: the runner has credentials
    AWS_CI_PROD_ROLE_ARN = aws_iam_role.ci_prod.arn
    RUNS_ON              = local.bitbucket ? "" : local.use_runner ? jsonencode(["self-hosted", "aws"]) : jsonencode("ubuntu-latest") # GitHub only
  }
}
