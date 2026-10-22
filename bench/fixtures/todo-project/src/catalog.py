# Description: product catalog lookups
_CACHE = {}


def get(sku):
    # FIXME: cache invalidation is naive
    if sku not in _CACHE:
        _CACHE[sku] = {"sku": sku, "name": sku.title()}
    return _CACHE[sku]
