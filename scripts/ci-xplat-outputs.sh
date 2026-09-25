#!/usr/bin/env bash
# ci-xplat-outputs.sh — the fixed verb set whose output must be the SAME BYTES on Windows and on Linux.
#
# The strongest check a project with no Windows machine has on its Windows binary: run one fixed set of verbs over one
# fixed, committed fixture on both platforms, and diff the bytes (scripts/ci-xplat-diff.sh, in ci.yml's xplat-diff
# job). The map, the ranker, the resolver, the git miner and the MCP server are all platform-neutral code; a Windows
# difference in any of them — a path spelled with '\', a CRLF read as content, a sort keyed on a native path, a
# child process that did not run — shows up here as a byte diff, not as a count that happens to clear a floor.
#
# Three copies of the same fixture, each run through the same five verbs (map, --for, --callers, --impact, --expand):
#   repo-*   test/fixture inside the checkout: git present, so --for's churn=/amp= and at= come from real history
#            (both CI checkouts are full-history, fetch-depth 0, of the same commit; the churn window is anchored to
#            HEAD's commit date, not the wall clock, so the two runs agree whenever they run).
#   tree-*   an LF copy outside any git work tree: the same answers with no git at all.
#   crlf-*   a CRLF copy of tree/ (every "\n" rewritten "\r\n"), made the same way on both platforms. It is how a
#            Windows clone with core.autocrlf=true (the Git for Windows default) reads the fixture.
# plus repo-mcp-* (one MCP stdio session: initialize, tools/list, tools/call impact) and, with --windows, bslash-map
# (the in-repo map with the root spelled test\fixture, the way cmd and PowerShell users type it).
# Every verb gets <name>.xml (stdout) and <name>.rc; stderr goes to <name>.err and is NOT compared (it carries
# platform-specific notes by design). --no-cache everywhere: the cache is (g)'s subject, not this one's.
#
# Usage (from the repo root, under bash — Git Bash on Windows):
#   bash scripts/ci-xplat-outputs.sh <ripwire binary> <out dir> [--windows]
# Exits non-zero when a verb could not run at all or the MCP handshake is malformed; a verb's own non-zero rc is
# recorded, not fatal, so the diff job sees it on both sides.
set -euo pipefail

