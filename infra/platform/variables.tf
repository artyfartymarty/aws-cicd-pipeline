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
