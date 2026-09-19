from pkg.target_mod import helper_fn
from pkg.sub.deep import run as _unused_decoy_run  # a SECOND file also defining `run`, reachable from
                                                     # this file's own import graph -- makes Rule 3
                                                     # (file-level import narrow, pre-existing) see TWO
                                                     # candidate files and bail, isolating whether the
                                                     # module-ALIAS rule below fires for helper_fn instead

def uses_fromimport_member():
    return helper_fn.run()
