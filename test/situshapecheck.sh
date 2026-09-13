#!/usr/bin/env bash
# situshapecheck.sh — --situ's DISCLOSURE SHAPE: every fact the report used to say in a sentence is said as
# an attribute, and nothing it disclosed has gone missing.
#
#   test/situshapecheck.sh
#   RIPWIRE_BIN=asan/ripwire test/situshapecheck.sh
#
# WHY THIS EXISTS. --situ is the mid-task report, and it is the one verb with no XML root to hang attributes
# on — so every disclosure it owed was written as prose, and the prose grew: the graph-count floor clause ran
# 601 B, the decl/def partner header 229 B, the tests-to-run header 267 B, and the script-gates caveat 152 B,
# on a report whose whole ANSWER (the [2] rows) is what the agent acts on. A byte attribution over the frozen
# question set (PLAN_OUTPUT_ROUTING_LOOP §1.2) put ~800 B per answer in those four sentences, repeated on every
# call, carrying facts a reader can only use if they are NAMED — which is what an attribute is.
#
# METHODOLOGY §9 is the rule this gate enforces: honesty lives in ATTRIBUTES, and a shortened sentence may not
# quietly drop a floor, a cap, or a caveat. So each arm below names ONE disclosure the prose carried and
# asserts the attribute form still carries it — by name, with a reading — plus a byte ratchet per line so the
# prose cannot creep back. test/floormarkcheck.sh keeps the two anchor phrases; this gate mirrors them, so a
# regression reds HERE too rather than only in a gate about a different property.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

# ── the fixture: a header/implementation pair with a test partner, a same-stem DECOY in another directory,
#    and a caller, so [1] has a blast radius AND a decl/def partner list. Seeded as a git repo because --situ
#    mines co-change; the dates are fixed so the report is reproducible.
FX="$TMP/fx"
mkdir -p "$FX/core" "$FX/other" "$FX/app"
cat > "$FX/core/widget.h" <<'EOF'
#pragma once
int widgetArea( int w, int h );
int widgetPerimeter( int w, int h );
EOF
cat > "$FX/core/widget.cc" <<'EOF'
#include "core/widget.h"

int widgetArea( int w, int h )
{
    return w * h;
}

int widgetPerimeter( int w, int h )
{
    return 2 * ( w + h );
}
EOF
cat > "$FX/core/widget_test.cc" <<'EOF'
#include "core/widget.h"

int test_widget_area()
{
    return widgetArea( 2, 3 );
}
EOF
cat > "$FX/core/widget.inl" <<'EOF'
inline int widgetSquare( int s ) { return s * s; }
EOF
cat > "$FX/core/gadget.cc" <<'EOF'
int gadgetSpin( int n ) { return n + 1; }
EOF
cat > "$FX/other/widget.cc" <<'EOF'
int otherWidget( int n ) { return n - 1; }
EOF
# the WIDE stem: nine same-directory, same-stem siblings, so the block's cap and its disclosure are live
for f in wide.h wide_test.cc wide_unittest.cc wide_spec.cc wideTest.cc; do
  printf '#pragma once\nint wideThing_%s( int n );\n' "$( printf '%s' "$f" | tr './-' '___' )" > "$FX/core/$f"
done
printf 'int wideThing( int n ) { return n; }\n' > "$FX/core/wide.cc"
for f in wide.inl wide.ipp wide.hpp wide.hxx; do
  printf 'inline int wideInline_%s( int n ) { return n; }\n' "$( printf '%s' "$f" | tr './-' '___' )" > "$FX/core/$f"
done
cat > "$FX/app/main.cc" <<'EOF'
#include "core/widget.h"

int appMain()
{
    return widgetArea( 4, 5 ) + widgetPerimeter( 4, 5 );
}
EOF
( cd "$FX" && git init -q -b main >/dev/null 2>&1
  git config user.email rw@example.invalid; git config user.name ripwire
  git add -A >/dev/null 2>&1
  GIT_AUTHOR_DATE='2026-01-01T00:00:00 +0000' GIT_COMMITTER_DATE='2026-01-01T00:00:00 +0000' \
    git commit -q -m seed >/dev/null 2>&1 ) || true

OUT="$TMP/situ.txt"
"$BIN" "$FX" --situ=core/widget.cc >"$OUT" 2>/dev/null
REPO_OUT="$TMP/repo.txt"
"$BIN" "$ROOT" --situ=src/graph.h >"$REPO_OUT" 2>/dev/null

