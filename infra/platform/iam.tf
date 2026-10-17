# Two layers of IAM, so dev and prod are separated inside ONE AWS account
# (the same shape the team sandbox account will use):
#
#   runner role (instance profile)   can only: register the runner, write build
#        |                           artifacts, and assume a deploy role.
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

# --- Runner (base) role ------------------------------------------------------

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
  name               = "${var.project}-runner"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.project}-runner"
  role = aws_iam_role.runner.name
}

# Lets you open a shell with `aws ssm start-session` instead of SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "${local.arn_pfx}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "runner" {
  statement {
    sid       = "GithubPat"
    actions   = ["ssm:GetParameter"]
    resources = ["${local.arn_pfx}:ssm:${var.region}:${local.account}:parameter/${var.project}/github-pat"]
  }
  statement {
    sid       = "DecryptPatViaSsm"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
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

resource "aws_iam_role_policy" "runner" {
  name   = "${var.project}-runner-scoped"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner.json
}

# --- Per-environment permissions boundary for app roles ---------------------

data "aws_iam_policy_document" "app_boundary" {
  for_each = local.envs

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
}

resource "aws_iam_policy" "app_boundary" {
  for_each = local.envs
  name     = "${var.project}-${each.key}-app-boundary"
  policy   = data.aws_iam_policy_document.app_boundary[each.key].json
}

# --- Per-environment deploy roles -------------------------------------------

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.runner.arn]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each             = local.envs
  name                 = "${var.project}-deploy-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
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
    sid = "AppRolesWithBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePermissionsBoundary",
    ]
    resources = ["${local.arn_pfx}:iam::${local.account}:role/${var.project}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.app_boundary[each.key].arn]
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
