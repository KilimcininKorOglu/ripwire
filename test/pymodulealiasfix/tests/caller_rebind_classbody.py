import target_mod as tm

class RebindClassBody:
    tm = {"run": lambda x: x}

    def uses_rebind_classbody(self):
        return tm.run(1)
