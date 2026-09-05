# One template per group: a bare managed node group cannot set kubelet
# max-pods, attach extra SGs, or harden IMDS. No image_id/bootstrap -
# EKS still manages the AMI and merges its own user-data part.
resource "aws_launch_template" "node" {
  for_each = local.node_groups

  name_prefix = "${each.value.name}-"

  # A template with its own SGs suppresses the automatic cluster-SG
  # attachment - list it explicitly or control-plane traffic breaks.
  vpc_security_group_ids = concat(
    [var.cluster_security_group_id],
    var.ssh_key_name == null ? [] : [aws_security_group.ssh[0].id],
  )

  # remote_access is not allowed alongside a template; key + SG replace it.
  key_name = var.ssh_key_name

  # IMDSv2 only, hop limit 1: pods cannot reach the node's IAM credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # disk_size is not allowed on the node group alongside a template.
  block_device_mappings {
    device_name = "/dev/xvda" # AL2023 root device

    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, each.value.tags, {
      Name = each.value.name
    })
  }

  # kubelet's pod ceiling is fixed at boot from ENI limits (17 on t3.medium)
  # and ignores CNI prefix delegation - which must be enabled (gitops-flux)
  # or nodes advertise slots the CNI cannot fill.
  user_data = var.max_pods == null ? null : base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${var.max_pods}
    --//--
  EOT
  )

  tags = merge(var.tags, {
    Name = each.value.name
  })
}
