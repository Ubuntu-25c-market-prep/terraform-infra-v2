locals {
  security_groups = { for group in var.security_groups : group.name => group }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${var.name}-${each.value.name}"
  description = each.value.description
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = each.value.ingress

    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = ingress.value.security_groups
    }
  }

  dynamic "egress" {
    for_each = each.value.egress

    content {
      description     = egress.value.description
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = egress.value.cidr_blocks
      security_groups = egress.value.security_groups
    }
  }

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.value.name}"
  })

  # Id format checks run at plan so REPLACE-ME placeholders fail there, not at apply.
  lifecycle {
    precondition {
      condition     = can(regex("^vpc-[0-9a-f]{8}([0-9a-f]{9})?$", var.vpc_id))
      error_message = "vpc_id must be a VPC id (vpc-<hex>) - replace the placeholder with the network stack output."
    }
    precondition {
      condition = alltrue([
        for r in concat(each.value.ingress, each.value.egress) : alltrue([
          for sg in r.security_groups : can(regex("^sg-[0-9a-f]{8}([0-9a-f]{9})?$", sg))
        ])
      ])
      error_message = "Security group '${each.key}': every referenced security group must be a real id (sg-<hex>) - replace the placeholder with the other stack's output (e.g. the bastion's security_group_id)."
    }
  }
}
