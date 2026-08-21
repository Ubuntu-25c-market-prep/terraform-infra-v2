# Terraform owns the target groups; it never registers a target. Pod IPs
# are registered by the AWS Load Balancer Controller via TargetGroupBinding
# (see the nlb stack README), so the groups survive cluster rebuilds and
# can be re-bound from a replacement cluster during blue-green.
resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = "${var.name}-${each.value.name}"
  vpc_id      = var.vpc_id
  target_type = "ip"
  port        = each.value.port
  protocol    = each.value.protocol

  deregistration_delay = each.value.deregistration_delay
  preserve_client_ip   = each.value.preserve_client_ip
  proxy_protocol_v2    = each.value.proxy_protocol_v2

  # A TCP health check only probes the port; HTTP/HTTPS also need a path
  # and matcher (the provider rejects them on TCP, hence the conditionals).
  health_check {
    protocol            = each.value.health_check.protocol
    port                = each.value.health_check.port
    path                = each.value.health_check.protocol == "TCP" ? null : each.value.health_check.path
    matcher             = each.value.health_check.protocol == "TCP" ? null : each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })
}
