# IAM role chain, so dev and prod are separated inside ONE AWS account (the
# same shape as work's "OIDC base role -> provisioner role"):
#
#   non-prod base role                  can: publish build artifacts, read
#     (runner instance role in ec2 mode, non-prod config, assume non-prod
#      or <project>-ci via GitHub OIDC)  deploy roles. Never prod.
#        +--> <project>-deploy-dev      manages only <project>-dev-* resources
#                                       and app/dev.tfstate
#
#   prod base role <project>-ci-prod    GitHub OIDC, trusted ONLY for workflows
#     (both modes)                       running on refs/heads/main. Can read
#                                        artifacts and prod config, assume the
#        +--> <project>-deploy-prod      prod deploy role. Cannot publish builds.
#
# The self-hosted runner never holds prod-capable credentials: prod jobs always
# run on GitHub-hosted runners with the main-only OIDC role.
#
# Deploy roles may create IAM roles only if they carry that env's boundary, so a
# pipeline run can never mint a role that reaches another env.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  arn_pfx   = "arn:${data.aws_partition.current.partition}"
  state_bkt = "${var.project}-tfstate-${local.account}"
  envs      = toset(var.environments)
  prod_envs = toset([for e in var.environments : e if contains(var.prod_environments, e)])
  nonprod   = setsubtract(local.envs, local.prod_envs)

  use_oidc     = var.runner_mode == "github-oidc"
  org_boundary = var.org_permissions_boundary_arn != "" ? var.org_permissions_boundary_arn : null

  # Boundary carried by each env's deploy role and every role it creates: one
  # the account owner supplies (sandbox), else a per-env one created below.
  env_boundary_arn = {
    for e in local.envs : e => lookup(var.org_env_boundary_arns, e, aws_iam_policy.app_boundary[e].arn)
  }

  nonprod_base_arn = local.use_runner ? aws_iam_role.runner[0].arn : aws_iam_role.ci[0].arn
  nonprod_base_id  = local.use_runner ? aws_iam_role.runner[0].id : aws_iam_role.ci[0].id

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# --- GitHub OIDC provider (always: prod always deploys through OIDC) ---------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# --- Non-prod base role: runner (ec2 mode) ----------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  count                = local.use_runner ? 1 : 0
  name                 = "${var.project}-runner"
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume.json
  permissions_boundary = local.org_boundary
}

resource "aws_iam_instance_profile" "runner" {
  count = local.use_runner ? 1 : 0
  name  = "${var.project}-runner"
  role  = aws_iam_role.runner[0].name
}

# Lets you open a shell with `aws ssm start-session` instead of SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = local.use_runner ? 1 : 0
  role       = aws_iam_role.runner[0].name
  policy_arn = "${local.arn_pfx}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- Non-prod base role: GitHub OIDC, any branch (github-oidc mode) ---------

data "aws_iam_policy_document" "github_any_ref" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "ci" {
  count                = local.use_oidc ? 1 : 0
  name                 = "${var.project}-ci"
  assume_role_policy   = data.aws_iam_policy_document.github_any_ref.json
  permissions_boundary = local.org_boundary
  max_session_duration = 3600
}

