#!/usr/bin/env bash
# mcpstdiolinecapcheck.sh — the INPUT BLOW-UP guard on the --mcp stdio transport's request LINE
# (src/infra/stdinline.h readByteSafeLineBounded / src/mcp.h kMcpStdioLineMaxBytes).
#
# THE DEFECT. The stdio JSON-RPC loop (src/mcp.h runMcp) read one request per line with
# readByteSafeLine, whose OWN contract is to grow without limit — the right behaviour for its other
# callers (gitmine.h's git-pipe readers, where a long path must never be split), but wrong for an
# untrusted network-shaped peer: a single line with no '\n' grows the buffer for as long as the peer
# keeps writing, so one runaway or hostile stdio client could exhaust memory on a long-lived server one
# line at a time. The HTTP transport (mcpserver.h) already bounds a request body at kMaxBodyBytes (8 MiB)
# before it ever reaches the JSON-RPC layer; stdio had no equivalent.
#
# THE FIX. readByteSafeLineBounded (stdinline.h) reads the SAME byte-safe way but stops growing `line` at
# kMcpStdioLineMaxBytes (32 MiB — a little above HTTP's bound, since a stdio edit-verb call carries its
# payload inline in the same line) and DRAINS the remainder of an over-limit line without buffering it, so
# the stream position still recovers at the next '\n'. runMcp() refuses an over-limit line with a named
# JSON-RPC error (code -32600, id:null per the JSON-RPC 2.0 "id unknown" rule) and keeps the loop running —
# the request line is never handed to dispatchMcpLine, and the connection is not dropped.
#
# Every arm asserts:
#   1. An under-limit request dispatches exactly as before (no false positive).
#   2. An over-limit request is refused with the NAMED error, not a crash, a hang or a generic parse
#      failure — and the refusal names the limit (the byte count appears in the message).
#   3. THE SERVER KEEPS SERVING — a normal request sent immediately after the refused one still gets a
#      real answer, on the SAME process / SAME stdin stream.
#   4. RSS during the over-limit request stays a small, bounded multiple of the cap, never approaching the
#      size of the line the peer sent — proving the line was drained, not buffered.
#
# MUTATION CONTROL: assertion 2/3 are exactly what reverting to plain readByteSafeLine removes — the
# process still ANSWERS (eventually), so this is a memory/behaviour regression a naive "does it crash"
# probe would miss; RSS (arm D) is the one that catches it directly. Run against a pre-fix binary —
#   RIPWIRE_BIN=<base>/ripwire bash test/mcpstdiolinecapcheck.sh
# — and arm B/D must FAIL (no refusal message; RSS tracks the line size) while arm A still passes.
#
# Usage:  bash test/mcpstdiolinecapcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/mcpstdiolinecapcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "mcpstdiolinecapcheck: python3 required"; exit 2; }
echo "mcpstdiolinecapcheck: BIN=$BIN"

# ===================================================================================================
# (P) THE RUNNER — every --mcp run below goes through test/lib/caprun.py, never timeout(1). Stock macOS ships no
# timeout(1): on the macOS CI legs `timeout 30 …` answered 127 and every arm below failed on "timeout: command not
# found" (#277, release macos-26 Release shard 3/4). The runner is proven here on this host before any arm trusts it:
# it passes an exit status through, it enforces the cap, and it reports a command it cannot start as EXECFAIL, which
# no arm below can read as an rc.
# ===================================================================================================
echo "-- (P) the capped runner works on this host"
CAPRUN="$ROOT/test/lib/caprun.py"
capRun(){ python3 "$CAPRUN" "$@" 2>&1 | tail -1; }   # capRun SECONDS [opts] -- CMD… -> "rc=N ms=M" | "TIMEOUT ms=M" | "EXECFAIL …"
if [ ! -f "$CAPRUN" ]; then
    no "P0: the runner test/lib/caprun.py is missing — no arm below can run"
else
    P1="$( capRun 5 -- sh -c 'exit 3' )"; P2="$( capRun 1 -- sleep 5 )"; P3="$( capRun 5 -- "$TMP/no-such-binary" )"
    case "$P1" in "rc=3 "*) ok "P1: an exit status passes through the runner ($P1)" ;; *) no "P1: the runner did not report rc=3: $P1" ;; esac
    case "$P2" in "TIMEOUT "*) ok "P2: the runner enforces its cap ($P2)" ;; *) no "P2: the runner did not time out a 5 s sleep under a 1 s cap: $P2" ;; esac
    case "$P3" in "EXECFAIL "*) ok "P3: a command that cannot start is EXECFAIL, never an exit status" ;; *) no "P3: a missing command was not reported as EXECFAIL: $P3" ;; esac
fi
# rcOf RESULT -> the exit status, or empty when the run did not complete (TIMEOUT / EXECFAIL), so a caller compares
# against a real number and an unfinished run can never equal one.
rcOf(){ case "$1" in "rc="*) printf '%s' "${1#rc=}" | cut -d' ' -f1 ;; *) printf '' ;; esac; }

mkdir -p "$TMP/pkg"
cat > "$TMP/pkg/mod.py" <<'PY'
def hello():
    return 1
PY

CAP=33554432   # kMcpStdioLineMaxBytes — kept in sync by eye; a drift here just weakens the boundary,
               # it cannot false-PASS (arm B checks the message NAMES the limit, whatever it is)

# ===================================================================================================
# (A) an under-limit request dispatches normally
# ===================================================================================================
echo "-- (A) a 1 MB request line dispatches normally"
python3 -c "
import json
print(json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call',
                   'params':{'name':'grep','arguments':{'path':'.','pattern':'hello'}}}) + ' ' * 1000000)
