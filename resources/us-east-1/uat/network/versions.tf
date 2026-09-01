terraform {
  required_version = ">= 1.10.0" # 1.10+ for S3 native state locking (use_lockfile)

  # Bucket/key/region come from the workflow's -backend-config flags (the
  # bucket name is not committed - public repo). Without this empty block
  # those flags are silently ignored and CI state would be written to the
  # runner and lost.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
