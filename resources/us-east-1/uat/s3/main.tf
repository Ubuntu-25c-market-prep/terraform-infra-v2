locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../uat-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).s3,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  buckets = [
    for f in fileset("${path.module}/config", "*.yaml") :
    merge(local.config.bucket_defaults, yamldecode(file("${path.module}/config/${f}")))
  ]

  name_prefix = "${local.config.org}-${local.config.env}"

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

module "s3" {
  source = "../../../../modules/s3"

  name    = local.name_prefix
  buckets = local.buckets

  tags = local.tags
}
