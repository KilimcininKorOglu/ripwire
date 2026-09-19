#!/usr/bin/env bash
# expandbodyfirstcheck.sh — #289 gate: when an AMBIGUOUS --expand (>1 definition) is served in bundle mode
# (the ranked map AND the requested <bodies> both ride, chosen by chooseExpandServe/expandAutoServeScope),
# the bodies must be served BEFORE the map, not buried behind it — and the ride-along escape hatch
# (--top-k=0 for bodies alone) must be disclosed IN THE DOCUMENT, not stderr-only, so a caller reading only
# stdout (the common case for a tool-calling agent) can see both the answer and the way to skip the map on
# the next call.
#
# THIS DOES NOT TOUCH test/expandtopk0check.sh's locked contract, arm (B): an ambiguous name still gets the
# caller's ORDINARY default (the ranked map rides along, no topk_default="0", the stderr note still fires).
# Only the ORDER the map/bodies are served in, and the VISIBILITY of the pre-existing escape hatch, change.
#
# Fixtures: test/expandtopk0fix/dupA.c + dupB.c — the SAME two-definition dupTarget fixture
# test/expandtopk0check.sh (B) uses, forced into bundle mode with --pack-budget-bytes=10 exactly like that
# gate's own sanity arm (both tiny files together are well over 10 bytes, so chooseExpandServe
# deterministically picks mode="bundle" regardless of this fixture's absolute byte counts on this machine).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/expandbodyfirstcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/expandtopk0fix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/expandtopk0fix directory"; exit 2; }
cd "$ROOT"
echo "expandbodyfirstcheck: BIN=$BIN  FIX=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

"$BIN" "$FIX" --expand=dupTarget --pack-budget-bytes=10 --no-cache >"$TMP/dup.xml" 2>"$TMP/dup.err"

# ── sanity: the fixture really landed in bundle mode (map+bodies both ride) — otherwise every arm below
#    proves nothing (identical to expandtopk0check.sh (B)'s own sanity arm, same fixture, same forcing flag).
grep -q 'mode="bundle"' "$TMP/dup.xml" \
    && ok "(A) sanity: the ambiguous probe landed in bundle mode (map+bodies both ride)" \
    || no "(A) sanity failed: --pack-budget-bytes=10 did not force bundle mode — arm proves nothing"

# ── (B) THE CORE FIX: <bodies> starts before the ranked map's <r ...>, or no map rides at all. ───────────
bodiesOff="$( grep -bo '<bodies' "$TMP/dup.xml" | head -1 | cut -d: -f1 )"
mapOff="$(    grep -bo '<r '     "$TMP/dup.xml" | head -1 | cut -d: -f1 )"
if [ -z "$bodiesOff" ]; then
    no "(B) no <bodies> tag at all — the requested body is missing"
elif [ -z "$mapOff" ]; then
    ok "(B) <bodies> present and no ranked map rides along (nothing to order against)"
elif [ "$bodiesOff" -lt "$mapOff" ]; then
    ok "(B) <bodies> (byte $bodiesOff) starts BEFORE the ranked map (byte $mapOff)"
else
    no "(B) <bodies> (byte $bodiesOff) starts AFTER the ranked map (byte $mapOff) — the body is buried behind the map"
fi

# ── (C) exactly ONE <bodies> tag — guards the early/late reorder switch (bodiesEmittedEarly) against ever
#        double-emitting the section it moved. Minified XML is one line, so this counts OCCURRENCES, not
#        matching lines (`grep -c` would undercount on a single-line document).
bodiesTagCount="$( grep -o '<bodies ' "$TMP/dup.xml" | wc -l | tr -d ' ' )"
[ "$bodiesTagCount" = 1 ] \
    && ok "(C) exactly one <bodies> tag (no double-emission from the early/late reorder guard)" \
    || no "(C) <bodies> tag appears $bodiesTagCount times — expected exactly 1"

# ── (D) document size is bounded — this tiny 2-file, 2-symbol fixture's complete bundle (map + both bodies)
#        is a few KB at most; a regression that re-renders or duplicates a section would blow well past this.
docBytes="$( wc -c < "$TMP/dup.xml" | tr -d ' ' )"
if [ "$docBytes" -gt 0 ] && [ "$docBytes" -lt 8192 ]; then
    ok "(D) document size is bounded ($docBytes B)"
else
    no "(D) document size $docBytes B is unbounded/unexpected for this tiny fixture"
fi

# ── (E) the ride-along escape hatch is disclosed IN-BAND — a `note=` attribute on <ctx>, not stderr-only.
grep -q 'note="the ranked top-' "$TMP/dup.xml" \
    && ok "(E) the ride-along escape hatch is disclosed IN-BAND (note= attribute on <ctx>)" \
    || no "(E) no in-band note= disclosure — the escape hatch is stderr-only"

# ── (F) the pre-existing stderr note still fires too (kept for a human tailing the terminal). ─────────────
grep -qi 'rides along' "$TMP/dup.err" \
    && ok "(F) the pre-existing stderr ride-along note still fires" \
    || no "(F) stderr ride-along note regressed"

# ── (G) expandtopk0check.sh (B)'s locked contract is untouched: an ambiguous name still gets NO
#        topk_default="0" — only the order/visibility changed, not the "map still rides" decision.
if grep -q 'topk_default="0"' "$TMP/dup.xml"; then
    no "(G) ambiguous --expand wrongly got the exact-name topk_default=\"0\" default (breaks expandtopk0check.sh (B))"
else
    ok "(G) ambiguous --expand still carries NO topk_default= — expandtopk0check.sh (B)'s contract is untouched"
fi

# ── (H) well-formed XML (the reorder + the new attribute must not break the document). ─────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/dup.xml" 2>"$TMP/xmllint.err"; then
        ok "(H) document is well-formed XML (xmllint --noout)"
    else
        no "(H) xmllint --noout failed: $( cat "$TMP/xmllint.err" )"
    fi
else
    echo "  SKIP  (H) xmllint not on PATH"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAIL"
fi
exit "$fail"
