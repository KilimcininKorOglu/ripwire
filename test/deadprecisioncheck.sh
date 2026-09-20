#!/usr/bin/env bash
# deadprecisioncheck.sh — A5 internal-linkage dead-code gate.
#
# T13/fix1 (2026-09-20): --dead-code used to stamp confidence="high" as a hardcoded literal on every
# finding — a claim the code did not support (no per-finding evidence of resolver ambiguity, dynamic
# dispatch or reflection risk backed it). Removed rather than faked: the root no longer carries a
# confidence= attribute at all, and evidence= alone states the (disclosed, name-based) rule every row
# met. This gate used to assert confidence="high" was present; it now asserts it is ABSENT.

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
