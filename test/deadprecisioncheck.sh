#!/usr/bin/env bash
# deadprecisioncheck.sh — A5 internal-linkage dead-code gate.
#
# T13/fix1 (2026-09-20): --dead-code used to stamp confidence="high" as a hardcoded literal on every
# finding — a claim the code did not support (no per-finding evidence of resolver ambiguity, dynamic
# dispatch or reflection risk backed it). Removed rather than faked: the root no longer carries a
# confidence= attribute at all, and evidence= alone states the (disclosed, name-based) rule every row
# met. This gate used to assert confidence="high" was present; it now asserts it is ABSENT.
#
# 0.6.6 D4 (arms R1-R4, a temp tree): a pytest test method was a high-confidence row because the Python def's
# signature span runs on through the comment that opens its body ("# the static type is unchanged").
#   R1  a `static` inside a comment is not linkage evidence (Python `#`, C `//` and `/* */`) — no row;
#   R2  a Python def a test runner or a decorator reaches is never a row, even with a real `static` token in its
#       signature (pytest test*/xunit hook in test_*.py, a test*/setUp method of a TestCase subclass, @decorated).
#       The two reasons are counted apart (review of 0.6.6 D4): runner-root-excluded= counts the test-runner roots only,
#       decorated-excluded= the decorated defs (a decorator MAY register the def; a wrapper such as @property may not);
#   R3  the C control: a real `static` orphan is still a row;
#   R4  --safe-delete's dead_code_candidate= asks the same shape: 0 on a runner root, 1 on the C orphan.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/deadfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --dead-code --no-cache >"$TMP/b" 2>/dev/null
diff -q "$TMP/a" "$TMP/b" >/dev/null || { echo "FAIL dead-code output is not deterministic"; exit 1; }

python3 - "$TMP/a" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
if root.get("confidence") is not None:
    raise SystemExit("FAIL dead-code must not stamp a confidence= it cannot support (found %r)" % root.get("confidence"))
if root.get("evidence") != "internal-linkage+zero-callers":
    raise SystemExit("FAIL dead-code default must qualify its graph evidence")

names = [node.get("n") for node in root.findall("d")]
if names != ["orphan"] or root.get("count") != "1":
    raise SystemExit(f"FAIL expected only internal static orphan, found {names}")

print("PASS internal-only dead candidate=orphan, no confidence= claim")
PY

# ── 0.6.6 D4: comments and Python runner roots ────────────────────────────────────────────────────────────────
T="$TMP/runner"; mkdir -p "$T/tests" "$T/pkg" "$T/c"
cat >"$T/tests/test_things.py" <<'PYSRC'
import unittest
import pytest


@pytest.fixture
def resource(static=1):
    return static


def test_top_level():
    # the static type is unchanged
    assert True


def test_param(static=2):
    assert static


def setup_module(static=None):
    pass


class TestGroup:
    def test_method(self):
        # the static type is unchanged
        assert True


class LegacyCase(unittest.TestCase):
    def setUp(self, static=None):
        self.x = 1

    def test_case(self, static=None):
        self.assertEqual(self.x, 1)
PYSRC
cat >"$T/pkg/core.py" <<'PYSRC'
def app_route(fn):
    return fn


@app_route
def handler(static=3):
    return static


def orphan_commented():
    # nothing calls this static helper
    return 4
PYSRC
cat >"$T/c/unit.c" <<'CSRC'
static int orphan_c( void )
{
    return 5;
}

int commented_c( void ) // not static
{
    return 6;
}

int block_c( void ) /* static in a block */
{
    return 7;
}
CSRC
"$BIN" "$T" --dead-code --no-cache >"$TMP/r" 2>"$TMP/r.err" || { echo "FAIL R dead-code on the runner tree exited non-zero"; cat "$TMP/r.err"; exit 1; }
python3 - "$TMP/r" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
names = [node.get("n") for node in root.findall("d")]
if names != ["orphan_c"]:
    raise SystemExit(f"FAIL R1/R2/R3 expected only the C static orphan, found {names}")
if root.get("runner-root-excluded") != "4":
    raise SystemExit(f"FAIL R2 runner-root-excluded= should count the 4 test-runner roots (test_param, setup_module, setUp, test_case), found {root.get('runner-root-excluded')!r}")
if root.get("decorated-excluded") != "2":
    raise SystemExit(f"FAIL R2 decorated-excluded= should count the 2 decorated defs (@pytest.fixture resource, @app_route handler), found {root.get('decorated-excluded')!r}")
print("PASS R1-R3 comment static is not linkage; test-runner roots (runner-root-excluded=4) and decorated defs (decorated-excluded=2) counted apart; C orphan kept")
PY
[ $? -eq 0 ] || exit 1
if grep -qE 'runner-root-excluded|decorated-excluded' "$TMP/a"; then echo "FAIL R2 runner-root-excluded=/decorated-excluded= must be absent at 0 (deadfix corpus)"; exit 1; fi
sd_py="$( "$BIN" "$T" --safe-delete=tests/test_things.py:test_param --no-cache 2>/dev/null )"
sd_c="$( "$BIN" "$T" --safe-delete=c/unit.c:orphan_c --no-cache 2>/dev/null )"
case "$sd_py" in *'dead_code_candidate="0"'*) ;; *) echo "FAIL R4 safe-delete on a pytest root must say dead_code_candidate=0"; exit 1;; esac
case "$sd_c" in *'dead_code_candidate="1"'*) ;; *) echo "FAIL R4 safe-delete on the C static orphan must say dead_code_candidate=1"; exit 1;; esac
echo "PASS R4 safe-delete dead_code_candidate= agrees (runner root 0, C orphan 1)"
