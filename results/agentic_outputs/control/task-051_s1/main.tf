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
}

##############################
# Lambda fulfillment function
##############################

data "archive_file" "pizza_order_lambda" {
  type        = "zip"
  output_path = "${path.module}/pizza_order_lambda.zip"

  source {
    filename = "index.py"
    content  = <<-EOT
      import json


      def close(fulfillment_state, message):
          return {
              "dialogAction": {
                  "type": "Close",
                  "fulfillmentState": fulfillment_state,
                  "message": {"contentType": "PlainText", "content": message},
              }
          }


      def handler(event, context):
          slots = event.get("currentIntent", {}).get("slots", {}) or {}
          crust = slots.get("crust", "hand tossed")
          size = slots.get("size", "medium")
          topping = slots.get("topping", "cheese")

          message = (
              "Thanks! Your {size} {crust} pizza with {topping} "
              "is on its way.".format(size=size, crust=crust, topping=topping)
          )
          print(json.dumps({"order": slots}))
          return close("Fulfilled", message)
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

resource "aws_iam_role" "pizza_order_lambda" {
  name               = "pizza-order-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "pizza_order_lambda_basic" {
  role       = aws_iam_role.pizza_order_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "pizza_order" {
  function_name    = "pizza-order-fulfillment"
  role             = aws_iam_role.pizza_order_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.pizza_order_lambda.output_path
  source_code_hash = data.archive_file.pizza_order_lambda.output_base64sha256

  depends_on = [aws_iam_role_policy_attachment.pizza_order_lambda_basic]
}

resource "aws_lambda_permission" "allow_lex" {
  statement_id  = "AllowExecutionFromLex"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pizza_order.function_name
  principal     = "lex.amazonaws.com"
  source_arn    = "arn:aws:lex:us-east-1:123456789012:intent:OrderPizza:*"
}

##############################
# Lex slot types and intent
##############################

resource "aws_lex_slot_type" "crust" {
  name        = "PizzaCrustType"
  description = "Available pizza crusts"

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust"]
  }

  enumeration_value {
    value    = "thick"
    synonyms = ["deep dish", "pan"]
  }

  enumeration_value {
    value = "hand tossed"
  }

  value_selection_strategy = "TOP_RESOLUTION"
  create_version           = true
}

resource "aws_lex_slot_type" "topping" {
  name        = "PizzaToppingType"
  description = "Available pizza toppings"

  enumeration_value {
    value = "cheese"
  }

  enumeration_value {
    value    = "pepperoni"
    synonyms = ["peperoni"]
  }

  enumeration_value {
    value = "mushroom"
  }

  value_selection_strategy = "TOP_RESOLUTION"
  create_version           = true
}

resource "aws_lex_intent" "order_pizza" {
  name           = "OrderPizza"
  description    = "Order a pizza for delivery"
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "Order me a {size} {crust} pizza with {topping}",
    "Can I get a pizza",
  ]

  slot {
    name             = "size"
    description      = "The size of the pizza"
    slot_constraint  = "Required"
    slot_type        = "AMAZON.AlphaNumeric"
    priority         = 1
    sample_utterances = ["A {size} pizza please"]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like? Small, medium or large?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name            = "crust"
    description     = "The crust of the pizza"
    slot_constraint = "Required"
    slot_type       = aws_lex_slot_type.crust.name
    slot_type_version = aws_lex_slot_type.crust.version
    priority        = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What crust would you like? Thin, thick or hand tossed?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name            = "topping"
    description     = "The topping of the pizza"
    slot_constraint = "Required"
    slot_type       = aws_lex_slot_type.topping.name
    slot_type_version = aws_lex_slot_type.topping.version
    priority        = 3

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "Which topping would you like?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Should I place your pizza order?"
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
      uri             = aws_lambda_function.pizza_order.arn
    }
  }

  depends_on = [aws_lambda_permission.allow_lex]
}

##############################
# Lex bot
##############################

resource "aws_lex_bot" "pizza_order" {
  name             = "PizzaOrderingBot"
  description      = "Bot for ordering pizzas"
  child_directed   = false
  create_version   = true
  idle_session_ttl_in_seconds = 600
  locale           = "en-US"
  process_behavior = "BUILD"
  voice_id         = "Joanna"

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist at this time."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I didn't understand you. What would you like to do?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
