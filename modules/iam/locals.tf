locals {
  roles = { for role in var.roles : role.name => role }

  oidc_host = var.oidc_issuer_url == null ? "" : replace(var.oidc_issuer_url, "https://", "")

  policy_attachments = {
    for pair in flatten([
      for role in var.roles : [
        for arn in role.policy_arns : {
          role = role.name
          arn  = arn
        }
      ]
    ]) : "${pair.role}/${basename(pair.arn)}" => pair
  }
}
