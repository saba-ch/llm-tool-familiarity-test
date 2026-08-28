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

resource "aws_kinesis_stream" "input" {
  name        = "analytics-input-stream"
  shard_count = 1

  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  tags = {
    Name        = "analytics-input-stream"
    Environment = "dev"
  }
}

resource "aws_iam_role" "analytics" {
  name = "kinesis-analytics-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "analytics" {
  name = "kinesis-analytics-app-policy"
  role = aws_iam_role.analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
        ]
        Resource = aws_kinesis_stream.input.arn
      }
    ]
  })
}

resource "aws_kinesis_analytics_application" "example" {
  name        = "example-analytics-application"
  description = "Basic Kinesis Analytics application reading from a Kinesis stream"

  inputs {
    name_prefix = "SOURCE_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.input.arn
      role_arn     = aws_iam_role.analytics.arn
    }

    parallelism {
      count = 1
    }

    schema {
      record_columns {
        name     = "COL_1"
        sql_type = "VARCHAR(8)"
        mapping  = "$.col1"
      }

      record_columns {
        name     = "COL_2"
        sql_type = "DOUBLE"
        mapping  = "$.col2"
      }

      record_encoding = "UTF-8"

      record_format {
        mapping_parameters {
          json {
            record_row_path = "$"
          }
        }
      }
    }
  }

  tags = {
    Name = "example-analytics-application"
  }
}
