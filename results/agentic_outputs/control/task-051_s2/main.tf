terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

locals {
  name_prefix = "pizza-order"
}

#############################################
# Lambda packaging (inline source, no ext zip)
#############################################

data "archive_file" "pizza_fulfillment" {
  type        = "zip"
  output_path = "${path.module}/build/pizza_fulfillment.zip"

  source {
    filename = "index.py"
    content  = <<-EOT
      import json


      def handler(event, context):
          slots = event.get("currentIntent", {}).get("slots", {})
          crust = slots.get("crust", "hand tossed")
          topping = slots.get("topping", "cheese")
          size = slots.get("size", "medium")
          count = slots.get("count", "1")

          message = (
              "Thanks! Your order for {0} {1} {2} pizza(s) with {3} "
              "is on its way.".format(count, size, crust, topping)
          )

          return {
              "dialogAction": {
                  "type": "Close",
                  "fulfillmentState": "Fulfilled",
                  "message": {"contentType": "PlainText", "content": message},
              }
          }
    EOT
  }
}

#############################################
# IAM for the Lambda function
#############################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#############################################
# Lambda function + Lex invoke permission
#############################################

resource "aws_lambda_function" "pizza_fulfillment" {
  function_name = "${local.name_prefix}-fulfillment"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.pizza_fulfillment.output_path
  source_code_hash = data.archive_file.pizza_fulfillment.output_base64sha256

  timeout     = 10
  memory_size = 128

  depends_on = [aws_iam_role_policy_attachment.lambda_basic]
}

resource "aws_lambda_permission" "allow_lex" {
  statement_id  = "AllowExecutionFromLex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pizza_fulfillment.function_name
  principal     = "lex.amazonaws.com"
  source_arn    = "arn:aws:lex:us-east-1:123456789012:intent:OrderPizza:*"
}

#############################################
# Lex slot type, intent and bot
#############################################

resource "aws_lex_slot_type" "crust" {
  name        = "PizzaCrust"
  description = "Available pizza crusts"

  enumeration_value {
    value    = "thick"
    synonyms = ["deep dish", "pan"]
  }

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust", "crispy"]
  }

  value_selection_strategy = "ORIGINAL_VALUE"
  create_version           = true
}

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent that orders a pizza"

  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order me a {size} {crust} pizza with {topping}",
    "Can I get a pizza",
  ]

  slot {
    name           = "size"
    description    = "The size of the pizza"
    slot_constraint = "Required"
    slot_type      = "AMAZON.AlphaNumeric"
    priority       = 1

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like? Small, medium or large?"
        content_type = "PlainText"
      }
    }

    sample_utterances = ["I want a {size} pizza"]
  }

  slot {
    name           = "crust"
    description    = "The crust of the pizza"
    slot_constraint = "Required"
    slot_type      = aws_lex_slot_type.crust.name
    slot_type_version = aws_lex_slot_type.crust.version
    priority       = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What crust would you like? Thin or thick?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name           = "topping"
    description    = "The topping of the pizza"
    slot_constraint = "Required"
    slot_type      = "AMAZON.AlphaNumeric"
    priority       = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What topping would you like?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Okay, should I order your pizza?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I cancelled your order."
      content_type = "PlainText"
    }
  }

  dialog_code_hook {
    message_version = "1"
    uri             = aws_lambda_function.pizza_fulfillment.arn
  }

  fulfillment_activity {
    type = "CodeHook"

    code_hook {
      message_version = "1"
      uri             = aws_lambda_function.pizza_fulfillment.arn
    }
  }

  depends_on = [aws_lambda_permission.allow_lex]
}

resource "aws_lex_bot" "pizza" {
  name        = "PizzaOrderingBot"
  description = "Bot that takes pizza orders"

  child_directed                  = false
  create_version                  = true
  idle_session_ttl_in_seconds     = 600
  process_behavior                = "BUILD"
  locale                          = "en-US"
  voice_id                        = "Salli"
  enable_model_improvements       = true

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist at this time."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I didn't understand you, what would you like to do?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}

output "bot_name" {
  value = aws_lex_bot.pizza.name
}

output "lambda_arn" {
  value = aws_lambda_function.pizza_fulfillment.arn
}
