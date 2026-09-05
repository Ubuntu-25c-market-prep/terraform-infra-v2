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

  # Each entry of config.yaml's roles array, merged over role_defaults
  # (shallow: a nested map stated in an entry replaces the whole default map).
  roles = [for item in local.config.roles : merge(local.config.role_defaults, item)]

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

# No remote state: the cluster's OIDC provider (needed by irsa roles) is
# stated in config.yaml, pasted from the eks stack's outputs.
module "iam_roles" {
  source = "../../../../modules/iam-roles"

  name     = null # policy and role names are stated in full in config.yaml (<env>-<Name>-<region>)
  policies = local.config.policies
  roles    = local.roles

  oidc_provider_arn = local.config.oidc_provider_arn
  oidc_issuer_url   = local.config.oidc_issuer_url

  tags = local.tags
}
