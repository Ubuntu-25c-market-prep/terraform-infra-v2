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
      Component = "network"
      Repo      = local.config.repo
    })
  }
}
