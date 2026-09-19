#!/usr/bin/env bash
# forhdrshapecheck.sh — R2-AF (round 2, answer-first ordering, owner-approved): the S4 shape gate for
# `<hdr p= of=/>`, the --for lookup that answers "what else has to change with the file this task already
# names" — the file's one same-directory, same-stem declaration/implementation partner, printed FIRST
# inside the root, right after the legend (round-2 amendment §R7; PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/
# 12_round2_PREREG.md).
#
# WHAT THIS GATE PINS.
#   (1) a task that names a file with a unique decl/impl partner gets `<hdr p="partner" of="named"/>` as
#       the FIRST child of the root, before <sigs>/<hops> — never a wrapping element, never inside <tail>.
#   (2) the element is DEFINED, verbatim, in BOTH legend dialects: FULL (198 B) under the default posture
#       (which is `--legend=full`, spelled explicitly here so a drift in the default cannot hide this arm)
#       and COMPACT (96 B) under `--legend=compact`. Absent when the answer carries no row (present-only).
#   (3) ROBUSTNESS — no reordering and no `<hdr>` row when the named path is: absent from the index,
#       ambiguous (matches more than one indexed file), or names a file with no decl/impl convention
#       (partner absent or itself ambiguous). Guessing is explicitly forbidden by §R7; these arms prove
#       the tool refuses rather than guesses.
#   (4) the direction is symmetric (naming the source finds the header; naming the header finds the
#       source) and a partner that is ALSO named in the task is suppressed (§R7's "not itself named" rule).
#   (5) the MCP `for` twin (mcpverbs.h forTaskText) emits the SAME row set as the CLI, from the SAME
#       resolver (rw::forNamedHeaderRows, mention.h) — one resolution, two surfaces.
#   (6) determinism and xmllint well-formedness on every fixture this gate builds.
#
# RED-FIRST: every positive arm below is asserted to be genuinely new — run this gate against a
# pre-AF binary (RIPWIRE_BIN=<base ripwire> bash test/forhdrshapecheck.sh) and arms (1)-(2) and (4)-(5)
# read FAIL, because no such binary emits `<hdr>` at all. This file does not special-case that: the
# same assertions are red on the base binary and green on this lane's, by construction.
#
# Usage: bash test/forhdrshapecheck.sh [path/to/ripwire]
# Exits non-zero on any failure. Read-only outside its own scratch dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# ── the fixture: an unambiguous decl/impl pair, a lone file with no partner, a same-stem DECOY in a
#    different directory (makes the bare basename "widget.cc" ambiguous), and a same-dir same-stem TEST
#    partner that shares no known decl/impl extension (so it never displaces the .h answer).
FX="$TMP/fx"
mkdir -p "$FX/core" "$FX/other"
cat > "$FX/core/widget.h" <<'EOF'
#pragma once
int widgetArea( int w, int h );
EOF
cat > "$FX/core/widget.cc" <<'EOF'
#include "core/widget.h"
int widgetArea( int w, int h ) { return w * h; }
EOF
cat > "$FX/core/widget_test.cc" <<'EOF'
#include "core/widget.h"
int test_widget_area() { return widgetArea( 2, 3 ); }
EOF
cat > "$FX/core/gadget.cc" <<'EOF'
int gadgetSpin( int n ) { return n + 1; }
EOF
# the decoy: same STEM as core/widget.cc, different DIRECTORY — makes a bare "widget.cc" mention name
# TWO indexed files, so resolution must refuse rather than guess which one.
cat > "$FX/other/widget.cc" <<'EOF'
int otherWidget( int n ) { return n - 1; }
EOF
[ -s "$FX/core/widget.h" ] && [ -s "$FX/other/widget.cc" ] || { echo "fixture write failed"; exit 2; }

hdr_of(){ "$BIN" "$FX" --for="$1" "${@:2}" 2>/dev/null | grep -o '<hdr[^>]*>'; }

