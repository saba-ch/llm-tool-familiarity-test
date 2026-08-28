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

resource "aws_s3_bucket" "pike" {
  bucket = "pike-680235478471"
}

resource "aws_s3_bucket_request_payment_configuration" "pike" {
  bucket = aws_s3_bucket.pike.id
  payer  = "Requester"
}
