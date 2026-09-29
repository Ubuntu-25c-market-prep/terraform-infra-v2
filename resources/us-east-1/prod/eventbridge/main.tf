locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../prod-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).eventbridge,
    # a plain merge keeps only the last tags map, so combine them explicitly
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  # event_pattern is written as YAML and sent as JSON
  rules = [
    for item in local.config.rules : merge(local.config.rule_defaults, item, {
      event_pattern = try(item.event_pattern, null) == null ? null : jsonencode(item.event_pattern)
    })
  ]

  tags = local.config.tags
}

module "eventbridge" {
  source = "../../../../modules/eventbridge"

  rules = local.rules

  tags = local.tags
}
