#!/usr/bin/env bash
# withprofilecheck.sh — gate for --with-profile=FILE, the --lint × #PROF_TSV heat join (the SYZYGY
# advice-mode pairing: static finding shape × measured PMU weight). Asserts, on test/cachefix/ with a
# hand-written #PROF_TSV fixture:
#   1. determinism — the joined run twice is byte-identical
#   2. JOIN — the pointer-chase finding at unfriendly.cpp:38 (inside pointerChase, which opens at L31)
#      gains heat_* from the site at L33, with the fixture's exact values; the root carries heat_joined="1"
#   3. FENCE — a site OUTSIDE every finding's enclosing symbol (file head, L5) annotates NOTHING
#   4. heat_joined="0" is honest, not an error (sites only in friendly.cpp → 0 joins, exit 0)
#   5. refusals: --with-profile alone (no --lint) exits 1; a missing file exits 1; a file with no
#      #PROF_TSV sentinel pair exits 1 — "joined nothing" and "read the wrong file" never look alike
#   6. the heat legend appears ONLY when the flag is armed; bare --lint output carries no heat_*
#   7. xmllint-clean
#   8. a line column past INT_MAX joins nothing (std::atoi kept its low 32 bits and joined it); control at line 33
# Does NOT edit test/regression.sh (the orchestrator wires it).
#
#   RIPWIRE_BIN=build/ripwire bash test/withprofilecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/cachefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/cachefix dir — fixture missing"; exit 2; }

echo "withprofilecheck: BIN=$BIN  CORPUS=$CORPUS"

# The hand-written profile: one site INSIDE pointerChase (L33 — findings at/after it join), one at
# file scope (L5 — inside no symbol, must join nothing). Format = profileScope.h::print_tsv verbatim.
printf '#PROF_TSV_BEGIN\tone row per scope, aggregated across threads; counters are RAW integers\n' >  "$TMP/prof.txt"
printf 'scope\tfile\tline\tcalls\ttotal_ms\tl1d_mpki\n'                                             >> "$TMP/prof.txt"
printf 'chase walk\tunfriendly.cpp\t33\t12\t48.500\t7.250\n'                                        >> "$TMP/prof.txt"
printf 'file head\tunfriendly.cpp\t5\t1\t1.000\t0.100\n'                                            >> "$TMP/prof.txt"
printf '#PROF_TSV_END\n'                                                                            >> "$TMP/prof.txt"

# 1. determinism
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof.txt" --no-cache > "$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof.txt" --no-cache > "$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -6; }
OUT="$TMP/out1"

# 2. the join — exact row, exact values, root counter
grep -q 'rule="cache-pointer-chase-loop" p="[^"]*unfriendly.cpp:38" in="pointerChase" heat_scope="chase walk" heat_calls="12" heat_total_ms="48.500" heat_l1d_mpki="7.250"' "$OUT" \
    && ok "join: L38 chase finding carries the L33 site's measured values" || no "join row missing or wrong values"
if grep -q 'heat_joined="1"' "$OUT"; then ok 'root heat_joined="1"'; else no 'root heat_joined="1" missing'; fi

# 3. the fence — exactly ONE annotated finding in total (the L5 file-head site joined nothing)
HEATS="$( grep -o 'heat_scope="' "$OUT" | wc -l | tr -d ' ' )"
[ "$HEATS" = "1" ] && ok "fence: exactly 1 annotated finding (file-head site joined nothing)" \
    || no "fence: expected 1 heat_scope, got $HEATS"

# 4. zero joins is honest
printf '#PROF_TSV_BEGIN\thdr\nscope\tfile\tline\tcalls\ttotal_ms\nx\tfriendly.cpp\t2\t1\t1.000\n#PROF_TSV_END\n' > "$TMP/prof0.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/prof0.txt" --no-cache > "$TMP/out0" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q 'heat_joined="0"' "$TMP/out0" && ok 'zero joins → exit 0 + heat_joined="0"' \
    || no "zero-join case: rc=$rc or heat_joined=0 missing"

# 5. refusals
"$BIN" "$CORPUS" --with-profile="$TMP/prof.txt" --no-cache >/dev/null 2>"$TMP/e1"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'modifies --lint' "$TMP/e1"; then ok "flag alone refuses (exit 1, names --lint)"; else no "flag-alone: rc=$rc"; fi
"$BIN" "$CORPUS" --lint --with-profile="$TMP/absent.txt" --no-cache >/dev/null 2>"$TMP/e2"; rc=$?
if [ "$rc" -eq 1 ]; then ok "missing file refuses (exit 1)"; else no "missing file: rc=$rc"; fi
printf 'not a profile at all\n' > "$TMP/junk.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/junk.txt" --no-cache >/dev/null 2>"$TMP/e3"; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'PROF_TSV' "$TMP/e3"; then ok "sentinel-less file refuses (exit 1, names the block)"; else no "junk file: rc=$rc"; fi

# 6. the heat legend is armed-only
if grep -q 'with-profile: heat_\*' "$OUT"; then ok "heat legend present when armed"; else no "heat legend missing when armed"; fi
"$BIN" "$CORPUS" --lint --no-cache > "$TMP/plain" 2>/dev/null
grep -q 'heat_' "$TMP/plain" && no "bare --lint leaked heat_* content" || ok "bare --lint carries no heat_* (legend and attrs)"

# 8. an out-of-range line column joins nothing. 4294967329 is 2^32 + 33: through std::atoi (undefined past INT_MAX; libc
#    keeps the low 32 bits) it read as line 33 and annotated the L38 finding with a site that is not there. A line that
#    does not parse as a positive int is a row that carries nothing joinable, like a short row.
printf '#PROF_TSV_BEGIN\thdr\nscope\tfile\tline\tcalls\ttotal_ms\nwide\tunfriendly.cpp\t4294967329\t9\t9.000\n#PROF_TSV_END\n' > "$TMP/profwide.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/profwide.txt" --no-cache > "$TMP/outwide" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'heat_joined="0"' "$TMP/outwide" && ! grep -q 'heat_scope="wide"' "$TMP/outwide"; then
    ok 'an out-of-range line column (2^32+33) joins nothing: heat_joined="0"'
else
    no "an out-of-range line column joined a finding (rc=$rc, $( grep -o 'heat_joined="[0-9]*"' "$TMP/outwide" ), $( grep -c 'heat_scope="wide"' "$TMP/outwide" ) row(s) carry it)"
fi
# control: the same row with the line written in range (33) joins the L38 finding, so the arm above reads the parse
sed 's/4294967329/33/' "$TMP/profwide.txt" > "$TMP/profnarrow.txt"
"$BIN" "$CORPUS" --lint --with-profile="$TMP/profnarrow.txt" --no-cache > "$TMP/outnarrow" 2>/dev/null
if grep -q 'heat_joined="1"' "$TMP/outnarrow" && grep -q 'heat_scope="wide"' "$TMP/outnarrow"; then
    ok "control: the same row at line 33 joins (heat_joined=\"1\")"
else
    no "control: the same row at line 33 did not join — the out-of-range arm above cannot conclude"
fi

# 7. xmllint
if xmllint --noout "$OUT" 2>/dev/null; then ok "xmllint clean"; else no "xmllint reported malformed XML"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
