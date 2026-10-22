# Description: checkout unit tests
from src.checkout import start


def test_start_pending():
    assert start({"lines": []})["status"] == "pending"
