import target_mod as tm

def uses_rebind_unresolved():
    return tm.run(1)

import totally_unknown_module_xyz as tm
