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

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent to order a pizza"

  sample_utterances = [
    "I want to order a pizza",
    "I want to order a {PizzaSize} pizza",
    "Order me a pizza",
  ]

  slot {
    name             = "PizzaSize"
    description      = "The size of the pizza to order"
    slot_constraint  = "Required"
    slot_type        = "AMAZON.AlphaNumeric"
    priority         = 1
    sample_utterances = [
      "A {PizzaSize} pizza please",
    ]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What size pizza would you like? Small, medium or large?"
        content_type = "PlainText"
      }
    }
  }

  slot {
    name            = "PizzaCount"
    description     = "How many pizzas to order"
    slot_constraint = "Required"
    slot_type       = "AMAZON.NUMBER"
    priority        = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "How many pizzas would you like to order?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Should I place your order for {PizzaCount} {PizzaSize} pizza(s)?"
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
      message_version = "1"
      uri             = "arn:aws:lambda:us-east-1:123456789012:function:OrderPizzaFulfillment"
    }
  }

  conclusion_statement {
    message {
      content      = "All right, I have ordered your {PizzaCount} {PizzaSize} pizza(s). They will be ready in about 20 minutes."
      content_type = "PlainText"
    }

    response_card = "{\"version\":1,\"contentType\":\"application/vnd.amazonaws.card.generic\"}"
  }
}

resource "aws_lex_bot" "pizza_order_bot" {
  name             = "PizzaOrderBot"
  description      = "Bot for ordering pizzas"
  child_directed   = false
  create_version   = false
  idle_session_ttl_in_seconds = 600
  locale           = "en-US"
  process_behavior = "BUILD"
  voice_id         = "Salli"

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I did not understand you. What would you like to order?"
      content_type = "PlainText"
    }
  }

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist at this time. Goodbye."
      content_type = "PlainText"
    }
  }
}
