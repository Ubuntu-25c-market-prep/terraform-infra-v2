data "aws_kms_alias" "secrets" {
  count = var.secrets_kms_key_alias == null ? 0 : 1

  name = var.secrets_kms_key_alias
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  enabled_cluster_log_types = var.enabled_cluster_log_types

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = var.security_group_ids
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  # Envelope encryption of Kubernetes Secrets, only when an alias is given.
  # The alias (not the key id) is what config carries - this repo is public.
  dynamic "encryption_config" {
    for_each = var.secrets_kms_key_alias == null ? [] : [1]

    content {
      provider {
        key_arn = data.aws_kms_alias.secrets[0].target_key_arn
      }
      resources = ["secrets"]
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}
