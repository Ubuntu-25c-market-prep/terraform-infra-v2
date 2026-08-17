output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data of the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA (null when create_oidc = false)"
  value       = var.create_oidc ? aws_iam_openid_connect_provider.this[0].arn : null
}

output "oidc_issuer_url" {
  description = "URL of the cluster's OIDC issuer"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
