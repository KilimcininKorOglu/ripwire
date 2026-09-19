import target_mod as tm

def rebind_global_helper():
    global tm
    tm = 1

def uses_rebind_global():
    return tm.run(1)
