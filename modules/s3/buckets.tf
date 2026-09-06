# Baseline on every bucket: encryption, no public access, TLS-only,
# versioning by default. The account id suffix keeps names globally unique.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.name}-${each.value.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = each.value.force_destroy

  tags = merge(var.tags, {
    Name = "${var.name}-${each.value.name}"
  })

  lifecycle {
    precondition {
      condition     = length("${var.name}-${each.value.name}-${data.aws_caller_identity.current.account_id}") <= 63
      error_message = "Bucket '${each.value.name}': the full name '${var.name}-${each.value.name}-<account-id>' exceeds S3's 63-character limit - at most ${63 - length(var.name) - 14} characters are available for the name."
    }
  }
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
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  # Parts of an upload the client never completed are invisible and billed forever.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

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