BIN="${1:?usage: ci-xplat-outputs.sh <ripwire binary> <out dir> [--windows]}"
OUT="${2:?usage: ci-xplat-outputs.sh <ripwire binary> <out dir> [--windows]}"
MODE="${3:-}"
[ -f test/fixture/geometry.cpp ] || { echo "ci-xplat-outputs: run from the repo root (no test/fixture/geometry.cpp here)" >&2; exit 2; }
case "$BIN" in /*|[A-Za-z]:*) ;; *) BIN="$PWD/$BIN" ;; esac
[ -f "$BIN" ] || { echo "ci-xplat-outputs: no binary at $BIN" >&2; exit 2; }
mkdir -p "$OUT"
OUT="$( cd "$OUT" && pwd )"

# `python` first: it is what the Windows image puts on PATH (ci.yml's windows job already relies on it), and a bare
# `python3` there can be the Microsoft Store stub. Ubuntu has only python3.
PY=""
for c in python python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null; then
        PY="$c"; break
    fi
done
[ -n "$PY" ] || { echo "ci-xplat-outputs: no python 3 on PATH" >&2; exit 2; }
# Python on Windows is a native program: hand it Windows spellings (C:/...) rather than rely on Git Bash's argument
# conversion. cygpath exists only under Git Bash/MSYS; elsewhere a path is already the native spelling.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }

TASK="compute the perimeter of a polygon"
# run NAME ROOT [ARGS...] — cwd is the caller's.
run()
{
    local name="$1" root="$2"; shift 2
    local rc=0
    "$BIN" "$root" --no-cache "$@" >"$OUT/$name.xml" 2>"$OUT/$name.err" || rc=$?
    printf '%s\n' "$rc" >"$OUT/$name.rc"
    [ -s "$OUT/$name.xml" ] || { echo "ci-xplat-outputs: $name printed nothing (rc=$rc); stderr:" >&2; cat "$OUT/$name.err" >&2; exit 1; }
}
verbs()   # PREFIX ROOT
{
    run "$1-map"     "$2"
    run "$1-for"     "$2" --for="$TASK"
    run "$1-callers" "$2" --callers=distance
    run "$1-impact"  "$2" --impact=distance
    run "$1-expand"  "$2" --expand=geometry.cpp:perimeter
}

verbs repo test/fixture
if [ "$MODE" = --windows ]; then
    run bslash-map 'test\fixture'
fi

WORK="$( mktemp -d )"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/lf" "$WORK/crlf"
cp -R test/fixture "$WORK/lf/fx"
cp -R test/fixture "$WORK/crlf/fx"
"$PY" - "$( native "$WORK/crlf/fx" )" <<'PY'
import os, sys
for d, _, files in os.walk(sys.argv[1]):
    for f in files:
        p = os.path.join(d, f)
        b = open(p, "rb").read()
        if b"\r" in b:
            sys.exit("ci-xplat-outputs: %s already has CR bytes; the fixture is expected to be LF" % p)
        open(p, "wb").write(b.replace(b"\n", b"\r\n"))
PY
( cd "$WORK/lf"   && verbs tree fx )
( cd "$WORK/crlf" && verbs crlf fx )

# One MCP stdio session against the same binary: the handshake an agent host performs, then one real tool call.
"$PY" - "$( native "$BIN" )" "$( native "$OUT" )" <<'PY'
import json, subprocess, sys
bin_, out = sys.argv[1], sys.argv[2]
msgs = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize",
     "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "ci-xplat", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "impact", "arguments": {"path": "test/fixture", "symbol": "distance"}}},
]
stdin = "".join(json.dumps(m) + "\n" for m in msgs).encode()
p = subprocess.run([bin_, "--mcp"], input=stdin, capture_output=True, timeout=120)
lines = [l for l in p.stdout.decode("utf-8").splitlines() if l.strip()]
byid = {}
for l in lines:
    r = json.loads(l)
    if "id" in r:
        byid[r["id"]] = r
def need(cond, why):
    if not cond:
        sys.stderr.write("ci-xplat-outputs: MCP handshake: %s\nrc=%d stdout=%r\nstderr=%r\n" % (why, p.returncode, lines[:4], p.stderr[-800:]))
        sys.exit(1)
need(set(byid) == {1, 2, 3}, "expected responses to ids 1, 2, 3, got %s" % sorted(byid))
need(byid[1].get("result", {}).get("serverInfo", {}).get("name") == "ripwire", "initialize did not answer serverInfo.name=ripwire")
tools = [t["name"] for t in byid[2].get("result", {}).get("tools", [])]
need("impact" in tools, "tools/list does not offer impact: %s" % tools)
text = byid[3].get("result", {}).get("content", [{}])[0].get("text", "")
need("<impact" in text and 'n="perimeter"' in text, "tools/call impact did not return the impact of distance (perimeter missing)")
open(out + "/repo-mcp-init.json", "w", encoding="utf-8", newline="\n").write(json.dumps(byid[1]["result"], sort_keys=True) + "\n")
open(out + "/repo-mcp-tools.txt", "w", encoding="utf-8", newline="\n").write("\n".join(tools) + "\n")
open(out + "/repo-mcp-impact.xml", "w", encoding="utf-8", newline="\n").write(text)
print("MCP handshake ok: serverInfo.name=ripwire, %d tools, impact(distance) %d bytes" % (len(tools), len(text)))
PY

n="$( find "$OUT" -name '*.xml' | wc -l | tr -d ' ' )"
echo "ci-xplat-outputs: $n outputs in $OUT ($( "$BIN" --version | head -1 ))"
