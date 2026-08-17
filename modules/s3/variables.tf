variable "name" {
  description = "Prefix for the bucket names (usually <org>-<env>)"
  type        = string
}

variable "buckets" {
  description = "Buckets to create; the account id is appended to the name for global uniqueness"
  type = list(object({
    name          = string
    versioning    = optional(bool, true)
    force_destroy = optional(bool, false) # true lets terraform destroy a NON-EMPTY bucket - data loss, opt in per bucket
    lifecycle_rules = optional(list(object({
      id                         = string
      prefix                     = optional(string)
      expiration_days            = optional(number)
      noncurrent_expiration_days = optional(number)
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z][a-z0-9-]*$", b.name))])
    error_message = "Bucket names must be lowercase alphanumeric with dashes, starting with a letter."
  }

  validation {
    condition     = length(distinct([for b in var.buckets : b.name])) == length(var.buckets)
    error_message = "Bucket names must be unique."
  }

  validation {
    condition = alltrue([
      for b in var.buckets : alltrue([
        for r in b.lifecycle_rules :
        r.expiration_days != null || r.noncurrent_expiration_days != null
      ])
    ])
    error_message = "Every lifecycle rule must set expiration_days and/or noncurrent_expiration_days - a rule that expires nothing does nothing."
  }
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
