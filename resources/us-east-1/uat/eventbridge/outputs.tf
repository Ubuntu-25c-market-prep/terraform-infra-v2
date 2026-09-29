output "rule_arns" {
  description = "Map of rule name to ARN"
  value       = module.eventbridge.rule_arns
}
