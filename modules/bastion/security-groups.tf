# SSH in from the stated CIDRs only, and OUT only what egress_rules
# allows - a bastion forwards SSH and updates itself; it is not a
# general egress path. Without this group, instances with no
# security_group_ids would silently land in the VPC's default group.
resource "aws_security_group" "this" {
  count = var.create_security_group ? 1 : 0

  name        = "${var.name}-bastion"
  description = "SSH ingress and stated egress for the bastion host"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    # No CIDRs stated = no SSH rule at all, the group is egress-only.
    for_each = length(var.ssh_ingress_cidrs) > 0 ? [true] : []

    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_ingress_cidrs
    }
  }

  dynamic "egress" {
    for_each = var.egress_rules

    content {
      description = egress.value.description
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-bastion"
  })

  lifecycle {
    # Validations cannot see other variables on TF 1.5, so the
    # cross-variable check lives here (same pattern as the vpc module).
    precondition {
      condition     = var.vpc_id != null
      error_message = "create_security_group = true requires vpc_id."
    }
  }
}
