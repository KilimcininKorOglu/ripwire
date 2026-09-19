import target_mod as tm

def uses_rebind_walrus():
    if (tm := {"run": lambda x: x}):
        return tm.run(1)
