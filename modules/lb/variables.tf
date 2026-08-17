variable "name" {
  description = "Full name of the load balancer (also the prefix for target group names)"
  type        = string

  validation {
    condition     = length(var.name) <= 32 && can(regex("^[a-zA-Z0-9-]+$", var.name)) && !startswith(var.name, "internal-")
    error_message = "ALB names are limited to 32 alphanumeric/hyphen characters and must not start with internal-."
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
    error_message = "An ALB requires subnets in at least two availability zones."
  }
}

variable "backend_security_group_id" {
  description = "Security group of the targets (the EKS cluster SG - pod ENIs carry it under the VPC CNI). The module opens it to the ALB on every target/health-check port."
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

variable "idle_timeout" {
  description = "Connection idle timeout in seconds"
  type        = number
  default     = 60
}

variable "deletion_protection" {
  description = "Protect the load balancer from deletion (its DNS name is an external contract - keep true wherever anything points at it)"
  type        = bool
  default     = false
}

variable "drop_invalid_header_fields" {
  description = "Drop HTTP headers with invalid fields before they reach the targets"
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate for the HTTPS :443 listener; null serves plain HTTP on :80 only"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS negotiation policy of the HTTPS listener (unused without a certificate)"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "target_groups" {
  description = "IP-mode target groups; pods are registered by the ALB controller via TargetGroupBinding, never by Terraform"
  type = list(object({
    name                 = string
    port                 = number
    protocol             = optional(string, "HTTP")
    deregistration_delay = optional(number, 30)
    health_check = optional(object({
      path                = optional(string, "/")
      port                = optional(string, "traffic-port")
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
      matcher             = optional(string, "200-399")
    }), {})
    routing = object({
      priority      = number
      path_patterns = optional(list(string), [])
      host_headers  = optional(list(string), [])
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
    error_message = "Target group names are limited to 32 characters including the '<alb name>-' prefix."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.port >= 1 && tg.port <= 65535])
    error_message = "Target group ports must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : contains(["HTTP", "HTTPS"], tg.protocol)])
    error_message = "Target group protocol must be HTTP or HTTPS (L4 traffic belongs on an NLB, not this module)."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.health_check.port == "traffic-port" || can(tonumber(tg.health_check.port))])
    error_message = "health_check.port must be \"traffic-port\" or a port number (as a string)."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : tg.routing.priority >= 1 && tg.routing.priority <= 50000])
    error_message = "Listener rule priorities must be between 1 and 50000."
  }

  validation {
    condition     = length(distinct([for tg in var.target_groups : tg.routing.priority])) == length(var.target_groups)
    error_message = "Listener rule priorities must be unique across target groups."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : length(tg.routing.path_patterns) + length(tg.routing.host_headers) > 0])
    error_message = "Every target group needs at least one routing condition: path_patterns and/or host_headers."
  }

  validation {
    condition     = alltrue([for tg in var.target_groups : alltrue([for p in tg.routing.path_patterns : startswith(p, "/")])])
    error_message = "Every path pattern must start with /."
  }
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
