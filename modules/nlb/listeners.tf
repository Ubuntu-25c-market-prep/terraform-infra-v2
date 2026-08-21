# An NLB listener has no rules: one listener port forwards to exactly one
# target group, so every tg/ file declares its own listener. A TLS
# listener terminates with the stack's certificate and forwards plain
# TCP to the target group.
resource "aws_lb_listener" "this" {
  for_each = local.target_groups

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.listener.port
  protocol          = each.value.listener.protocol

  certificate_arn = each.value.listener.protocol == "TLS" ? var.certificate_arn : null
  ssl_policy      = each.value.listener.protocol == "TLS" ? var.ssl_policy : null
  alpn_policy     = each.value.listener.protocol == "TLS" ? each.value.listener.alpn_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  tags = var.tags

  # Cross-variable checks are not allowed in variable validation blocks
  # before Terraform 1.9, hence a precondition here.
  lifecycle {
    precondition {
      condition     = each.value.listener.protocol != "TLS" || local.tls_enabled
      error_message = "Target group ${each.key} declares a TLS listener but no certificate is set (certificate_domain in config.yaml)."
    }
  }
}
