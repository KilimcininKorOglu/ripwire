import target_mod as tm

def rebind_negctrl_helper():
    global unrelated_name
    unrelated_name = 5

def uses_rebind_negctrl():
    return tm.run(1)
