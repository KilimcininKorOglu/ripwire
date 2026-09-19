import target_mod as tm

def uses_rebind_except():
    try:
        pass
    except Exception as tm:
        return tm.run(1)
