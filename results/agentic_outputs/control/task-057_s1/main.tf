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

resource "aws_kinesis_stream" "this" {
  name             = "basic-kinesis-stream"
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Name        = "basic-kinesis-stream"
    Environment = "dev"
  }
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.this.name
}

output "kinesis_stream_arn" {
  value = aws_kinesis_stream.this.arn
}
