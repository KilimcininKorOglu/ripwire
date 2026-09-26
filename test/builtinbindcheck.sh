#!/usr/bin/env bash
# builtinbindcheck.sh — a call on a receiver of unproven type never binds to an in-repo method by a BUILTIN name alone.
#
#   test/builtinbindcheck.sh                          # uses build/ripwire on test/builtinbindfix
#   RIPWIRE_BIN=asan/ripwire test/builtinbindcheck.sh
#   test/builtinbindcheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. A member call whose receiver's type no rule proved reaches buildGraph's name ladder with its spelling as the
# only evidence, and a name with ONE in-repo definition binds to it. `d.get( k )` on a dict is such a call, and so is
# `m.get( k )` on a JS Map or `h.fetch( k )` on a Ruby Hash. On a real Python corpus one `ConnectionPool.get` collected
# 611 callers that way — 5 of them real — became the default map's first symbol, and inflated every --callers, --impact
# and --test-gate answer that reached it. Rule 3's include narrow did the same one step earlier: a caller file that
# transitively imports the class's module says nothing about whether this receiver is an instance of the class.
#
# THE FIX (graph.h BuiltinMethodGate; the tables and their generator commands are in src/externalnames.h). A call whose
# name is a method of its language's builtin map, list, set or string type, and that no qualifier, import binding or
# receiver rule resolved, keeps only the definitions its FILE gives evidence for: a method whose class (or a class in
# its inheritance cone) the file names; a free function only when the call is not a classified member access. Nothing
# kept means the call is DECLINED and counted (header declined=, declined_calls= on the callers/impact answers). The
# list decides only WHEN evidence is required — a name outside it keeps the ladder — and languages with no table keep
# the ladder whole, each for a reason graph.h records beside the gate.
#
# THE FIXTURE (test/builtinbindfix/). Per language, one in-repo method named like a builtin method, called from a file
# that names its class (the edge must SURVIVE) and from plain.* files that never do (the calls must NOT bind).
#   (A) Python true edges survive: a typed local (Rule 2), `self.pool = ConnectionPool()` then `self.pool.get()`
#       (file evidence), and an untyped parameter in a file that names a SUBCLASS (cone evidence) — exactly those three
#   (B) Python builtin calls do not bind: dict.get, a parameter's .get, os.environ.get, self.store.get — none is a
#       caller row, and all four are counted as declined_calls="4" (the RED arm on a pre-change binary)
#   (C) a nested helper `def decode( raw )` inside a method is no method: `raw.decode( "utf-8" )` elsewhere is declined,
#       while the bare call inside its enclosing method still binds
#   (D) control: a name OUTSIDE the table (`checkout`) still binds by name from the same plain file — the gate is not
#       a general receiver-type requirement
#   (M) control: Rule 3 still chooses between two admitted FREE functions — a bare `add( … )` in a file that imports
#       helpers/sums.py binds there and not to other/sums.py's namesake, as it did before the gate
#   (N) a member call can never reach a free function: `table.get`, `config.get`, `self.store.get` and
#       `os.environ.get` (rooted at an import from outside the tree) all skip the module-level `def get` in lookup.py,
#       which the pre-change binary split every one of them onto by directory locality
#   (E) JavaScript: Map.get and Array.push are declined; `new ConnectionPool()` in the file keeps its edge
#   (F) TypeScript: the named import carries a parameter annotated with the class (the extractor records no
#       per-parameter type there), while Map.get in a file that never names it is declined
#   (G) Ruby: Hash#fetch is declined; `RbPool.new` in the file keeps the edge
#   (H) stated scope: Java has no table (graph.h floor 5), so its Map.get keeps binding by name — the pin that makes a
#       change there deliberate rather than accidental
#   (I) the header: declined=9 in the stats comment, a full legend that defines hdr:declined= and names the builtin
#       clause, and a census whose dispositions sum to calls= with declined equal to the header's
#   (J) --impact counts the declines that could have reached the method and lists only the true callers
#   (K) the predicates can fail: a callers document carrying a plain.py row, and one without declined_calls=
#   (L) determinism x2 (map and census), xmllint, no degrade alert on stderr
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/builtinbindfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "builtinbindcheck: BIN=$BIN  CORPUS=$CORPUS"

