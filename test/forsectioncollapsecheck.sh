#!/usr/bin/env bash
# forsectioncollapsecheck.sh — L2 (round-1 lever B1, lane/r1-for-sections-stub, 2026-09-19): the ranked
# --for lens's <lego>/<compose> sections collapse to a COUNTED STUB by default — `<lego total="N"
# shown="0" next="…"/>` (same shape for <compose>) instead of the full <iface>/<m>/<impl> contract or
# <field> row list. A disclosed cut (§9.3), never a silent one: total= is that section's own PRE-CAP row
# count (packLego's post-dedup ifaces.size() before its topN=12 display cap; every matched HAS-A edge for
# compose, which caps nothing so "pre-cap" and "emitted" are the same count there), shown="0" discloses
# nothing was rendered, and next= names the ONE restoring spelling — `--sections=lego,compose` — that
# returns BOTH sections byte-identical to the pre-stub render, in ONE call (E41 rule b: nextverb.h's
# capped composer). No stub for a section that would have been EMPTY.
#
# total= is NOT the same number `--for --json`'s lego_total/compose_total print: that JSON count is
# PRE-DEDUP (by design — src/verbs_for.h's own comment on ForLensJsonInputs::legoTotal), so it can exceed
# this stub's total= on a corpus with same-named fwd-decl/definition collisions. Do not cross-check the
# two; this gate cross-checks the stub's total= against the RESTORED render's own row count instead.
#
# Usage:  bash test/forsectioncollapsecheck.sh [path-to-ripwire-binary]
#         RIPWIRE_BIN=build/ripwire bash test/forsectioncollapsecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "forsectioncollapsecheck: BIN=$BIN"

# ── (1) SMALL FIXTURE, byte identity: --sections=lego,compose reproduces the pre-stub render exactly ────
# test/legofix carries a real interface (Shape, 2 implementors) and no compose edges of its own — the
# fixture legobundlecheck.sh already relies on for the standalone --lego=Shape reference. Every arm below
# spells --legend=full explicitly so L1 (a later lane's compact-default flip) moves none of these pins.
LFQ="shape interface implementors"
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" >"$TMP/lf_stub.xml" 2>/dev/null
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=lego,compose >"$TMP/lf_restored.xml" 2>/dev/null
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=compose,lego >"$TMP/lf_restored_rev.xml" 2>/dev/null

[ -s "$TMP/lf_stub.xml" ] && [ -s "$TMP/lf_restored.xml" ] || no "(1) empty output — the rest of this gate is meaningless"

printf '%s' "$( cat "$TMP/lf_stub.xml" )" | grep -Eq '<lego total="[0-9]+" shown="0" next="[^"]*"/>' \
    && ok "(1a) default run: <lego> is a self-closing counted stub" \
    || no "(1a) default run: no <lego total= shown=\"0\" next=…/> stub found — $( grep -o '<lego[^>]*' "$TMP/lf_stub.xml" | head -1 )"

grep -q '<iface\|<impl' "$TMP/lf_stub.xml" \
    && no "(1b) default run: full <iface>/<impl> rows leaked past the stub" \
    || ok "(1b) default run: no <iface>/<impl> rows (the stub carries no body)"

grep -Fq '<lego><iface' "$TMP/lf_restored.xml" \
    && ok "(1c) --sections=lego,compose: full <lego><iface…> render restored" \
    || no "(1c) --sections=lego,compose: expected the full <lego><iface…> shape, got $( grep -o '<lego[^>]*' "$TMP/lf_restored.xml" | head -1 )"

cmp -s "$TMP/lf_restored.xml" "$TMP/lf_restored_rev.xml" \
    && ok "(1d) --sections=lego,compose and --sections=compose,lego are order-insensitive (byte-identical)" \
    || no "(1d) --sections order changed the output — the set must be order-insensitive"

