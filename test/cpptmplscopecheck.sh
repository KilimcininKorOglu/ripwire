#!/usr/bin/env bash
# cpptmplscopecheck.sh — gate: a C++ member of a class TEMPLATE keys ONE identity, the one its non-template twin
# keys, with no template-argument list anywhere in its scope.
#
# THE DEFECT (observed 2026-09-16 while fixing the --pin-census field escape). An out-of-line member definition of
# a class template kept the scope's template-argument list: `template <class T> void Box<T>::grow() {}` minted
# `<s t="method" n="grow" sc="Box&lt;T&gt;">` beside the in-class declaration's `sc="Box"`. One member became two
# identities, so `--callers=Box::grow` resolved the selector to the DECLARATION and answered `count="0"` while
# `use( Box<int>& b ) { b.grow(); }` sat in plain sight — the edge landed on the `Box<T>::grow` row no selector
# names. The same raw text reached every consumer of the id: the S6-C locality tie-break compared `Box<T>::` with
# `Box::` segment by segment, the census printed `SmallVec<T, Alloc, SizeType,<LF> GrowingPolicy, N>::grow` with
# the line break in the id, and a scope whose arguments themselves hold `::` was cut INSIDE the list
# (`template<> void Slot<std::string>::clear()` scoped as `string>`).
#
# The reference side had the twin defect at two segments: a static call `Factory<int>::make()` carried the
# qualifier `Factory<int>`, which keys no canonical entry, so the call fell to the bare-name tier and SPLIT onto an
# unrelated `Decoy::make` — a caller published for a function nobody called. (At three or more segments the
# §H4 re-split already stripped the arguments, which is why `a::b::Box<int>::get` in cppqualcheck was never red.)
#
# THE SPECIALIZATION DECISION, deliberately: an explicit or partial specialization's member keys the PRIMARY
# template's identity. `template<> void Box<int>::grow()`, `template<class T> void Slot<T*>::clear()` and the
# members declared inside `template<> struct Slot<bool> { … }` are all `Slot::clear` / `Box::grow`. Why:
#   * identity here is what a caller can WRITE and a call site can NAME. The resolver is name-based and does no
#     template-argument deduction, so it can never route `b.grow()` on a `Box<int>` to a `Box<int>` identity; a
#     scope carrying arguments is one no call edge and no selector can reach (measured on the pre-fix binary:
#     every such row had --callers count=0);
#   * the spelling is not canonical — `Box<T>` / `Box<U>` / `Box<T, A>` / a list broken over lines are one class,
#     so keeping any of it splits one entity by formatting;
#   * a specialization body joins the member exactly the way an overload does: several bodies under one name,
#     each keeping its own row and line, callers the UNION (which is what counts_floor already promises). The
#     alternative hides the specialization from --callers/--impact/--uses entirely, which is the worse lie;
#   * precedent in this tree: Rust's `impl<T> Foo<T>` already scopes to `Foo`, and the C++ 3-segment reference
#     re-split already strips (`numeric_limits<std::size_t>::max` keys `numeric_limits`).
#
# THREE CORPORA, generated below into a scratch dir (never committed under test/, where the live-tree gates would
# index them: the repo already has a `grow` with callers, and a fixture def beside it would move the live graph):
#   plain/  the CONTROL — the non-template twin, the join the codebase already makes (decl + out-of-line def = one
#           row, overloads="2"; --callers=Box::grow defs="2" count="1" use).
#   templ/  the SAME file with the template added — line-aligned (the `template <class T>` prefix shares the line),
#           so the ONE difference is templateness; every answer must be byte-identical to plain/'s. `plain` and
#           `templ` are the same length on purpose: root="…" rides in the bytes.
#   shape/  every other spelling, each with its own names so arms cannot lean on each other: a multi-line
#           argument list, a nested-namespace chain, a C++17 nested namespace, a template inside a template, an
#           out-of-line nested class of a template, the three specialization forms (one with `::` inside its
#           arguments), and the two-segment static call with a same-name decoy.
#
# EVERY expected value below is a LITERAL read by hand off the fixture text, never derived the way the code does.
#
# RED-FIRST (2026-09-16, main b1489df4, plain build): 27 of 36 checks FAIL. The 9 that pass are the §1 control,
# the presence guards, determinism, and two arms green on both binaries by construction (--callers=Leaf::shed, whose
# selector already matched `Tree<T>::Leaf` by suffix; the seven-clear-definitions count). The failures, by section —
#   §2 templ/ --callers=Box::grow defs="1" count="0" (control defs="2" count="1"); the map keeps a separate
#      sc="Box&lt;T&gt;" row; --impact reaches="0", --uses defs="1"; census target box.hpp::Box<T>::grow
#   §3 11 sc= values carry template text, one of them with &#10;; census ids split across lines; --callers count="0"
#      for reserveMore, fill, stack, link
#   §4 slot.hpp scopes Slot<T> / string> / Slot<T*> / Slot<bool>; --callers=Slot::clear defs="1" count="0"
#   §5 --callers=Decoy::make count="1" (the false caller build), --callers=Factory::make count="0", build amb="1",
#      census mech=split
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/cpptmplscopecheck.sh   |   bash test/cpptmplscopecheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

