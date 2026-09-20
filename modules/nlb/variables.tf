variable "name" {
  description = "Full name of the load balancer (also the prefix for target group names)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the load balancer and target groups are created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the load balancer places its ENIs in (one per AZ, at least two)"
  type        = list(string)
}

variable "backend_security_group_id" {
  description = "Security group of the targets (the EKS cluster SG - pod ENIs carry it under the VPC CNI). The module opens it to the NLB on every target/health-check port."
  type        = string
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
}

variable "ip_address_type" {
  description = "IP address type of the load balancer"
  type        = string
  default     = "ipv4"
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
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
