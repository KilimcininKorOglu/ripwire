from .pool import ConnectionPool


def true_local(key):
    pool = ConnectionPool()
    return pool.get(key)


class PoolUser:
    def __init__(self):
        self.pool = ConnectionPool()

    def true_field(self, key):
        return self.pool.get(key)
