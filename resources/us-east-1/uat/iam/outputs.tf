output "policy_arns" {
  description = "Map of config policy name to ARN - paste into a role's policy_arns here or attached_policies in eks/iam.yaml"
  value       = module.iam_roles.policy_arns
}

output "role_arns" {
  description = "Map of role name to ARN"
  value       = module.iam_roles.role_arns
}
