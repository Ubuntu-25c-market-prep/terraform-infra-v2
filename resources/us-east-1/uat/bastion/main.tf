locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../uat-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).bastion,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  name_prefix = "${local.config.org}-${local.config.env}"

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "${path.module}/../network/terraform.tfstate"
  }
}

locals {
  # Rule CIDRs differ per environment. The token "@vpc" in any cidr_blocks
  # entry resolves to THIS environment's VPC CIDR (from the network stack)
  # at plan time - same convention as the eks stack.
  egress_rules_resolved = [
    for rule in local.config.egress_rules : merge(rule, {
      cidr_blocks = [for c in rule.cidr_blocks : c == "@vpc" ? data.terraform_remote_state.network.outputs.vpc_cidr_block : c]
    })
  ]
}

module "bastion" {
  source = "../../../../modules/bastion"

  name   = local.name_prefix
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default.
  create_security_group = local.config.create_security_group
  key_name              = local.config.key_name
  ssh_public_key        = local.config.ssh_public_key
  ssh_ingress_cidrs     = local.config.ssh_ingress_cidrs
  egress_rules          = local.egress_rules_resolved

  # Subnets are referenced by NAME - the id lookup fails the plan when the
  # name does not exist in the network stack's public subnets. Public on
  # purpose: SSH comes in from the internet, and with nat_gateway = none
  # a private instance would have no route out either.
  instances = [
    for instance in local.config.instances : {
      name             = instance.name
      subnet_id        = data.terraform_remote_state.network.outputs.public_subnet_ids[instance.subnet]
      instance_type    = instance.instance_type
      root_volume_size = instance.root_volume_size
    }
  ]

  tags = local.tags
}
