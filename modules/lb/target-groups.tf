# Terraform owns the target groups; it never registers a target. Pod IPs
# are registered by the AWS Load Balancer Controller via TargetGroupBinding
# (see the lb stack README), so the groups survive cluster rebuilds and can
# be re-bound from a replacement cluster during blue-green.
resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = "${var.name}-${each.value.name}"
  vpc_id      = var.vpc_id
  target_type = "ip"
  port        = each.value.port
  protocol    = each.value.protocol

  deregistration_delay = each.value.deregistration_delay

  health_check {
    path                = each.value.health_check.path
    port                = each.value.health_check.port
    protocol            = each.value.protocol
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    matcher             = each.value.health_check.matcher
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })
}
