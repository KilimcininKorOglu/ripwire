from ..a.timer import Timer
from ..b.config import load


def train(path, key):
    timer = Timer()
    cfg = load(path)
    cfg.update({"lr": key})
    return timer, cfg
