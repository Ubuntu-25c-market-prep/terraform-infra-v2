variable "name" {
  description = "Registry namespace; repositories are created as <name>/<repository name>"
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
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
