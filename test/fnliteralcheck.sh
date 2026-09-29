#!/usr/bin/env bash
# fnliteralcheck.sh — a name bound to a FUNCTION LITERAL owns that literal's body, in every language whose
# tags.scm captures the binding as a definition (JS, TS, Lua, Python).
#
# The defect (0.6.5): the @definition node of `const f = (x) => {…}` is the lexical_declaration, of
# `M.f = function(x) … end` the assignment_statement, of a class-body `f = lambda self, x: g(x)` the
# assignment — none of which owns a `body:` field. So bodyByte stayed 0, sigEndByte == endByte, and
# `--callees=f` answered bodyless_defs="1" for a function with a body: a FALSE claim, and every verb that
# skips bodyless symbols (quality panel, clones, naming, hotspots, biggest-first) silently skipped them.
#
# The fix (src/ingest_relations.h, kFnLiteralBinding + defBodyNodeOf): when the def node has no body, walk
# from the @name up to the def node looking for a value-carrying field (value:/right:, or the first value
# of a positional expression_list) whose value — through cast/paren wrappers — is a function literal, and
# adopt THAT literal's body. Metrics (params, cx, nest) read from the literal, not the declaration.
#
# Fixture (test/fnliteralfix/): arrows.ts, arrows.js, mod.lua, cls.py — each row's comment in the source
# says what it pins. Every expected value is counted by hand from the fixture.
#
# Usage:
#   test/fnliteralcheck.sh [BIN]
#   RIPWIRE_BIN=asan/ripwire test/fnliteralcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fnliteralfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fnliteralfix directory"; exit 2; }
echo "fnliteralcheck: BIN=$BIN  FIX=$FIX"

# ---- 1. every literal-bound name is ONE definition WITH a body ------------------------------------------
echo "=== 1. --callees: literal-bound names are bodied definitions (bodyless_defs absent) ==="
header(){ ( cd "$FIX" && "$BIN" . --callees="$1" --no-cache --legend=compact 2>/dev/null ) | grep -oE '<callees [^>]*>' | head -1; }
for name in blockArrow conciseArrow bareParam fnExprConst exportedArrow castArrow satisfiesArrow firstOfTwo secondOfTwo handle \
            jsArrow jsConcise jsLegacyVar onPair jsField jsExported \
            luaAssigned luaLocal luaField luaField2 \
            py_lambda; do
    h="$( header "$name" )"
    if [ -z "$h" ]; then no "$name: no <callees> header"; continue; fi
    if ! printf '%s' "$h" | grep -q ' defs="1"'; then no "$name: expected defs=1 — got: $h"; continue; fi
    if printf '%s' "$h" | grep -q ' bodyless_defs='; then no "$name: still claims a bodyless def — $h"; else ok "$name: defs=1, bodied"; fi
    # every fixture binding calls its sink exactly once — the body's call must attribute to THIS symbol
    if printf '%s' "$h" | grep -q ' count="1"'; then ok "$name: its one call is its own (count=1)"; else no "$name: expected count=1 — got: $h"; fi
done

# ---- 2. real bodyless declarations stay bodyless ----------------------------------------------------------
echo "=== 2. declarations without a body stay bodyless ==="
h="$( header declaredOnly )"
printf '%s' "$h" | grep -q ' defs="1".* bodyless_defs="1"' && ok "declaredOnly: bodyless_defs=1" || no "declaredOnly: expected bodyless — got: $h"
h="$( header overloaded )"
printf '%s' "$h" | grep -q ' defs="3".* bodyless_defs="2"' && ok "overloaded: 2 signatures bodyless, 1 bodied" || no "overloaded: expected defs=3 bodyless_defs=2 — got: $h"
# `declare const f: (x) => void;` binds a TYPE, not a literal: it is not a function definition at all (the
# tags query needs a value:), so --callees refuses it — never a bodied def.
if ( cd "$FIX" && "$BIN" . --callees=declaredConst --no-cache --legend=compact 2>&1 >/dev/null ) | grep -q 'symbol not found: declaredConst'; then
    ok "declaredConst: not a function definition"
else
    no "declaredConst: became a definition — $( header declaredConst )"
fi

# ---- 3. metrics read from the literal ---------------------------------------------------------------------
echo "=== 3. --metrics: params / cx / nest / loc read from the literal ==="
( cd "$FIX" && "$BIN" . --metrics --no-cache --legend=compact 2>/dev/null ) | sed 's/></>\n</g' >"$TMP/m"
row(){ grep -E "<s t=\"[^\"]*\" n=\"$1\"" "$TMP/m" | head -1; }
attr(){ # name attr val why
    local r; r="$( row "$1" )"
    if [ -z "$r" ]; then no "$1: metrics row missing"; return; fi
    if printf '%s' "$r" | grep -q " $2=\"$3\""; then ok "$1: $2=$3 ($4)"; else no "$1: expected $2=$3 ($4) — got: $r"; fi
}
attr castArrow   params 1 "the arrow's one param, not the inline type annotation's three"
attr secondOfTwo params 2 "its own arrow, not the first declarator's"
attr firstOfTwo  loc    1 "its own declarator line, not the two-line declaration"
attr secondOfTwo loc    1 "its own declarator line, not the two-line declaration"
attr luaField    loc    1 "its own table field, not the whole four-line table"
attr blockArrow  params 2 "block-bodied arrow"
attr bareParam   params 1 "x => …: a lone parameter without a list"
attr blockArrow  cx     2 "one if"
attr luaAssigned params 2 "M.f = function(x, y)"
attr luaAssigned cx     2 "one if"
attr luaField2   params 2 "table-field literal"
attr py_lambda   params 2 "lambda self, x"
attr py_lambda   cx     1 "the lambda, read from the lambda"
# py_lambda's nest is deliberately NOT pinned: cc_isNestingOnly matches kind "lambda", which is ALSO the anonymous
# keyword token inside every Python lambda node, so any function containing a lambda reads one level too deep.
# That is a Python-wide metric defect (every function with a lambda moves), separate from this binding fix.

# ---- 4. a callback passed as an argument never becomes a definition ---------------------------------------
echo "=== 4. anonymous callbacks are not definitions ==="
n="$( grep -c '<s t=' "$TMP/m" )"
[ "$n" = "37" ] && ok "symbol rows = 37 (no anonymous callback minted a def)" || no "expected 37 symbol rows — got $n"
if grep -qE '<s t="[^"]*" n=""' "$TMP/m"; then no "an unnamed symbol row appeared"; else ok "no unnamed symbol rows"; fi

# ---- 5. determinism ---------------------------------------------------------------------------------------
( cd "$FIX" && "$BIN" . --no-cache >"$TMP/a" 2>/dev/null; "$BIN" . --no-cache >"$TMP/b" 2>/dev/null )
diff -q "$TMP/a" "$TMP/b" >/dev/null && ok "default map byte-identical run-to-run" || no "non-deterministic default map"

echo
if [ "$fail" = 0 ]; then echo "fnliteralcheck: ALL PASS"; else echo "fnliteralcheck: FAIL"; fi
exit "$fail"
