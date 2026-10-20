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
  description = "owner/name of the GitHub repo (runner_mode ec2 / github-oidc)."
  type        = string
  default     = ""
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
  description = "VPC range. At work, use the range Enterprise Networks allocates so it doesn't overlap the internal network."
  type        = string
  default     = "10.20.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a CIDR block such as 10.20.0.0/16."
  }
}

variable "private_subnet_cidrs" {
  description = "Two private subnet ranges inside vpc_cidr, one per AZ. Leave null to carve /24s out of a /16 automatically; set them when IT hands out a smaller range."
  type        = list(string)
  default     = null
  validation {
    condition     = var.private_subnet_cidrs == null ? true : length(var.private_subnet_cidrs) == 2
    error_message = "Give exactly two private subnet CIDRs, one per AZ."
  }
}

variable "private_network" {
  description = <<-EOT
    Optional route from work's internal network (on-prem and the Tools account runners)
    into the private subnets. Off (null) by default. IT applies it, because the attachment
    needs a resource share from Enterprise Networks and the SCP only lets IT's role make one.
      transit_gateway_id - today's Transit Gateway, or
      core_network_arn   - the AWS Cloud WAN core network work is migrating to (set one, not both)
      internal_cidrs     - private ranges to send there. Never a default route: the sandbox
                           must have no path to the internet.
  EOT
  type = object({
    transit_gateway_id = optional(string)
    core_network_arn   = optional(string)
    internal_cidrs     = list(string)
  })
  default = null
  validation {
    condition = var.private_network == null ? true : (
      (var.private_network.transit_gateway_id == null) != (var.private_network.core_network_arn == null)
    )
    error_message = "Set exactly one of transit_gateway_id or core_network_arn."
  }
  validation {
    condition = var.private_network == null ? true : length(var.private_network.internal_cidrs) > 0 && alltrue([
      for c in var.private_network.internal_cidrs : can(cidrhost(c, 0)) && anytrue([
        # c is inside p when it is no wider and masking c to p's length gives p
        for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
        tonumber(split("/", c)[1]) >= tonumber(split("/", p)[1]) &&
        cidrhost("${cidrhost(c, 0)}/${split("/", p)[1]}", 0) == cidrhost(p, 0)
      ])
    ])
    error_message = "internal_cidrs must be private ranges inside 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16. A default route (0.0.0.0/0) would give the sandbox internet through work's egress."
  }
}

variable "environments" {
  description = "Environments that share this account. Each gets its own deploy role, boundary and state file."
  type        = list(string)
  default     = ["dev", "qa", "prod"]
}

variable "runner_mode" {
  description = <<-EOT
    How CI reaches AWS.
      "ec2"            - a self-hosted GitHub Actions runner EC2 in this account (needs an
                         internet gateway). My account.
      "github-oidc"    - GitHub-hosted runners sign in with OIDC; nothing runs in the account
                         and no internet gateway is created.
      "bitbucket-oidc" - Bitbucket Pipelines steps sign in with OIDC; same shape as
                         github-oidc. The work pattern (Yield sandbox).
  EOT
  type        = string
  default     = "ec2"
  validation {
    condition     = contains(["ec2", "github-oidc", "bitbucket-oidc"], var.runner_mode)
    error_message = "runner_mode must be ec2, github-oidc or bitbucket-oidc."
  }
}

variable "create_oidc_provider" {
  description = "Create the CI OIDC provider (GitHub or Bitbucket). Set false if the account already has it (only one per issuer per account)."
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

# --- Bitbucket (runner_mode = "bitbucket-oidc") -------------------------------
# Copy each value from Bitbucket: Repository settings > Pipelines > OpenID Connect.

variable "bitbucket_oidc_url" {
  description = "Identity provider URL, https://api.bitbucket.org/2.0/workspaces/<workspace>/pipelines-config/identity/oidc"
  type        = string
  default     = ""
  validation {
    condition     = var.bitbucket_oidc_url == "" || can(regex("^https://api\\.bitbucket\\.org/2\\.0/workspaces/[^/]+/pipelines-config/identity/oidc$", var.bitbucket_oidc_url))
    error_message = "bitbucket_oidc_url must be the Identity provider URL shown in Bitbucket."
  }
}

variable "bitbucket_oidc_audience" {
  description = "Audience, ari:cloud:bitbucket::workspace/<workspace-uuid>"
  type        = string
  default     = ""
}

variable "bitbucket_repo_uuid" {
  description = "Repository UUID including the braces, e.g. {0f1e...}."
  type        = string
  default     = ""
  validation {
    condition     = var.bitbucket_repo_uuid == "" || can(regex("^\\{[0-9a-f-]{36}\\}$", var.bitbucket_repo_uuid))
    error_message = "bitbucket_repo_uuid must be the repository UUID with its braces."
  }
}

variable "bitbucket_deployment_uuids" {
  description = "Deployment environment UUIDs (with braces) by env name. Every env in prod_environments needs one."
  type        = map(string)
  default     = {}
}
