output "instance_ids" {
  description = "Map of instance name to instance ID"
  value       = { for name, instance in aws_instance.this : name => instance.id }
}

output "public_ips" {
  description = "Map of instance name to public IP (the SSH target; empty string for instances without one)"
  value       = { for name, instance in aws_instance.this : name => instance.public_ip }
}

output "private_ips" {
  description = "Map of instance name to private IP"
  value       = { for name, instance in aws_instance.this : name => instance.private_ip }
}

output "security_group_id" {
  description = "ID of the module-created security group (null when create_security_group = false)"
  value       = one(aws_security_group.this[*].id)
}

output "key_pair_name" {
  description = "Name of the module-created key pair (null when using an existing key_name or no SSH)"
  value       = one(aws_key_pair.this[*].key_name)
}
