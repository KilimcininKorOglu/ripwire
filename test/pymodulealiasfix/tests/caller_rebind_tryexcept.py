try:
    import target_mod as tm
except ImportError:
    import pkg.sub.deep as tm

def uses_rebind_tryexcept():
    return tm.run(1)
