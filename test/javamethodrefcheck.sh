#!/usr/bin/env bash
# javamethodrefcheck.sh — recall + precision gate for issue #74.
#
# The pinned grammar gives a simple type and a variable the same receiver node,
# so the resolver must prove the receiver is a repository type before minting a call.
#
# Maintainer (joyful-ii-V-I, 2026-09-10 on #74): land the two-method contrast as a
# test/*check.sh that is RED first, asserting that the lambda form and the reference
# form yield the *same* caller set — not just a bigger number.
#
# Fixture is the issue's pair, verbatim:
#   lambda:           item -> Util.conv(item)     inside lambdaForm
#   method reference: Util::conv                  inside methodRefForm
#
# WHAT THIS GATE ASSERTS (and what it refuses to assert):
#   - the caller SET of conv is exactly {lambdaForm, methodRefForm}
#   - NOT "count went from 1 to 2" (a count-only arm stays green if a third
#     unrelated caller appears, or if both names vanish and something else
#     fills the quota)
#   - lambdaForm is present first, so an empty extraction cannot read as
#     "same set" (CONTRIBUTING.md §2 shape 3: empty equals agreement)
#   - both spellings are still WRITTEN in the fixture source (V5 presence
#     guard: deleting the method-ref line would otherwise satisfy an absence)
#
# MUTATION (CONTRIBUTING.md §2 rule 1–2): rewrite Util::conv → Util::convX in
# a scratch copy, assert the rewrite took, then re-extract --callers=conv.
# The caller set MUST change. On unmodified main it does not — the method-ref
# site was never an edge — so this arm is RED for the same hole, not green
# by vacuity.
#
# Registration owed on a real commit: add javamethodrefcheck to the alphabetical
# `for _g in` list in test/regression.sh (after javarubycheck). test/manifestcheck.sh
# fails a committed top-level *check.sh that is missing from that list. Re-derive
# the published gate count from the loop (docs/gatecount_build.py), never carry it.
#
# Usage:  RIPWIRE_BIN=/path/to/ripwire bash test/javamethodrefcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/javamethodreffix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
[ -f "$FIX/A.java" ] && [ -f "$FIX/Widget.java" ] && [ -f "$FIX/Outer.java" ] \
    || { echo "fixture files missing under $FIX"; exit 2; }

echo "javamethodrefcheck: BIN=$BIN  FIX=$FIX"

# ── fixture presence (source text, never tool output) ─────────────────────────
for spelling in \
    'item -> Widget.makeFn(item)' 'Widget::makeFn' 'Outer.Inner::makeFn' \
    'Widget::<Object>makeFn' 'widget::instanceFn' 'widget::makeFn' 'Widget::instanceFn' \
    'this::thisFn' 'this::makeFn' 'super::superFn' 'super::makeFn' 'Widget::new' \
    'Widget::localShadowFn' 'Widget::fieldShadowFn'; do
    grep -qF "$spelling" "$FIX/A.java" \
        && ok "fixture still spells $spelling" \
        || no "fixture no longer spells $spelling — the matrix is vacuous"
done

# ── extract caller / use-site sets ────────────────────────────────────────────
# JSON --callers: one name per callers[].n. SET comparison, never a count.
callers_set() {
    "$BIN" "$1" --no-cache --callers="$2" --json 2>/dev/null \
        | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    obj = json.loads(raw)
except Exception:
    sys.exit(2)
names = sorted({ row.get("n","") for row in obj.get("callers", []) if row.get("n") })
print(" ".join(names))
'
}

# --uses in_id values for role=call sites of conv (default XML).
uses_in_ids() {
    "$BIN" "$1" --no-cache --uses=conv 2>/dev/null \
        | python3 -c '
import re, sys
xml = sys.stdin.read()
ids = sorted(set(re.findall(r"in_id=\"([^\"]+)\"", xml)))
print(" ".join(ids))
'
}

expect_callers() {
    local symbol="$1" expected="$2" got
    got="$(callers_set "$FIX" "$symbol")" || got=""
    echo "callers_set($symbol) = [$got]"
    [ "$got" = "$expected" ] \
        && ok "$symbol caller set is exactly [$expected]" \
        || no "$symbol caller set expected [$expected], got [$got]"
}

# Recall: lambda and each statically typed method-reference form reach makeFn;
# same-name expression/this/super controls below must not enlarge this set.
expect_callers makeFn "genericTypeMethod lambdaForm nestedTypeMethod typeMethod"

# Precision: expression receivers and constructors mint no ordinary call edge.
expect_callers instanceFn ""
expect_callers thisFn ""
expect_callers superFn ""
expect_callers Widget ""

# The receiver identifier itself is not the call target.
expect_callers widget ""

# Shadowing negatives: a parameter, local, or field named like the type is a
# value receiver. The grammar cannot tell, so the resolver must refuse.
expect_callers localShadowFn ""
expect_callers fieldShadowFn ""

# ── mutation: rewrite the method-ref spelling; the caller set MUST move ───────
MUT="$TMP/mut"
mkdir -p "$MUT"
cp "$FIX/Widget.java" "$MUT/Widget.java"
cp "$FIX/Outer.java" "$MUT/Outer.java"
cp "$FIX/Util.java" "$MUT/Util.java"
# leave the lambda site intact; only the Type::method spelling changes
sed 's/Widget::makeFn/Widget::missingFn/' "$FIX/A.java" >"$MUT/A.java"
grep -qF 'map(Widget::missingFn)' "$MUT/A.java" && ! grep -qF 'map(Widget::makeFn)' "$MUT/A.java" \
    && ok "mutation took: Widget::makeFn -> Widget::missingFn (lambda site untouched)" \
    || no "mutation did not take — refusing to trust the post-mutation extraction"
grep -qF 'item -> Widget.makeFn(item)' "$MUT/A.java" \
    && ok "mutation left the lambda spelling intact" \
    || no "mutation accidentally rewrote the lambda site"

S1="$( callers_set "$MUT" makeFn )" || S1=""
echo "callers_set(makeFn) after mutation = [${S1}]"

[ "$S1" = "genericTypeMethod lambdaForm nestedTypeMethod" ] \
    && ok "mutating Widget::makeFn removes only typeMethod" \
    || no "mutation expected [genericTypeMethod lambdaForm nestedTypeMethod], got [$S1]"

# ── determinism on the unmodified fixture ─────────────────────────────────────
A="$( "$BIN" "$FIX" --no-cache --callers=makeFn --json 2>/dev/null || true )"
B="$( "$BIN" "$FIX" --no-cache --callers=makeFn --json 2>/dev/null || true )"
[ -n "$A" ] && [ "$A" = "$B" ] \
    && ok "determinism: --callers=makeFn --json byte-identical across two runs" \
    || no "determinism: --callers=makeFn --json differed or was empty"

if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$FIX" --no-cache --uses=makeFn 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed: --uses=makeFn" \
        || no "xml malformed: --uses=makeFn"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