" > "$TMP/req_a.txt" 2>/dev/null || true
# pad INSIDE a JSON string so the request stays valid JSON, not trailing garbage
python3 -c "
import json
req = {'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'grep','arguments':{'path':'.','pattern':'hello' + 'x'*900000}}}
print(json.dumps(req))
" > "$TMP/req_a.txt"
OUT_A="$( "$BIN" "$TMP" --mcp < "$TMP/req_a.txt" 2>"$TMP/req_a.err" )"
RC_A=$?
if [ "$RC_A" = 0 ] && printf '%s' "$OUT_A" | grep -q '"id":1'; then
    ok "A1: a ~1 MB under-limit request line is dispatched and answered"
else
    no "A1: the under-limit request did not dispatch (rc=$RC_A)"; cat "$TMP/req_a.err"; printf '%s\n' "$OUT_A" | head -c 300
fi

# ===================================================================================================
# (B) an over-limit request line is refused with a NAMED JSON-RPC error, not a crash or a hang
# ===================================================================================================
echo "-- (B) a 160 MB request line is refused with a named error"
python3 -c "
pad = 'A' * 167772160
line = '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"pad\":\"' + pad + '\"}'
open('$TMP/req_b.txt', 'w').write(line + chr(10))
open('$TMP/req_b_followup.txt', 'w').write(chr(10).join([
    line,
    '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}',
]) + chr(10))
"
RUN_B="$( capRun 30 --stdin "$TMP/req_b.txt" --stdout "$TMP/req_b.out" --stderr "$TMP/req_b.err" -- "$BIN" "$TMP" --mcp )"
OUT_B="$( cat "$TMP/req_b.out" 2>/dev/null )"
RC_B="$( rcOf "$RUN_B" )"
if [ "$RC_B" = 0 ]; then
    ok "B1: rc=0 on the over-limit line (no crash, no hang)"
else
    no "B1: --mcp did not finish with rc=0 on a 160 MB request line ($RUN_B)"; cat "$TMP/req_b.err" 2>/dev/null
fi
if printf '%s' "$OUT_B" | grep -q '"code":-32600' && printf '%s' "$OUT_B" | grep -q "$CAP"; then
    ok "B2: the refusal is JSON-RPC code -32600 and NAMES the $CAP-byte limit"
else
    no "B2: the refusal did not carry code -32600 and the named limit"; printf '%s\n' "$OUT_B" | head -c 300
fi
if printf '%s' "$OUT_B" | grep -q '"id":null'; then
    ok "B3: the refusal uses id:null (no field in an over-limit frame is a reliable id)"
else
    no "B3: the refusal did not use id:null"
fi

# ===================================================================================================
# (C) THE SERVER KEEPS SERVING — a normal request right after the refused one still gets answered, on
# the SAME stdin stream / SAME process
# ===================================================================================================
echo "-- (C) the server keeps serving after an over-limit line"
RUN_C="$( capRun 30 --stdin "$TMP/req_b_followup.txt" --stdout "$TMP/req_c.out" --stderr "$TMP/req_c.err" -- "$BIN" "$TMP" --mcp )"
OUT_C="$( cat "$TMP/req_c.out" 2>/dev/null )"
RC_C="$( rcOf "$RUN_C" )"
LINES_C="$( printf '%s\n' "$OUT_C" | wc -l | tr -d ' ' )"
if [ "$RC_C" = 0 ] && [ "$LINES_C" -ge 2 ]; then
    ok "C1: the process emitted 2 response lines (the refusal, then the next request's real answer)"
else
    no "C1: expected 2 response lines after the oversized line, got $LINES_C ($RUN_C)"; cat "$TMP/req_c.err" 2>/dev/null
fi
if printf '%s' "$OUT_C" | grep -q '"id":2' && printf '%s' "$OUT_C" | grep -q '"result"'; then
    ok "C2: the follow-up request (id=2, a plain ping) got a real result — the connection was not dropped"
else
    no "C2: the follow-up request after the refusal did not get a real result"; printf '%s\n' "$OUT_C" | tail -c 300
fi

# ===================================================================================================
# (D) RSS stays bounded — the 160 MB line must NOT be buffered in full (the pre-fix behaviour).
# 160 MB is chosen to sit well ABOVE the 32 MB cap plus any bounded reader's own overhead, so a
# reader that still buffers the whole line (the pre-fix readByteSafeLine) is clearly distinguishable
# from one that drains past the cap (this fix) on RSS alone, not just on the refusal message.
# ===================================================================================================
echo "-- (D) peak RSS on the 160 MB line stays well under the line size"
if command -v /usr/bin/time >/dev/null 2>&1 && /usr/bin/time -l true >/dev/null 2>"$TMP/rss_probe.txt"; then
    /usr/bin/time -l "$BIN" "$TMP" --mcp < "$TMP/req_b.txt" >/dev/null 2>"$TMP/time_d.txt"
    RSS_D="$( grep 'maximum resident set size' "$TMP/time_d.txt" | awk '{print $1}' )"
    if [ -n "$RSS_D" ] && [ "$RSS_D" -lt 100000000 ]; then
        ok "D1: peak RSS ${RSS_D} bytes stays under 100 MB on a 160 MB request line (the line was drained, not buffered)"
    else
        no "D1: peak RSS '${RSS_D}' bytes is missing or too high for a bounded reader"
    fi
else
    echo "  SKIP  D1: /usr/bin/time -l unavailable on this platform (macOS/BSD form expected)"
fi

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
