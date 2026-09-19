import target_mod as tm

def uses_rebind_with():
    with open("x") as tm:
        return tm.run(1)
