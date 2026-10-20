# One small VPC.
#   * Private subnets (always): where Lambdas run when lambda_in_vpc is on. No
#     route to the internet at all; S3 and DynamoDB are reached through free
#     gateway endpoints.
#   * Public runner subnet + internet gateway (runner_mode = "ec2" only): the
#     runner needs to reach GitHub. Its security group allows no inbound
#     traffic; you reach it through SSM. No NAT gateway (about $33/month).
#   * Optional route to work's internal network (private_network, off by
#     default): a Transit Gateway or Cloud WAN attachment plus routes for
#     internal ranges only. Never a default route.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  use_runner = var.runner_mode == "ec2"
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnet_cidrs = coalesce(var.private_subnet_cidrs, [
    for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, 10 + i)
  ])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

# --- Private side (no internet) ---------------------------------------------

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.project}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "lambda" {
  name        = "${var.project}-lambda"
  description = "Lambdas in private subnets: no inbound, HTTPS to AWS endpoints only"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "HTTPS; there is no internet route, so this only reaches VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-lambda" }
}

# --- Public runner subnet (ec2 mode only) -----------------------------------

resource "aws_internet_gateway" "this" {
  count  = local.use_runner ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "runner" {
  count                   = local.use_runner ? 1 : 0
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = local.azs[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-runner-subnet" }
}

resource "aws_route_table" "runner" {
  count  = local.use_runner ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-runner-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
}

resource "aws_route_table_association" "runner" {
  count          = local.use_runner ? 1 : 0
  subnet_id      = aws_subnet.runner[0].id
  route_table_id = aws_route_table.runner[0].id
}

resource "aws_security_group" "runner" {
  count       = local.use_runner ? 1 : 0
  name        = "${var.project}-runner"
  description = "Self-hosted runner: no inbound, HTTPS out only"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "HTTPS to GitHub, AWS APIs, package mirrors"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-runner" }
}

# --- Free gateway endpoints --------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.private.id], aws_route_table.runner[*].id)
  tags              = { Name = "${var.project}-s3-endpoint" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${var.project}-dynamodb-endpoint" }
}

# --- Optional route to work's internal network (private_network) ----------
# Lets work's runners and on-prem reach the private subnets. Traffic only: CI
# still gets AWS credentials from OIDC. internal_cidrs is validated to private
# ranges, so this can never become a way to the internet.

locals {
  work_tgw   = try(var.private_network.transit_gateway_id, null)
  work_core  = try(var.private_network.core_network_arn, null)
  work_cidrs = try(var.private_network.internal_cidrs, [])
}

resource "aws_ec2_transit_gateway_vpc_attachment" "work" {
  count              = local.work_tgw != null ? 1 : 0
  transit_gateway_id = local.work_tgw
  vpc_id             = aws_vpc.this.id
  subnet_ids         = aws_subnet.private[*].id
  tags               = { Name = "${var.project}-work-network" }
}

resource "aws_networkmanager_vpc_attachment" "work" {
  count           = local.work_core != null ? 1 : 0
  core_network_id = element(split("/", local.work_core), 1)
  vpc_arn         = aws_vpc.this.arn
  subnet_arns     = aws_subnet.private[*].arn
  tags            = { Name = "${var.project}-work-network" }
}

resource "aws_route" "work" {
  count                  = length(local.work_cidrs)
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = local.work_cidrs[count.index]
  transit_gateway_id     = local.work_tgw
  core_network_arn       = local.work_core

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.work, aws_networkmanager_vpc_attachment.work]
}
