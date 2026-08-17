output "instance_ids" {
  description = "Map of instance name to instance ID"
  value       = module.bastion.instance_ids
}

output "public_ips" {
  description = "Map of instance name to public IP - the SSH target (ssh ec2-user@<ip>)"
  value       = module.bastion.public_ips
}

output "private_ips" {
  description = "Map of instance name to private IP"
  value       = module.bastion.private_ips
}

output "security_group_id" {
  description = "ID of the bastion host's security group (SSH in, stated egress only)"
  value       = module.bastion.security_group_id
}