# ── (1) THE ROW — first child of the root, before <sigs> ───────────────────────────────────────────────
OUT1="$( "$BIN" "$FX" --for="fix core/widget.cc" 2>/dev/null )"
H1="$( printf '%s' "$OUT1" | grep -o '<hdr[^>]*>' | head -1 )"
if [ -z "$H1" ]; then
  no "(1) --for=\"fix core/widget.cc\" carries no <hdr> row at all"
else
  case "$H1" in
    *'p="core/widget.h"'*'of="core/widget.cc"'*) ok "(1) row names the header as p= and the source as of=: $H1" ;;
    *) no "(1) row has the wrong p=/of= pair: $H1" ;;
  esac
  # first child of the root: nothing but the header/legend comment(s) between the root open and <hdr>
  BEFORE="$( printf '%s' "$OUT1" | sed 's/<hdr /\n<hdr /' | head -1 )"
  case "$BEFORE" in
    *'<sigs'*|*'<hops'*|*'<d '*) no "(1) a ranked row appears before <hdr>: $BEFORE" ;;
    *) ok "(1) <hdr> precedes every ranked/hops row" ;;
  esac
  case "$OUT1" in
    *'<hdr'*'<sigs'*) ok "(1) <hdr> sits before <sigs> in document order" ;;
    *) no "(1) <hdr> does not precede <sigs>: could not confirm document order" ;;
  esac
  case "$OUT1" in
    *'<tail'*'<hdr'*) no "(1) <hdr> is nested after/inside <tail> — it must be a first-class root child" ;;
    *) ok "(1) <hdr> is not folded into <tail>" ;;
  esac
fi

# ── (2) THE LEGEND — both dialects, verbatim, present-only ─────────────────────────────────────────────
FULL="$( "$BIN" "$FX" --for="fix core/widget.cc" --legend=full 2>/dev/null )"
FULLCLAUSE='; hdr p= of=: the file the task names (of=) has exactly one same-directory, same-stem declaration/implementation partner (p=), listed first by name alone: a lookup, not a ranked or graph-derived row'
case "$FULL" in
  *"$FULLCLAUSE"*) ok "(2) --legend=full defines <hdr> with the exact §R7 sentence (198 B)" ;;
  *) no "(2) --legend=full is missing the exact FULL <hdr> clause" ;;
esac
COMPACT="$( "$BIN" "$FX" --for="fix core/widget.cc" --legend=compact 2>/dev/null )"
COMPACTCLAUSE="; hdr p= of=: the named file's one same-dir same-stem decl/impl partner, listed first (a lookup)"
case "$COMPACT" in
  *"$COMPACTCLAUSE"*) ok "(2) --legend=compact defines <hdr> with the exact §R7 sentence (96 B)" ;;
  *) no "(2) --legend=compact is missing the exact COMPACT <hdr> clause" ;;
esac
# present-only: a task naming nothing with a partner defines <hdr> NOWHERE
NOPARTNER="$( "$BIN" "$FX" --for="fix core/gadget.cc" --legend=full 2>/dev/null )"
case "$NOPARTNER" in
  *'<hdr'*) no "(2) a task with no partner still emits <hdr>" ;;
  *"$FULLCLAUSE"*) no "(2) present-only violated: the legend defines <hdr> on an answer with no such row" ;;
  *) ok "(2) present-only: no row, no clause, on a task naming a partner-less file" ;;
esac

# ── (3) ROBUSTNESS — absent / ambiguous / no-convention never reorders and never guesses ────────────────
ABSENT="$( hdr_of 'fix core/nosuchfile.cc' )"
[ -z "$ABSENT" ] && ok "(3) an unindexed named path emits no <hdr> (never guesses)" \
                  || no "(3) an unindexed named path emitted: $ABSENT"