echo "cpptmplscopecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plain" "$TMP/templ" "$TMP/shape" || { echo "could not create the scratch corpora under $TMP"; exit 2; }
cd "$TMP"

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE ' count="[0-9]+"' | head -1 | tr -dc 0-9; }
defs(){ printf '%s' "$1" | grep -oE ' defs="[0-9]+"' | head -1 | tr -dc 0-9; }
el(){ printf '%s' "$1" | grep -oE '<(callers|callees|uses|impact) .*' | head -1; }   # the answer, without the legend
noroot(){ sed -e 's/ root="[^"]*"//g'; }

# ── the corpora ─────────────────────────────────────────────────────────────────────────────────────────────────
cat > plain/box.hpp <<'EOF'
struct Box
{
    void grow();
};
void Box::grow()
{
}
void use( Box& b )
{
    b.grow();
}
EOF
cat > templ/box.hpp <<'EOF'
template <class T> struct Box
{
    void grow();
};
template <class T> void Box<T>::grow()
{
}
void use( Box<int>& b )
{
    b.grow();
}
EOF

# multi-line argument list — the census report's own shape
cat > shape/smallvec.hpp <<'EOF'
template <class T, class Alloc, class SizeType, class GrowingPolicy, int N>
struct SmallVec
{
    void reserveMore();
};
template <class T, class Alloc, class SizeType,
          class GrowingPolicy, int N>
void SmallVec<T, Alloc, SizeType,
              GrowingPolicy, N>::reserveMore()
{
}
void useVec( SmallVec<int, int, int, int, 4>& v )
{
    v.reserveMore();
}
EOF

# namespaces, a template inside a template, and an out-of-line nested class of a template
cat > shape/nested.hpp <<'EOF'
namespace outer
{
namespace inner
{
template <class T>
struct Cell
{
    void fill();
};
}
}
template <class T>
void outer::inner::Cell<T>::fill()
{
}
namespace outer::inner
{
template <class T>
struct Tray
{
    void stack();
};
template <class T>
void Tray<T>::stack()
{
}
}
template <class T>
struct Tree
{
    template <class U>
    struct Node
    {
        void link();
    };
    struct Leaf;
};
template <class T>
template <class U>
void Tree<T>::Node<U>::link()
{
}
template <class T>
struct Tree<T>::Leaf
{
    void shed();
};
void useNested( outer::inner::Cell<int>& c, outer::inner::Tray<int>& t, Tree<int>::Node<long>& n, Tree<int>::Leaf& l )
{
    c.fill();
    t.stack();
    n.link();
    l.shed();
}
EOF

