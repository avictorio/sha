# Description: stock levels and reorder alerts
REORDER_LEVEL = 10


def needs_reorder(qty):
    # TODO: make the reorder level configurable per SKU
    return qty < REORDER_LEVEL
