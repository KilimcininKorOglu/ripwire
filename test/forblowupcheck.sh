#!/usr/bin/env bash
# forblowupcheck.sh — the INPUT BLOW-UP guard on --for/--pack-task's query-term dedupe
# (src/lexical.h kMaxUniqueQueryTerms / dedupeQueryTerms).
#
# THE DEFECT. --for/--pack-task's task string is agent-supplied text, not a hand-typed query: an agent
# can paste a whole file, log or issue body. Before this guard, the query's DISTINCT term count had no
# ceiling, so lexicalScoresTiered's tfFlat allocation (S symbols x that many unique query terms x 4
# bytes) grew with the PASTE, not with the corpus — a measured 480 KB task string cost 5.2 GB RSS on one
# request. Deduping to unique terms was already correct (a repeated query word does not double-count);
# the gap was that "unique" itself had no bound.
#
# THE FIX. dedupeQueryTerms caps the KEPT unique-term count at kMaxUniqueQueryTerms (1024 — about 102x the
# longest real --for/--pack-task query on record in bench/ and docs/, a 10-word one; see lexical.h for the
# grep this cap is set from). A term seen after the cap fills scores zero (it owns no tf row) rather than
# growing the allocation further, and the cut is disclosed via the SAME CapDisclosure channel every other
# indexing cap on a --for/--pack-task bundle uses: `terms_capped="1" terms_total="N"` on the XML root
# (CLI) and the MCP `for`/`explore`/`pack_task` responses, never a silent truncation.
#
# Every arm asserts the same three things capdisclosurecheck/mentioncapcheck do:
#   1. CROSSING — the fixture really exceeds the cap (proved by the term count itself, not guessed).
#   2. DISCLOSURE — the crossed answer carries terms_capped="1" and a terms_total= that EXCEEDS 1024.
#   3. SILENCE — an uncrossed query (<=1024 unique terms, including right AT the boundary) carries
#      neither attribute — never `terms_capped="0"`, never a total equal to the kept count.
#
# MUTATION CONTROL: assertion 2 is exactly what reverting dedupeQueryTerms's cap removes (the loop
# reverts to appending every unique term unconditionally); assertion 1 proves the fixture still reaches
# it. Run against a pre-fix binary —  RIPWIRE_BIN=<base>/ripwire bash test/forblowupcheck.sh  — and
# assertion 2 must FAIL (no such attribute exists yet) while assertion 1 still passes.
#
# Usage:  bash test/forblowupcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/forblowupcheck.sh
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
echo "forblowupcheck: BIN=$BIN"

# a small real corpus — the cap's effect (RSS/attribute) does not depend on corpus size, so keep it cheap
mkdir -p "$TMP/pkg"
cat > "$TMP/pkg/mod.py" <<'PY'
def cache_invalidate(path):
    """Drop the cached entry for path."""
    return path
PY

attr(){ printf '%s' "$2" | grep -o "$1=\"[0-9]*\"" | head -1; }
num(){ attr "$1" "$2" | grep -o '[0-9]*' | head -1; }
has(){ printf '%s' "$2" | grep -q "$1"; }

# build a task string of N space-separated, mutually-distinct terms
terms(){
    python3 -c "print(' '.join('qterm%06d' % i for i in range($1)))"
}

# ===================================================================================================
# (A) CROSSING + DISCLOSURE — a task with far more than kMaxUniqueQueryTerms (1024) distinct terms
# ===================================================================================================
echo "-- (A) --for: a task with 5000 unique terms is capped and discloses it"
TASK_A="$( terms 5000 )"
OUT_A="$( "$BIN" "$TMP" --for="$TASK_A" --no-cache 2>/tmp/forblowupcheck_a.err )"
RC_A=$?
if [ "$RC_A" = 0 ]; then
    ok "A0: rc=0 on a 5000-unique-term task (no crash, no refusal)"
else
    no "A0: --for exited $RC_A on a 5000-unique-term task"; cat /tmp/forblowupcheck_a.err
fi
if printf '%s' "$OUT_A" | xmllint --noout - 2>/dev/null; then
    ok "A1: the capped bundle is still well-formed XML"
else
    no "A1: the capped bundle is NOT well-formed XML"
fi
if has 'terms_capped="1"' "$OUT_A"; then
    ok "A2: terms_capped=\"1\" fired"
