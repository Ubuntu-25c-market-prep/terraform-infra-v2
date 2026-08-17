locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../uat-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).alb,
    yamldecode(file("${path.module}/config.yaml")).target_groups,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  name_prefix = "${local.config.org}-${local.config.env}"

  target_groups = [
    for f in fileset("${path.module}/tg", "*.yaml") :
    merge(local.config.target_group_defaults, yamldecode(file("${path.module}/tg/${f}")))
  ]

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "${path.module}/../network/terraform.tfstate"
  }
}

data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "${path.module}/../eks/terraform.tfstate"
  }
}

# The certificate is resolved by DOMAIN, never by ARN - this repo is
# public and ACM ARNs embed the account id (same rule as the KMS alias in
# the eks stack). null = no certificate = plain HTTP on :80.
data "aws_acm_certificate" "this" {
  # for_each (not count) so `domain` is never evaluated as null
  for_each = local.config.certificate_domain == null ? [] : toset([local.config.certificate_domain])

  domain      = each.value
  statuses    = ["ISSUED"]
  most_recent = true
}

module "lb" {
  source = "../../../../modules/lb"

  name   = "${local.name_prefix}-${local.config.name}"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  # Internet-facing ALBs live in the public subnets, internal ones with
  # the workloads. Terraform places the ALB itself, so no
  # kubernetes.io/role/*elb discovery tags are involved (the network
  # stack deliberately applies none until this infra is ready).
  subnet_ids = local.config.internal ? values(data.terraform_remote_state.network.outputs.private_subnet_ids) : values(data.terraform_remote_state.network.outputs.public_subnet_ids)

  # Pod ENIs carry the EKS cluster SG (VPC CNI), so ip-target traffic
  # lands there; the module opens it to the ALB per target port.
  backend_security_group_id = data.terraform_remote_state.eks.outputs.cluster_security_group_id

  # Strict lookups on purpose: every value must be stated in config.yaml,
  # so a missing or misspelled key fails the plan instead of silently
  # falling back to a module default.
  internal                   = local.config.internal
  ingress_cidrs              = local.config.ingress_cidrs
  ip_address_type            = local.config.ip_address_type
  idle_timeout               = local.config.idle_timeout
  deletion_protection        = local.config.deletion_protection
  drop_invalid_header_fields = local.config.drop_invalid_header_fields
  certificate_arn            = local.config.certificate_domain == null ? null : data.aws_acm_certificate.this[local.config.certificate_domain].arn
  ssl_policy                 = local.config.ssl_policy

  target_groups = local.target_groups

  tags = local.tags
}
