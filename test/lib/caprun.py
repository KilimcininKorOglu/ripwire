#!/usr/bin/env python3
"""caprun.py — run one command under a wall-clock cap, WITHOUT timeout(1), and say exactly how it ended.

    python3 test/lib/caprun.py CAP_SECONDS [--cwd DIR] [--stdin FILE] [--stdout FILE] [--stderr FILE] -- CMD [ARG ...]

Prints ONE line on stdout, and exits 0 whenever it could report:
    rc=<exit status> ms=<wall milliseconds>     the command ran to completion (any exit status, reported as-is)
    TIMEOUT ms=<wall milliseconds>              the cap elapsed; the command was killed
    EXECFAIL <reason>                           the command could not be started at all (missing, not executable)

WHY THIS EXISTS. mcpstdiolinecapcheck and traceasanlinearcheck ran their binary through `timeout 20 …`. Stock macOS
ships no timeout(1), so on the macOS CI legs the shell answered 127 in about a millisecond: mcpstdiolinecapcheck
failed every arm on "timeout: command not found" (#277, release macos-26 Release shard 3/4), and
traceasanlinearcheck's arm B read that 127 as a 1 ms TIMING SAMPLE and passed vacuously (CodeRabbit on #277). A
runner that cannot start its command must say so in a form no caller can mistake for a measurement, which is what
EXECFAIL is. test/regexguardcheck.sh's capRun solves the same problem in shell; this is the python form, because the
trace gate needs millisecond timing that a 100 ms polling loop cannot give.
"""
import subprocess
import sys
import time


def main(argv):
    if "--" not in argv or len(argv) < 3:
        print("EXECFAIL usage: caprun.py CAP_SECONDS [--cwd DIR] [--stdin FILE] [--stdout FILE] [--stderr FILE] -- CMD [ARG ...]")
        return 2
    split = argv.index("--")
    head, cmd = argv[1:split], argv[split + 1:]
    if not head or not cmd:
        print("EXECFAIL usage: a cap and a command are both required")
        return 2
    cap = float(head[0])
    opts = {"--cwd": None, "--stdin": None, "--stdout": None, "--stderr": None}
    rest = head[1:]
    while rest:
        if rest[0] not in opts or len(rest) < 2:
            print("EXECFAIL usage: unknown or incomplete option %r" % rest[0])
            return 2
        opts[rest[0]] = rest[1]
        rest = rest[2:]

    def sink(path):
        return open(path, "wb") if path else subprocess.DEVNULL

    stdin = open(opts["--stdin"], "rb") if opts["--stdin"] else subprocess.DEVNULL
    stdout, stderr = sink(opts["--stdout"]), sink(opts["--stderr"])
    started = time.monotonic()
    try:
        completed = subprocess.run(cmd, cwd=opts["--cwd"], stdin=stdin, stdout=stdout, stderr=stderr, timeout=cap)
    except subprocess.TimeoutExpired:
        print("TIMEOUT ms=%d" % int((time.monotonic() - started) * 1000))
        return 0
    except OSError as exc:   # FileNotFoundError / PermissionError: nothing ran, so there is nothing to time
        print("EXECFAIL %s: %s" % (type(exc).__name__, exc))
        return 0
    print("rc=%d ms=%d" % (completed.returncode, max(1, int((time.monotonic() - started) * 1000))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
