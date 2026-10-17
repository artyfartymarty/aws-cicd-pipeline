variable "project" {
  type    = string
  default = "cicd-lab"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  description = "dev or prod. Each env has its own state file (app/<env>.tfstate) and its own resources."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "build_sha" {
  description = "Git commit SHA of the build to deploy. The artifact is builds/<sha>/app.zip."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.build_sha))
    error_message = "build_sha must be a full 40-character git SHA."
  }
}

variable "artifact_bucket" {
  type = string
}

variable "app_boundary_arn" {
  description = "Permissions boundary the app role must carry (output of the platform stack)."
  type        = string
}

variable "memory_mb" {
  description = "Lambda memory. Set per env with a TF_VAR_memory_mb GitHub Environment variable if you need to."
  type        = number
  default     = 128
}

variable "lambda_subnet_ids" {
  description = "Private subnets for the Lambda (LAMBDA_SUBNET_IDS env variable). Empty = not in a VPC."
  type        = list(string)
  default     = []
}

variable "lambda_security_group_ids" {
  type    = list(string)
  default = []
}

variable "artifact_version" {
  description = "S3 version ID of the build's first upload (set by the pipeline)."
  type        = string
  default     = ""
}
