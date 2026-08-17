output "security_group_ids" {
  description = "Map of security group name to ID for all groups"
  value       = { for name, group in aws_security_group.this : name => group.id }
}

output "cluster_security_group_ids" {
  description = "IDs of the groups with attach_to_cluster: true"
  value = [
    for name, group in local.security_groups :
    aws_security_group.this[name].id if group.attach_to_cluster
  ]
}
