locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../prod-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).iam,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  roles = [
    for f in fileset("${path.module}/config", "*.yaml") :
    merge(local.config.role_defaults, yamldecode(file("${path.module}/config/${f}")))
  ]

  needs_oidc = length([for role in local.roles : role if role.type == "irsa"]) > 0

  name_prefix = "${local.config.org}-${local.config.env}"

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

data "terraform_remote_state" "cluster" {
  count = local.needs_oidc ? 1 : 0

  backend = "local"

  config = {
    path = "${path.module}/../eks/terraform.tfstate"
  }
}

module "iam" {
  source = "../../../../modules/iam"

  name  = local.name_prefix
  roles = local.roles

  oidc_provider_arn = local.needs_oidc ? data.terraform_remote_state.cluster[0].outputs.oidc_provider_arn : null
  oidc_issuer_url   = local.needs_oidc ? data.terraform_remote_state.cluster[0].outputs.oidc_issuer_url : null

  tags = local.tags
}
