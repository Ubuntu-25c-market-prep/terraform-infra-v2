variable "name" {
  description = "Prefix for role and policy names (<prefix>-<role name>); null = names are used verbatim (full names stated in config)"
  type        = string
  default     = null
}

variable "roles" {
  description = "IAM roles to create; type is service, irsa or github"
  type = list(object({
    name                 = string
    type                 = optional(string, "service")
    description          = optional(string)
    services             = optional(list(string), [])
    namespace            = optional(string)
    service_account      = optional(string)
    github_org           = optional(string) # github: <org>@<org id>
    github_repository    = optional(string) # github: <repo>@<repo id>
    github_ref           = optional(string) # github: refs/heads/main, refs/tags/*, ...
    policy_arns          = optional(list(string), [])
    max_session_duration = optional(number)
    permissions_boundary = optional(string)
    policy = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = list(string)
      conditions = optional(map(map(list(string))), {}) # IAM Condition: {operator: {key: [values]}}
    })), [])
  }))
  default  = []
  nullable = false
}

variable "policies" {
  description = "Standalone customer-managed IAM policies to create (referenced by ARN from roles here or in other stacks)"
  type = list(object({
    name        = string
    description = optional(string, "Managed by Terraform")
    statements = list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = list(string)
      conditions = optional(map(map(list(string))), {}) # IAM Condition: {operator: {key: [values]}}
    }))
  }))
  default  = []
  nullable = false
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider; required for irsa roles"
  type        = string
  default     = null
}

variable "oidc_issuer_url" {
  description = "URL of the cluster's OIDC issuer; required for irsa roles"
  type        = string
  default     = null
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (token.actions.githubusercontent.com); required for github roles"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