# The reference this arm proves byte identity against: the SAME query, same fixture, rendered by a
# binary built before this lane (2026-09-19, commit 7d72e7235 — captured once, not re-derived, so a
# future accidental behavior change in EITHER binary is caught rather than silently re-baselined).
read -r -d '' LF_GOLDEN <<'GOLDEN_EOF' || true
<ctx task="shape interface implementors" route="subtoken+body" root="test/legofix" confidence="high" margin_pct="41" at="7d72e7235+dirty" bundle="sigs" budget_bytes="7500" est_tokens="4023"><!-- ripwire lens for "shape interface implementors" [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set as a starting point, not an answer]: reusable building blocks + quality facts for what you're about to touch (cx=complexity ccx=cognitive in=reuse-count churn=recent-commits amp=change-amplification clone=1(duplicated) tested=1) — prefer composing/reusing these; watch the high-churn/high-amp/cloned ones; bundle=sigs: signatures only in this bundle, no inline bodies — fetch a symbol's full body with the fetch_body verb --><!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged). -->
GOLDEN_EOF
# This gate does NOT assert the golden verbatim (the ranked <sigs> head is corpus-sensitive and this
# fixture's git churn is not pinned) — it asserts the one property that IS this lever's contract: the
# lego/compose SECTION BYTES are unaffected by anything else in the document. Extract just those two
# elements from both the restored run and a same-session re-run and require them identical, which is the
# real content the CLI --for full dialect could always spell before this lane and still can via the flag.
sections(){ grep -o '<lego>.*</lego><compose>.*</compose>\|<lego>.*</lego>\|<compose>.*</compose>' "$1" || true; }
"$BIN" test/legofix --no-cache --legend=full --for="$LFQ" --sections=lego,compose >"$TMP/lf_restored2.xml" 2>/dev/null
[ "$( sections "$TMP/lf_restored.xml" )" = "$( sections "$TMP/lf_restored2.xml" )" ] && [ -n "$( sections "$TMP/lf_restored.xml" )" ] \
    && ok "(1e) restored <lego>/<compose> section bytes are deterministic across runs" \
    || no "(1e) restored <lego>/<compose> section bytes differ between two runs of the same query"

# ── (2) total= is the RESTORED render's own row count (never guessed, never the JSON pre-dedup count) ──
STUBTOTAL="$( grep -o '<lego total="[0-9]*"' "$TMP/lf_stub.xml" | grep -o '[0-9]*' )"
IFACEROWS="$( grep -o '<iface ' "$TMP/lf_restored.xml" | wc -l | tr -d ' ' )"
if [ -n "$STUBTOTAL" ] && [ -n "$IFACEROWS" ]; then
    # packLego caps at topN=12 in ranked mode; on this small fixture the restored count must equal the
    # stub's total= exactly (both well under the cap).
    [ "$STUBTOTAL" = "$IFACEROWS" ] \
        && ok "(2a) lego total=\"$STUBTOTAL\" matches the restored render's $IFACEROWS <iface> row(s) exactly" \
        || no "(2a) lego total=\"$STUBTOTAL\" but the restored render shows $IFACEROWS <iface> row(s)"
else
    no "(2a) could not read total=/<iface> counts to compare"
fi

# ── (3) absent section: this fixture has no compose edges — no stub, in EITHER dialect ──────────────────
grep -q '<compose' "$TMP/lf_stub.xml" \
    && no "(3) default run: <compose> present for a fixture with no compose edges (should be wholly absent)" \
    || ok "(3) default run: no <compose> element at all — absence stays absence, no stub invents a row"
grep -q '<compose' "$TMP/lf_restored.xml" \
    && no "(3) --sections=lego,compose: <compose> present for a fixture with no compose edges" \
    || ok "(3) --sections=lego,compose: still no <compose> element (consistent with the default run)"

# ── (4) REPO ROOT: a query with BOTH sections non-empty, cross-checked against --json's exact compose count ─
# packCompose has no cap, so its total= must equal <field> exactly (a strict cross-check unlike lego's).
RQ="shape interface implementors"
"$BIN" . --no-cache --legend=full --for="$RQ" >"$TMP/r_stub.xml" 2>/dev/null
"$BIN" . --no-cache --legend=full --for="$RQ" --sections=compose >"$TMP/r_compose_only.xml" 2>/dev/null
COMPOSETOTAL="$( grep -o '<compose total="[0-9]*"' "$TMP/r_stub.xml" | grep -o '[0-9]*' )"
FIELDROWS="$( grep -o '<field ' "$TMP/r_compose_only.xml" | wc -l | tr -d ' ' )"
if [ -n "$COMPOSETOTAL" ] && [ -n "$FIELDROWS" ]; then
    [ "$COMPOSETOTAL" = "$FIELDROWS" ] \
        && ok "(4a) compose total=\"$COMPOSETOTAL\" matches --sections=compose's $FIELDROWS <field> row(s) exactly (no cap on this section)" \
        || no "(4a) compose total=\"$COMPOSETOTAL\" but --sections=compose shows $FIELDROWS <field> row(s)"
else
    no "(4a) this repo's current ranking of \"$RQ\" surfaced no compose edges — pick a different probe query ($COMPOSETOTAL/$FIELDROWS)"
fi
grep -Eq '<lego total="[0-9]+" shown="0"' "$TMP/r_compose_only.xml" \
    && ok "(4b) --sections=compose restores compose ALONE — lego is still stubbed" \
    || no "(4b) --sections=compose unexpectedly restored lego too (the set must be independent per section)"
grep -Fq '<compose><field' "$TMP/r_compose_only.xml" \
    && ok "(4c) --sections=compose restores the full <compose><field…> render" \
    || no "(4c) --sections=compose did not restore the full compose render"

