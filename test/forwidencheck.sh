#!/usr/bin/env bash
# forwidencheck.sh — L-W (routing-loop round, owner decision 2026-09-12): --for pages its answer ONE FILE PER
# ROW, and its next= points at that page when the answer is thin.
#
# THE DEFECT. On the pre-registered follow-up ladder (RocksDB, frozen 30), every ripwire follow-up completed
# 0 answers through step 4: --for's next= pointed at --expand (a BODY, not a wider list), --top-k was INERT
# on --for, and --format=candidates is symbol-grain (40 symbols is about 18 files in 11 KB). The one
# follow-up that completed answers in that ladder was a FILE-grain widening page (+8 completes at ~6 KB
# each, one row per file). Local telemetry: --for -> --expand was followed 0 of 259 times.
#
# THE CONTRACT this gate pins:
#   (1) `--for=TASK --limit=N` (offset=M pages) is a FILE page: one <f p= score= n= sym=/> row per file, one
#       file per row (no duplicates), root-relative p= exactly as every other verb spells it (verbatim path
#       lookup is how an answer is scored complete).
#   (2) The page is ranked file-first by a bounded union-coverage score: the fixture's gold file, whose four
#       symbols each match ONE query term, sits at file-rank 8..30 on the page and is ABSENT from the default
#       --for answer (its best symbol is weaker than twenty single-term files that outrank it in best-symbol
#       order, which is what the default's <tail> walks).
#   (3) The page is deterministic and well-formed; a cut page carries the house paging vocabulary
#       (shown= total= capped="1" has_more= next_offset=) and a next= naming the next page; the second page
#       has no row in common with the first and the pages concatenate to the wider page in order.
#   (4) coverage= rides --for's root on a THIN answer (both dialects) and is DEFINED in the legend the reader meets
#       first; a CONFIDENT answer carries neither the attribute nor the clause (owner decision 2026-09-12 22:55:
#       present-only), and the --json and MCP twins follow the same rule in both states.
#   (5) next= on the r=1 row names the widening page (`--for=... --limit=40`) when the answer is THIN
#       (coverage under 50, or a ranked head spread over fewer than 3 files) and stays --expand=FILE:NAME
#       on a confident answer.
#   (6) --limit=0 and a non-numeric --limit are refused; the page refuses the bundle-shaping flags rather
#       than silently ignoring them.
#   (7) The MCP `for` twin takes the same `limit` argument and serves the same page (root attribute names
#       equal, the gold path present).
#
# RED-FIRST: every arm below was run against the pre-change binary (--limit refused outright on --for;
# no coverage=; next= always --expand) and reported FAIL before the code landed.
#
# The corpus is GENERATED here, in a temp dir this script creates and removes, so no tracked fixture
# perturbs the crawl other gates measure. Its shape (why each file group exists) is documented inline.
#
# Usage:  bash test/forwidencheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forwidencheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "forwidencheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/corpus"
mkdir -p "$FIX"

# ── the fixture ─────────────────────────────────────────────────────────────────────────────────────────
# Query terms: alpha beta gamma delta (+ zeta, which nothing carries — the S1-shaped "(#12147)" token every
# commit-subject query drags along; it lowers coverage= honestly). BM25 field weights: a name token counts
# x3, a body token x1, so a symbol's score is driven by its NAME's term frequency, saturating in tf and
# falling with document length.
#   big/  3 files x 14 symbols, each name carrying two terms at tf=9 — the top-42 symbols, so the default
#         40-row head covers exactly these three files.
#   mid/  9 files x 2 symbols, each name two terms at tf=3 — outscore every single-term symbol; each file's
#         union covers all four terms (same union-coverage as the gold, stronger best symbol: ranks ABOVE
#         the gold on the page — the gold lands at page rank 3 + 9 + 1 = 13).
#   flip/ 20 files x 1 symbol, one term at tf=9 — a stronger BEST symbol than the gold's (tf=3), so in
#         best-symbol order (the default's <tail>) all twenty sit above the gold (file rank 33 > 3 + 24
#         tail rows: absent from the default answer), but their union covers ONE term, so on the page they
#         sit below it.
#   gold/ 1 file x 4 symbols, one term each at tf=3 — the file only a union-coverage ranking surfaces.
python3 - "$FIX" <<'PY'
import os, sys
root = sys.argv[1]
def w( rel, text ):
    p = os.path.join( root, rel ); os.makedirs( os.path.dirname( p ), exist_ok=True )
    open( p, "w" ).write( text )
