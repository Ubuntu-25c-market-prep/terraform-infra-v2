locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../dev-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).ecr,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  repositories = [
    for f in fileset("${path.module}/config", "*.yaml") :
    merge(local.config.repository_defaults, yamldecode(file("${path.module}/config/${f}")))
  ]

  name_prefix = "${local.config.org}-${local.config.env}"

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

module "ecr" {
  source = "../../../../modules/ecr"

  name         = local.name_prefix
  repositories = local.repositories

  tags = local.tags
}
