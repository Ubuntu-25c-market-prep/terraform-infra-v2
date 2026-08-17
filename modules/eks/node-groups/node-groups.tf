resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = var.cluster_name
  node_group_name = "${var.name}-${each.value.name}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = each.value.subnet_ids != null ? each.value.subnet_ids : var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size
  ami_type       = each.value.ami_type
  labels         = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints

    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  scaling_config {
    min_size     = each.value.min_size
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.value.name}"
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}
