terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  aws_account_id = "123456789012"
  aws_region     = "us-east-1"
  bot_name       = "PizzaOrderingBot"
  intent_name    = "OrderPizza"
}

##########################
# Lambda fulfillment code
##########################

data "archive_file" "pizza_fulfillment" {
  type        = "zip"
  output_path = "${path.module}/pizza_fulfillment.zip"

  source {
    filename = "index.py"
    content  = <<-EOT
      import json


      def handler(event, context):
          slots = event.get("currentIntent", {}).get("slots", {})
          crust = slots.get("Crust", "regular")
          count = slots.get("PizzaCount", 1)

          message = "Thanks! Your order of {} {} crust pizza(s) is on its way.".format(
              count, crust
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

resource "aws_iam_role" "pizza_fulfillment" {
  name               = "pizza-order-fulfillment-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "pizza_fulfillment_basic" {
  role       = aws_iam_role.pizza_fulfillment.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "pizza_fulfillment" {
  function_name = "pizza-order-fulfillment"
  role          = aws_iam_role.pizza_fulfillment.arn
  handler       = "index.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.pizza_fulfillment.output_path
  source_code_hash = data.archive_file.pizza_fulfillment.output_base64sha256

  timeout = 10

  depends_on = [aws_iam_role_policy_attachment.pizza_fulfillment_basic]
}

resource "aws_lambda_permission" "allow_lex" {
  statement_id  = "AllowExecutionFromLex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pizza_fulfillment.function_name
  principal     = "lex.amazonaws.com"
  source_arn    = "arn:aws:lex:${local.aws_region}:${local.aws_account_id}:intent:${local.intent_name}:*"
}

##########################
# Lex slot type + intent
##########################

resource "aws_lex_slot_type" "crust" {
  name        = "PizzaCrustType"
  description = "Available pizza crust styles"

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust", "crispy"]
  }

  enumeration_value {
    value    = "thick"
    synonyms = ["deep dish", "pan"]
  }

  enumeration_value {
    value = "stuffed"
  }

  value_selection_strategy = "TOP_RESOLUTION"
  create_version           = true
}

resource "aws_lex_intent" "order_pizza" {
  name        = local.intent_name
  description = "Order a pizza for delivery"

  sample_utterances = [
    "I want to order a pizza",
    "Order me a pizza",
    "I would like to order {PizzaCount} {Crust} crust pizzas",
  ]

  slot {
    name             = "PizzaCount"
    description      = "How many pizzas to order"
    slot_constraint  = "Required"
    slot_type        = "AMAZON.NUMBER"
    priority         = 1
    sample_utterances = ["I want {PizzaCount} pizzas"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "How many pizzas would you like?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name              = "Crust"
    description       = "The crust style of the pizza"
    slot_constraint   = "Required"
    slot_type         = aws_lex_slot_type.crust.name
    slot_type_version = aws_lex_slot_type.crust.version
    priority          = 2
    sample_utterances = ["I want a {Crust} crust"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What crust would you like: thin, thick, or stuffed?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Should I place your pizza order now?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I have cancelled your pizza order."
      content_type = "PlainText"
    }
  }

  fulfillment_activity {
    type = "CodeHook"

    code_hook {
      message_version = "1.0"
      uri             = aws_lambda_function.pizza_fulfillment.arn
    }
  }

  create_version = true

  depends_on = [aws_lambda_permission.allow_lex]
}

##########################
# Lex bot
##########################

resource "aws_lex_bot" "pizza" {
  name             = local.bot_name
  description      = "Bot for ordering pizzas"
  child_directed   = false
  locale           = "en-US"
  voice_id         = "Joanna"
  idle_session_ttl_in_seconds = 600
  process_behavior = "SAVE"

  abort_statement {
    message {
      content      = "Sorry, I am not able to take your pizza order right now."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I didn't understand that. Can you say it again?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
