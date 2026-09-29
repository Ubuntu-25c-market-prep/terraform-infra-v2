output "queue_arns" {
  description = "Map of queue name to ARN"
  value       = module.sqs.queue_arns
}

output "queue_urls" {
  description = "Map of queue name to URL"
  value       = module.sqs.queue_urls
}
