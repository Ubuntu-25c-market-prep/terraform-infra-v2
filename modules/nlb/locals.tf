locals {
  target_groups = { for tg in var.target_groups : tg.name => tg }

  tls_enabled = var.certificate_arn != null

  # Every port the NLB must reach on the backend SG: the target ports plus
  # any numeric health-check overrides ("traffic-port" adds nothing new).
  backend_ports = distinct(concat(
    [for tg in var.target_groups : tg.port],
    [for tg in var.target_groups : tonumber(tg.health_check.port) if can(tonumber(tg.health_check.port))],
  ))

  # One security-group ingress rule per listener port and IP protocol.
  # TCP_UDP listeners need both a tcp and a udp rule; TLS is tcp on the
  # wire. Keyed "<port>-<ip protocol>" so the same port can carry both.
  listener_ingress = {
    for e in flatten([
      for tg in var.target_groups : [
        for proto in(tg.listener.protocol == "UDP" ? ["udp"] : tg.listener.protocol == "TCP_UDP" ? ["tcp", "udp"] : ["tcp"]) : {
          key         = "${tg.listener.port}-${proto}"
          port        = tg.listener.port
          ip_protocol = proto
          description = "${tg.listener.protocol} listener ${tg.listener.port} (${tg.name})"
        }
      ]
    ]) : e.key => e
  }

  # Cross product of listener rules and allowed CIDRs.
  listener_ingress_cidrs = {
    for p in setproduct(keys(local.listener_ingress), var.ingress_cidrs) :
    "${p[0]}-${p[1]}" => merge(local.listener_ingress[p[0]], { cidr = p[1] })
  }
}
