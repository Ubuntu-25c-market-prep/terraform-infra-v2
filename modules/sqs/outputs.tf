output "queue_arns" {
  description = "Map of queue name to ARN"
  value       = { for name, queue in aws_sqs_queue.this : name => queue.arn }
}

output "queue_urls" {
  description = "Map of queue name to URL"
  value       = { for name, queue in aws_sqs_queue.this : name => queue.url }
}
