# Description: cart totals and discounts
from src.utils.money import fmt


def subtotal(lines):
    return sum(line["qty"] * line["price"] for line in lines)


def total(lines, discount=0.0):
    # TODO: apply coupon stacking rules
    sub = subtotal(lines)
    result = sub - discount  # TODO: clamp at zero
    return result


def summary(lines):
    # TODO: round per line item, not per cart
    return fmt(total(lines))
