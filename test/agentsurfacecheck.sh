#!/usr/bin/env bash
# agentsurfacecheck.sh — a shape an AGENT cannot be told about is a shape that does not ship.
#
# WHAT THIS GATE IS FOR. 0.6.1 adds surfaces an agent has to ASK for: a directory-scoped recency window, a
# file-grain widening page, grouped test rows, short symbol ids. Every one of them was measured, gated and
# documented — and none of that reaches the agent that has to type the flag. The tool's own reference
# (docs/COMMANDS.md) names every flag by construction and its recorded captures contain every attribute,
# which is exactly why it is NOT accepted as the surface here: a gate a generated document satisfies for
# free cannot fail. The surfaces that count are the ones an agent actually LOADS mid-task:
#
#     skills/*/*.md          the skill bodies
#     src/wrap.h             the pasteable primer `ripwire wrap AGENT` writes into a client's rules file
#
# TWO ARMS, two different questions.
#
#   (A) THE RATCHET — every long flag `--help` advertises is named on one of those surfaces, except the
#       ones recorded in test/agentsurfacefix/unnamed_flags_baseline.txt. That file is an INVENTORY OF
#       KNOWN DEBT, not an approval (legendcoverage_baseline.txt's rule, same shape): it may only be
#       edited DOWNWARD, and a NEW flag that no skill names turns this arm red in the commit that adds the
#       flag rather than a release later. The match is WORD-BOUNDED: 23 flag pairs share a prefix
#       (`--in` inside `--index-out`, `--not` inside `--notes`, `--for` inside `--format`), and a
#       substring test would report every one of them as named by its longer sibling.
#
#   (B) THE ROUND'S NEW SHAPES — the term AND the verb it belongs to, within five lines of each other on
#       one surface. Naming `--limit` somewhere and `--for` somewhere else does not tell an agent that the
#       widening page exists; the PAIR is the instruction. Two things make this arm honest:
#
#       • What the BINARY emits and what a SKILL must spell are different strings. The binary prints
#         `<g hops=…>` and its legend defines `<g>`, so the probe looks for `<g`; a skill must spell
#         `<g ` with the space, or `<graph-query` would satisfy a row about grouped test rows.
#       • Every row is PROBED against this build, and the probe RUNS the verb — `--help` advertising a
#         flag is not evidence that the flag emits anything (that was this gate's own defect: the
#         `--limit=`/`--offset=` rows only asked whether `--help` mentioned them).
#
#       A shape this build does not have yet is DECLARED on the PENDING list with the lane that ships it,
#       and a surface may name it while it is there — that is how a skill can be written once for a
#       release that lands in four PRs. The gate is SELF-HEALING on arrival: a pending shape that shows up
#       in the binary with its pairing already satisfied PASSES, so the lane that ships it never has to
#       edit this file. What stays red is the dishonest direction: a surface promising a shape this build
#       refuses with NO lane declared for it.
#
# Usage:  bash test/agentsurfacecheck.sh [PATH_TO_RIPWIRE]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASELINE="$ROOT/test/agentsurfacefix/unnamed_flags_baseline.txt"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$BASELINE" ] || { echo "missing $BASELINE — this gate is a ratchet and cannot run without its floor"; exit 2; }
cd "$ROOT"
echo "agentsurfacecheck: BIN=$BIN"