cd "$CORPUS" || exit 2                               # every file:name selector below is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>/dev/null; }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
# the caller rows of a callers/impact document as sorted "file:name" lines (p= without its line number)
rows(){ grep -oE '<s [^>]*/>' "$1" | python3 -c '
import re, sys
out = set()
for line in sys.stdin:
    n = re.search( r" n=\"([^\"]*)\"", line ); p = re.search( r" p=\"([^\"]*)\"", line )
    if n and p:
        out.add( p.group( 1 ).rsplit( ":", 1 )[ 0 ] + ":" + n.group( 1 ) )
print( " ".join( sorted( out ) ) )'; }
# callers(sel, want_rows, want_declined): the exact caller set and the exact declined_calls= ("" = absent)
callers_are(){
    local sel="$1" want="$2" wantd="$3" doc="${4:-}"
    if [ -z "$doc" ]; then doc="$TMP/callers.xml"; rw --callers="$sel" >"$doc"; fi
    local R got gotd; R="$( root_tag "$doc" callers )"; got="$( rows "$doc" )"; gotd="$( attr "$R" declined_calls )"
    [ -n "$R" ] && [ "$got" = "$want" ] && [ "$gotd" = "$wantd" ]
}
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
disp_in(){ grep -m1 '^# dispositions ' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
legend_of(){ python3 - "$1" <<'PY'
import re, sys
t = open( sys.argv[1] ).read()
m = re.match( r"(\s*<!--.*?-->)+", t, re.S )
print( m.group( 0 ) if m else "" )
PY
}
conserves(){ python3 - "$1" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[1] ) )
calls = kv.pop( "calls", None )
sys.exit( 0 if calls is not None and "unaccounted" in kv and kv[ "unaccounted" ] == 0 and sum( kv.values() ) == calls else 1 )
PY
}
check(){   # label | selector | want rows | want declined_calls
    if callers_are "$2" "$3" "$4"; then ok "$1"
    else no "$1 — got rows [$( rows "$TMP/callers.xml" )] declined_calls=\"$( attr "$( root_tag "$TMP/callers.xml" callers )" declined_calls )\""; fi
}

# ── (A) + (B) Python ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (A)(B) Python: the evidenced callers stay, the builtin calls are declined and counted ==="
PYGET='py/uses_pool.py:true_field py/uses_pool.py:true_local py/uses_smart.py:via_subclass'
check "(A)+(B) --callers=py/pool.py:get is exactly the typed local, the self.pool field and the subclass-evidenced parameter; declined_calls=\"4\"" \
      py/pool.py:get "$PYGET" 4
rows "$TMP/callers.xml" | grep -q 'py/plain.py' \
    && no "(B) a plain.py call (dict/param/environ/self.store .get) is still a caller of ConnectionPool.get" \
    || ok "(B) no plain.py function is a caller of ConnectionPool.get"

# ── (C) the nested helper ─────────────────────────────────────────────────────────────────────────────────────
echo "=== (C) a nested helper is no method ==="
check "(C) --callers=py/pool.py:decode is only its enclosing render; raw.decode(\"utf-8\") is declined_calls=\"1\"" \
      py/pool.py:decode 'py/pool.py:render' 1

# ── (D) control: a name outside the table keeps the ladder ────────────────────────────────────────────────────
echo "=== (D) control: a non-builtin name still binds by name ==="
check "(D) --callers=py/pool.py:checkout keeps untyped_checkout (not a builtin name: the ladder is unchanged)" \
      py/pool.py:checkout 'py/plain.py:untyped_checkout' ''

# ── (M) (N) free functions ────────────────────────────────────────────────────────────────────────────────────
echo "=== (M)(N) free functions: Rule 3 still chooses among admitted ones; a member call reaches none ==="
check "(M) --callers=py/helpers/sums.py:add is the importing bare call (Rule 3 over the admitted free functions)" \
      py/helpers/sums.py:add 'py/uses_add.py:total' ''
check "(M) --callers=py/other/sums.py:add has no caller and no decline (the import chose its namesake)" py/other/sums.py:add '' ''
check "(N) --callers=py/lookup.py:get has no caller: the four member .get calls could have meant it and are declined_calls=\"4\"" \
      py/lookup.py:get '' 4

# ── (E) (F) (G) the other gated languages ─────────────────────────────────────────────────────────────────────
echo "=== (E)(F)(G) JavaScript, TypeScript, Ruby ==="
check "(E) --callers=js/pool.js:get is jsTrueLocal only; Map.get is declined_calls=\"1\"" js/pool.js:get 'js/uses.js:jsTrueLocal' 1
check "(E) --callers=js/pool.js:push has no caller; Array.push is declined_calls=\"1\"" js/pool.js:push '' 1
check "(F) --callers=ts/pool.ts:get keeps the import-evidenced annotated parameter; Map.get is declined_calls=\"1\"" \
      ts/pool.ts:get 'ts/uses.ts:tsAnnotated' 1