terms = [ "alpha", "beta", "gamma", "delta" ]
for b in range( 1, 4 ):
    body = ""
    for k in range( 1, 8 ):
        body += "int alpha_alpha_alpha_beta_beta_beta_b%d_f%02d() { return %d; }\n" % ( b, k, k )
        body += "int gamma_gamma_gamma_delta_delta_delta_b%d_f%02d() { return %d; }\n" % ( b, k, k )
    w( "big/big_%02d.cpp" % b, body )
for m in range( 1, 10 ):
    w( "mid/mid_%02d.cpp" % m, "int alpha_beta_m%02d() { return 1; }\nint gamma_delta_m%02d() { return 2; }\n" % ( m, m ) )
for f in range( 1, 21 ):
    t = terms[ ( f - 1 ) % 4 ]
    w( "flip/flip_%02d.cpp" % f, "int %s_%s_%s_f%02d() { return 0; }\n" % ( t, t, t, f ) )
w( "gold/widen_target.cpp", "".join( "int %s_target_helper() { return 3; }\n" % t for t in terms ) )
PY
GOLD="gold/widen_target.cpp"
THIN="alpha beta gamma delta zeta"
CONFIDENT="alpha beta"
[ -f "$FIX/$GOLD" ] || { no "fixture: $GOLD was not written — every arm below would be vacuous"; echo "FAILURES ABOVE"; exit 1; }
ok "fixture written: 33 files, gold at $GOLD"

run(){ "$BIN" "$FIX" --no-cache "$@" 2>"$TMP/err"; }
cat > "$TMP/rows.py" <<'PY'
# print one `p` per <f> row of the page, in document order (the page's own row order)
import re, sys
s = sys.stdin.read()
for m in re.finditer( r'<f ([^>]*)/>', s ):
    p = re.search( r'\bp="([^"]*)"', m.group( 1 ) )
    print( p.group( 1 ) if p else "?" )
