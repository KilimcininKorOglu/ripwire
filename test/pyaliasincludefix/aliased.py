import pkg.mod as pm
import os.path as osp


def pyai_caller_aliased():
    return pyai_helper() + len( osp.sep )
