variable "name" {
  description = "Prefix for node group and IAM role names (usually the cluster name)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster the node groups join"
  type        = string
}

variable "subnet_ids" {
  description = "Fallback subnets for groups that state no subnet_ids of their own; null = every group must state them"
  type        = list(string)
  default     = null
}

variable "node_groups" {
  description = "Managed node groups to create"
  type = list(object({
    name           = string
    subnet_ids     = optional(list(string)) # null = the module-wide subnet_ids
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 1)
    desired_size   = optional(number, 2)
    max_size       = optional(number, 3)
    disk_size      = optional(number, 20)
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    labels         = optional(map(string), {})
    tags           = optional(map(string), {}) # extra per-group tags, merged over the module-wide tags
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string # NO_SCHEDULE | PREFER_NO_SCHEDULE | NO_EXECUTE
    })), [])
  }))

  validation {
    condition     = alltrue([for g in var.node_groups : g.min_size <= g.desired_size && g.desired_size <= g.max_size && g.max_size >= 1])
    error_message = "Node group sizing must satisfy min_size <= desired_size <= max_size (and max_size >= 1)."
  }

  validation {
    condition     = alltrue([for g in var.node_groups : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for g in var.node_groups : length(g.instance_types) > 0])
    error_message = "Every node group must list at least one instance type."
  }

  validation {
    condition     = alltrue([for g in var.node_groups : g.disk_size > 0])
    error_message = "disk_size must be a positive number of GiB."
  }

  validation {
    condition = alltrue([
      for g in var.node_groups : alltrue([
        for t in g.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ])
    ])
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "ssh_key_name" {
  description = "EC2 key pair for SSH to the nodes (remote_access); null = no SSH. Set at creation only - changing it replaces the node groups."
  type        = string
  default     = null
}

variable "ssh_source_cidrs" {
  description = "CIDRs allowed to SSH to the nodes (the jump server, e.g. 10.0.0.10/32). Required with ssh_key_name - without a source AWS opens :22 to the internet."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vpc_id" {
  description = "VPC of the nodes - hosts the SSH source security group; required with ssh_key_name"
  type        = string
  default     = null
}

variable "addons" {
  description = "EKS addons to install once the node groups exist"
  type = list(object({
    name                 = string
    version              = optional(string)
    configuration_values = optional(string)
  }))
  default  = []
  nullable = false
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
