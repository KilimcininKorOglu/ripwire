import target_mod as tm

def uses_rebind_for():
    for tm in range(3):
        pass
    return tm.run(1)
