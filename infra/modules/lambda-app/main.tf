# Layer 1 module: one Lambda + its DynamoDB table + a least-privilege role
# (with the env's permissions boundary) + a log group. Every name starts
# with name_prefix, which is what the deploy roles are scoped to.

locals {
  name = var.name_prefix
}

# The "database" of this demo: on-demand, so an idle table costs nothing.
resource "aws_dynamodb_table" "items" {
  name         = "${local.name}-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  deletion_protection_enabled = var.deletion_protection
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name                 = "${local.name}-app"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume.json
  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.items.arn]
  }
}

# Lets Lambda create its network interfaces in the private subnets.
resource "aws_iam_role_policy_attachment" "vpc" {
  count      = length(var.subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.app.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_partition" "current" {}

resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${local.name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "app" {
  function_name = "${local.name}-api"
  role          = aws_iam_role.app.arn
  runtime       = "python3.12"
  architectures = ["arm64"]
  handler       = "handler.handler"
  memory_size   = var.memory_mb
  timeout       = 10

  # Same artifact in every env: only the env vars differ (like appConfig at work).
  s3_bucket = var.artifact_bucket
  s3_key    = var.artifact_key
  # Pin the exact object version, so a later upload to the same key can't
  # change what gets deployed.
  s3_object_version = var.artifact_version != "" ? var.artifact_version : null

  tags = { BuildSha = var.build_sha }

  environment {
    variables = {
      APP_ENV    = var.env
      BUILD_SHA  = var.build_sha
      TABLE_NAME = aws_dynamodb_table.items.name
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  depends_on = [aws_cloudwatch_log_group.app, aws_iam_role_policy.app, aws_iam_role_policy_attachment.vpc]
}
