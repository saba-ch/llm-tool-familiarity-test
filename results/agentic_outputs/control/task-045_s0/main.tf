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
    "I would like to order a pizza",
    "Can I get a pizza",
  ]

  fulfillment_activity {
    type = "ReturnIntent"
  }

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
        content      = "Okay, no drink then. Your pizza order is complete."
        content_type = "PlainText"
      }
    }
  }
}

resource "aws_lex_bot" "order_pizza" {
  name             = "OrderPizzaBot"
  description      = "Bot for ordering pizza"
  child_directed   = false
  process_behavior = "BUILD"
  locale           = "en-US"

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
      content      = "I didn't understand you. What would you like to do?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
