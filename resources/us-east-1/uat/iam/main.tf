locals {
  global_values = yamldecode(file("${path.module}/../../../global-values.yaml"))
  region_values = yamldecode(file("${path.module}/../../regional-values.yaml"))
  env_values    = yamldecode(file("${path.module}/../uat-values.yaml"))

  config = merge(
    local.global_values,
    local.region_values,
    local.env_values,
    yamldecode(file("${path.module}/config.yaml")).iam,
    # tags exist in every layer; a plain merge keeps only the last map, so
    # combine them explicitly (later layers win on the same key)
    { tags = merge(local.global_values.tags, local.region_values.tags, local.env_values.tags) },
  )

  # One self-contained file per policy / role; only *.yaml is read
  policy_files = { for f in fileset("${path.module}/policies", "*.yaml") : trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/policies/${f}")) }
  role_files   = { for f in fileset("${path.module}/roles", "*.yaml") : trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/roles/${f}")) }

  # Org/Env/Component/Repo are added by the provider's default_tags
  tags = local.config.tags
}

# Non-cluster IAM only: service and github roles. IRSA roles are created by
# the eks stack (eks/iam.yaml), which has the cluster's OIDC provider.
module "iam_roles" {
  source = "../../../../modules/iam"

  name     = null # policy and role names are stated in full in each file (<env>-<Name>-<region>)
  policies = values(local.policy_files)
  roles    = values(local.role_files)

  github_oidc_provider_arn = local.config.github_oidc_provider_arn

  tags = local.tags
}
