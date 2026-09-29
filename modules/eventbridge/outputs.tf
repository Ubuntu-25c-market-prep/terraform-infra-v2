output "rule_arns" {
  description = "Map of rule name to ARN"
  value       = { for name, rule in aws_cloudwatch_event_rule.this : name => rule.arn }
}
