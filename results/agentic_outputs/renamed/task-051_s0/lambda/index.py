import json


def handler(event, context):
    """Simple Lex fulfillment hook for the pizza ordering bot."""
    slots = event.get("currentIntent", {}).get("slots", {})
    crust = slots.get("crust", "hand tossed")
    size = slots.get("size", "medium")
    topping = slots.get("topping", "cheese")

    message = "Your {} {} pizza with {} is on its way!".format(size, crust, topping)

    return {
        "dialogAction": {
            "type": "Close",
            "fulfillmentState": "Fulfilled",
            "message": {"contentType": "PlainText", "content": message},
        }
    }
