variable "name" {
  description = "Name of the EKS cluster; also used as a prefix for its components"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the cluster (at least two AZs)"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version; null lets AWS pick the current default"
  type        = string
  default     = null
}

variable "endpoint_public_access" {
  description = "Allow public access to the cluster API endpoint"
  type        = bool
  default     = true
  nullable    = false
}

variable "endpoint_private_access" {
  description = "Allow private (in-VPC) access to the cluster API endpoint"
  type        = bool
  default     = false
  nullable    = false
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to send to CloudWatch"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "security_group_ids" {
  description = "Additional security groups to attach to the cluster"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Tags applied to all resources in the module"
  type        = map(string)
  default     = {}
}

variable "create_oidc" {
  description = "Create the IAM OIDC provider for IRSA"
  type        = bool
  default     = true
  nullable    = false
}

variable "service_ipv4_cidr" {
  description = "CIDR for Kubernetes service IPs; null lets AWS pick one"
  type        = string
  default     = null
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}

variable "node_ingress_rules" {
  description = "Extra ingress rules on the EKS-managed cluster security group (the SG every managed node uses), keyed by rule name. Sources: IPv4 CIDRs and/or other security groups."
  type = map(object({
    description                   = optional(string, "Managed by Terraform")
    cidr_blocks                   = optional(list(string), [])
    referenced_security_group_ids = optional(list(string), [])
    from_port                     = optional(number)
    to_port                       = optional(number)
    ip_protocol                   = string
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) :
      length(r.cidr_blocks) + length(r.referenced_security_group_ids) > 0
    ])
    error_message = "Every node ingress rule needs at least one source: cidr_blocks and/or referenced_security_group_ids."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) :
      contains(["-1", "tcp", "udp", "icmp", "icmpv6"], r.ip_protocol) || can(tonumber(r.ip_protocol))
    ])
    error_message = "ip_protocol must be -1, tcp, udp, icmp, icmpv6 or an IP protocol number."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) :
      r.ip_protocol == "-1" ? (r.from_port == null && r.to_port == null) : (r.from_port != null && r.to_port != null)
    ])
    error_message = "ip_protocol -1 (all traffic) must omit from_port/to_port; any other protocol requires both."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) :
      r.from_port == null || (r.from_port >= 0 && r.to_port <= 65535 && r.from_port <= r.to_port)
    ])
    error_message = "Rule ports must satisfy 0 <= from_port <= to_port <= 65535."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) : alltrue([
        for c in r.cidr_blocks : can(cidrhost(c, 0))
      ])
    ])
    error_message = "Every cidr_blocks entry must be a valid IPv4 CIDR (an unresolved token like @vpc means the stack did not substitute it)."
  }

  validation {
    condition = alltrue([
      for r in values(var.node_ingress_rules) : alltrue([
        for sg in r.referenced_security_group_ids : can(regex("^sg-", sg))
      ])
    ])
    error_message = "Every referenced_security_group_ids entry must be a security group id (sg-...)."
  }
}

variable "secrets_kms_key_alias" {
  description = "KMS key alias for envelope encryption of Secrets (e.g. alias/u25c-dev-eks); null disables"
  type        = string
  default     = null
}

variable "authentication_mode" {
  description = "Cluster authentication mode; API = access entries only (aws-auth ConfigMap is deprecated)"
  type        = string
  default     = "API"
  nullable    = false

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API, API_AND_CONFIG_MAP or CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Give the identity that creates the cluster (the CI apply role) an admin access entry"
  type        = bool
  default     = true
  nullable    = false
}

variable "access_entries" {
  description = "Human/extra access entries. EKS auto-creates entries for managed node groups and its service-linked role - do not list those here."
  type = list(object({
    name              = string
    type              = optional(string, "STANDARD") # STANDARD | EC2_LINUX (node roles this stack does not create, e.g. Karpenter)
    role_name         = optional(string)             # exact IAM role name, resolved at plan time (keeps account-id ARNs out of the public repo)
    role_name_pattern = optional(string)             # IAM role name regex, resolved at plan time - searches SSO roles only
    principal_arn     = optional(string)             # alternative: explicit principal
    policy            = optional(string)             # e.g. AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy; STANDARD only
    kubernetes_groups = optional(list(string), [])   # bind to cluster RBAC groups instead of / besides an EKS access policy; STANDARD only
    scope             = optional(string, "cluster")  # cluster | namespace
    namespaces        = optional(list(string), [])
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for e in var.access_entries :
      length([for p in [e.role_name, e.role_name_pattern, e.principal_arn] : p if p != null]) == 1
    ])
    error_message = "Each access entry must set exactly one of role_name, role_name_pattern or principal_arn."
  }

  validation {
    condition     = alltrue([for e in var.access_entries : contains(["STANDARD", "EC2_LINUX"], e.type)])
    error_message = "Access entry type must be STANDARD or EC2_LINUX."
  }

  validation {
    condition = alltrue([
      for e in var.access_entries :
      e.type == "STANDARD"
      ? (e.policy != null || length(e.kubernetes_groups) > 0)
      : (e.policy == null && length(e.kubernetes_groups) == 0)
    ])
    error_message = "STANDARD access entries need a policy and/or kubernetes_groups; EC2_LINUX entries must set neither (EKS grants node permissions itself)."
  }

  validation {
    condition     = alltrue([for e in var.access_entries : e.type == "STANDARD" || e.role_name_pattern == null])
    error_message = "EC2_LINUX entries must use role_name or principal_arn - role_name_pattern only searches SSO roles."
  }

  validation {
    condition     = alltrue([for e in var.access_entries : contains(["cluster", "namespace"], e.scope)])
    error_message = "Access entry scope must be cluster or namespace."
  }

  validation {
    condition = alltrue([
      for e in var.access_entries :
      e.scope != "namespace" || length(e.namespaces) > 0
    ])
    error_message = "A namespace-scoped access entry must list at least one namespace."
  }
}
