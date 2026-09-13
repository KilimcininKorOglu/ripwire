#!/usr/bin/env bash
# agentsurfacecheck.sh — a shape an AGENT cannot be told about is a shape that does not ship.
#
# WHAT THIS GATE IS FOR. 0.6.1 adds surfaces an agent has to ASK for: a directory-scoped recency window,
# a file-grain widening page, grouped test rows, short symbol ids. Every one of them was measured, gated
# and documented — and none of that reaches the agent that has to type the flag. The tool's own reference
# (docs/COMMANDS.md) names every flag by construction, which is exactly why it is NOT accepted as the
# surface here: a gate that a generated document satisfies for free cannot fail. The surfaces that count
# are the ones an agent actually LOADS mid-task:
#
#     skills/*/*.md          the skill bodies
#     src/wrap.h             the pasteable primer `ripwire wrap AGENT` writes into a client's rules file
#
# TWO ARMS, two different questions.
#
#   (A) THE RATCHET — every long flag `--help` advertises is named on one of those surfaces, except the
#       ones recorded in test/agentsurfacefix/unnamed_flags_baseline.txt. That file is an INVENTORY OF
#       KNOWN DEBT, not an approval (legendcoverage_baseline.txt's rule, same shape): it may only be
#       edited DOWNWARD, and a NEW flag that no skill names turns this arm red in the commit that adds
#       the flag rather than a release later.
#
#   (B) THE ROUND'S NEW SHAPES — a term AND the verb it belongs to, within five lines of each other on
#       one surface. Naming `--limit` somewhere and `--for` somewhere else does not tell an agent that
#       the widening page exists; the PAIR is the instruction. Each row is probed against the binary
#       first, because a surface may not promise a flag this build cannot parse: a term the binary does
#       not emit yet is reported with the lane that ships it and asserts nothing. The moment it arrives
#       the pairing requirement turns on by itself — and the PENDING list is asserted in the other
#       direction too, so a shape that has landed cannot stay parked on it (trap ledger: a cap that opts
#       out of its own relief).
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
"$BIN" --help=all 2>&1 | grep -oE '^[[:space:]]+--[a-z][a-z0-9-]*' | tr -d ' ' | sort -u >"$TMP/flags.txt"
FLAGN="$( wc -l <"$TMP/flags.txt" | tr -d ' ' )"
[ "$FLAGN" -ge 100 ] && ok "(A) --help advertises $FLAGN long flags (the census has a population)" \
                     || no "(A) only $FLAGN long flags were extracted from --help — the census is broken, not clean"
: >"$TMP/unnamed.txt"
while read -r flag; do
    grep -qF -- "$flag" "$TMP/surfaces.txt" || printf '%s\n' "$flag" >>"$TMP/unnamed.txt"
done <"$TMP/flags.txt"
grep -vE '^[[:space:]]*(#|$)' "$BASELINE" | awk '{print $1}' | sort -u >"$TMP/known.txt"
comm -23 "$TMP/unnamed.txt" "$TMP/known.txt" >"$TMP/new_unnamed.txt"
if [ -s "$TMP/new_unnamed.txt" ]; then
    no "(A) flag(s) no skill body and no wrap primer names, and not on the recorded floor: $( tr '\n' ' ' <"$TMP/new_unnamed.txt" )"
else
    ok "(A) every advertised long flag is named on an agent surface, except the $( wc -l <"$TMP/known.txt" | tr -d ' ' ) on the recorded floor"
fi
# …and the floor may only shrink: a flag recorded as debt that a skill NOW names must leave the file.
: >"$TMP/stale.txt"
while read -r flag; do
    [ -n "$flag" ] || continue
    grep -qF -- "$flag" "$TMP/surfaces.txt" && printf '%s\n' "$flag" >>"$TMP/stale.txt"
done <"$TMP/known.txt"
[ -s "$TMP/stale.txt" ] \
    && no "(A) the floor records flag(s) an agent surface now names — delete the line(s) in the same commit: $( tr '\n' ' ' <"$TMP/stale.txt" )" \
    || ok "(A) every line on the recorded floor is still a real gap"

# ── (B) this round's new shapes: the term AND its verb, on one surface, within five lines ─────────────
# row: TERM | VERB | PROBE | PROBE_PATTERN | LANE
#   PROBE "help"   — the term is a flag; the binary HAS it when --help=all advertises it
#   PROBE "<argv>" — run the binary with that argv and look for PROBE_PATTERN in its output
ROWS='
--in=|--rank-by=churn-decay|help|--in=|the directory-scoped recency window
--limit=|--for|help|--limit=|the file-grain widening page
--offset=|--for|help|--offset=|the widening page continuation
coverage=|--for|test/fixture --for=area --limit=5|coverage="|the thin-answer coverage gauge
sc=|--for|test/cppqualfix| sc="|short symbol ids on map rows
<g|--affected|. --affected=src/cli.h|<g|grouped tests-to-run rows (the row shape, or the legend clause that defines it)
merge_bombs_skipped=|--rank-by=churn-decay|. --rank-by=churn-decay|merge_bombs_skipped=|the skipped-merge-bomb disclosure
scope=|--in=|. --rank-by=churn-decay --in=src|scope=|the scoped recency block
'
# PENDING: shapes this release lands in another lane, which this build does not have yet. A row here
# asserts nothing about the surfaces — and FAILS the moment the binary does have it, so the list cannot
# outlive its reason.
PENDING='|--in=|sc=|<g|merge_bombs_skipped=|scope=|'

# named PAIR: TERM and VERB within a five-line window of one surface file
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

printf '%s\n' "$ROWS" | while IFS='|' read -r TERM VERB PROBE PAT LANE; do
    [ -n "${TERM:-}" ] || continue
    if [ "$PROBE" = "help" ]; then
        "$BIN" --help=all </dev/null 2>&1 | grep -qF -- "$PAT" && present=1 || present=0
    else
        # shellcheck disable=SC2086
        "$BIN" $PROBE </dev/null 2>/dev/null | grep -qF -- "$PAT" && present=1 || present=0
    fi
    pending=0
    case "$PENDING" in *"|$TERM|"*) pending=1;; esac
    if [ "$present" = 1 ] && [ "$pending" = 1 ]; then
        printf '  FAIL  (B) %s (%s) has landed in this build — take it off the PENDING list in this gate and require its surface\n' "$TERM" "$LANE"
        continue
    fi
    if [ "$present" = 0 ]; then
        if [ "$pending" = 1 ]; then
            printf '  PASS  (B) %s (%s) is not in this build yet; the pairing requirement turns on with the lane that ships it\n' "$TERM" "$LANE"
        else
            printf '  FAIL  (B) %s (%s) is neither in this build nor declared pending — the row is stale\n' "$TERM" "$LANE"
        fi
        continue
    fi
    if WHERE="$( pairNamed "$TERM" "$VERB" )"; then
        printf '  PASS  (B) %s is named beside %s on an agent surface (%s) — %s\n' "$TERM" "$VERB" "$WHERE" "$LANE"
    else
        printf '  FAIL  (B) no skill body or wrap primer names %s within five lines of %s — %s is unreachable from a skill\n' "$TERM" "$VERB" "$LANE"
    fi
done >"$TMP/brows" 2>&1
cat "$TMP/brows"
grep -q '^  FAIL' "$TMP/brows" && fail=1

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES PRESENT"; exit 1
