# fnliteralcheck fixture (Python): a lambda bound to a class attribute is callable surface with a body.


def py_sink(v):
    return v + 1


class Holder:
    py_lambda = lambda self, x: py_sink(x)

    def use_py(self):
        return self.py_lambda(1)
