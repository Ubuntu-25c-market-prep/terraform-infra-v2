variable "name" {
  description = "Prefix for node group and IAM role names (usually the cluster name)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster the node groups join"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the node groups launch instances in (a group's own subnet_ids, when set, wins over this)"
  type        = list(string)
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