# the specialization forms — explicit member (with `::` INSIDE its argument list), partial class, explicit class
cat > shape/slot.hpp <<'EOF'
template <class T>
struct Slot
{
    void clear();
};
template <class T>
void Slot<T>::clear()
{
}
template <>
void Slot<std::string>::clear()
{
}
template <class T>
struct Slot<T*>
{
    void clear();
};
template <class T>
void Slot<T*>::clear()
{
}
template <>
struct Slot<bool>
{
    void clear();
};
void Slot<bool>::clear()
{
}
void useSlot( Slot<int>& a, Slot<int*>& b )
{
    a.clear();
    b.clear();
}
EOF

# the two-segment static call, with a same-final-name decoy in another class
cat > shape/statics.hpp <<'EOF'
template <class T>
struct Factory
{
    static Factory make();
};
template <class T>
Factory<T> Factory<T>::make()
{
    return {};
}
struct Decoy
{
    static Decoy make();
};
Decoy Decoy::make()
{
    return {};
}
void build()
{
    Factory<int>::make();
}
EOF

# ── §1 THE CONTROL: how the codebase already joins a NON-template out-of-line member ────────────────────────────
PMAP="$( run plain --no-cache --legend=compact )"
PCALL="$( run plain --callers=Box::grow --no-cache --legend=compact )"
[ "$( printf '%s' "$PMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | sed 's/ k="[^"]*"//' )" = '<s t="method" n="grow" sc="Box" overloads="2">' ] \
    && ok "control: declaration + out-of-line definition are ONE map row, sc=\"Box\" overloads=\"2\"" \
    || no "control map row moved — the join this gate mirrors is not what it was: $( printf '%s' "$PMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | tr '\n' ' ' )"
{ [ "$( defs "$PCALL" )" = 2 ] && [ "$( cnt "$PCALL" )" = 1 ] && printf '%s' "$PCALL" | grep -q '<s t="fn" n="use" p="box.hpp:8"/>'; } \
    && ok "control: --callers=Box::grow defs=\"2\" count=\"1\" -> use (box.hpp:8)" \
    || no "control: --callers=Box::grow expected defs=2 count=1 use, got: $( el "$PCALL" )"

# ── §2 THE CONTRAST: the template twin answers byte-identically ─────────────────────────────────────────────────
TMAP="$( run templ --no-cache --legend=compact )"
TCALL="$( run templ --callers=Box::grow --no-cache --legend=compact )"
{ [ "$( defs "$TCALL" )" = 2 ] && [ "$( cnt "$TCALL" )" = 1 ] && printf '%s' "$TCALL" | grep -q '<s t="fn" n="use" p="box.hpp:8"/>'; } \
    && ok "templ: --callers=Box::grow defs=\"2\" count=\"1\" -> use — the definition and the declaration are one member" \
    || no "templ: --callers=Box::grow expected defs=2 count=1 use (the control's answer), got: $( el "$TCALL" )"
[ "$( printf '%s' "$TMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | sed 's/ k="[^"]*"//' )" = '<s t="method" n="grow" sc="Box" overloads="2">' ] \
    && ok "templ: ONE map row sc=\"Box\" overloads=\"2\", as the control" \
    || no "templ: the member is still split across rows: $( printf '%s' "$TMAP" | grep -oE '<s t="method" n="grow"[^>]*>' | tr '\n' ' ' )"
[ "$( printf '%s' "$TMAP" | noroot )" = "$( printf '%s' "$PMAP" | noroot )" ] \
    && ok "templ: the whole map is byte-identical to the control's (root= aside)" \
    || no "templ: map differs from the control's: $( diff <( printf '%s' "$PMAP" | noroot | sed 's/<s /\n<s /g' ) <( printf '%s' "$TMAP" | noroot | sed 's/<s /\n<s /g' ) | grep '^[<>]' | tr '\n' ' ' )"
