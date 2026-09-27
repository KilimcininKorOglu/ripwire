from ..d.instance import registry


def take(key):
    return registry.pop(key)
