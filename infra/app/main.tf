# Layer 3 pattern: "python Lambda + table", one copy per environment in the same
# account. It only wires Layer 1 modules together; the Layer 2 pipeline
# (.github/workflows/_deploy.yml) runs init -> plan -> apply on it.
#
# Today the module comes from this repo. When modules move to their own repo,
# pin a tag instead, e.g.:
#   source = "git::https://github.com/<you>/tofu-modules.git//lambda-app?ref=v1.2.0"

module "app" {
  source = "../modules/lambda-app"

  name_prefix              = "${var.project}-${var.env}"
  env                      = var.env
  build_sha                = var.build_sha
  artifact_bucket          = var.artifact_bucket
  artifact_key             = "builds/${var.build_sha}/app.zip"
  permissions_boundary_arn = var.app_boundary_arn
  deletion_protection      = var.env == "prod"
  memory_mb                = var.memory_mb
  subnet_ids               = var.lambda_subnet_ids
  security_group_ids       = var.lambda_security_group_ids
}
