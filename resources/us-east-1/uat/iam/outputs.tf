output "role_arns" {
  description = "Map of role name to ARN"
  value       = module.iam.role_arns
}
