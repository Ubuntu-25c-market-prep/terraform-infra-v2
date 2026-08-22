locals {
  target_groups = { for tg in var.target_groups : tg.name => tg }

  https_enabled = var.certificate_arn != null

  # Every port the ALB must reach on the backend SG: the target ports plus
  # any numeric health-check overrides ("traffic-port" adds nothing new).
  backend_ports = distinct(concat(
    [for tg in var.target_groups : tg.port],
    [for tg in var.target_groups : tonumber(tg.health_check.port) if can(tonumber(tg.health_check.port))],
  ))
}
