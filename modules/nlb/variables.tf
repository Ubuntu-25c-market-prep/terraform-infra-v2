variable "name" {
  description = "Full name of the load balancer (also the prefix for target group names)"
  type        = string

  validation {
    condition     = length(var.name) <= 32 && can(regex("^[a-zA-Z0-9-]+$", var.name)) && !startswith(var.name, "internal-")
    error_message = "NLB names are limited to 32 alphanumeric/hyphen characters and must not start with internal-."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the load balancer and target groups are created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the load balancer places its ENIs in (one per AZ, at least two)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An NLB requires subnets in at least two availability zones."
  }
}

variable "backend_security_group_id" {
  description = "Security group of the targets (the EKS cluster SG - pod ENIs carry it under the VPC CNI). The module opens it to the NLB on every target/health-check port."
  type        = string

  validation {
    condition     = can(regex("^sg-", var.backend_security_group_id))
    error_message = "backend_security_group_id must be a security group id (sg-...)."
  }
}

variable "internal" {
  description = "Whether the load balancer is internal (no public IPs) or internet-facing"
  type        = bool
  default     = false
}

variable "ingress_cidrs" {
  description = "CIDRs allowed to reach the listeners"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.ingress_cidrs) > 0 && alltrue([for c in var.ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "ingress_cidrs needs at least one valid IPv4 CIDR."
  }
}

variable "ip_address_type" {
  description = "IP address type of the load balancer"
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack"], var.ip_address_type)
    error_message = "ip_address_type must be ipv4 or dualstack."
  }
}

variable "cross_zone_load_balancing" {
  description = "Spread traffic across targets in every AZ (off by default on NLBs; each AZ's node only sees its own AZ's targets)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the load balancer from deletion (its DNS name is an external contract - keep true wherever anything points at it)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate for TLS listeners; null means no target group may declare a TLS listener"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS negotiation policy of TLS listeners (unused without a certificate)"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "target_groups" {
  description = "IP-mode target groups, each with its own listener; pods are registered by the ALB controller via TargetGroupBinding, never by Terraform"
  type = list(object({
    name                 = string
    port                 = number
    protocol             = optional(string, "TCP")
    deregistration_delay = optional(number, 30)
    preserve_client_ip   = optional(bool, true)
    proxy_protocol_v2    = optional(bool, false)
    health_check = optional(object({
      protocol            = optional(string, "TCP")
      port                = optional(string, "traffic-port")
      path                = optional(string, "/")
      matcher             = optional(string, "200-399")
      interval            = optional(number, 10)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 2)
    }), {})
    listener = object({
      port        = number
      protocol    = optional(string, "TCP")
      alpn_policy = optional(string, "None")
    })
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(distinct([for tg in var.target_groups : tg.name])) == length(var.target_groups)
    error_message = "Target group names must be unique."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : length("${var.name}-${tg.name}") <= 32])
    error_message = "Target group names are limited to 32 characters including the '<nlb name>-' prefix."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.port >= 1 && tg.port <= 65535])
    error_message = "Target group ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : contains(["TCP", "UDP", "TCP_UDP"], tg.protocol)])
    error_message = "Target group protocol must be TCP, UDP or TCP_UDP (TLS terminates at the listener; HTTP routing belongs on an ALB, not this module)."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : contains(["TCP", "HTTP", "HTTPS"], tg.health_check.protocol)])
    error_message = "health_check.protocol must be TCP, HTTP or HTTPS."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.health_check.port == "traffic-port" || can(tonumber(tg.health_check.port))])
    error_message = "health_check.port must be \"traffic-port\" or a port number (as a string)."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.health_check.protocol == "TCP" || startswith(tg.health_check.path, "/")])
    error_message = "health_check.path must start with / for HTTP/HTTPS health checks."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.health_check.timeout < tg.health_check.interval])
    error_message = "health_check.timeout must be shorter than health_check.interval."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : contains(["TCP", "UDP", "TCP_UDP", "TLS"], tg.listener.protocol)])
    error_message = "Listener protocol must be TCP, UDP, TCP_UDP or TLS."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.listener.port >= 1 && tg.listener.port <= 65535])
    error_message = "Listener ports must be between 1 and 65535."
  }

  validation {
    condition     = length(distinct([for tg in var.target_groups : tg.listener.port])) == length(var.target_groups)
    error_message = "Listener ports must be unique across target groups (an NLB listener forwards to exactly one target group)."
  }

  # A UDP listener must front a UDP-capable group; a TCP/TLS listener a
  # TCP-capable one (TCP_UDP groups accept either).
  validation {
    condition = alltrue([
      for tg in var.target_groups :
      (tg.listener.protocol == "UDP" && contains(["UDP", "TCP_UDP"], tg.protocol)) ||
      (tg.listener.protocol == "TCP_UDP" && tg.protocol == "TCP_UDP") ||
      (contains(["TCP", "TLS"], tg.listener.protocol) && contains(["TCP", "TCP_UDP"], tg.protocol))
    ])
    error_message = "Listener and target group protocols must match: UDP listener -> UDP/TCP_UDP group, TCP_UDP -> TCP_UDP, TCP/TLS -> TCP/TCP_UDP."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : contains(["None", "HTTP1Only", "HTTP2Only", "HTTP2Optional", "HTTP2Preferred"], tg.listener.alpn_policy)])
    error_message = "listener.alpn_policy must be None, HTTP1Only, HTTP2Only, HTTP2Optional or HTTP2Preferred."
  }
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
