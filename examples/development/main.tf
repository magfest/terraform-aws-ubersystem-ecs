terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.38.0"
    }
  }
}

# -------------------------------------------------------------------
# Pre-requisite Module Info
# -------------------------------------------------------------------


# -------------------------------------------------------------------
# Module Example
# -------------------------------------------------------------------

module "ubersystem" {
  source = "../../"

  ecs_cluster           = var.ecs_cluster
  cert_arn              = var.cert_arn
  hostname              = var.hostname
  db_secret             = var.db_secret
  subnet_ids            = var.subnet_ids
  security_groups       = var.security_groups
}
