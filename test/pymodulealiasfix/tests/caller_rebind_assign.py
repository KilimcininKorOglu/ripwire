import target_mod as tm

def uses_rebind_assign():
    tm = {"run": lambda x: x}
    return tm.run(1)
