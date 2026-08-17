output "node_role_arn" {
  description = "ARN of the shared IAM role used by the node groups"
  value       = aws_iam_role.node.arn
}

output "node_group_names" {
  description = "Names of the managed node groups"
  value       = [for group in aws_eks_node_group.this : group.node_group_name]
}
