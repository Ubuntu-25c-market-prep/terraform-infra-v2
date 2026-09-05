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

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

# No remote state: vpc_id and each instance's subnet_id are stated in
# config.yaml, pasted from the network stack's outputs.
module "bastion" {
  source = "../../../../modules/bastion"

  name   = local.config.name # <env>-bastion-<region> (config.yaml)
  vpc_id = local.config.vpc_id

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default.
  create_security_group = local.config.create_security_group
  key_name              = local.config.key_name
  ssh_public_key        = local.config.ssh_public_key
  ssh_ingress_cidrs     = local.config.ssh_ingress_cidrs
  egress_rules          = local.config.egress_rules

  # subnet_id must be a PUBLIC subnet: SSH comes in from the internet, and
  # with nat_gateway = none a private instance would have no route out.
  instances = [
    for instance in local.config.instances : {
      name             = instance.name
      subnet_id        = instance.subnet_id
      instance_type    = instance.instance_type
      root_volume_size = instance.root_volume_size
    }
  ]

  tags = local.tags
}