[ -s "$OUT" ] || { no "the fixture produced no --situ report at all — every arm below would be a false green"; echo "situshapecheck: SOME FAILED"; exit 1; }
grep -q '^  \[1\] blast radius' "$OUT" || { no "the fixture's report has no [1] section — fixture broken"; echo "situshapecheck: SOME FAILED"; exit 1; }
ok "fixture: --situ=core/widget.cc produced a report with a [1] section"

# the one line matching a pattern, and its byte length
line_of(){ grep -m1 -- "$1" "$2"; }
len_of(){ local l; l="$( line_of "$1" "$2" )"; printf '%s' "${#l}"; }

# ── (1) THE GRAPH-COUNT FLOOR — four gauges, one line, both anchor phrases ───────────────────────────────
# Was 601 B of prose on every answer. The facts it owed: counts_floor, the two resolver gauges, the third
# (unindexed) gauge when the build could not read some files at all, that every count is a FLOOR, and how to
# read a zero. All six survive; only the sentence around them is gone.
FL="$( line_of 'counts_floor=1' "$REPO_OUT" )"
if [ -z "$FL" ]; then
  no "(1) --situ states no counts_floor at all"
else
  for tok in 'counts_floor=1' 'graph_ambiguous=' 'graph_unresolved='; do
    case "$FL" in *"$tok"*) ok "(1) floor line carries $tok" ;; *) no "(1) floor line lost $tok: $FL" ;; esac
  done
  # the two phrases test/floormarkcheck.sh matches, mirrored here so a regression reds in both gates
  case "$FL" in *'is a FLOOR, never a total'*) ok "(1) floor line keeps the anchor phrase 'is a FLOOR, never a total'" ;;
                *) no "(1) floor line lost floormarkcheck's anchor phrase: $FL" ;; esac
  case "$FL" in *'none found'*) ok "(1) floor line keeps the zero reading ('none found')" ;;
                *) no "(1) floor line lost the zero reading: $FL" ;; esac
  # the third gauge rides exactly when the map header's unindexed= is non-zero (#66's attribute⇒clause rule)
  # the oracle is the XML sibling over the SAME corpus: --affected's root carries graph_unindexed= when, and
  # only when, some file no grammar in this build could read was crawled. (The map header's own unindexed= is
  # an extension HISTOGRAM, not a count, so it cannot serve as the oracle here.)
  UNIDX="$( "$BIN" "$ROOT" --affected=src/graph.h 2>/dev/null | tr ' ' '\n' | sed -n 's/^graph_unindexed="\([0-9]*\)".*/\1/p' | head -1 )"
  if [ "${UNIDX:-0}" -gt 0 ]; then
    case "$FL" in *"graph_unindexed=$UNIDX"*) ok "(1) floor line carries graph_unindexed=$UNIDX, the same gauge --affected's root carries" ;;
                  *) no "(1) --affected says graph_unindexed=$UNIDX and the floor line does not carry it: $FL" ;; esac
  else
    case "$FL" in *'graph_unindexed='*) no "(1) floor line claims graph_unindexed= on a corpus with nothing unindexed" ;;
                  *) ok "(1) floor line omits graph_unindexed= — nothing was unindexed" ;; esac
  fi
  N="$( len_of 'counts_floor=1' "$REPO_OUT" )"
  [ "$N" -le 200 ] && ok "(1) floor line is ${N} B (ratchet 200) — an attribute line, not a paragraph" \
                   || no "(1) floor line is ${N} B, over the 200 B ratchet: the prose has crept back"
fi

# ── (2) THE DECL/DEF PARTNER HEADER — the "NOT dependents" caveat becomes an attribute ───────────────────
# The 229 B sentence existed to stop a reader treating the partner rows as transitive dependents. That is a
# NAMEABLE fact: not_dependents=1, beside the count.
PH="$( line_of 'decl/def partners' "$OUT" )"
if [ -z "$PH" ]; then
  no "(2) the fixture's report lists no decl/def partners — the arm would be a false green"
