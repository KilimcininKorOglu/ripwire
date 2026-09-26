from .smart import SmartPool


def make_pool():
    return SmartPool()


def via_subclass(pool, key):
    return pool.get(key)
