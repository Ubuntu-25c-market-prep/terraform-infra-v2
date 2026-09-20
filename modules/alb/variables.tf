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
  description = "Security group of the targets (the EKS cluster SG - pod ENIs carry it under the VPC CNI). The module opens it to the ALB on every target/health-check port."
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
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