# The surfaces, concatenated once. src/wrap.h is included whole: its blurb is the only agent-facing prose
# in it, and a term named in a neighbouring comment is a term a reader of that file still meets.
cat skills/*/*.md src/wrap.h >"$TMP/surfaces.txt"
[ -s "$TMP/surfaces.txt" ] && ok "the agent surfaces are readable ($( wc -l <"$TMP/surfaces.txt" | tr -d ' ' ) lines of skill bodies + the wrap primer)" \
                           || no "no agent surface content was read — every arm below would pass by finding nothing"

# ── (A) the ratchet: every advertised long flag is named on a surface, or recorded as known debt ───────
"$BIN" --help=all </dev/null 2>&1 | grep -oE '^[[:space:]]+--[a-z][a-z0-9-]*' | tr -d ' ' | sort -u >"$TMP/flags.txt"
FLAGN="$( wc -l <"$TMP/flags.txt" | tr -d ' ' )"
[ "$FLAGN" -ge 100 ] && ok "(A) --help advertises $FLAGN long flags (the census has a population)" \
                     || no "(A) only $FLAGN long flags were extracted from --help — the census is broken, not clean"
# WORD-BOUNDED: a flag is named only when the next byte is not one a flag name can continue with.
named(){ grep -qE -- "$1([^a-zA-Z0-9-]|\$)" "$TMP/surfaces.txt"; }
: >"$TMP/unnamed.txt"
while read -r flag; do
    named "$flag" || printf '%s\n' "$flag" >>"$TMP/unnamed.txt"
done <"$TMP/flags.txt"
# the prefix pairs the bounded match exists for — printed, so the population it protects is visible
PREFIXPAIRS="$( python3 - "$TMP/flags.txt" <<'PY'
import sys
flags = [ l.strip() for l in open( sys.argv[1] ) if l.strip() ]
print( sum( 1 for a in flags for b in flags if a != b and b.startswith( a ) ) )
PY
)"
[ "$PREFIXPAIRS" -ge 1 ] && ok "(A) $PREFIXPAIRS advertised flag(s) are a strict PREFIX of another — the bounded match is load-bearing" \
                         || no "(A) no prefix pair found; the bounded-match arm is inspecting nothing"
grep -vE '^[[:space:]]*(#|$)' "$BASELINE" | awk '{print $1}' | sort -u >"$TMP/known.txt"
comm -23 "$TMP/unnamed.txt" "$TMP/known.txt" >"$TMP/new_unnamed.txt"
if [ -s "$TMP/new_unnamed.txt" ]; then
    no "(A) flag(s) no skill body and no wrap primer names, and not on the recorded floor: $( tr '\n' ' ' <"$TMP/new_unnamed.txt" )"
else
    ok "(A) every advertised long flag is named on an agent surface, except the $( wc -l <"$TMP/known.txt" | tr -d ' ' ) on the recorded floor"
fi
# …and the floor may only shrink: a flag recorded as debt that a surface NOW names must leave the file.
: >"$TMP/stale.txt"
while read -r flag; do
    [ -n "$flag" ] || continue
    named "$flag" && printf '%s\n' "$flag" >>"$TMP/stale.txt"
done <"$TMP/known.txt"
[ -s "$TMP/stale.txt" ] \
    && no "(A) the floor records flag(s) an agent surface now names — delete the line(s) in the same commit: $( tr '\n' ' ' <"$TMP/stale.txt" )" \
    || ok "(A) every line on the recorded floor is still a real gap"

# ── (B) this round's new shapes: the term AND its verb, on one surface, within five lines ─────────────
# row: TERM | SURFACE_TERM | VERB | PROBE ARGV | PROBE PATTERN | LANE
# TERM is the identity (and what the PENDING list names); SURFACE_TERM is what a skill must spell; the
# probe RUNS the verb — no row is satisfied by --help alone.
ROWS='
--in=|--in=|--rank-by=churn-decay|. --rank-by=churn-decay --in=src|scope="src"|the directory-scoped recency window
--limit=|--limit=|--for|test/fixture --for=area --limit=5|limit="5"|the file-grain widening page
--offset=|--offset=|--for|test/fixture --for=area --limit=5 --offset=1|offset="1"|the widening page continuation
coverage=|coverage=|--for|test/fixture --for=area --limit=5|coverage="|the thin-answer coverage gauge
sc=|sc=|--for|test/cppqualfix| sc="|short symbol ids on map rows
<g|<g |--affected|. --affected=src/cli.h|<g|grouped tests-to-run rows
merge_bombs_skipped=|merge_bombs_skipped=|--rank-by=churn-decay|. --rank-by=churn-decay|merge_bombs_skipped=|the skipped-merge-bomb disclosure
scope=|scope=|--in=|. --rank-by=churn-decay --in=src|scope="src"|the scoped recency block
'
ROWCOUNT_EXPECTED=8
# PENDING: shapes this release lands in ANOTHER lane, which this build does not have yet. A surface may
# name one while it is declared here; when it arrives the pairing requirement turns on by itself and the
# row passes without anyone editing this file.
PENDING='|--in=|sc=|<g|merge_bombs_skipped=|scope=|'

# named PAIR: SURFACE_TERM and VERB within a five-line window of one surface file
pairNamed(){
    python3 - "$1" "$2" skills src/wrap.h <<'PY'
import sys, pathlib
term, verb = sys.argv[1], sys.argv[2]
files = []
for base in sys.argv[3:]:
    p = pathlib.Path( base )
    files.extend( sorted( p.rglob( "*.md" ) ) if p.is_dir() else [ p ] )
for f in files:
    lines = f.read_text( encoding = "utf-8", errors = "replace" ).splitlines()
    for i, line in enumerate( lines ):
        if term not in line:
            continue
        window = "\n".join( lines[ max( 0, i - 2 ) : i + 3 ] )
        if verb in window:
            sys.stdout.write( f"{f}:{i+1}" )
            sys.exit( 0 )
sys.exit( 1 )
PY
}

rows=0
printf '%s\n' "$ROWS" | while IFS='|' read -r TERM STERM VERB PROBE PAT LANE; do
    [ -n "${TERM:-}" ] || continue
    printf 'ROW\n' >>"$TMP/rowcount"
    # shellcheck disable=SC2086
    "$BIN" $PROBE </dev/null 2>/dev/null | grep -qF -- "$PAT" && present=1 || present=0
    pending=0
    case "$PENDING" in *"|$TERM|"*) pending=1;; esac
    paired=0; WHERE=""
    if WHERE="$( pairNamed "$STERM" "$VERB" )"; then paired=1; fi
    if [ "$present" = 1 ] && [ "$paired" = 1 ]; then
        printf '  PASS  (B) %s is named as %s beside %s on an agent surface (%s) — %s\n' "$TERM" "$STERM" "$VERB" "$WHERE" "$LANE"
    elif [ "$present" = 1 ]; then
        printf '  FAIL  (B) this build emits %s and no skill body or wrap primer spells %s within five lines of %s — %s is unreachable from a skill\n' "$TERM" "$STERM" "$VERB" "$LANE"
    elif [ "$pending" = 1 ]; then
        if [ "$paired" = 1 ]; then
            printf '  PASS  (B) %s (%s) is DECLARED pending and already paired on a surface (%s) — it turns on with the lane that ships it\n' "$TERM" "$LANE" "$WHERE"
        else
            printf '  PASS  (B) %s (%s) is DECLARED pending and named nowhere — nothing is promised that this build refuses\n' "$TERM" "$LANE"
        fi
    elif [ "$paired" = 1 ]; then
        printf '  FAIL  (B) a surface promises %s (%s) and this build refuses it, with no lane declared for it — declare it or delete the sentence\n' "$TERM" "$LANE"
    else
        printf '  FAIL  (B) %s (%s) is neither in this build nor declared pending nor named anywhere — the row is stale\n' "$TERM" "$LANE"
    fi
done >"$TMP/brows" 2>&1
cat "$TMP/brows"
grep -q '^  FAIL' "$TMP/brows" && fail=1
# POPULATION: a row set that silently shrank to zero would print nothing and pass (the harness-reports-
# success-for-work-it-skipped trap). The count is asserted, not assumed.
ROWSEEN="$( wc -l <"$TMP/rowcount" 2>/dev/null | tr -d ' ' )"; ROWSEEN="${ROWSEEN:-0}"
{ [ "$ROWSEEN" -gt 0 ] && [ "$ROWSEEN" = "$ROWCOUNT_EXPECTED" ]; } \
    && ok "(B) the shape table has its full population ($ROWSEEN of $ROWCOUNT_EXPECTED rows probed)" \
    || no "(B) $ROWSEEN of $ROWCOUNT_EXPECTED shape rows were probed — the arm inspected a different table than it claims"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
