variable "project" {
  description = "Name prefix for every resource. The runner can only manage resources that start with it."
  type        = string
  default     = "cicd-lab"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "owner/name of the GitHub repo the runner registers to."
  type        = string
}

variable "instance_type" {
  description = "Runner size. t4g.micro (Graviton, 1 GB RAM + swap) is plenty for OpenTofu and zipping a Lambda."
  type        = string
  default     = "t4g.micro"
}

variable "use_spot" {
  description = "Run the runner as a persistent Spot instance (about 70% cheaper; it stops instead of terminating on interruption)."
  type        = bool
  default     = true
}

variable "tofu_version" {
  description = "OpenTofu version installed on the runner. Keep in step with the workflows."
  type        = string
  default     = "1.12.0"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "environments" {
  description = "Environments that share this account. Each gets its own deploy role, boundary and state file."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "runner_mode" {
  description = <<-EOT
    How CI reaches AWS.
      "ec2"         - a self-hosted runner EC2 in this account (needs an internet gateway).
      "github-oidc" - GitHub-hosted runners sign in with OIDC; nothing runs in the account
                      and no internet gateway is created. Use this in the Yield sandbox.
  EOT
  type        = string
  default     = "ec2"
  validation {
    condition     = contains(["ec2", "github-oidc"], var.runner_mode)
    error_message = "runner_mode must be ec2 or github-oidc."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (only one per account)."
  type        = bool
  default     = true
}

variable "org_permissions_boundary_arn" {
  description = "Boundary the account forces on new roles (the sandbox's yield-boundary). Applied to the base roles."
  type        = string
  default     = ""
}

variable "lambda_in_vpc" {
  description = "Run app Lambdas in the private subnets (required where the account forbids non-VPC Lambdas, as the Yield sandbox does)."
  type        = bool
  default     = false
}

variable "prod_environments" {
  description = "Environments that only the main-only OIDC role can deploy to. The runner never gets credentials for these."
  type        = list(string)
  default     = ["prod"]
}

variable "org_env_boundary_arns" {
  description = <<-EOT
    Per-env boundaries supplied by the account owner (sandbox: yield-dev-boundary,
    yield-prod-boundary from sandbox-guardrails/). Each env's deploy role and all
    roles it creates carry it. Envs not listed get a boundary created here.
  EOT
  type        = map(string)
  default     = {}
}

variable "runner_version" {
  description = "GitHub Actions runner version, pinned (https://github.com/actions/runner/releases)."
  type        = string
  default     = "2.328.0"
}
