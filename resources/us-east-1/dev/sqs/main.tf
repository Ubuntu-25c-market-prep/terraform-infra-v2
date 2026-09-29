locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../dev-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).sqs,
    # a plain merge keeps only the last tags map, so combine them explicitly
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  queues = [for item in local.config.queues : merge(local.config.queue_defaults, item)]

  tags = local.config.tags
}

module "sqs" {
  source = "../../../../modules/sqs"

  queues = local.queues

  tags = local.tags
}
