# SSH runs through the launch template (key_name + this SG) - the jump
# server CIDRs become one small SG: tcp/22 in from them, nothing else.
resource "aws_security_group" "ssh" {
  count = var.ssh_key_name == null ? 0 : 1

  name        = "${var.name}-node-ssh"
  description = "SSH to the nodes from the jump server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-node-ssh"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.ssh_key_name == null ? toset([]) : toset(var.ssh_source_cidrs)

  security_group_id = aws_security_group.ssh[0].id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_eks_node_group" "this" {
  for_each = local.node_groups

  cluster_name    = var.cluster_name
  node_group_name = each.value.name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = each.value.subnet_ids != null ? each.value.subnet_ids : var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  ami_type       = each.value.ami_type
  labels         = each.value.labels

  # SGs, disk, IMDS, SSH key and max-pods user data live in the template.
  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

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
    Name = each.value.name
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}
