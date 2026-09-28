import os


def dict_get(key):
    table = {}
    return table.get(key)


def param_get(config, key):
    return config.get(key)


def env_get(key):
    return os.environ.get(key)


def bytes_decode(raw):
    return raw.decode("utf-8")


def untyped_checkout(pool):
    return pool.checkout()


class Cache:
    def __init__(self):
        self.store = {}

    def lookup(self, key):
        return self.store.get(key)
