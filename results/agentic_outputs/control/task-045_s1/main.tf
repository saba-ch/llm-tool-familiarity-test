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
  description = "Intent that lets a user order a pizza"

  sample_utterances = [
    "I want to order a pizza",
    "Order me a pizza",
    "I would like to order a {PizzaSize} pizza",
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

  # Follow up question asked after the intent is fulfilled.
  follow_up_prompt {
    prompt {
      max_attempts = 2

      message {
        content      = "Would you like to order a drink with your pizza?"
        content_type = "PlainText"
      }
    }

    rejection_statement {
      message {
        content      = "Okay, no drink. Your pizza is on its way!"
        content_type = "PlainText"
      }
    }
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }
}

resource "aws_lex_bot" "pizza_order_bot" {
  name             = "PizzaOrderBot"
  description      = "Bot for ordering pizza"
  child_directed   = false
  locale           = "en-US"
  process_behavior = "BUILD"
  voice_id         = "Salli"

  idle_session_ttl_in_seconds = 600

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist at this time."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I didn't understand you, what would you like to order?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
