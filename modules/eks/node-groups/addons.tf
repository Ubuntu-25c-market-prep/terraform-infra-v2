resource "aws_eks_addon" "this" {
  for_each = local.addons

  cluster_name         = var.cluster_name
  addon_name           = each.value.name
  addon_version        = each.value.version
  configuration_values = each.value.configuration_values

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}
