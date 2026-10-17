# Two layers of IAM, so dev and prod are separated inside ONE AWS account
# (the same shape the team sandbox account will use):
#
#   base role                        can only: write build artifacts and assume a
#     (runner instance role, or      deploy role (+ read the runner's GitHub token
#      the GitHub OIDC role)         in ec2 mode).
#        +--> <project>-deploy-dev   manages only <project>-dev-* resources and
#        |                           the app/dev.tfstate state file.
#        +--> <project>-deploy-prod  manages only <project>-prod-* resources and
#                                    the app/prod.tfstate state file.
#
# A deploy role may create IAM roles only if they carry that env's permissions
# boundary, so a pipeline run can never mint a role that reaches the other env.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  arn_pfx   = "arn:${data.aws_partition.current.partition}"
  state_bkt = "${var.project}-tfstate-${local.account}"
  envs      = toset(var.environments)
}

# --- Base role: the self-hosted runner's instance role, or the GitHub OIDC role

locals {
  use_oidc      = var.runner_mode == "github-oidc"
  org_boundary  = var.org_permissions_boundary_arn != "" ? var.org_permissions_boundary_arn : null
  base_role_arn = local.use_runner ? aws_iam_role.runner[0].arn : aws_iam_role.ci[0].arn
  base_role_id  = local.use_runner ? aws_iam_role.runner[0].id : aws_iam_role.ci[0].id
  # Boundary each env's app roles must carry: the org one if the account forces
  # one, otherwise a per-env boundary created below.
  app_boundary_arn = {
    for e in local.envs : e => local.org_boundary != null ? local.org_boundary : aws_iam_policy.app_boundary[e].arn
  }
}

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

# GitHub OIDC: short-lived credentials for workflows in github_repo only.
resource "aws_iam_openid_connect_provider" "github" {
  count          = local.use_oidc && var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.use_oidc && !var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  count = local.use_oidc ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[*].arn : data.aws_iam_openid_connect_provider.github[*].arn
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
  assume_role_policy   = data.aws_iam_policy_document.github_assume[0].json
  permissions_boundary = local.org_boundary
  max_session_duration = 3600
}

data "aws_iam_policy_document" "base" {
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
  statement {
    sid       = "ArtifactsPublish"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/builds/*"]
  }
  statement {
    sid       = "AssumeDeployRoles"
    actions   = ["sts:AssumeRole"]
    resources = [for e in local.envs : "${local.arn_pfx}:iam::${local.account}:role/${var.project}-deploy-${e}"]
  }
}

resource "aws_iam_role_policy" "base" {
  name   = "${var.project}-base-scoped"
  role   = local.base_role_id
  policy = data.aws_iam_policy_document.base.json
}

# --- Per-environment permissions boundary for app roles ---------------------
# Skipped when the account forces its own boundary (org_permissions_boundary_arn).

data "aws_iam_policy_document" "app_boundary" {
  for_each = local.org_boundary == null ? local.envs : toset([])

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.arn_pfx}:logs:${var.region}:${local.account}:log-group:/aws/lambda/${var.project}-${each.key}-*"]
  }
  statement {
    sid = "OwnTables"
    actions = [
      "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
      "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan",
    ]
    resources = ["${local.arn_pfx}:dynamodb:${var.region}:${local.account}:table/${var.project}-${each.key}-*"]
  }
  statement {
    sid = "LambdaInVpcNetworking"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets",
      "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_boundary" {
  for_each = local.org_boundary == null ? local.envs : toset([])
  name     = "${var.project}-${each.key}-app-boundary"
  policy   = data.aws_iam_policy_document.app_boundary[each.key].json
}

# --- Per-environment deploy roles -------------------------------------------

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [local.base_role_arn]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each             = local.envs
  name                 = "${var.project}-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
  permissions_boundary = local.org_boundary
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.envs

  # State: only this env's file and its lock file.
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = ["${local.arn_pfx}:s3:::${local.state_bkt}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/${each.key}.tfstate*"]
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
    sid       = "LogGroupsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
  statement {
    sid       = "LambdaVpcLookups"
    actions   = ["ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeNetworkInterfaces"]
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
      values   = [local.app_boundary_arn[each.key]]
    }
  }
  statement {
    sid = "AppRolesManage"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags",
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
    sid       = "DenyBoundaryEscape"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicy"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.envs
  name     = "deploy-${each.key}"
  role     = aws_iam_role.deploy[each.key].id
  policy   = data.aws_iam_policy_document.deploy[each.key].json
}
