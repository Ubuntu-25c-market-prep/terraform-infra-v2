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
      Component = "ecr"
      Repo      = local.config.repo
    })
  }
}
