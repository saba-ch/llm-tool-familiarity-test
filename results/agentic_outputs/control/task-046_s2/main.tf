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

resource "aws_lex_slot_type" "crust" {
  name        = "PizzaCrustType"
  description = "Available pizza crusts"

  enumeration_value {
    value    = "thin"
    synonyms = ["thin crust", "crispy"]
  }

  enumeration_value {
    value    = "thick"
    synonyms = ["deep dish", "pan"]
  }

  value_selection_strategy = "TOP_RESOLUTION"
  create_version           = true
}

resource "aws_lex_intent" "order_pizza" {
  name        = "OrderPizza"
  description = "Intent to order a pizza"

  sample_utterances = [
    "I want to order a pizza",
    "Order me a {CrustType} crust pizza",
    "Can I get a pizza",
  ]

  slot {
    name           = "CrustType"
    description    = "The type of pizza crust"
    slot_constraint = "Required"
    slot_type      = aws_lex_slot_type.crust.name
    slot_type_version = aws_lex_slot_type.crust.version
    priority       = 1

    sample_utterances = [
      "I want a {CrustType} crust pizza",
    ]

    value_elicitation_prompt {
      max_attempts = 2

      message {
        content      = "What kind of crust would you like? Thin or thick?"
        content_type = "PlainText"
      }
    }
  }

  confirmation_prompt {
    max_attempts = 2

    message {
      content      = "Okay, a {CrustType} crust pizza. Should I place the order?"
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
      content      = "All right, your {CrustType} crust pizza is on its way!"
      content_type = "PlainText"
    }

    response_card = "{\"version\":1,\"contentType\":\"application/vnd.amazonaws.card.generic\"}"
  }

  fulfillment_activity {
    type = "ReturnIntent"
  }

  create_version = true
}

resource "aws_lex_bot" "pizza_orderer" {
  name             = "PizzaOrderingBot"
  description      = "Bot that takes pizza orders"
  child_directed   = false
  idle_session_ttl_in_seconds = 600
  process_behavior = "BUILD"
  locale           = "en-US"
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
      content      = "I didn't understand you. What would you like to do?"
      content_type = "PlainText"
    }
  }

  intent {
    intent_name    = aws_lex_intent.order_pizza.name
    intent_version = aws_lex_intent.order_pizza.version
  }
}