check "(G) --callers=rb/pool.rb:fetch keeps rb_true_local; Hash#fetch is declined_calls=\"1\"" rb/pool.rb:fetch 'rb/uses.rb:rb_true_local' 1

# ── (H) stated scope ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (H) stated scope: Java keeps the name ladder ==="
check "(H) --callers=java/JPool.java:get still lists javaMapGet with no declined_calls= (no Java table, graph.h floor 5)" \
      java/JPool.java:get 'java/JPlain.java:javaMapGet' ''

# ── (I) header, legend, census conservation ───────────────────────────────────────────────────────────────────
echo "=== (I) the header, its legend and the census agree ==="
"$BIN" . --no-cache --pin-census="$TMP/c.tsv" --legend=full >"$TMP/map.xml" 2>"$TMP/err" || no "(I) the map run exited non-zero"
HDR="$( stats "$TMP/map.xml" )"
[ "$( gauge "$HDR" declined )" = 9 ] && ok "(I) header declined=9 (four Python .get, one bytes .decode, JS Map.get and Array.push, TS Map.get, Ruby Hash#fetch)" \
    || no "(I) header declined= should be 9: ${HDR:-no stats comment}"
legend_of "$TMP/map.xml" | grep -q 'hdr:declined=[^>]*builtin-type-method-name' \
    && ok "(I) the full map legend defines hdr:declined= including the builtin-name clause" \
    || no "(I) the full map legend does not name the builtin-name decline under hdr:declined="
DISP="$( grep -m1 '^# dispositions ' "$TMP/c.tsv" )"
if conserves "$DISP"; then ok "(I) census dispositions sum to calls= with unaccounted=0: $DISP"
else no "(I) census does not conserve: ${DISP:-no dispositions line}"; fi
[ "$( disp_in "$TMP/c.tsv" declined )" = "$( gauge "$HDR" declined )" ] \
    && ok "(I) census declined= equals the header's" || no "(I) census declined=$( disp_in "$TMP/c.tsv" declined ) vs header $( gauge "$HDR" declined )"

# ── (J) impact ────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== (J) --impact ==="
rw --impact=py/pool.py:get >"$TMP/impact.xml"
R="$( root_tag "$TMP/impact.xml" impact )"
[ "$( rows "$TMP/impact.xml" )" = "$PYGET" ] && [ "$( attr "$R" declined_calls )" = 4 ] && [ "$( attr "$R" reaches )" = 3 ] \
    && ok "(J) --impact=py/pool.py:get reaches=\"3\" (the three true callers) with declined_calls=\"4\"" \
    || no "(J) --impact=py/pool.py:get: ${R:-no <impact> root} rows [$( rows "$TMP/impact.xml" )]"

# ── (K) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (K) mutation controls ==="
printf '<callers of="py/pool.py:get" count="4" declined_calls="4"><s t="fn" n="dict_get" p="py/plain.py:4"/><s t="fn" n="true_field" p="py/uses_pool.py:13"/><s t="fn" n="true_local" p="py/uses_pool.py:4"/><s t="fn" n="via_subclass" p="py/uses_smart.py:8"/></callers>' >"$TMP/mut1.xml"
callers_are py/pool.py:get "$PYGET" 4 "$TMP/mut1.xml" && no "(K) a callers document with a plain.py row passed the (A) predicate" \
    || ok "(K) a plain.py caller row turns the (A) predicate red"
printf '<callers of="py/pool.py:get" count="3"><s t="fn" n="true_field" p="py/uses_pool.py:13"/><s t="fn" n="true_local" p="py/uses_pool.py:4"/><s t="fn" n="via_subclass" p="py/uses_smart.py:8"/></callers>' >"$TMP/mut2.xml"
callers_are py/pool.py:get "$PYGET" 4 "$TMP/mut2.xml" && no "(K) a callers document without declined_calls= passed the (A) predicate" \
    || ok "(K) a silent drop (no declined_calls=) turns the (A) predicate red"

# ── (L) determinism, well-formedness, no alert ────────────────────────────────────────────────────────────────
echo "=== (L) determinism x2, xmllint, stderr ==="
"$BIN" . --no-cache --pin-census="$TMP/c2.tsv" --legend=full >"$TMP/map2.xml" 2>>"$TMP/err"
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(L) map and census byte-identical across two runs" \
    || no "(L) two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map.xml" "$TMP/impact.xml" 2>/dev/null; then ok "(L) xmllint: map and impact well-formed"
    else no "(L) xmllint rejected an answer"; fi
fi
if [ ! -s "$TMP/err" ]; then ok "(L) nothing on stderr"
else no "(L) stderr is not empty"; sed 's/^/          /' "$TMP/err"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
