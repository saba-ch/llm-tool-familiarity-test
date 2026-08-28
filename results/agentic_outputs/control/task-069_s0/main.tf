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

resource "aws_kinesis_video_stream" "example" {
  name                    = "example-video-stream"
  data_retention_in_hours = 24
  device_name             = "kinesis-video-device"
  media_type              = "video/h264"

  tags = {
    Name        = "example-video-stream"
    Environment = "dev"
  }
}
