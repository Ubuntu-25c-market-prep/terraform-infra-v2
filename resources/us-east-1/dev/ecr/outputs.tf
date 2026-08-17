output "repository_urls" {
  description = "Map of repository name to URL"
  value       = module.ecr.repository_urls
}

output "repository_arns" {
  description = "Map of repository name to ARN"
  value       = module.ecr.repository_arns
}
