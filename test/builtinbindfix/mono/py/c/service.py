class Service:
    def __init__(self, pool):
        self.pool = pool

    def run(self):
        return self.pool.popitem()
