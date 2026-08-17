output "alb_arn" {
  description = "ARN of the load balancer"
  value       = module.lb.alb_arn
}

output "alb_dns_name" {
  description = "DNS name of the load balancer - point CNAME/alias records here"
  value       = module.lb.alb_dns_name
}

output "alb_zone_id" {
  description = "Route53 hosted zone ID of the load balancer, for alias records"
  value       = module.lb.alb_zone_id
}

output "alb_security_group_id" {
  description = "ID of the load balancer's security group"
  value       = module.lb.security_group_id
}

output "target_group_arns" {
  description = "Map of config target group name to ARN - paste into the TargetGroupBinding's targetGroupARN"
  value       = module.lb.target_group_arns
}
