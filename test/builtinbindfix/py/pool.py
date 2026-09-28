class ConnectionPool:
    def __init__(self):
        self._conns = {}

    def get(self, key):
        return self._conns.get(key)

    def checkout(self):
        return self._conns

    def render(self, rows):
        def decode(raw):
            return raw

        return [decode(row) for row in rows]