else
  case "$PH" in *'not_dependents=1'*) ok "(2) partner header carries not_dependents=1" ;;
                *) no "(2) partner header does not name the NOT-dependents caveat as an attribute: $PH" ;; esac
  case "$PH" in *'(2)'*|*'(1)'*|*'(3)'*) ok "(2) partner header still states how many partners there are" ;;
                *) no "(2) partner header lost its count: $PH" ;; esac
  N="$( len_of 'decl/def partners' "$OUT" )"
  [ "$N" -le 140 ] && ok "(2) partner header is ${N} B (ratchet 140)" \
                   || no "(2) partner header is ${N} B, over the 140 B ratchet"
fi

# ── (3) SECTION [1]'s pr-context ASIDE — a cap is a number, so it is an attribute ────────────────────────
# "--pr-context's own per-file blast-radius list is also capped, at 20" is one number and one target.
B1="$( line_of '\[1\] blast radius' "$REPO_OUT" )"
case "$B1" in
  *'capped=1'*) ok "(3) [1] keeps pageview.h's shown=/total=/capped= triple" ;;
  *)            no "(3) [1] lost its cut disclosure: $B1" ;;
esac
case "$B1" in
  *'prcontext_cap=20'*) ok "(3) [1] names --pr-context's own cap as prcontext_cap=20" ;;
  *)                    no "(3) [1] does not carry prcontext_cap=20: $B1" ;;
esac
case "$B1" in
  *"pr-context's own per-file blast-radius list is also capped"*)
      no "(3) [1] still spells the pr-context cap as a sentence" ;;
  *)  ok "(3) [1] no longer spells the pr-context cap as a sentence" ;;
esac

# ── (4) SECTION [2]'s EVIDENCE ORDER — the same attribute its XML sibling carries ────────────────────────
# --affected's root says order="evidence"; --situ said the same thing in 127 B of prose and never named it.
B2="$( line_of '\[2\] tests to run' "$REPO_OUT" )"
case "$B2" in
  *'order=evidence'*) ok "(4) [2] names its ordering as order=evidence, like --affected's root" ;;
  *)                  no "(4) [2] does not carry order=evidence: $B2" ;;
esac
case "$B2" in
  *'[changed]'*) ok "(4) [2] keeps a reading of the evidence tags the rows carry" ;;
  *)             no "(4) [2] dropped the reading of [changed]/[partner]/hops — the tags would be undefined" ;;
esac
N="$( len_of '\[2\] tests to run' "$REPO_OUT" )"
[ "$N" -le 230 ] && ok "(4) [2] header is ${N} B (ratchet 230)" \
                 || no "(4) [2] header is ${N} B, over the 230 B ratchet"

# ── (5) THE SCRIPT-GATES BLIND SPOT — the same counter --affected carries as an attribute ────────────────
SG="$( line_of 'script_gates_unmodelled=' "$REPO_OUT" )"
AFF="$( "$BIN" "$ROOT" --affected=src/graph.h 2>/dev/null | tr ' ' '\n' | sed -n 's/^script_gates_unmodelled="\([0-9]*\)".*/\1/p' | head -1 )"
if [ -z "$SG" ]; then
  no "(5) --situ does not name its script-gate blind spot as script_gates_unmodelled="
else
  ok "(5) --situ carries script_gates_unmodelled= as an attribute"
  case "$SG" in *"script_gates_unmodelled=$AFF"*) ok "(5) --situ and --affected report the SAME count ($AFF)" ;;
                *) no "(5) --situ's count disagrees with --affected's script_gates_unmodelled=\"$AFF\": $SG" ;; esac
  case "$SG" in *'not call edges'*) ok "(5) the blind spot keeps its cause (script-to-binary edges are not call edges)" ;;
                *) no "(5) the blind spot lost its cause: $SG" ;; esac
  N="$( len_of 'script_gates_unmodelled=' "$REPO_OUT" )"
  [ "$N" -le 140 ] && ok "(5) script-gates line is ${N} B (ratchet 140)" \
                   || no "(5) script-gates line is ${N} B, over the 140 B ratchet"
fi

# ── (6) NOTHING WENT MISSING, AND THE REPORT GOT SMALLER ────────────────────────────────────────────────
# The whole point: fewer bytes, same facts. Every disclosure token above must be present in ONE report.
MISSING=""
for tok in 'counts_floor=1' 'graph_ambiguous=' 'graph_unresolved=' 'order=evidence' 'script_gates_unmodelled=' 'capped=1' 'prcontext_cap='; do
  grep -q -- "$tok" "$REPO_OUT" || MISSING="$MISSING $tok"