# Each verb's presence guard reads the attribute that verb actually answers with: --callers count=, --impact
# reaches=, --uses defs=. --uses reads defs= and not count= because a `::` selector's count= on --uses is 0 on the
# CONTROL too — a separate selector defect with its own lane (fix/uses-qualified-selector) — so a count= guard
# would declare the arm vacuous for a reason this gate is not about, while defs= is exactly the join (1 vs 2).
for pair in callers:count impact:reaches uses:defs; do
    verb="${pair%%:*}"; attr="${pair#*:}"
    P="$( run plain "--$verb=Box::grow" --no-cache --legend=compact | noroot )"
    T="$( run templ "--$verb=Box::grow" --no-cache --legend=compact | noroot )"
    got="$( printf '%s' "$P" | grep -oE " $attr=\"[0-9]+\"" | head -1 | tr -dc 0-9 )"
    # presence guard: two empty answers agree about nothing (CONTRIBUTING §2 shape 3)
    if [ -z "$got" ] || [ "$got" = 0 ]; then
        no "control --$verb=Box::grow answered $attr='$got' — the contrast below would be vacuous"
        continue
    fi
    [ "$T" = "$P" ] \
        && ok "templ: --$verb=Box::grow byte-identical to the control ($attr=\"$got\")" \
        || no "templ: --$verb=Box::grow differs from the control — control: $( el "$P" ) — templ: $( el "$T" )"
done
run plain --pin-census="$TMP/plain.tsv" --no-cache >/dev/null
run templ --pin-census="$TMP/templ.tsv" --no-cache >/dev/null
PC="$( grep -E $'^(C|S)\t' "$TMP/plain.tsv" 2>/dev/null )"
TC="$( grep -E $'^(C|S)\t' "$TMP/templ.tsv" 2>/dev/null )"
printf '%s\n' "$PC" | grep -qE $'^C\t[a-z-]+\t.*\tbox\\.hpp::use#[0-9]+\tgrow\tbox\\.hpp::Box::grow#[0-9]+\t10$' \
    && ok "control census: use -> box.hpp::Box::grow at line 10" \
    || no "control census row for use -> grow missing: $( printf '%s' "$PC" | tr '\n\t' '| ' )"
[ -n "$PC" ] && [ "$TC" = "$PC" ] \
    && ok "templ census: every C and S row identical to the control's (the S6-C id space is the same)" \
    || no "templ census differs — control: $( printf '%s' "$PC" | tr '\n\t' '| ' ) — templ: $( printf '%s' "$TC" | tr '\n\t' '| ' )"

