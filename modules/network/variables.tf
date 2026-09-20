variable "name" {
  description = "Name of the VPC; also used as a prefix for its components"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets to create in the VPC"
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
}

variable "private_subnets" {
  description = "Private subnets to create in the VPC (no internet route; gateway endpoints only)"
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
  default  = []
  nullable = false
}

variable "public_route_table_name" {
  description = "Explicit Name tag for the public route table; null = <name>-public"
  type        = string
  default     = null
}

variable "private_route_tables" {
  description = "Private route tables keyed by Name, each listing the private subnets it routes (every private subnet in exactly one); {} = one table per subnet"
  type        = map(list(string))
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

variable "region" {
  description = "AWS region, for the gateway endpoint service names"
  type        = string
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the S3 gateway endpoint on every route table"
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_dynamodb_gateway_endpoint" {
  description = "Create the DynamoDB gateway endpoint on every route table"
  type        = bool
  default     = false
  nullable    = false
}
