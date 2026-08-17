variable "name" {
  description = "Prefix for the repository names"
  type        = string
}

variable "repositories" {
  description = "ECR repositories to create"
  type = list(object({
    name                 = string
    image_tag_mutability = optional(string, "MUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, false)
    untagged_expiry_days = optional(number)
    max_image_count      = optional(number)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for repo in var.repositories : contains(["MUTABLE", "IMMUTABLE"], repo.image_tag_mutability)])
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }

  validation {
    condition     = alltrue([for repo in var.repositories : can(regex("^[a-z][a-z0-9._/-]*$", repo.name))])
    error_message = "Repository names must be lowercase alphanumeric with . _ / - (ECR requirement)."
  }

  validation {
    condition = alltrue([
      for repo in var.repositories :
      (repo.untagged_expiry_days == null || repo.untagged_expiry_days > 0) &&
      (repo.max_image_count == null || repo.max_image_count > 0)
    ])
    error_message = "untagged_expiry_days and max_image_count must be positive when set."
  }
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