# ── §3 NO TEMPLATE ARGUMENTS IN ANY SCOPE, over every other spelling ────────────────────────────────────────────
SMAP="$( run shape --no-cache --legend=compact )"
run shape --pin-census="$TMP/shape.tsv" --no-cache >/dev/null
SC_ALL="$( printf '%s' "$SMAP" | grep -oE ' sc="[^"]*"' )"
# 17 by hand once joined: smallvec 2 (SmallVec, reserveMore) + nested 9 (Cell fill Tray stack Tree Node link Leaf shed)
# + slot 2 (Slot, clear) + statics 4 (Factory, Factory::make, Decoy, Decoy::make). The split pre-fix map has more rows.
[ "$( printf '%s\n' "$SC_ALL" | grep -c . )" -ge 17 ] \
    && ok "presence: the shape map carries $( printf '%s\n' "$SC_ALL" | grep -c . ) sc= attributes (>= 17) — the sweep below has a population" \
    || no "presence: the shape map carries only $( printf '%s\n' "$SC_ALL" | grep -c . ) sc= attributes — the no-arguments sweep would be vacuous"
BAD="$( printf '%s\n' "$SC_ALL" | grep -E '&lt;|&gt;|&#10;|&#13;' )"
[ -z "$BAD" ] \
    && ok "no sc= value holds a template-argument list or a line break" \
    || no "$( printf '%s\n' "$BAD" | grep -c . ) sc= values still carry template text: $( printf '%s' "$BAD" | tr '\n' ' ' )"
[ -s "$TMP/shape.tsv" ] \
    && ok "presence: the shape census wrote rows" \
    || no "the shape census wrote nothing — the two census arms below would be vacuous"
[ "$( grep -v '^#' "$TMP/shape.tsv" | grep -c '<' )" = 0 ] \
    && ok "no census id holds a template-argument list" \
    || no "census ids still carry template text: $( grep -v '^#' "$TMP/shape.tsv" | grep '<' | tr '\n\t' '| ' )"
[ "$( grep -v '^#' "$TMP/shape.tsv" | grep -cvE $'^(C|S|O)\t' )" = 0 ] \
    && ok "every census data line is a whole C/S row — no id broke across lines" \
    || no "census lines that are not whole rows (an id split by a line break): $( grep -v '^#' "$TMP/shape.tsv" | grep -vE $'^(C|S|O)\t' | tr '\n\t' '| ' )"

row(){ printf '%s' "$SMAP" | grep -oE "<s t=\"$1\" n=\"$2\"[^>]*>" | sed 's/ k="[^"]*"//'; }
expect_row(){   # $1 kind  $2 name  $3 exact tag (k= stripped)  $4 prose
    [ "$( row "$1" "$2" )" = "$3" ] \
        && ok "$4: $3" \
        || no "$4 — expected $3, got: $( row "$1" "$2" | tr '\n' ' ' )"
}
expect_callers(){   # $1 selector  $2 defs  $3 caller name  $4 prose
    local out; out="$( run shape "--callers=$1" --no-cache --legend=compact )"
    { [ "$( defs "$out" )" = "$2" ] && [ "$( cnt "$out" )" = 1 ] && printf '%s' "$out" | grep -q "<s t=\"fn\" n=\"$3\""; } \
        && ok "--callers=$1 defs=\"$2\" count=\"1\" -> $3 — $4" \
        || no "--callers=$1 expected defs=$2 count=1 $3 — $4 — got: $( el "$out" )"
}

expect_row     method reserveMore '<s t="method" n="reserveMore" sc="SmallVec" overloads="2">' "multi-line argument list joins its declaration"
expect_callers SmallVec::reserveMore 2 useVec "the list broken over two lines, both in the declarator and in the header"
expect_row     method fill  '<s t="method" n="fill" sc="Cell" overloads="2">'  "outer::inner::Cell<T>::fill (2+ segment declarator) joins"
expect_callers Cell::fill   2 useNested "nested-namespace chain"
expect_row     method stack '<s t="method" n="stack" sc="Tray" overloads="2">' "Tray<T>::stack inside a C++17 nested namespace joins"
expect_callers Tray::stack  2 useNested "C++17 nested namespace"
expect_row     method link  '<s t="method" n="link" sc="Node" overloads="2">'  "Tree<T>::Node<U>::link keys its IMMEDIATE scope, arguments stripped"
expect_callers Node::link   2 useNested "a template member of a template"
expect_row     cls    Leaf  '<s t="cls" n="Leaf" sc="Tree">'                  "the out-of-line nested class Tree<T>::Leaf scopes to its container"
expect_row     method shed  '<s t="method" n="shed" sc="Tree::Leaf">'         "its member scopes to Tree::Leaf, the non-template Outer::Inner reading"
expect_callers Leaf::shed   1 useNested "member of an out-of-line nested class of a template"

# ── §4 SPECIALIZATIONS KEY THE PRIMARY TEMPLATE'S MEMBER (the decision in the header) ───────────────────────────
expect_row     method clear '<s t="method" n="clear" sc="Slot" overloads="7">' \
    "all seven clear rows (primary decl+def, explicit member, partial decl+def, explicit class decl+member) are one member"
expect_callers Slot::clear  7 useSlot "every specialization body is a definition of Slot::clear"
SLOTIDS="$( awk -F'\t' '$1=="S" && $2 ~ /^slot\.hpp::/ && $2 ~ /::clear#/ { sub( /#[0-9]+$/, "", $2 ); print $2 }' "$TMP/shape.tsv" | sort -u )"
[ "$SLOTIDS" = "slot.hpp::Slot::clear" ] \
    && ok "census: every clear definition in slot.hpp has the one id slot.hpp::Slot::clear (was Slot<T> / string> / Slot<T*> / Slot<bool>)" \
    || no "census: slot.hpp clear ids are not all slot.hpp::Slot::clear: $( printf '%s' "$SLOTIDS" | tr '\n' ' ' )"
[ "$( awk -F'\t' '$1=="S" && $2 ~ /^slot\.hpp::.*::clear#/' "$TMP/shape.tsv" | grep -c . )" = 7 ] \
    && ok "census: seven clear definitions — the specializations were joined, not dropped" \
    || no "census: expected 7 clear S rows, got $( awk -F'\t' '$1=="S" && $2 ~ /^slot\.hpp::.*::clear#/' "$TMP/shape.tsv" | grep -c . )"

# ── §5 THE REFERENCE SIDE: a two-segment call through a template-id is QUALIFIED, not sprayed onto a decoy ─────
expect_callers Factory::make 2 build "Factory<int>::make() keys Factory::make"
DECOY="$( run shape --callers=Decoy::make --no-cache --legend=compact )"
{ [ "$( defs "$DECOY" )" = 2 ] && [ "$( cnt "$DECOY" )" = 0 ]; } \
    && ok "--callers=Decoy::make defs=\"2\" count=\"0\" — no false caller (was count=\"1\" build)" \
    || no "--callers=Decoy::make expected defs=2 count=0, got: $( el "$DECOY" )"
[ "$( run shape --uses=make --no-cache --legend=compact | grep -oE '<u role="call" p="statics\.hpp:21" in_id="build"/>' | grep -c . )" = 1 ] \
    && ok "presence: build's make() site is still a use-site — the zero above is resolution, not a lost reference" \
    || no "build's make() site vanished from --uses=make — the Decoy arm is vacuous"
printf '%s' "$SMAP" | grep -qE '<s t="fn" n="build"[^>]* amb=' \
    && no "build still carries amb= — the call was split, not qualified" \
    || ok "build carries no amb= (was amb=\"1\")"
[ "$( awk -F'\t' '$1=="C" && $6 ~ /^statics\.hpp::build#/ { sub( /#[0-9]+$/, "", $8 ); print $2 "\t" $8 }' "$TMP/shape.tsv" )" = "$( printf 'qualified\tstatics.hpp::Factory::make' )" ] \
    && ok "census: build's site is decided by mech=qualified -> statics.hpp::Factory::make" \
    || no "census: build's site expected qualified -> Factory::make, got: $( awk -F'\t' '$1=="C" && $6 ~ /^statics\.hpp::build#/' "$TMP/shape.tsv" | tr '\n\t' '| ' )"

# ── §6 determinism ──────────────────────────────────────────────────────────────────────────────────────────────
run shape --pin-census="$TMP/shape2.tsv" --no-cache >"$TMP/smap2.xml"
{ [ "$( cat "$TMP/smap2.xml" )" = "$( run shape --no-cache )" ] && cmp -s "$TMP/shape.tsv" "$TMP/shape2.tsv"; } \
    && ok "deterministic: map and census byte-identical across two --no-cache runs" \
    || no "shape map or census differs between two identical runs"

if [ "$fail" = 0 ]; then echo "cpptmplscopecheck: ALL PASS"; else echo "cpptmplscopecheck: FAIL"; fi
exit "$fail"
