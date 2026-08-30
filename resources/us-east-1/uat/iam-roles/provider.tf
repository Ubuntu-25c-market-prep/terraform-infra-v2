terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = local.config.region

  # Applied to every resource. Org/Env/Component/Repo plus the shared tags from
  # the layered *-values.yaml files.
  default_tags {
    # Common tags (ManagedBy, Workstream, ...) come from the layered
    # *-values.yaml files - add new default tags there, not here.
    tags = merge(local.config.tags, {
      Org       = local.config.org
      Env       = local.config.env
      Component = "iam-roles"
      Repo      = local.config.repo
    })
  }
}