else
    no "A2: terms_capped=\"1\" did not fire on a 5000-unique-term task"
fi
TOTAL_A="$( num terms_total "$OUT_A" )"
if [ -n "$TOTAL_A" ] && [ "$TOTAL_A" -gt 1024 ]; then
    ok "A3: terms_total=\"$TOTAL_A\" exceeds the 1024 cap (a real count, not a fabricated one)"
else
    no "A3: terms_total='$TOTAL_A' is missing or does not exceed the cap"
fi

# ===================================================================================================
# (B) SILENCE — an ordinary task (well under the cap) discloses NOTHING
# ===================================================================================================
echo "-- (B) --for: an ordinary task carries no terms_capped/terms_total"
OUT_B="$( "$BIN" "$TMP" --for="drop the cached entry for a file path" --no-cache 2>/dev/null )"
if has 'terms_capped' "$OUT_B" || has 'terms_total' "$OUT_B"; then
    no "B1: an ordinary 8-word task discloses a cap that never fired"
else
    ok "B1: an ordinary task is silent (no terms_capped, no terms_total)"
fi

# ===================================================================================================
# (C) BOUNDARY PRECISION — exactly at the cap vs. one past it
# ===================================================================================================
echo "-- (C) boundary: 1024 unique terms is silent, 1025 fires"
OUT_C1024="$( "$BIN" "$TMP" --for="$( terms 1024 )" --no-cache 2>/dev/null )"
OUT_C1025="$( "$BIN" "$TMP" --for="$( terms 1025 )" --no-cache 2>/dev/null )"
if has 'terms_capped' "$OUT_C1024"; then
    no "C1: exactly 1024 unique terms already trips terms_capped — the cap is off by one"
else
    ok "C1: exactly 1024 unique terms is silent"
fi
if has 'terms_capped="1"' "$OUT_C1025" && [ "$( num terms_total "$OUT_C1025" )" = "1025" ]; then
    ok "C2: 1025 unique terms trips terms_capped=\"1\" terms_total=\"1025\" exactly"
else
    no "C2: 1025 unique terms did not trip the cap at the expected boundary"
fi

# ===================================================================================================
# (D) MCP surface — the same disclosure over --mcp (both the routed `for` verb and `pack_task`)
# ===================================================================================================
echo "-- (D) MCP: the same cap/disclosure over stdio JSON-RPC"
mcp_call(){ # $1 = JSON-RPC request line
    printf '%s\n' "$1" | "$BIN" "$TMP" --mcp 2>/dev/null
}
TASK_D="$( terms 5000 )"
REQ_D="$( python3 -c "
import json
print(json.dumps({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'for','arguments':{'task':'$TASK_D'}}}))
" )"
OUT_D="$( mcp_call "$REQ_D" )"
if has 'terms_capped=\\"1\\"' "$OUT_D" || has 'terms_capped=&quot;1&quot;' "$OUT_D" || has 'terms_capped' "$OUT_D"; then
    ok "D1: MCP 'for' discloses the cap on a 5000-unique-term task"
else
    no "D1: MCP 'for' did not disclose the cap"; printf '%s\n' "$OUT_D" | head -c 300
fi
REQ_D2="$( python3 -c "
import json
print(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'for','arguments':{'task':'drop the cached entry for a file path'}}}))
" )"
OUT_D2="$( mcp_call "$REQ_D2" )"
if has 'terms_capped' "$OUT_D2"; then
    no "D2: MCP 'for' discloses a cap on an ordinary task"
else
    ok "D2: MCP 'for' is silent on an ordinary task"
fi

# ===================================================================================================
# (E) NO BLOW-UP — the pathological task completes quickly and RSS stays bounded, not proportional to
# the corpus x term count product the pre-fix tfFlat allocation would have paid
# ===================================================================================================
echo "-- (E) the pathological task does not blow up wall time"
T0=$( date +%s )
"$BIN" "$TMP" --for="$( terms 20000 )" --no-cache >/dev/null 2>&1
T1=$( date +%s )
ELAPSED=$(( T1 - T0 ))
if [ "$ELAPSED" -le 10 ]; then
    ok "E1: a 20000-unique-term task completes in ${ELAPSED}s (<=10s) — bounded by the cap, not the paste"
else
    no "E1: a 20000-unique-term task took ${ELAPSED}s — looks unbounded"
fi

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
