# NLBs support security groups (the module relies on it): the NLB SG
# gates what reaches the listeners, and the targets' SG can reference the
# NLB SG instead of whitelisting client CIDRs - even with client IP
# preservation on, because SG evaluation happens at the NLB.
resource "aws_security_group" "nlb" {
  name        = var.name
  description = "Network load balancer ${var.name} - listener ingress, target egress"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = var.name
  })
}

# One rule per listener port, IP protocol and allowed CIDR. An NLB has no
# fixed :80/:443 - every listener port comes from a tg/ file.
resource "aws_vpc_security_group_ingress_rule" "listeners" {
  for_each = local.listener_ingress_cidrs

  security_group_id = aws_security_group.nlb.id
  description       = each.value.description
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = each.value.ip_protocol
}

# Egress is per target port on purpose - no allow-all fallback, so traffic
# to anything but a registered target port is dropped at the NLB. The NLB
# SG's egress rules also govern its health checks.
resource "aws_vpc_security_group_egress_rule" "to_targets_tcp" {
  for_each = { for p in local.backend_ports : tostring(p) => p }

  security_group_id            = aws_security_group.nlb.id
  description                  = "Traffic and health checks to targets on ${each.key}/tcp"
  referenced_security_group_id = var.backend_security_group_id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_targets_udp" {
  for_each = { for p in local.backend_ports : tostring(p) => p if local.udp_targets }

  security_group_id            = aws_security_group.nlb.id
  description                  = "Traffic to targets on ${each.key}/udp"
  referenced_security_group_id = var.backend_security_group_id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "udp"
}

# The matching ingress on the TARGETS' security group. With ip targets the
# NLB talks straight to pod ENIs, which carry the EKS cluster SG under the
# VPC CNI. The rule lives here, not in the eks stack, because its source
# (the NLB SG) is born in this module - the eks stack would need this
# stack applied first, inverting the dependency order.
resource "aws_vpc_security_group_ingress_rule" "targets_from_nlb_tcp" {
  for_each = { for p in local.backend_ports : tostring(p) => p }

  security_group_id            = var.backend_security_group_id
  description                  = "NLB ${var.name} traffic and health checks on ${each.key}/tcp"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "targets_from_nlb_udp" {
  for_each = { for p in local.backend_ports : tostring(p) => p if local.udp_targets }

  security_group_id            = var.backend_security_group_id
  description                  = "NLB ${var.name} traffic on ${each.key}/udp"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "udp"
}

locals {
  # Health checks are always tcp, so tcp rules exist for every port; udp
  # rules only when some target group actually carries UDP.
  udp_targets = anytrue([for tg in var.target_groups : contains(["UDP", "TCP_UDP"], tg.protocol)])
}
