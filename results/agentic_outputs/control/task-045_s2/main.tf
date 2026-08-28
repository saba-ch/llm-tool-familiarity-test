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
    "I would like to order a pizza",
    "Order me a pizza",
    "I want a pizza",
  ]

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Okay, shall I place your pizza order?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I have cancelled your pizza order."
      content_type = "PlainText"
    }
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
        content      = "Okay, no drinks added to your order."
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
  idle_session_ttl_in_seconds = 600
  process_behavior = "BUILD"
  voice_id         = "Salli"

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist at this time."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I did not understand you. What would you like to do?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
