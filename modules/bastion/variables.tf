variable "name" {
  description = "Prefix for instance, key pair and security group names (usually <org>-<env>)"
  type        = string
}

variable "instances" {
  description = "Bastion instances to create. Access is via SSH (key_name / ssh_public_key + ssh_ingress_cidrs)."
  type = list(object({
    name               = string
    subnet_id          = string
    instance_type      = optional(string, "t3.micro")
    security_group_ids = optional(list(string), [])
    ami_id             = optional(string) # null = latest AL2023 x86_64 via SSM parameter (never a hardcoded AMI id)
    root_volume_size   = optional(number, 20)
    user_data          = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(distinct([for i in var.instances : i.name])) == length(var.instances)
    error_message = "Instance names must be unique."
  }

  validation {
    condition     = alltrue([for i in var.instances : i.root_volume_size > 0])
    error_message = "root_volume_size must be a positive number of GiB."
  }
}

variable "create_security_group" {
  description = "Create a security group (SSH in from ssh_ingress_cidrs, out per egress_rules) and attach it to every instance. Requires vpc_id."
  type        = bool
  default     = true
  nullable    = false
}

variable "egress_rules" {
  description = "Egress rules on the module-created security group; [] = NO egress at all. A bastion needs SSH into the VPC and HTTPS for package updates - not 0.0.0.0/0 on every port. (DNS and NTP use the link-local AWS resolvers, which security groups do not filter.)"
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default  = []
  nullable = false
}

variable "key_name" {
  description = "Name of an EXISTING EC2 key pair for SSH access (created outside this repo). Mutually exclusive with ssh_public_key; both null = no SSH."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "PUBLIC key material (e.g. 'ssh-ed25519 AAAA...') - safe to commit, only the private half is secret. The module creates key pair <name>-bastion from it. Mutually exclusive with key_name."
  type        = string
  default     = null
}

variable "ssh_ingress_cidrs" {
  description = "CIDRs allowed to SSH (port 22) into the module-created security group; [] = no SSH ingress rule"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vpc_id" {
  description = "VPC the module-created security group is created in (required when create_security_group = true, unused otherwise)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
