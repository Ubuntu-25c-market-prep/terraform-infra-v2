output "role_arns" {
  description = "Map of role name to ARN"
  value       = { for name, role in aws_iam_role.this : name => role.arn }
}

output "policy_arns" {
  description = "Map of config policy name to ARN - what a role's policy_arns / attached_policies points at"
  value       = { for name, policy in aws_iam_policy.this : name => policy.arn }
}

output "role_names" {
  description = "Map of config role name to full IAM role name"
  value       = { for name, role in aws_iam_role.this : name => role.name }
}
