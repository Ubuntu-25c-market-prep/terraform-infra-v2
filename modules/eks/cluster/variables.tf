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
}

variable "secrets_kms_key_arn" {
  description = "KMS key ARN for envelope encryption of Secrets; null disables"
  type        = string
  default     = null
}

variable "authentication_mode" {
  description = "Cluster authentication mode; API = access entries only (aws-auth ConfigMap is deprecated)"
  type        = string
  default     = "API"
  nullable    = false
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
    role_name         = optional(string)             # exact IAM role name, resolved at plan time (an arn: key works too)
    role_name_pattern = optional(string)             # IAM role name regex, resolved at plan time - searches SSO roles only
    principal_arn     = optional(string)             # alternative: explicit principal
    policy            = optional(string)             # e.g. AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy; STANDARD only
    kubernetes_groups = optional(list(string), [])   # bind to cluster RBAC groups instead of / besides an EKS access policy; STANDARD only
    scope             = optional(string, "cluster")  # cluster | namespace
    namespaces        = optional(list(string), [])
  }))
  default  = []
  nullable = false
}
