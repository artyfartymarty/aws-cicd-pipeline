# One small VPC for the runner. There is no NAT gateway (about $33/month): the
# runner sits in a public subnet with a public IP but its security group allows
# no inbound traffic at all, and you reach it through SSM Session Manager.
# S3 traffic (state + artifacts) goes through a free gateway endpoint and never
# leaves the AWS network.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_subnet" "runner" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-runner-subnet" }
}

resource "aws_route_table" "runner" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project}-runner-rt" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "runner" {
  subnet_id      = aws_subnet.runner.id
  route_table_id = aws_route_table.runner.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.runner.id]
  tags              = { Name = "${var.project}-s3-endpoint" }
}

resource "aws_security_group" "runner" {
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
