output "bucket_names" {
  description = "Map of config bucket name to full bucket name"
  value       = module.s3.bucket_names
}

output "bucket_arns" {
  description = "Map of config bucket name to bucket ARN"
  value       = module.s3.bucket_arns
}