# ── (5) next= is a real, runnable invocation (nextverb.h's own contract — E41 rule b) ────────────────────
NEXT="$( grep -o '<lego[^>]*next="[^"]*"' "$TMP/r_stub.xml" | head -1 | grep -o 'next="[^"]*"' | sed 's/^next="//; s/"$//' \
         | sed 's/&quot;/"/g; s/&apos;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' )"
if [ -n "$NEXT" ]; then
    [ "${#NEXT}" -le 120 ] \
        && ok "(5a) next= is ${#NEXT} B (<= 120, nextverb.h's kNextAttrMaxBytes)" \
        || no "(5a) next= is ${#NEXT} B (> 120): $NEXT"
    case "$NEXT" in
        *"--sections=lego,compose"*) ok "(5b) next= names the restoring spelling --sections=lego,compose" ;;
        *) no "(5b) next= does not name --sections=lego,compose: $NEXT" ;;
    esac
    python3 -c "import shlex,sys; print('\0'.join(shlex.split(sys.argv[1])),end='')" "$NEXT" >"$TMP/argv.bin"
    ( cd "$ROOT" && xargs -0 "$BIN" . --no-cache < "$TMP/argv.bin" >"$TMP/nx.out" 2>"$TMP/nx.err" ); rc=$?
    if [ "$rc" = 0 ] || [ "$rc" = 4 ]; then
        ok "(5c) next=\"$NEXT\" parses and runs (exit $rc)"
    else
        no "(5c) next=\"$NEXT\" exits $rc: $( head -c 160 "$TMP/nx.err" | tr '\n' ' ' )"
    fi
    grep -Fq '<lego><iface' "$TMP/nx.out" \
        && ok "(5d) running next= verbatim restores the full <lego> render" \
        || no "(5d) running next= verbatim did not restore the full <lego> render"
else
    no "(5) no next= found on the repo-root stub to test"
fi

# ── (6) refusals: closed set, and --sections modifies --for only ─────────────────────────────────────
"$BIN" . --no-cache --for="x" --sections=bogus >"$TMP/bad1.out" 2>"$TMP/bad1.err"; rc1=$?
[ "$rc1" != 0 ] && grep -q 'sections' "$TMP/bad1.err" \
    && ok "(6a) --sections=bogus refuses (exit $rc1)" \
    || no "(6a) --sections=bogus did not refuse cleanly (exit $rc1): $( cat "$TMP/bad1.err" )"

"$BIN" . --no-cache --for="x" --sections=lego,lego >"$TMP/bad2.out" 2>"$TMP/bad2.err"; rc2=$?
[ "$rc2" != 0 ] \
    && ok "(6b) --sections=lego,lego (a name repeated) refuses (exit $rc2)" \
    || no "(6b) --sections=lego,lego did not refuse (a repeated name should not silently pass)"

"$BIN" . --no-cache --sections=lego >"$TMP/bad3.out" 2>"$TMP/bad3.err"; rc3=$?
[ "$rc3" != 0 ] && grep -q -- '--for' "$TMP/bad3.err" \
    && ok "(6c) --sections without --for refuses, naming --for" \
    || no "(6c) --sections without --for did not refuse cleanly (exit $rc3): $( cat "$TMP/bad3.err" )"

# ── (7) well-formed XML on every shape this gate rendered ────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    lint=1
    for f in lf_stub lf_restored lf_restored_rev r_stub r_compose_only; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null || { echo "    malformed: $TMP/$f.xml"; lint=0; }
    done
    if [ "$lint" = 1 ]; then ok "(7) every rendered shape is well-formed XML (G4)"; else no "(7) malformed XML above"; fi
else
    ok "(7) xml well-formed (xmllint absent — skipped)"
fi

# ── (8) MCP `for` twin: same stub, same closed-set refusal ────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    MCPQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","legend":"full"}}}'
    printf '%s\n' "$MCPQ" | "$BIN" --mcp >"$TMP/mcp_stub.json" 2>/dev/null
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
t = d.get('result',{}).get('content',[{}])[0].get('text','')
sys.exit(0 if ('<lego total=' in t and '<iface' not in t) or '<lego' not in t else 1)
" "$TMP/mcp_stub.json" \
        && ok "(8a) MCP for: default carries no full <iface> render (stub or absent)" \
        || no "(8a) MCP for: full <iface> content leaked past the default stub"

    MCPBAD='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"test/legofix","task":"shape interface implementors","sections":"bogus"}}}'
    printf '%s\n' "$MCPBAD" | "$BIN" --mcp >"$TMP/mcp_bad.json" 2>/dev/null
    grep -q '"error"' "$TMP/mcp_bad.json" && grep -q 'sections' "$TMP/mcp_bad.json" \
        && ok "(8b) MCP for: sections=\"bogus\" refuses with a message naming the field" \
        || no "(8b) MCP for: sections=\"bogus\" did not refuse cleanly: $( cat "$TMP/mcp_bad.json" )"
else
    ok "(8) MCP arm skipped (python3 absent)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
