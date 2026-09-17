output "policy_arns" {
  description = "Map of config policy name to ARN - paste into a role's policy_arns here or attached_policies in eks/iam.yaml"
  value       = module.iam_roles.policy_arns
}

output "role_arns" {
  description = "Map of role name to ARN"
  value       = module.iam_roles.role_arns
}

output "aws_load_balancer_controller_policy_arn" {
  description = "ARN of the full AWS Load Balancer Controller policy - paste into attached_policies in eks/iam.yaml"
  value       = aws_iam_policy.aws_load_balancer_controller.arn
}

output "cert_manager_policy_arn" {
  description = "ARN of the cert-manager Route53 DNS-01 policy - paste into attached_policies in eks/iam.yaml"
  value       = aws_iam_policy.cert_manager.arn
}

output "external_dns_policy_arn" {
  description = "ARN of the external-dns Route53 policy - paste into attached_policies in eks/iam.yaml"
  value       = aws_iam_policy.external_dns.arn
}
