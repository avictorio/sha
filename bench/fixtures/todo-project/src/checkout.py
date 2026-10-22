# Description: checkout flow and payment hand-off
from src.cart import total


def start(cart):
    amount = total(cart["lines"])
    # TODO: handle declined cards with a retry message
    return {"amount": amount, "status": "pending"}
