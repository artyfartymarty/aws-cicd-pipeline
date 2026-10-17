variable "name_prefix" {
  description = "Prefix for every resource, e.g. cicd-lab-dev. Must match the deploy role's scope."
  type        = string
}

variable "env" {
  type = string
}

variable "build_sha" {
  type = string
}

variable "artifact_bucket" {
  type = string
}

variable "artifact_key" {
  type = string
}

variable "permissions_boundary_arn" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "memory_mb" {
  type    = number
  default = 128
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "subnet_ids" {
  description = "Private subnets to run in. Empty = no VPC (not allowed in the Yield sandbox)."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "artifact_version" {
  description = "S3 version ID of the artifact. The pipeline passes the FIRST version ever uploaded for the build."
  type        = string
  default     = ""
}
