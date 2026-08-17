output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the load balancer - the stable entry point; CNAME/alias records point here"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route53 hosted zone ID of the load balancer, for alias records"
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ID of the load balancer's security group"
  value       = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "Map of config target group name to ARN - what a TargetGroupBinding's targetGroupARN points at"
  value       = { for name, tg in aws_lb_target_group.this : name => tg.arn }
}

output "target_group_names" {
  description = "Map of config target group name to full AWS target group name"
  value       = { for name, tg in aws_lb_target_group.this : name => tg.name }
}
