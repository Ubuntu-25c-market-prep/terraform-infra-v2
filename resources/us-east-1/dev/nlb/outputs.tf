output "nlb_arn" {
  description = "ARN of the load balancer"
  value       = module.nlb.nlb_arn
}

output "nlb_dns_name" {
  description = "DNS name of the load balancer - point CNAME/alias records here"
  value       = module.nlb.nlb_dns_name
}

output "nlb_zone_id" {
  description = "Route53 hosted zone ID of the load balancer, for alias records"
  value       = module.nlb.nlb_zone_id
}

output "nlb_security_group_id" {
  description = "ID of the load balancer's security group"
  value       = module.nlb.security_group_id
}

output "target_group_arns" {
  description = "Map of config target group name to ARN - paste into the TargetGroupBinding's targetGroupARN"
  value       = module.nlb.target_group_arns
}
