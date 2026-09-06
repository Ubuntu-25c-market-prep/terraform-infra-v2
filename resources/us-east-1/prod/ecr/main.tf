locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../prod-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).ecr,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  # Each entry of config.yaml's repositories array, merged over repository_defaults
  # (shallow: a nested map stated in an entry replaces the whole default map).
  repositories = [for item in local.config.repositories : merge(local.config.repository_defaults, item)]

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

module "ecr" {
  source = "../../../../modules/ecr"

  name         = "${local.config.env}-ecr-${local.config.region}" # <env>-ecr-<region>/<app>
  repositories = local.repositories

  tags = local.tags
}
