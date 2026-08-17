# Every bucket gets the same safety baseline:
# encryption at rest, no public access, TLS-only, versioning by default.
# The account id suffix keeps names globally unique WITHOUT committing the
# account id anywhere - it is resolved at plan time.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.name}-${each.value.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = each.value.force_destroy

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = each.value.versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "deny_insecure_transport" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.this[each.key].arn,
        "${aws_s3_bucket.this[each.key].arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  # The public access block must exist before a bucket policy is evaluated.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for name, bucket in local.buckets : name => bucket if length(bucket.lifecycle_rules) > 0 }

  bucket = aws_s3_bucket.this[each.key].id

  dynamic "rule" {
    for_each = each.value.lifecycle_rules

    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix != null ? rule.value.prefix : ""
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []

        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days != null ? [1] : []

        content {
          noncurrent_days = rule.value.noncurrent_expiration_days
        }
      }
    }
  }
}
