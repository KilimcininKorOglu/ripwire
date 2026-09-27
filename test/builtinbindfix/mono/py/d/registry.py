class Registry:
    def __init__(self):
        self._items = {}

    def pop(self, key):
        return self._items.pop(key)
