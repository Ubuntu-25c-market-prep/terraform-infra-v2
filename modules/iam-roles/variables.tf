variable "name" {
  description = "Prefix for role and policy names (<prefix>-<role name>); null = names are used verbatim (full names stated in config)"
  type        = string
  default     = null
}

variable "roles" {
  description = "IAM roles to create; type is either service or irsa"
  type = list(object({
    name                 = string
    type                 = optional(string, "service")
    description          = optional(string)
    services             = optional(list(string), [])
    namespace            = optional(string)
    service_account      = optional(string)
    policy_arns          = optional(list(string), [])
    max_session_duration = optional(number)
    permissions_boundary = optional(string)
    policy = optional(list(object({
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for role in var.roles : contains(["service", "irsa"], role.type)])
    error_message = "Role type must be service or irsa."
  }

  validation {
    condition     = alltrue([for role in var.roles : length(role.services) > 0 if role.type == "service"])
    error_message = "A service role must list at least one service principal (e.g. eks.amazonaws.com)."
  }

  validation {
    condition = alltrue([
      for role in var.roles :
      role.namespace != null && role.service_account != null
      if role.type == "irsa"
    ])
    error_message = "An irsa role must set namespace AND service_account - the trust policy is conditioned on system:serviceaccount:<namespace>:<service_account> (without it, a pod in any namespace could assume the role)."
  }

  validation {
    condition = alltrue([
      for role in var.roles :
      length(role.policy_arns) > 0 || length(role.policy) > 0
    ])
    error_message = "A role with no policy_arns and no inline policy grants nothing - remove it or give it permissions."
  }
}

variable "policies" {
  description = "Standalone customer-managed IAM policies to create (referenced by ARN from roles here or in other stacks)"
  type = list(object({
    name        = string
    description = optional(string, "Managed by Terraform")
    statements = list(object({
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(distinct([for p in var.policies : p.name])) == length(var.policies)
    error_message = "Policy names must be unique."
  }

  validation {
    condition     = alltrue([for p in var.policies : length(p.statements) > 0])
    error_message = "Every policy needs at least one statement."
  }
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

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}
