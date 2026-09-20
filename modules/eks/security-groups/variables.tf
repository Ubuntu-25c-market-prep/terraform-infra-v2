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
    tags              = optional(map(string), {}) # extra per-group tags, merged over the module-wide tags
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
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
