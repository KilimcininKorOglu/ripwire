import target_mod as tm

def uses_rebind_defshadow():
    def tm():
        pass
    return tm.run(1)