data "aws_iam_policy_document" "nonprod_base" {
  dynamic "statement" {
    for_each = local.use_runner ? [1] : []
    content {
      sid       = "GithubPat"
      actions   = ["ssm:GetParameter"]
      resources = ["${local.arn_pfx}:ssm:${var.region}:${local.account}:parameter/${var.project}/github-pat"]
    }
  }
  dynamic "statement" {
    for_each = local.use_runner ? [1] : []
    content {
      sid       = "DecryptPatViaSsm"
      actions   = ["kms:Decrypt"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${var.region}.amazonaws.com"]
      }
    }
  }
  statement {
    sid       = "ArtifactsList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  # Put is allowed, but the first version of each build is the one that gets
  # deployed (see _deploy.yml), and nobody can delete versions.
  statement {
    sid       = "ArtifactsPublish"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/builds/*"]
  }
  statement {
    sid       = "NonProdConfig"
    actions   = ["ssm:GetParameter"]
    resources = [for e in local.nonprod : "${local.arn_pfx}:ssm:${var.region}:${local.account}:parameter/${var.project}/env/${e}/config"]
  }
  statement {
    sid       = "AssumeNonProdDeployRoles"
    actions   = ["sts:AssumeRole"]
    resources = [for e in local.nonprod : "${local.arn_pfx}:iam::${local.account}:role/${var.project}-deploy-${e}"]
  }
}

resource "aws_iam_role_policy" "nonprod_base" {
  name   = "${var.project}-nonprod-base"
  role   = local.nonprod_base_id
  policy = data.aws_iam_policy_document.nonprod_base.json
}

# --- Prod base role: GitHub OIDC, main branch only (both modes) -------------
# The sub claim is "repo:<owner>/<repo>:ref:refs/heads/main" only for jobs on
# main that do NOT declare a GitHub `environment:` (that would change the sub).
# A workflow edited on another branch gets a different sub and is refused here,
# whatever its YAML says.

data "aws_iam_policy_document" "github_main_only" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ci_prod" {
  name                 = "${var.project}-ci-prod"
  assume_role_policy   = data.aws_iam_policy_document.github_main_only.json
  permissions_boundary = local.org_boundary
  max_session_duration = 3600
}

data "aws_iam_policy_document" "prod_base" {
  statement {
    sid       = "ArtifactsReadOnly"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    sid       = "ArtifactObjectsReadOnly"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/builds/*"]
  }
  statement {
    sid       = "ProdConfig"
    actions   = ["ssm:GetParameter"]
    resources = [for e in local.prod_envs : "${local.arn_pfx}:ssm:${var.region}:${local.account}:parameter/${var.project}/env/${e}/config"]
  }
  statement {
    sid       = "AssumeProdDeployRoles"
    actions   = ["sts:AssumeRole"]
    resources = [for e in local.prod_envs : "${local.arn_pfx}:iam::${local.account}:role/${var.project}-deploy-${e}"]
  }
}

resource "aws_iam_role_policy" "prod_base" {
  name   = "${var.project}-prod-base"
  role   = aws_iam_role.ci_prod.id
  policy = data.aws_iam_policy_document.prod_base.json
}

# --- Per-environment boundary (skipped where the account owner supplies one) -
# Caps the deploy role AND every app role it creates. Self-propagating: a role
# under it can only create roles under it.

data "aws_iam_policy_document" "app_boundary" {
  for_each = local.envs

  statement {
    sid     = "OwnEnvResources"
    actions = ["lambda:*", "dynamodb:*", "logs:*"]
    resources = [
      "${local.arn_pfx}:lambda:${var.region}:${local.account}:function:${var.project}-${each.key}-*",
      "${local.arn_pfx}:dynamodb:${var.region}:${local.account}:table/${var.project}-${each.key}-*",
      "${local.arn_pfx}:logs:${var.region}:${local.account}:log-group:/aws/lambda/${var.project}-${each.key}-*",
      "${local.arn_pfx}:logs:${var.region}:${local.account}:log-group:/aws/lambda/${var.project}-${each.key}-*:*",
    ]
  }
  statement {
    sid     = "OwnState"
    actions = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${local.arn_pfx}:s3:::${local.state_bkt}",
      "${local.arn_pfx}:s3:::${local.state_bkt}/app/${each.key}.tfstate",
      "${local.arn_pfx}:s3:::${local.state_bkt}/app/${each.key}.tfstate.tflock",
    ]
  }
  statement {
    sid       = "ReadArtifacts"
    actions   = ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetObject", "s3:GetObjectVersion"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/builds/*"]
  }
  statement {
    sid = "DescribeAndVpcNetworking"
    actions = [
      "logs:DescribeLogGroups", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcs",
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }
  statement {
    sid = "OwnEnvRolesOnlyUnderThisBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePermissionsBoundary",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = ["${local.arn_pfx}:iam::${local.account}:policy/${var.project}-${each.key}-app-boundary"]
    }
  }
  statement {
    sid = "OwnEnvRolesManage"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:ListRoleTags", "iam:PassRole",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
  }
  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["${local.arn_pfx}:iam::${local.account}:policy/${var.project}-${each.key}-app-boundary"]
  }
}

resource "aws_iam_policy" "app_boundary" {
  for_each = local.envs
  name     = "${var.project}-${each.key}-app-boundary"
  policy   = data.aws_iam_policy_document.app_boundary[each.key].json
}

# --- Per-environment deploy roles -------------------------------------------

data "aws_iam_policy_document" "deploy_assume" {
  for_each = local.envs
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [contains(var.prod_environments, each.key) ? aws_iam_role.ci_prod.arn : local.nonprod_base_arn]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each             = local.envs
  name                 = "${var.project}-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume[each.key].json
  permissions_boundary = local.env_boundary_arn[each.key]
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.envs

  # State: only this env's file and its lock file. "env:/" is where the S3
  # backend lists workspaces during init.
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = ["${local.arn_pfx}:s3:::${local.state_bkt}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/${each.key}.tfstate*", "env:/*", "env:/"]
    }
  }
  statement {
    sid     = "StateRW"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${local.arn_pfx}:s3:::${local.state_bkt}/app/${each.key}.tfstate",
      "${local.arn_pfx}:s3:::${local.state_bkt}/app/${each.key}.tfstate.tflock",
    ]
  }

  # Artifacts: read-only. Deploy roles promote builds, they never create them.
  statement {
    sid       = "ArtifactsList"
    actions   = ["s3:ListBucketVersions"]
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    sid       = "ArtifactsRead"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.artifacts.arn}/builds/*"]
  }

  statement {
    sid       = "Lambda"
    actions   = ["lambda:*"]
    resources = ["${local.arn_pfx}:lambda:${var.region}:${local.account}:function:${var.project}-${each.key}-*"]
  }
  statement {
    sid       = "DynamoDb"
    actions   = ["dynamodb:*"]
    resources = ["${local.arn_pfx}:dynamodb:${var.region}:${local.account}:table/${var.project}-${each.key}-*"]
  }
  statement {
    sid     = "LogGroups"
    actions = ["logs:*"]
    resources = [
      "${local.arn_pfx}:logs:${var.region}:${local.account}:log-group:/aws/lambda/${var.project}-${each.key}-*",
      "${local.arn_pfx}:logs:${var.region}:${local.account}:log-group:/aws/lambda/${var.project}-${each.key}-*:*",
    ]
  }
  statement {
    sid       = "Describe"
    actions   = ["logs:DescribeLogGroups", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }

  statement {
    sid = "AppRolesWithBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePermissionsBoundary",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.env_boundary_arn[each.key]]
    }
  }
  statement {
    sid = "AppRolesManage"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole", "iam:ListRoleTags",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
  }
  statement {
    sid       = "PassAppRolesToLambda"
    actions   = ["iam:PassRole"]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = [local.env_boundary_arn[each.key]]
  }

  # Never make a function public, never weaken a boundary, never rewrite trust.
  statement {
    sid    = "DenyPublicLambdaAndEscapes"
    effect = "Deny"
    actions = [
      "lambda:AddPermission", "lambda:CreateFunctionUrlConfig", "lambda:UpdateFunctionUrlConfig",
      "lambda:AddLayerVersionPermission",
      "iam:DeleteRolePermissionsBoundary", "iam:UpdateAssumeRolePolicy",
      "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.envs
  name     = "deploy-${each.key}"
  role     = aws_iam_role.deploy[each.key].id
  policy   = data.aws_iam_policy_document.deploy[each.key].json
}

# --- Per-env config, outside the repo (stands in for Config Graph infraConfig)

resource "aws_ssm_parameter" "env_config" {
  for_each = local.envs
  name     = "/${var.project}/env/${each.key}/config"
  type     = "String"
  value = jsonencode({
    deploy_role_arn           = aws_iam_role.deploy[each.key].arn
    app_boundary_arn          = local.env_boundary_arn[each.key]
    lambda_subnet_ids         = var.lambda_in_vpc ? aws_subnet.private[*].id : []
    lambda_security_group_ids = var.lambda_in_vpc ? [aws_security_group.lambda.id] : []
  })
}