done
[ -z "$MISSING" ] && ok "(6) one report carries every disclosure attribute" \
                  || no "(6) the report is missing:$MISSING"
# determinism, on the verb this gate reshapes
"$BIN" "$FX" --situ=core/widget.cc >"$TMP/d1" 2>/dev/null
"$BIN" "$FX" --situ=core/widget.cc >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"
then
    ok "(6) --situ is byte-identical across two runs"
else
    no "(6) --situ is not deterministic"
fi

# ── (7) LEXICAL SIBLINGS (L-D) — the files that move WITH a changed file, which no graph walk can reach ──
# A change to core/widget.cc almost always touches core/widget.h and core/widget_test.cc, and neither is a
# transitive DEPENDENT: a header does not call its own implementation, and a test the graph cannot link (a
# fixture-built harness, a generated main) is reached by nothing. The frozen-30 attribution put two of our
# incomplete answers exactly there. This block is lexical and static — same directory, same stem — so it
# costs no history and cannot leak a future commit into an answer about the present.
SIB="$( grep -m1 'lexical siblings' "$OUT" )"
if [ -z "$SIB" ]; then
  no "(7) --situ lists no lexical siblings for core/widget.cc"
else
  ok "(7) --situ has a lexical-siblings block: $SIB"
  sib_rows(){ sed -n '/lexical siblings/,/^  \[2\]/p' "$1" | awk '/^        [^ (]/ && NF == 1 && $1 !~ /=/ { print $1 }'; }
  ROWS="$( sib_rows "$OUT" )"
  for want in core/widget.h core/widget_test.cc core/widget.inl; do
    printf '%s\n' "$ROWS" | grep -qx -- "$want" \
      && ok "(7) siblings include $want" \
      || no "(7) siblings do NOT include $want (rows: $( printf '%s' "$ROWS" | tr '\n' ' ' ))"
  done
  # the DECOY: same stem, different directory. A sibling is a neighbour, not a namesake.
  printf '%s\n' "$ROWS" | grep -qx -- 'other/widget.cc' \
    && no "(7) siblings wrongly include other/widget.cc — a same-stem file in a DIFFERENT directory" \
    || ok "(7) siblings exclude other/widget.cc (same stem, different directory)"
  # the neighbour that is not a namesake
  printf '%s\n' "$ROWS" | grep -qx -- 'core/gadget.cc' \
    && no "(7) siblings wrongly include core/gadget.cc — same directory, different stem" \
    || ok "(7) siblings exclude core/gadget.cc (same directory, different stem)"
  # the changed file itself is not its own sibling
  printf '%s\n' "$ROWS" | grep -qx -- 'core/widget.cc' \
    && no "(7) siblings list the changed file itself" \
    || ok "(7) siblings exclude the changed file itself"
  # root-relative, like every other path in the report
  BAD="$( printf '%s\n' "$ROWS" | grep -E '^(/|\./)' | head -1 )"
  if [ -z "$BAD" ]
  then
      ok "(7) sibling paths are root-relative"
  else
      no "(7) sibling path '$BAD' is absolute or ./-prefixed"
  fi
  case "$SIB" in
    *'not_dependents=1'*) ok "(7) the block says these are NOT transitive dependents (not_dependents=1)" ;;
    *)                    no "(7) the block does not say these rows are not dependents: $SIB" ;;
  esac
fi

# ── (7b) BOUNDED, and the bound DISCLOSED ───────────────────────────────────────────────────────────────
WIDE="$TMP/wide.txt"
"$BIN" "$FX" --situ=core/wide.cc >"$WIDE" 2>/dev/null
WSIB="$( grep -m1 'lexical siblings' "$WIDE" )"
if [ -z "$WSIB" ]; then
  no "(7b) the wide-stem file lists no siblings at all — the cap arm would be a false green"
