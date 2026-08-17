output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data of the cluster"
  value       = module.cluster.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group"
  value       = module.cluster.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA"
  value       = module.cluster.oidc_provider_arn
}

output "oidc_issuer_url" {
  description = "URL of the cluster's OIDC issuer"
  value       = module.cluster.oidc_issuer_url
}

output "node_role_arn" {
  description = "ARN of the shared IAM role used by the node groups"
  value       = module.node_groups.node_role_arn
}

output "node_group_names" {
  description = "Names of the managed node groups"
  value       = module.node_groups.node_group_names
}

output "security_group_ids" {
  description = "Map of security group name to ID for the extra groups from sg/"
  value       = module.security_groups.security_group_ids
}

output "attached_security_group_ids" {
  description = "IDs of the extra groups with attach_to_cluster: true"
  value       = module.security_groups.cluster_security_group_ids
}

output "irsa_role_names" {
  description = "Map of config role name to full IAM role name for IRSA roles"
  value       = module.irsa.role_names
}