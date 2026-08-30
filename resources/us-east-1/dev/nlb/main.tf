locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../dev-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).nlb,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  name_prefix = "${local.config.org}-${local.config.env}"

  # Each entry of config.yaml's target_groups array, merged over
  # target_group_defaults (shallow: a health_check stated in an entry
  # replaces the whole default map).
  target_groups = [for tg in local.config.target_groups : merge(local.config.target_group_defaults, tg)]

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

# No remote state: vpc_id, subnet_ids and backend_security_group_id are
# stated in config.yaml, pasted from the network and eks stacks' outputs.

module "nlb" {
  source = "../../../../modules/nlb"

  name   = "${local.name_prefix}-${local.config.name}"
  vpc_id = local.config.vpc_id

  # Terraform places the NLB itself (subnet_ids from config.yaml), so no
  # kubernetes.io/role/*elb discovery tags are involved (the network
  # stack deliberately applies none until this infra is ready).
  subnet_ids                = local.config.subnet_ids
  backend_security_group_id = local.config.backend_security_group_id

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default.
  internal                  = local.config.internal
  ingress_cidrs             = local.config.ingress_cidrs
  ip_address_type           = local.config.ip_address_type
  cross_zone_load_balancing = local.config.cross_zone_load_balancing
  deletion_protection       = local.config.deletion_protection
  certificate_arn           = local.config.certificate_arn
  ssl_policy                = local.config.ssl_policy

  target_groups = local.target_groups

  tags = local.tags
}