else
  case "$WSIB" in
    *'capped=1'*) ok "(7b) a stem with more siblings than the cap discloses capped=1: $WSIB" ;;
    *)            no "(7b) the sibling block is cut without saying so: $WSIB" ;;
  esac
  case "$WSIB" in
    *'shown='*'total='*) ok "(7b) the cut names shown= and total=" ;;
    *)                   no "(7b) the cut names no shown=/total= pair: $WSIB" ;;
  esac
  case "$WSIB" in
    *'next: --situ'*) ok "(7b) the cut carries a pasteable next: that widens it" ;;
    *)                no "(7b) the cut offers no relief: $WSIB" ;;
  esac
  WROWS="$( sed -n '/lexical siblings/,/^  \[2\]/p' "$WIDE" | awk '/^        [^ (]/ && NF == 1 && $1 !~ /=/ { print $1 }' | grep -c . )"
  WTOTAL="$( printf '%s' "$WSIB" | sed -n 's/.*total=\([0-9]*\).*/\1/p' )"
  [ "${WROWS:-0}" -lt "${WTOTAL:-0}" ] && ok "(7b) ${WROWS} rows of ${WTOTAL} — the count is the population, not the rows" \
                                       || no "(7b) shown rows (${WROWS}) do not sit under total=${WTOTAL}"
  # --limit raises it, exactly as it raises [1] and [3]
  "$BIN" "$FX" --situ=core/wide.cc --limit=40 >"$TMP/wide40.txt" 2>/dev/null
  W40="$( sed -n '/lexical siblings/,/^  \[2\]/p' "$TMP/wide40.txt" | awk '/^        [^ (]/ && NF == 1 && $1 !~ /=/ { print $1 }' | grep -c . )"
  [ "${W40:-0}" -gt "${WROWS:-0}" ] && ok "(7b) --limit=40 widens the sibling block (${WROWS} -> ${W40} rows)" \
                                    || no "(7b) --limit did not widen the sibling block (${WROWS} -> ${W40})"
fi

# ── (7c) STATIC: the block does not depend on git history ───────────────────────────────────────────────
# The lesson this implements is deliberately LEXICAL: it must answer the same way on a tree with no history
# at all, which is also what makes it unable to leak a future commit into an answer about the present.
NOGIT="$TMP/nogit"; rm -rf "$NOGIT"; mkdir -p "$NOGIT"
( cd "$FX" && tar cf - --exclude .git . ) | ( cd "$NOGIT" && tar xf - )
"$BIN" "$NOGIT" --situ=core/widget.cc >"$TMP/nogit.txt" 2>/dev/null
NG="$( sed -n '/lexical siblings/,/^  \[2\]/p' "$TMP/nogit.txt" | awk '/^        [^ (]/ && NF == 1 && $1 !~ /=/ { print $1 }' )"
GT="$( sed -n '/lexical siblings/,/^  \[2\]/p' "$OUT" | awk '/^        [^ (]/ && NF == 1 && $1 !~ /=/ { print $1 }' )"
if [ -z "$NG" ]; then
  no "(7c) the sibling block vanished on a tree with no git history — it is not static"
elif [ "$NG" = "$GT" ]; then
  ok "(7c) the sibling block is identical with and without git history — static, so it cannot leak"
else
  no "(7c) the sibling block differs with and without git history: [$( printf '%s' "$NG" | tr '\n' ' ' )] vs [$( printf '%s' "$GT" | tr '\n' ' ' )]"
fi

# ── (7d) the MCP twin answers the same question with the same list ──────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  MCPOUT="$TMP/mcp.json"
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                 '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$FX"'","diff":"core/widget.cc"}}}' \
    | "$BIN" --mcp >"$MCPOUT" 2>/dev/null
  MROWS="$( python3 - "$MCPOUT" <<'PYEOF'
import json, sys
last = [l for l in open(sys.argv[1]) if l.strip()][-1]
r = json.loads(last)
try:
    inner = json.loads(r["result"]["content"][0]["text"])
except Exception:
    print("__NONE__"); raise SystemExit
sibs = inner.get("siblings")
if sibs is None:
    print("__MISSING__"); raise SystemExit
print(" ".join(sorted(s.get("file", "") for s in sibs)))
PYEOF
)"
  case "$MROWS" in
    __MISSING__|__NONE__) no "(7d) the MCP situational_awareness twin carries no siblings list ($MROWS)" ;;
    *core/widget.h*)      ok "(7d) the MCP twin carries the same siblings ($MROWS)" ;;
    *)                    no "(7d) the MCP twin's siblings disagree with the CLI report: $MROWS" ;;
  esac
fi

echo
if [ "$fail" -eq 0 ]; then echo "situshapecheck: ALL PASS"; else echo "situshapecheck: SOME FAILED"; fi
exit "$fail"
