output "role_arns" {
  description = "Map of role name to ARN"
  value       = module.iam_roles.role_arns
}