AMBIG="$( hdr_of 'fix widget.cc' )"
[ -z "$AMBIG" ] && ok "(3) a bare basename matching TWO files (core/ and other/) emits no <hdr> (ambiguous named file)" \
                 || no "(3) an ambiguous named-file mention still emitted: $AMBIG"

NOCONV="$( hdr_of 'fix core/gadget.cc' )"
[ -z "$NOCONV" ] && ok "(3) a file with no same-dir same-stem partner emits no <hdr>" \
                  || no "(3) a partner-less file emitted: $NOCONV"

# absent/ambiguous/no-convention must not reorder the document either — <sigs> (or <hops>) is still the
# first ranked element, exactly where it sits with the feature off.
for q in 'fix core/nosuchfile.cc' 'fix widget.cc' 'fix core/gadget.cc'; do
  O="$( "$BIN" "$FX" --for="$q" 2>/dev/null )"
  case "$O" in
    *'<hdr'*) no "(3) '$q' reordered the document with a spurious <hdr>" ;;
    *) ok "(3) '$q' left the document unreordered (no <hdr>)" ;;
  esac
done

# ── (4) SYMMETRIC DIRECTION, and a partner named elsewhere is suppressed ────────────────────────────────
REV="$( hdr_of 'fix core/widget.h' )"
case "$REV" in
  *'p="core/widget.cc"'*'of="core/widget.h"'*) ok "(4) naming the HEADER finds the source partner: $REV" ;;
  *) no "(4) naming core/widget.h did not find its source partner: $REV" ;;
esac
BOTH="$( hdr_of 'compare core/widget.cc against core/widget.h' )"
[ -z "$BOTH" ] && ok "(4) naming BOTH halves of a pair suppresses the row (the partner is already named)" \
               || no "(4) naming both halves still emitted a row: $BOTH"

# ── (5) MCP TWIN PARITY — the same resolver, the same row set ───────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  MCPOUT="$TMP/mcp.json"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                 '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":"'"$FX"'","task":"fix core/widget.cc"}}}' \
    | "$BIN" --mcp >"$MCPOUT" 2>/dev/null
  MHDR="$( python3 - "$MCPOUT" <<'PYEOF'
import json, re, sys
last = [ l for l in open( sys.argv[1] ) if l.strip() ][-1]
try:
    text = json.loads( last )["result"]["content"][0]["text"]
except Exception:
    print( "__NONE__" ); raise SystemExit
m = re.search( r'<hdr [^>]*>', text )
print( m.group( 0 ) if m else "__ABSENT__" )
PYEOF
)"
  case "$MHDR" in
    __NONE__) no "(5) the MCP \`for\` twin returned no readable content" ;;
    __ABSENT__) no "(5) the MCP \`for\` twin carries no <hdr> row for the same task the CLI answers" ;;
    *'p="core/widget.h"'*'of="core/widget.cc"'*) ok "(5) the MCP twin's <hdr> matches the CLI's: $MHDR" ;;
    *) no "(5) the MCP twin's <hdr> differs from the CLI's: $MHDR" ;;
  esac
fi

# ── (6) DETERMINISM + WELL-FORMEDNESS ────────────────────────────────────────────────────────────────
"$BIN" "$FX" --for="fix core/widget.cc" >"$TMP/d1.xml" 2>/dev/null
"$BIN" "$FX" --for="fix core/widget.cc" >"$TMP/d2.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && ok "(6) --for is byte-identical across two runs with a <hdr> row" \
                                    || no "(6) --for is not deterministic with a <hdr> row"
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$TMP/d1.xml" 2>/dev/null && ok "(6) the <hdr>-carrying document is well-formed XML (G4)" \
                                             || no "(6) the <hdr>-carrying document is NOT well-formed XML"
fi

echo
if [ "$fail" -eq 0 ]; then echo "forhdrshapecheck: ALL PASS"; else echo "forhdrshapecheck: SOME FAILED"; fi
exit "$fail"
