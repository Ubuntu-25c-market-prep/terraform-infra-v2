# :80 always exists. With a certificate it only redirects to :443;
# without one it carries the routing rules itself (dev without a domain).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.https_enabled ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.https_enabled ? [] : [1]

    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "no route"
        status_code  = "404"
      }
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  count = local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = var.ssl_policy

  # A request matching no rule gets 404, not a default backend - routing
  # to a service must be an explicit decision in a tg/ file.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "no route"
      status_code  = "404"
    }
  }

  tags = var.tags
}

locals {
  # Rules attach to the listener that actually serves traffic.
  routing_listener_arn = local.https_enabled ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

resource "aws_lb_listener_rule" "this" {
  for_each = local.target_groups

  listener_arn = local.routing_listener_arn
  priority     = each.value.routing.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  dynamic "condition" {
    for_each = length(each.value.routing.path_patterns) > 0 ? [1] : []

    content {
      path_pattern {
        values = each.value.routing.path_patterns
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.routing.host_headers) > 0 ? [1] : []

    content {
      host_header {
        values = each.value.routing.host_headers
      }
    }
  }

  tags = var.tags
}
