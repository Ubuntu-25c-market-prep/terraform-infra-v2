variable "name" {
  description = "Prefix for the bucket names, <env>-s3-<region>"
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
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
