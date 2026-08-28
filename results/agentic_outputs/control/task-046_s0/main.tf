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
  name           = "OrderPizza"
  description    = "Intent that lets a customer order a pizza"
  create_version = true

  sample_utterances = [
    "I want to order a pizza",
    "I want to order a {PizzaSize} pizza",
    "Order me a {PizzaSize} {PizzaCrust} crust pizza",
  ]

  slot {
    name           = "PizzaSize"
    description    = "The size of the pizza to order"
    slot_constraint = "Required"
    slot_type      = "AMAZON.AlphaNumeric"
    priority       = 1

    sample_utterances = [
      "I want a {PizzaSize} pizza",
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
    name           = "PizzaCrust"
    description    = "The crust of the pizza to order"
    slot_constraint = "Required"
    slot_type      = "AMAZON.AlphaNumeric"
    priority       = 2

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What crust would you like? Thin or thick?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Should I place your order for a {PizzaSize} {PizzaCrust} crust pizza?"
      content_type = "PlainText"
    }
  }

  rejection_statement {
    message {
      content      = "Okay, I have cancelled your pizza order."
      content_type = "PlainText"
    }
  }

  conclusion_statement {
    message {
      content      = "All right, I have ordered your {PizzaSize} {PizzaCrust} crust pizza. It will be ready in about 20 minutes. Thanks for your order!"
      content_type = "PlainText"
    }

    response_card = "{\"version\":1,\"contentType\":\"application/vnd.amazonaws.card.generic\",\"genericAttachments\":[{\"title\":\"Order complete\",\"subTitle\":\"Your pizza is on the way\"}]}"
  }

  fulfillment_activity {
    type = "CodeHook"

    code_hook {
      message_version = "1"
      uri             = "arn:aws:lambda:us-east-1:123456789012:function:PizzaOrderFulfillment"
    }
  }
}

resource "aws_lex_bot" "pizza_order_bot" {
  name             = "PizzaOrderBot"
  description      = "Bot that takes pizza orders"
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

  abort_statement {
    message {
      content      = "Sorry, I am not able to assist with your pizza order at this time."
      content_type = "PlainText"
    }
  }

  clarification_prompt {
    max_attempts = 2

    message {
      content      = "I didn't understand you. What would you like to order?"
      content_type = "PlainText"
    }
  }
}
