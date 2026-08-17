terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = local.config.region

  # Applied to every resource. The five org-mandated tags (FinOps showback
  # and Kyverno enforcement depend on them) plus the v2 addition: Component.
  default_tags {
    # Common tags (ManagedBy, Workstream, ...) come from the layered
    # *-values.yaml files - add new default tags there, not here.
    tags = merge(local.config.tags, {
      Org       = local.config.org
      Env       = local.config.env
      Component = "eks"
      Repo      = local.config.repo
    })
  }
}