PY
cat > "$TMP/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ) )
PY
rootattrs(){ python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search( r"<(files|ctx)\b([^>]*)>", s )
print( " ".join( sorted( set( re.findall( r"\s([a-z_]+)=\"", m.group( 2 ) ) ) ) ) if m else "" )
'; }

# ── (1) the default answer does NOT carry the gold; the page does, verbatim ─────────────────────────────
run --for="$THIN" >"$TMP/default.xml"; rc=$?
[ "$rc" = 0 ] || no "(1) default --for exited $rc: $( head -c 200 "$TMP/err" )"
if grep -q "p=\"$GOLD\"" "$TMP/default.xml"; then
    no "(1) the default --for answer already names $GOLD — the fixture does not exercise widening"
else
    ok "(1) the default --for answer (head + tail) does not name $GOLD"
fi
grep -q '<tail ' "$TMP/default.xml" && ok "(1) presence guard: the default answer carries a <tail> (the file-grain surface the gold fell past)" \
                                    || no "(1) presence guard: no <tail> in the default answer — the fixture shape changed"

run --for="$THIN" --limit=40 >"$TMP/page40.xml"; rc=$?
if [ "$rc" = 0 ] && grep -q '^<files ' "$TMP/page40.xml"; then
    ok "(1) --for --limit=40 exits 0 and answers with a <files> root"
else
    no "(1) --for --limit=40 exited $rc / no <files> root: $( head -c 300 "$TMP/err" "$TMP/page40.xml" | tr '\n' ' ' )"
fi
python3 "$TMP/rows.py" <"$TMP/page40.xml" >"$TMP/page40.rows"
if grep -qx "$GOLD" "$TMP/page40.rows"; then
    ok "(1) the page names $GOLD verbatim (root-relative p=)"
else
    no "(1) the page does not name $GOLD — rows: $( tr '\n' ' ' <"$TMP/page40.rows" | cut -c1-300 )"
fi

# ── (2) file-first rank: the gold sits at 8..30 on the page ─────────────────────────────────────────────
grank="$( grep -nx "$GOLD" "$TMP/page40.rows" | cut -d: -f1 | head -1 )"
if [ -n "$grank" ] && [ "$grank" -ge 8 ] && [ "$grank" -le 30 ]; then
    ok "(2) gold file-rank on the page is $grank (expected 8..30)"
else
    no "(2) gold file-rank on the page is '${grank:-absent}' (expected 8..30)"
fi
nrows="$( grep -c . "$TMP/page40.rows" )"
[ "$nrows" -ge 30 ] && ok "(2) the page holds $nrows file rows (the fixture has 33 positive-score files)" \
                    || no "(2) the page holds only $nrows rows"
if python3 - "$TMP/page40.xml" <<'PY'
import re, sys
s = open( sys.argv[1] ).read()
rows = re.findall( r'<f ([^>]*)/>', s )
bad = [ r for r in rows if not all( re.search( r'\b%s="' % a, r ) for a in ( "p", "score", "n", "sym" ) ) ]
sys.exit( 1 if bad or not rows else 0 )
PY
then ok "(2) every row carries p= score= n= sym="
else no "(2) a row lacks one of p= score= n= sym="; fi

# ── (3) one file per row, deterministic, well-formed, paged ────────────────────────────────────────────
dups="$( sort "$TMP/page40.rows" | uniq -d | grep -c . )"
if [ "$dups" = 0 ] && [ "$nrows" -ge 30 ]; then ok "(3) one row per file: no duplicate p= among $nrows rows"; else no "(3) $dups duplicate file row(s) on the page (rows=$nrows)"; fi
run --for="$THIN" --limit=40 >"$TMP/page40b.xml"
if [ -s "$TMP/page40.xml" ] && cmp -s "$TMP/page40.xml" "$TMP/page40b.xml"; then ok "(3) two runs are byte-identical (determinism)"; else no "(3) two runs of the same page differ (or the page is empty)"; fi
if xmllint --noout "$TMP/page40.xml" 2>/dev/null; then ok "(3) the page is well-formed XML"; else no "(3) the page is not well-formed XML"; fi

run --for="$THIN" --limit=10 >"$TMP/p1.xml"
run --for="$THIN" --limit=10 --offset=10 >"$TMP/p2.xml"
root1="$( grep -o '^<files [^>]*>' "$TMP/p1.xml" )"
for a in 'shown="10"' 'capped="1"' 'has_more="1"' 'next_offset="10"' 'total="' 'offset="0"' 'limit="10"'; do
    printf '%s' "$root1" | grep -q "$a" || no "(3) --limit=10 root lacks $a: $( printf '%s' "$root1" | cut -c1-300 )"
done
printf '%s' "$root1" | grep -q 'next="[^"]*--limit=10 --offset=10"' \
    && ok "(3) a cut page carries shown/capped/total/has_more/next_offset and next= naming the next page" \
    || no "(3) --limit=10 root has no next= naming '--limit=10 --offset=10': $( printf '%s' "$root1" | grep -o 'next="[^"]*"' )"
python3 "$TMP/rows.py" <"$TMP/p1.xml" >"$TMP/p1.rows"; python3 "$TMP/rows.py" <"$TMP/p2.xml" >"$TMP/p2.rows"
# extend-3 (R2-L3′, offset=0 only — see forpage.h) can append up to 3 rows to p1 AFTER its shown= rows; those
# are an explicitly-tagged appendix (extra=, p=/score= only), not part of the ranked walk, so the no-overlap /
# concatenation invariant below reads p1's shown= rows only — the same rows this arm pinned before extend-3
# existed. shown1 falls back to 10 (p1's own row count pre-lever) if the root's shown= is ever unreadable.
shown1="$( grep -o 'shown="[0-9]*"' "$TMP/p1.xml" | head -1 | tr -dc '0-9' )"; shown1="${shown1:-10}"
head -"$shown1" "$TMP/p1.rows" >"$TMP/p1.shown.rows"
overlap="$( sort "$TMP/p1.shown.rows" "$TMP/p2.rows" | uniq -d | grep -c . )"
[ "$overlap" = 0 ] && [ "$( grep -c . "$TMP/p2.rows" )" = 10 ] \
    && ok "(3) the second page has no row in common with the first's shown= rows, and holds 10 rows" \
    || no "(3) page overlap=$overlap, page-2 rows=$( grep -c . "$TMP/p2.rows" )"
cat "$TMP/p1.shown.rows" "$TMP/p2.rows" >"$TMP/p12.rows"
head -20 "$TMP/page40.rows" >"$TMP/page40.first20"
[ "$( grep -c . "$TMP/p12.rows" )" = 20 ] && cmp -s "$TMP/page40.first20" "$TMP/p12.rows" \
    && ok "(3) pages 1+2 (limit 10, shown= rows only) equal the first 20 rows of the limit-40 page, in order" \
    || no "(3) pages 1+2 (shown= rows) do not concatenate to the limit-40 page's first 20 rows"
grep -q 'has_more="0"' "$TMP/page40.xml" && ok "(3) the limit-40 page over 33 files says has_more=\"0\"" \
                                          || no "(3) the limit-40 page over 33 files does not say has_more=\"0\": $( grep -o '^<files [^>]*>' "$TMP/page40.xml" | cut -c1-300 )"

# ── (4) coverage= on the root, defined where the reader meets it ───────────────────────────────────────
for dialect in "" "--legend=compact"; do
    run --for="$THIN" $dialect >"$TMP/cov.xml"
    root="$( grep -o '^<ctx [^>]*>' "$TMP/cov.xml" )"
    legend="$( grep -o '<!--.*-->' "$TMP/cov.xml" | head -1 )"
    label="default dialect"; [ -n "$dialect" ] && label="compact dialect"
    if printf '%s' "$root" | grep -q ' coverage="[0-9][0-9]*"'; then
        ok "(4) $label: --for's root carries coverage=\"N\" ($( printf '%s' "$root" | grep -o 'coverage="[0-9]*"' ))"
    else
        no "(4) $label: --for's root has no coverage=: $( printf '%s' "$root" | cut -c1-200 )"
    fi
    printf '%s' "$legend" | grep -q 'coverage=' && ok "(4) $label: the leading legend defines coverage=" \
                                                 || no "(4) $label: the leading legend never spells coverage="
done
groot="$( grep -o '^<files [^>]*>' "$TMP/page40.xml" )"
if printf '%s' "$groot" | grep -q ' coverage="[0-9][0-9]*"'; then ok "(4) the page root carries coverage= too"; else no "(4) the page root lacks coverage="; fi
if grep -o '<!--.*-->' "$TMP/page40.xml" | head -1 | grep -q 'coverage='; then ok "(4) the page legend defines coverage="; else no "(4) the page legend never spells coverage="; fi
# the thin query's top symbol carries 2 of 5 terms (zeta is absent, and absent terms weigh most): under 50
covthin="$( grep -o '^<ctx [^>]*>' "$TMP/default.xml" | grep -o 'coverage="[0-9]*"' | tr -dc '0-9' )"
if [ -n "$covthin" ] && [ "$covthin" -lt 50 ]; then ok "(4) thin query: coverage=$covthin (under 50)"; else no "(4) thin query: coverage='${covthin:-absent}' (expected under 50)"; fi

# ── (5) next= names the page on a thin answer, --expand on a confident one ─────────────────────────────
top="$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/default.xml" | head -1 )"
thinnext="$( printf '%s' "$top" | grep -o 'next="[^"]*"' )"
if printf '%s' "$thinnext" | grep -q 'next="--for=' && printf '%s' "$thinnext" | grep -q -- '--limit=40"'; then
    ok "(5) thin answer: the r=1 row's next= names the widening page ($thinnext)"
else
    no "(5) thin answer: the r=1 row's next= is '${thinnext:-absent}' — expected --for=... --limit=40"
fi
run --for="$CONFIDENT" >"$TMP/conf.xml"
croot="$( grep -o '^<ctx [^>]*>' "$TMP/conf.xml" )"
covconf="$( printf '%s' "$croot" | grep -o 'coverage="[0-9]*"' | tr -dc '0-9' )"
if [ -z "$covconf" ]; then ok "(5) confident answer: the root carries NO coverage= (present-only)"; else no "(5) confident answer: the root carries coverage=$covconf — the gauge must ride thin answers only"; fi
grep -o '<!--.*-->' "$TMP/conf.xml" | head -1 | grep -q 'coverage=' && no "(5) confident answer: the legend still spells coverage= for an attribute the root does not carry" \
                                                                  || ok "(5) confident answer: no coverage clause in the legend (present-only)"
run --for="$CONFIDENT" --legend=compact >"$TMP/confc.xml"
{ grep -o '^<ctx [^>]*>' "$TMP/confc.xml" | grep -q ' coverage="'; } && no "(5) confident answer, compact dialect: coverage= present" || ok "(5) confident answer, compact dialect: no coverage=, no clause"
grep -o '<!--.*-->' "$TMP/confc.xml" | head -1 | grep -q 'coverage=' && no "(5) confident answer, compact dialect: the legend spells coverage=" || true
# the --json twin: the key rides thin answers only
run --for="$THIN" --json >"$TMP/thin.json"; run --for="$CONFIDENT" --json >"$TMP/conf.json"
if grep -q '"coverage":[0-9]' "$TMP/thin.json"; then ok "(5) --json thin answer carries \"coverage\":N"; else no "(5) --json thin answer lacks the coverage key"; fi
grep -q '"coverage":' "$TMP/conf.json" && no "(5) --json confident answer carries a coverage key" || ok "(5) --json confident answer carries no coverage key"
# the MCP twin, both states
for pair in "thin:$THIN" "confident:$CONFIDENT"; do
    state=${pair%%:*}; task=${pair#*:}
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$FIX" "$task" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py" >"$TMP/mcp_$state.xml"
    mroot="$( grep -o '^<ctx [^>]*>' "$TMP/mcp_$state.xml" )"; mleg="$( grep -o '<!--.*-->' "$TMP/mcp_$state.xml" | head -1 )"
    if [ "$state" = thin ]; then
        printf '%s' "$mroot" | grep -q ' coverage="[0-9]*"' && printf '%s' "$mleg" | grep -q 'coverage=' && printf '%s' "$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/mcp_$state.xml" | head -1 )" | grep -q 'next="--for=' \
            && ok "(5) MCP thin answer: coverage= on the root, defined, and the r=1 next= names the page" \
            || no "(5) MCP thin answer: coverage=/clause/page next= missing: $( printf '%s' "$mroot" | cut -c1-160 )"
    else
        { printf '%s' "$mroot" | grep -q ' coverage="'; } || printf '%s' "$mleg" | grep -q 'coverage=' \
            && no "(5) MCP confident answer: coverage= or its clause present" \
            || ok "(5) MCP confident answer: no coverage=, no clause (parity with the CLI)"
    fi
done
ctop="$( grep -o '<d [^>]*r="1"[^>]*>' "$TMP/conf.xml" | head -1 )"
printf '%s' "$ctop" | grep -q 'next="--expand=' && ok "(5) confident answer: the r=1 row keeps next=\"--expand=FILE:NAME\"" \
                                                 || no "(5) confident answer: the r=1 row's next= is '$( printf '%s' "$ctop" | grep -o 'next="[^"]*"' )'"
others="$( grep -o '<d [^>]*next=' "$TMP/default.xml" | grep -vc 'r="1"' || true )"
if [ "$others" = 0 ]; then ok "(5) next= rides the top row only"; else no "(5) $others non-top row(s) carry next="; fi
# the hint pastes: the ladder splits it with shlex, so the task must be quoted as a shell would
hint="$( printf '%s' "$thinnext" | sed 's/^next="//; s/"$//' )"
if [ -n "$hint" ]; then
    if python3 - "$BIN" "$FIX" "$hint" "$TMP/page40.xml" <<'PY'
import html, shlex, subprocess, sys
binp, fix, hint, page = sys.argv[1:5]
argv = shlex.split( html.unescape( hint ) )
r = subprocess.run( [ binp, fix, "--no-cache" ] + argv, capture_output=True )
sys.exit( 0 if r.returncode == 0 and r.stdout == open( page, "rb" ).read() else 1 )
PY
    then ok "(5) the pasted next= (shlex-split) reproduces the limit-40 page byte for byte"
    else no "(5) the pasted next= does not reproduce the limit-40 page: $hint"; fi
fi

# ── (6) refusals ────────────────────────────────────────────────────────────────────────────────────────
run --for="$THIN" --limit=0 >/dev/null; rc=$?
if [ "$rc" != 0 ] && grep -q -- '--limit' "$TMP/err"; then ok "(6) --limit=0 is refused (rc=$rc)"; else no "(6) --limit=0 not refused: rc=$rc $( head -c 160 "$TMP/err" )"; fi
run --for="$THIN" --limit=abc >/dev/null; rc=$?
if [ "$rc" != 0 ] && grep -q -- '--limit' "$TMP/err"; then ok "(6) --limit=abc is refused (rc=$rc)"; else no "(6) --limit=abc not refused: rc=$rc $( head -c 160 "$TMP/err" )"; fi
for flag in --json --format=candidates --detail=1 --signatures-only --token-budget=2000; do
    run --for="$THIN" --limit=5 $flag >"$TMP/shape.out"; rc=$?
    if [ "$rc" != 0 ] && [ ! -s "$TMP/shape.out" ]; then
        ok "(6) the page refuses $flag rather than ignoring it (rc=$rc)"
    else
        no "(6) the page accepted $flag: rc=$rc, $( wc -c <"$TMP/shape.out" | tr -d ' ' ) bytes on stdout, stderr: $( head -c 160 "$TMP/err" )"
    fi
done

# ── (7) the MCP twin serves the same page ──────────────────────────────────────────────────────────────
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s","limit":40}}}\n' \
       "$FIX" "$THIN" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py" >"$TMP/mcp.xml"
if grep -q '^<files ' "$TMP/mcp.xml"; then
    ok "(7) MCP for + limit answers with the <files> page"
else
    no "(7) MCP for + limit did not answer with a <files> page: $( head -c 300 "$TMP/mcp.xml" | tr '\n' ' ' )"
fi
python3 "$TMP/rows.py" <"$TMP/mcp.xml" >"$TMP/mcp.rows"
if grep -qx "$GOLD" "$TMP/mcp.rows"; then ok "(7) the MCP page names $GOLD"; else no "(7) the MCP page does not name $GOLD"; fi
[ -s "$TMP/page40.rows" ] && cmp -s "$TMP/mcp.rows" "$TMP/page40.rows" && ok "(7) the MCP page's rows equal the CLI page's rows, in order" \
                                          || no "(7) the MCP page's rows differ from the CLI page's"
cattrs="$( rootattrs <"$TMP/page40.xml" )"; mattrs="$( rootattrs <"$TMP/mcp.xml" )"
[ -n "$cattrs" ] && [ "$cattrs" = "$mattrs" ] && ok "(7) page root attribute names agree across the two dialects ($cattrs)" \
                                                || no "(7) page root attribute names differ — CLI: [$cattrs] MCP: [$mattrs]"

# ── (8) extend-3 (R2-L3′, PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/12_round2_PREREG.md Amendment 1 item 3) ──
# The page keeps every shipped row, byte for byte, and APPENDS up to 3 more rows (p= score= only) picked from
# the rows this call does NOT already show, by the blend key L3 registered (score/100 + path-subtoken overlap
# share, exact integer compare, path-string tie-break). On this fixture's THIN query, mid_08/mid_09/gold all
# tie the blend key exactly (same union-coverage share, 0 path hits): this arm pins the tie-break itself, not
# just presence — a naive "next 3 rows of the existing order" would answer mid_08,mid_09,gold (best-desc order,
# see forFileRowBefore); the registered blend key ties on best= and falls to path-string, so the answer is
# gold,mid_08,mid_09 ('g' < 'm'). RED on the pre-lever binary: no extra= attribute, page10 holds exactly 10
# rows, not 13.
attrnames(){ python3 -c '
import re, sys
row = sys.stdin.read().strip()
print( " ".join( sorted( re.findall( r"\s([a-z]+)=\"", " " + row ) ) ) )
'; }
run --for="$THIN" --limit=10 >"$TMP/page10.xml"; rc=$?
[ "$rc" = 0 ] || no "(8) --for --limit=10 exited $rc: $( head -c 200 "$TMP/err" )"
root10="$( grep -o '^<files [^>]*>' "$TMP/page10.xml" )"
if printf '%s' "$root10" | grep -q ' extra="3"'; then
    ok "(8) the limit=10 page root carries extra=\"3\""
else
    no "(8) the limit=10 page root lacks extra=\"3\": $( printf '%s' "$root10" | cut -c1-300 )"
fi
python3 "$TMP/rows.py" <"$TMP/page10.xml" >"$TMP/page10.rows"
n10="$( grep -c . "$TMP/page10.rows" )"
[ "$n10" = 13 ] && ok "(8) the limit=10 page holds 13 rows (10 shown + 3 extend)" \
                || no "(8) the limit=10 page holds $n10 rows (expected 13)"
head -10 "$TMP/page10.rows" >"$TMP/page10.first10"
head -10 "$TMP/page40.rows" >"$TMP/page40.first10"
if cmp -s "$TMP/page10.first10" "$TMP/page40.first10"; then
    ok "(8) byte identity: the first 10 rows of the limit=10 page equal the first 10 rows of the limit=40 page"
else
    no "(8) the limit=10 page's shown rows differ from the limit=40 page's first 10"
fi
grep -o '<f [^>]*/>' "$TMP/page10.xml" | head -10 >"$TMP/page10.shownxml"
grep -o '<f [^>]*/>' "$TMP/page40.xml" | head -10 >"$TMP/page40.first10xml"
if cmp -s "$TMP/page10.shownxml" "$TMP/page40.first10xml"; then
    ok "(8) byte identity holds at the full-row level too (p= score= n= sym=, not just p=)"
else
    no "(8) the shown rows differ at the attribute level between limit=10 and limit=40"
fi
tail -3 "$TMP/page10.rows" >"$TMP/page10.extra.rows"
printf 'gold/widen_target.cpp\nmid/mid_08.cpp\nmid/mid_09.cpp\n' >"$TMP/page10.extra.expect"
if cmp -s "$TMP/page10.extra.rows" "$TMP/page10.extra.expect"; then
    ok "(8) extend-3 tie-break: the appended rows are gold,mid_08,mid_09 in that order (path-string tie-break, not incoming order)"
else
    no "(8) extend-3 rows are $( tr '\n' ',' <"$TMP/page10.extra.rows" ) — expected gold/widen_target.cpp,mid/mid_08.cpp,mid/mid_09.cpp"
fi
extra_ok=1
for i in 11 12 13; do
    row="$( grep -o '<f [^>]*/>' "$TMP/page10.xml" | sed -n "${i}p" )"
    attrs="$( printf '%s' "$row" | attrnames )"
    [ "$attrs" = "p score" ] || { extra_ok=0; no "(8) extend row $i carries [$attrs], expected exactly p score: $row"; }
done
[ "$extra_ok" = 1 ] && ok "(8) all 3 extend rows carry p= and score= ONLY (no n=, no sym=)"
run --for="$THIN" --limit=10 >"$TMP/page10b.xml"
if cmp -s "$TMP/page10.xml" "$TMP/page10b.xml"; then ok "(8) two runs of the limit=10 page are byte-identical (determinism)"; else no "(8) two runs of the limit=10 page differ"; fi
if xmllint --noout "$TMP/page10.xml" 2>/dev/null; then ok "(8) the extend-3 page is well-formed XML"; else no "(8) the extend-3 page is not well-formed XML"; fi
# the untruncated limit=40 page (window covers the whole 33-file universe): no candidates left, so no extra=
if printf '%s' "$( grep -o '^<files [^>]*>' "$TMP/page40.xml" )" | grep -q ' extra='; then
    no "(8) the untruncated limit=40 page carries extra= — there are no unshown candidates to append"
else
    ok "(8) the untruncated limit=40 page carries no extra= (present-only: nothing left to append)"
fi
# both legend dialects define extra=
for dialect in "" "--legend=compact"; do
    run --for="$THIN" --limit=10 $dialect >"$TMP/leg10.xml"
    legend10="$( grep -o '<!--.*-->' "$TMP/leg10.xml" | head -1 )"
    label="full dialect"; [ -n "$dialect" ] && label="compact dialect"
    printf '%s' "$legend10" | grep -q 'extra=' && ok "(8) $label: the page legend defines extra=" \
                                                || no "(8) $label: the page legend never spells extra=: $( printf '%s' "$legend10" | cut -c1-200 )"
done
# the MCP twin carries the same extra= and the same 3 appended rows
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s","limit":10}}}\n' \
       "$FIX" "$THIN" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py" >"$TMP/mcp10.xml"
mroot10="$( grep -o '^<files [^>]*>' "$TMP/mcp10.xml" )"
printf '%s' "$mroot10" | grep -q ' extra="3"' && ok "(8) MCP limit=10 page also carries extra=\"3\" (dialect parity)" \
                                              || no "(8) MCP limit=10 page lacks extra=\"3\": $( printf '%s' "$mroot10" | cut -c1-300 )"
python3 "$TMP/rows.py" <"$TMP/mcp10.xml" >"$TMP/mcp10.rows"
cmp -s "$TMP/mcp10.rows" "$TMP/page10.rows" && ok "(8) MCP limit=10 page rows equal the CLI page's rows, in order (shown AND extend)" \
                                             || no "(8) MCP limit=10 page rows differ from the CLI page's"
# offset>0 appends NOTHING: extend-3 is the single follow-up page, not a walk-wide feature — appending on
# every offset would let an earlier page's "extra" duplicate a later page's real row (arm (3)'s invariant)
run --for="$THIN" --limit=10 --offset=10 >"$TMP/page10off.xml"
root10off="$( grep -o '^<files [^>]*>' "$TMP/page10off.xml" )"
if printf '%s' "$root10off" | grep -q ' extra='; then
    no "(8) --offset=10 carries extra= — extend-3 must fire on offset=0 only: $( printf '%s' "$root10off" | cut -c1-300 )"
else
    ok "(8) --offset=10 carries no extra= (extend-3 is offset=0 only)"
fi
python3 "$TMP/rows.py" <"$TMP/page10off.xml" >"$TMP/page10off.rows"
[ "$( grep -c . "$TMP/page10off.rows" )" = 10 ] && ok "(8) --offset=10 page holds exactly 10 rows (no append)" \
                                                 || no "(8) --offset=10 page holds $( grep -c . "$TMP/page10off.rows" ) rows (expected 10)"
# the SHOWN portion of offset=0 (its ranked walk, not its extend appendix) still has zero overlap with
# offset=10 — extend-3 only ever touches the appendix, never the walk itself (arm (3) already pins this at
# the general level; this re-checks it specifically against a page that used extend-3)
walkoverlap="$( sort "$TMP/p1.shown.rows" "$TMP/page10off.rows" | uniq -d | grep -c . )"
[ "$walkoverlap" = 0 ] && ok "(8) the offset=0 page's SHOWN rows and the offset=10 page share no row (extend-3 touches only its own appendix)" \
                        || no "(8) offset=0 shown rows and offset=10 overlap on $walkoverlap row(s) — extend-3 leaked into the ranked walk"
# the appendix itself is EXPECTED to echo rows a later page will also show (gold/mid_08/mid_09 are real
# ranked rows 11-13 — offset=10 legitimately shows them too); pin that expectation rather than leaving it
# an unstated coincidence, so a future change either keeps disclosing it this way or updates this line.
appendixoverlap="$( sort "$TMP/page10.extra.rows" "$TMP/page10off.rows" | uniq -d | grep -c . )"
[ "$appendixoverlap" = 3 ] && ok "(8) offset=0's 3 extend rows (gold,mid_08,mid_09) are exactly the rows offset=10 also shows — disclosed, not hidden" \
                            || no "(8) expected offset=0's extend rows to be the same 3 files offset=10 shows first; overlap=$appendixoverlap"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
