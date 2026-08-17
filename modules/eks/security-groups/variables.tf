variable "name" {
  description = "Prefix for the security group names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups are created in"
  type        = string
}

variable "security_groups" {
  description = "Security groups to create, each named by its purpose"
  type = list(object({
    name              = string
    description       = optional(string, "Managed by Terraform")
    attach_to_cluster = optional(bool, false)
    ingress = optional(list(object({
      description     = optional(string)
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), []) # source/destination SG ids (sg-...)
    })), [])
    egress = optional(list(object({
      description     = optional(string)
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string), [])
      security_groups = optional(list(string), [])
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        length(r.cidr_blocks) + length(r.security_groups) > 0
      ])
    ])
    error_message = "Every rule needs at least one source: cidr_blocks and/or security_groups."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) : alltrue([
          for sg in r.security_groups : can(regex("^sg-", sg))
        ])
      ])
    ])
    error_message = "Every security_groups entry must be a security group id (sg-...)."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        contains(["-1", "tcp", "udp", "icmp", "icmpv6"], r.protocol) || can(tonumber(r.protocol))
      ])
    ])
    error_message = "Rule protocol must be -1, tcp, udp, icmp, icmpv6 or an IP protocol number."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        r.from_port >= -1 && r.to_port <= 65535 && r.from_port <= r.to_port
      ])
    ])
    error_message = "Rule ports must satisfy -1 <= from_port <= to_port <= 65535."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) :
        r.protocol != "-1" || (r.from_port == 0 && r.to_port == 0)
      ])
    ])
    error_message = "Protocol -1 (all traffic) requires from_port = 0 and to_port = 0."
  }

  validation {
    condition = alltrue([
      for g in var.security_groups : alltrue([
        for r in concat(g.ingress, g.egress) : alltrue([
          for c in r.cidr_blocks : can(cidrhost(c, 0))
        ])
      ])
    ])
    error_message = "Every cidr_blocks entry must be a valid IPv4 CIDR (an unresolved token like @vpc means the stack did not substitute it)."
  }
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
