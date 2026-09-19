import target_mod as tm

def uses_rebind_module():
    return tm.run(1)

tm = {"run": lambda x: x}
