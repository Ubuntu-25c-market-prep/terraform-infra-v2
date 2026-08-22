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

  # Envelope encryption of Kubernetes Secrets, only when a key is given.
  dynamic "encryption_config" {
    for_each = var.secrets_kms_key_arn == null ? [] : [1]

    content {
      provider {
        key_arn = var.secrets_kms_key_arn
      }
      resources = ["secrets"]
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  depends_on = [aws_iam_role_policy_attachment.cluster]

  # Checked at plan (not validate) so a REPLACE-ME placeholder in config
  # fails the plan without breaking validate.
  lifecycle {
    precondition {
      condition     = alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", id))])
      error_message = "subnet_ids must be subnet ids (subnet-<hex>) - replace the placeholders with the network stack outputs."
    }
    precondition {
      condition     = var.secrets_kms_key_arn == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.secrets_kms_key_arn))
      error_message = "secrets_kms_key_arn '${coalesce(var.secrets_kms_key_arn, "null")}' is not a complete KMS key ARN - paste the real key ARN (arn:aws:kms:<region>:<12-digit account>:key/<uuid>)."
    }
  }
}
