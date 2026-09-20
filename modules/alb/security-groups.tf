resource "aws_security_group" "alb" {
  name        = var.name
  description = "Load balancer ${var.name} - listener ingress, target egress"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = local.https_enabled ? "HTTP (redirected to HTTPS)" : "HTTP"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = local.https_enabled ? toset(var.ingress_cidrs) : []

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Egress is per target port on purpose - no allow-all fallback, so traffic
# to anything but a registered target port is dropped at the ALB.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  for_each = { for p in local.backend_ports : tostring(p) => p }

  security_group_id            = aws_security_group.alb.id
  description                  = "Traffic and health checks to targets on ${each.key}"
  referenced_security_group_id = var.backend_security_group_id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}

# The matching ingress on the TARGETS' security group. With ip targets the
# ALB talks straight to pod ENIs, which carry the EKS cluster SG under the
# VPC CNI. The rule lives here, not in the eks stack, because its source
# (the ALB SG) is born in this module - the eks stack would need this
# stack applied first, inverting the dependency order.
resource "aws_vpc_security_group_ingress_rule" "targets_from_alb" {
  for_each = { for p in local.backend_ports : tostring(p) => p }

  security_group_id            = var.backend_security_group_id
  description                  = "ALB ${var.name} traffic and health checks on ${each.key}"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = each.value
  to_port                      = each.value
  ip_protocol                  = "tcp"
}
