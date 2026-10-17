# The self-hosted GitHub Actions runner (runner_mode = "ec2" only): one small
# Graviton EC2 instance.
# On boot it reads a GitHub token from SSM, asks GitHub for a short-lived
# registration token, and registers itself to the repo with the labels
# [self-hosted, linux, ARM64, aws, <project>].

data "aws_ssm_parameter" "al2023_arm64" {
  count = local.use_runner ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "runner" {
  count                  = local.use_runner ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.runner[0].id
  vpc_security_group_ids = [aws_security_group.runner[0].id]
  iam_instance_profile   = aws_iam_instance_profile.runner[0].name

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/runner-user-data.sh.tftpl", {
    project      = var.project
    region       = var.region
    github_repo  = var.github_repo
    tofu_version = var.tofu_version
  })

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${var.project}-runner" }

  lifecycle {
    ignore_changes = [ami] # don't replace the runner every time AWS ships a new AMI
  }
}
