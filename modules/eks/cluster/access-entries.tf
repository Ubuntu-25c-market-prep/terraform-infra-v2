locals {
  access_entries = { for e in var.access_entries : e.name => e }
}

# Resolve role-name patterns to ARNs at plan time, so the (public) config
# never contains account ids. Only SSO-reserved roles are searched.
data "aws_iam_roles" "access" {
  for_each = { for name, e in local.access_entries : name => e if e.role_name_pattern != null }

  name_regex  = each.value.role_name_pattern
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

# Exact role names (EC2_LINUX node roles, other non-SSO roles) resolve the
# same way: the name lives in config, the ARN only exists at plan time.
data "aws_iam_role" "access" {
  for_each = { for name, e in local.access_entries : name => e if e.role_name != null }

  name = each.value.role_name
}

locals {
  access_principals = {
    for name, e in local.access_entries :
    name => (
      e.principal_arn != null ? e.principal_arn :
      e.role_name != null ? data.aws_iam_role.access[name].arn :
      one(data.aws_iam_roles.access[name].arns[*])
    )
  }
}

resource "aws_eks_access_entry" "this" {
  for_each = local.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = local.access_principals[each.key]
  type              = each.value.type
  kubernetes_groups = length(each.value.kubernetes_groups) > 0 ? each.value.kubernetes_groups : null

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })

  lifecycle {
    precondition {
      condition     = each.value.role_name_pattern == null || length(data.aws_iam_roles.access[each.key].arns) == 1
      error_message = "Access entry '${each.key}': role_name_pattern must match exactly one IAM role (matched ${each.value.role_name_pattern == null ? 0 : length(data.aws_iam_roles.access[each.key].arns)})."
    }
  }
}

# EC2_LINUX entries get node permissions from EKS itself, and
# kubernetes_groups-only entries get theirs from cluster RBAC - policy
# associations only exist for STANDARD entries WITH a policy.
resource "aws_eks_access_policy_association" "this" {
  for_each = { for name, e in local.access_entries : name => e if e.type == "STANDARD" && e.policy != null }

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = each.value.scope
    namespaces = each.value.scope == "namespace" ? each.value.namespaces : null
  }
}
