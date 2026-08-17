variable "name" {
  description = "Name of the VPC; also used as a prefix for its components"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }
}

variable "public_subnets" {
  description = "Public subnets to create in the VPC"
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))

  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "At least one public subnet is required - a VPC without subnets cannot host anything."
  }

  validation {
    condition     = alltrue([for s in var.public_subnets : can(cidrhost(s.cidr_block, 0))])
    error_message = "Every subnet cidr_block must be a valid IPv4 CIDR."
  }

  validation {
    condition     = length(distinct([for s in var.public_subnets : s.cidr_block])) == length(var.public_subnets)
    error_message = "Subnet CIDR blocks must be unique - two subnets cannot share a range."
  }
}

variable "private_subnets" {
  description = "Private subnets to create in the VPC (no direct internet route; egress only via NAT when enabled)"
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for s in var.private_subnets : can(cidrhost(s.cidr_block, 0))])
    error_message = "Every subnet cidr_block must be a valid IPv4 CIDR."
  }

  validation {
    condition     = length(distinct([for s in var.private_subnets : s.cidr_block])) == length(var.private_subnets)
    error_message = "Subnet CIDR blocks must be unique - two subnets cannot share a range."
  }
}

variable "nat_gateway" {
  description = "NAT for the private subnets: none (isolated - S3 still reachable via the gateway endpoint), single (one NAT, cheapest), per_az (one NAT per private-subnet AZ, survives an AZ failure)"
  type        = string
  default     = "none"
  nullable    = false

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway)
    error_message = "nat_gateway must be none, single or per_az."
  }
}

variable "public_route_table_name" {
  description = "Explicit Name tag for the public route table; null = <name>-public"
  type        = string
  default     = null
}

variable "private_route_table_names" {
  description = "Explicit Name tag per private subnet's route table, keyed by SUBNET name; missing keys fall back to <name>-<subnet>"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "public_subnet_tags" {
  description = "Extra tags on the public subnets only (e.g. kubernetes.io/role/elb for LB controller discovery)"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "private_subnet_tags" {
  description = "Extra tags on the private subnets only (e.g. kubernetes.io/role/internal-elb)"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}

variable "instance_tenancy" {
  description = "Instance tenancy of the VPC"
  type        = string
  default     = "default"
  nullable    = false

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "instance_tenancy must be default or dedicated."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_network_address_usage_metrics" {
  description = "Enable Network Address Usage metrics for the VPC (CloudWatch NAU tracking)"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
  nullable    = false
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign public IPs to instances launched in the public subnets"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_s3_gateway_endpoint" {
  description = "Create an S3 gateway endpoint on the public route table"
  type        = bool
  default     = true
  nullable    = false
}
