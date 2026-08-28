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
  name        = "kinesis-analytics-input-stream"
  shard_count = 1

  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  tags = {
    Name = "kinesis-analytics-input-stream"
  }
}

resource "aws_iam_role" "kinesis_analytics" {
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

resource "aws_iam_role_policy" "kinesis_analytics" {
  name = "kinesis-analytics-app-policy"
  role = aws_iam_role.kinesis_analytics.id

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
  name        = "example-kinesis-analytics-application"
  description = "Basic Kinesis Analytics application reading from a Kinesis stream"

  code = <<-EOF
    CREATE OR REPLACE STREAM "DESTINATION_SQL_STREAM" (
      ticker_symbol VARCHAR(4),
      ticker_count  INTEGER
    );

    CREATE OR REPLACE PUMP "STREAM_PUMP" AS
      INSERT INTO "DESTINATION_SQL_STREAM"
        SELECT STREAM ticker_symbol, COUNT(*) AS ticker_count
        FROM "SOURCE_SQL_STREAM_001"
        GROUP BY ticker_symbol, STEP("SOURCE_SQL_STREAM_001".ROWTIME BY INTERVAL '60' SECOND);
  EOF

  inputs {
    name_prefix = "SOURCE_SQL_STREAM"

    kinesis_stream {
      resource_arn = aws_kinesis_stream.input.arn
      role_arn     = aws_iam_role.kinesis_analytics.arn
    }

    parallelism {
      count = 1
    }

    schema {
      record_columns {
        name     = "ticker_symbol"
        sql_type = "VARCHAR(4)"
        mapping  = "$.ticker_symbol"
      }

      record_columns {
        name     = "price"
        sql_type = "DOUBLE"
        mapping  = "$.price"
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
    Name = "example-kinesis-analytics-application"
  }
}
