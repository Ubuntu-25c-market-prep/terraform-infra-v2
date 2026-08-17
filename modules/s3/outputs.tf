output "bucket_names" {
  description = "Map of config bucket name to full bucket name"
  value       = { for name, bucket in aws_s3_bucket.this : name => bucket.bucket }
}

output "bucket_arns" {
  description = "Map of config bucket name to bucket ARN"
  value       = { for name, bucket in aws_s3_bucket.this : name => bucket.arn }
}
