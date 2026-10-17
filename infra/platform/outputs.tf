output "runner_instance_id" {
  value = aws_instance.runner.id
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
  }
}

output "github_environment_variables" {
  description = "Per-environment variables (GitHub Environments dev/prod). Plays the role of Config Graph infraConfig: env settings live outside the repo."
  value = {
    for e in local.envs : e => {
      DEPLOY_ROLE_ARN  = aws_iam_role.deploy[e].arn
      APP_BOUNDARY_ARN = aws_iam_policy.app_boundary[e].arn
    }
  }
}
