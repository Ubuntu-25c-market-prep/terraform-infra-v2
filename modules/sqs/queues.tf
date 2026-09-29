# Standard queues only, always encrypted and TLS-only.
resource "aws_sqs_queue" "this" {
  for_each = local.queues

  name = each.value.name

  message_retention_seconds  = each.value.message_retention_seconds
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  receive_wait_time_seconds  = each.value.receive_wait_time_seconds

  kms_master_key_id       = each.value.kms_key_id
  sqs_managed_sse_enabled = each.value.kms_key_id == null ? true : null

  tags = merge(var.tags, {
    Name = each.value.name
  })
}

# Roles in this account get access from their own IAM policy, not from here.
resource "aws_sqs_queue_policy" "this" {
  for_each = local.queues

  queue_url = aws_sqs_queue.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.this[each.key].arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }],
      [for services in [each.value.send_services] : {
        Sid       = "AllowServicesToSend"
        Effect    = "Allow"
        Principal = { Service = services }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.this[each.key].arn
      } if length(services) > 0],
    )
  })
}
