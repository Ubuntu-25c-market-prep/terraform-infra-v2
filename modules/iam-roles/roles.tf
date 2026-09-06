data "aws_iam_policy_document" "assume" {
  for_each = local.roles

  lifecycle {
    # Cross-variable check: irsa roles are meaningless without the cluster's
    # OIDC provider. Checked HERE (not on the role) because this data source
    # would otherwise fail first with a cryptic "Null value found in list".
    precondition {
      condition     = each.value.type != "irsa" || (var.oidc_provider_arn != null && var.oidc_issuer_url != null)
      error_message = "Role '${each.value.name}' is type irsa but oidc_provider_arn/oidc_issuer_url are null - apply the eks/cluster stack with create_oidc = true first."
    }
    precondition {
      condition     = each.value.type != "github" || var.github_oidc_provider_arn != null
      error_message = "Role '${each.value.name}' is type github but github_oidc_provider_arn is null."
    }
  }

  dynamic "statement" {
    for_each = each.value.type == "service" ? [1] : []

    content {
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = each.value.services
      }
    }
  }

  dynamic "statement" {
    for_each = each.value.type == "irsa" ? [1] : []

    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [var.oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_host}:sub"
        values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${local.oidc_host}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }

  # github: one repository, one ref; the org uses immutable-id subjects (org@id/repo@id)
  dynamic "statement" {
    for_each = each.value.type == "github" ? [1] : []

    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [var.github_oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:sub"
        values   = ["repo:${each.value.github_org}/${each.value.github_repository}:ref:${each.value.github_ref}"]
      }

      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name               = var.name == null ? each.value.name : "${var.name}-${each.value.name}"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json

  max_session_duration = each.value.max_session_duration
  permissions_boundary = each.value.permissions_boundary

  tags = merge(var.tags, {
    Name = var.name == null ? each.value.name : "${var.name}-${each.value.name}"
  })

}
