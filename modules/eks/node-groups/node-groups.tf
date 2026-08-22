# remote_access only accepts security groups as SSH sources, so the jump
# server CIDRs become one small SG: tcp/22 in from them, nothing else.
resource "aws_security_group" "ssh" {
  count = var.ssh_key_name == null ? 0 : 1

  name        = "${var.name}-node-ssh"
  description = "SSH to the nodes from the jump server"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-node-ssh"
  })

  # Id format checks run at plan so REPLACE-ME placeholders fail there, not at apply.
  lifecycle {
    precondition {
      condition     = can(regex("^vpc-[0-9a-f]{8}([0-9a-f]{9})?$", var.vpc_id))
      error_message = "vpc_id must be a VPC id (vpc-<hex>) - replace the placeholder with the network stack output."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.ssh_key_name == null ? toset([]) : toset(var.ssh_source_cidrs)

  security_group_id = aws_security_group.ssh[0].id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  # Checked at plan (not validate) so a REPLACE-ME placeholder in config
  # fails the plan, like the other ids, without breaking validate.
  lifecycle {
    precondition {
      condition     = can(cidrhost(each.value, 0))
      error_message = "ssh_source_cidrs entry '${each.value}' is not a valid IPv4 CIDR (expected the jump server address, e.g. 10.0.0.10/32)."
    }
  }
}

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

  # SSH to the nodes, only when a key is given; the source SG keeps :22
  # off the internet (AWS would open it to 0.0.0.0/0 otherwise).
  dynamic "remote_access" {
    for_each = var.ssh_key_name == null ? [] : [1]

    content {
      ec2_ssh_key               = var.ssh_key_name
      source_security_group_ids = [aws_security_group.ssh[0].id]
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for id in coalesce(each.value.subnet_ids, var.subnet_ids, []) : can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", id))])
      error_message = "Node group ${each.key}: subnet_ids must be subnet ids (subnet-<hex>) - replace the placeholders with the network stack outputs."
    }
    precondition {
      condition     = var.ssh_key_name == null || (length(var.ssh_source_cidrs) > 0 && var.vpc_id != null)
      error_message = "ssh_key_name needs ssh_source_cidrs (the jump server address) and vpc_id - otherwise :22 would be open to the internet."
    }
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.value.name}"
  })

  depends_on = [aws_iam_role_policy_attachment.node]
}
