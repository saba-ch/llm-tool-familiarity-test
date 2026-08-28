terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "platform_infra" {
  bucket = "wellcomecollection-platform-infra"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "platform_infra" {
  depends_on = [aws_s3_bucket_ownership_controls.platform_infra]

  bucket = aws_s3_bucket.platform_infra.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "platform_infra" {
  depends_on = [aws_s3_bucket_versioning.platform_infra]

  bucket = aws_s3_bucket.platform_infra.id

  rule {
    id     = "expire-tmp-objects"
    status = "Enabled"

    filter {
      prefix = "tmp/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "manage-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "transition-current-objects"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}
