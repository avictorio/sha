# Description: cart unit tests
from src.cart import subtotal


def test_subtotal():
    # TODO: add a test for empty carts
    assert subtotal([{"qty": 2, "price": 1.5}]) == 3.0
