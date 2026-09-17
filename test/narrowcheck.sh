#!/usr/bin/env bash
# narrowcheck.sh — gate for P2-D Rule 2 receiver-VARIABLE type narrowing (ABS-1 / locals-style scoping).
#
# The narrow: `Foo x; x.run()` and `auto y = Bar(); y.run()` resolve run to Foo::run / Bar::run ONLY
# (the var's type is known), instead of the bare §2a ladder's WRONG 1/k split across every same-named
# `run`. The soundness discipline (resolve.h::rule2RecvVarType) is "a wrong narrow is worse than no
# narrow": it fires ONLY when the var has a known, non-tombstoned type binding whose class actually
# DEFINES the called method (canonByName hit) — otherwise it degrades to §2a unchanged.
#
# The fixture pairs each narrowed caller with a NEGATIVE CONTROL of the SAME call shape whose receiver
# is a local the capture cannot type (`auto p = pool[ slot ]; p->run()`) — no var→type binding, so Rule 2
# can't fire and the call stays HONESTLY AMBIGUOUS. The narrowed-vs-control contrast is the proof the narrow
# is REAL (a binding-driven resolution, not a vacuously-unambiguous fixture). The control used to be a
# function PARAMETER; arms 7-18 are why it is not any more.
#
# Arms 7-16 — PARAMETER receivers (2026-09-16). A parameter's written type (LocalBindKind::ParamType) was
# captured but read only by the field use-site index, so `int Decoy::plainCaller( Target& other ) { return
# other.pick( 1 ); }` fell through Rule 2 to the S6-C locality tie-break, which hands the tie to the CALLER'S
# OWN class: one precise edge to Decoy::pick, no amb=, nothing disclosed. Rule 2 now reads ParamType records
# LEXICALLY — the innermost declaration of the name whose scope covers the call site decides, and only a
# declaration with a written type narrows. The fixture is GENERATED (line numbers are load-bearing: p= tells
# Target's methods, line 1, from Other's, line 2, and Decoy's, lines 5-6). Two kinds of arm:
#   * RED on the unfixed binary: the parameter/range-for/lambda receivers that must now pin to Target.
#   * RED on a NAIVE fix that folds ParamType into Rule 2's flat per-function table (observed, see the
#     commit): a range-for variable's type leaking to a later `auto` loop of the same name (12), to a
#     same-named FIELD read outside the loop (13), and an untyped nested redeclaration of a parameter (14);
#     plus (10), where the flat table's tombstone would throw away two precise answers.
#   * Arms 17-24 — a written type is recorded as its final segment and class names carry no namespace, so a type
#     written in namespace `std` (`std::map<int, int>`) matched an unrelated in-repo class `map`. `std` is reserved
#     to the implementation — a program declares no class in it — so a `std::`-led written type never narrows, for
#     a parameter (17), a typed local (19), a constructor-inferred local (20) and a C++ assignment (21). Every other
#     qualifier keeps its narrow: an in-repo namespace is the common case (22, 23). (24) pins the stated floor.
#   * Arm 25 — DISCLOSURE: a narrow decided by a qualified written type matched only its final segment, so it never reads
#     as precise. Its edge carries prov="final-segment" (the floor's wrong edge, a correct parameter narrow and the local
#     twin alike); an unqualified narrow and a uniquely named call carry no prov=, and both legends define the value.
#   * Arms 52-60 — a direct-initialized local whose every argument is a plain name (`IRBuilder<> Builder(Rem);`) parses as a
#     local FUNCTION declaration. The tags query minted a function symbol for it, the local's type binding was attributed
#     to that symbol instead of to the enclosing function, and Rule 2 never saw the type. RED on the unfixed binary:
#     52-58. RED on a naive fix that refuses every body-local declarator: 59. 60 pins the multiplication floor.
#
# Usage:
#   RIPWIRE_BIN=build/ripwire bash test/narrowcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/narrowcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/narrowfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/narrowfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "narrowcheck: BIN=$BIN  CORPUS=test/narrowfix"

"$BIN" "$FIX" --no-cache >"$TMP/map" 2>/dev/null

# ── 1) headline: exactly ONE ambiguous call remains — the untyped control. The two local-var callers
#       (cpp g, py g) narrowed away their ambiguity entirely. ─────────────────────────────────────────
amb="$( grep -o 'ambiguous=[0-9]*' "$TMP/map" | head -1 | grep -o '[0-9]*' )"
[ "$amb" = "1" ] && ok "exactly one ambiguous call remains (ambiguous=1 — only the untyped control)" \
                 || no "ambiguous=$amb (expected 1: the two local-var calls should narrow, the untyped control stays split)"

# ── 2) the untyped control `h` (auto p = pool[ slot ]; p->run()) MUST stay ambiguous — no var→type binding,
#       so Rule 2 cannot fire and the call honestly splits to BOTH run defs. ──────────────────────────────
grep -q 'n="h" amb="1"' "$TMP/map" \
    && ok "untyped control h() stays AMBIGUOUS (amb=1 — proves the narrow needs a real binding)" \
    || { no "untyped control h() is not amb=1 (the negative control failed — narrow may be vacuous)"; grep -o 'n="h"[^>]*' "$TMP/map" | head; }

# ── 3) the local-var callers `g` (cpp `Foo x`/`auto y=Bar()`, py `x=Foo()`) MUST be narrowed → NO amb= marker.
#       (Same call shape as the control; the ONLY difference is the local binding ⇒ this is the real-narrow proof.)
if grep -oE 'n="g"[^>]*' "$TMP/map" | grep -q 'amb='; then
    no "a local-var caller g() is still marked ambiguous (narrow did not fire)"; grep -oE 'n="g"[^>]*' "$TMP/map"
else
    ok "local-var callers g() are NARROWED (no amb= — x.run→Foo::run, y.run→Bar::run resolved 1:1)"
fi

# ── 4) under-link guard: the narrow must RESOLVE the calls, not DROP them. The cpp caller still has BOTH
#       run edges, pointing at the two distinct run DEFS (Foo::run and Bar::run) — one each, not zero, not 4. ─
ce="$( "$BIN" "$FIX" --callees=g --no-cache 2>/dev/null )"
nruncpp="$( printf '%s' "$ce" | grep -o 'n="run"[^>]*cpp/recv.cpp:[0-9]*' | sort -u | wc -l | tr -d ' ' )"
[ "$nruncpp" = "2" ] \
    && ok "cpp g() keeps BOTH run edges to distinct defs (no edge dropped, no cross-edge — $nruncpp targets)" \
    || { no "cpp g() has $nruncpp distinct run targets (want 2: Foo::run + Bar::run)"; printf '%s\n' "$ce" | tr '>' '\n' | grep run; }

# ── 5) determinism — the binding capture + narrow must be byte-stable run-to-run. ───────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/map2" 2>/dev/null
diff -q "$TMP/map" "$TMP/map2" >/dev/null \
    && ok "deterministic (narrowfix map byte-identical across two runs)" \
    || { no "non-deterministic narrowfix map"; diff "$TMP/map" "$TMP/map2" | head -6; }

# ── 6) cache transparency — narrowing facts (RawBind) survive the incremental cache: warm == cold. ──────
rm -f "$TMP/nc"
"$BIN" "$FIX" --cache="$TMP/nc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/nc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null \
    && ok "cache-transparent (bindings round-trip: warm == cold)" \
    || { no "binding cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

# ── Arms 7-16: PARAMETER receivers (see the header). LINE NUMBERS ARE ASSERTED BELOW — edit with care.
#   Target::pick/peek c.cpp:1   Other::pick/peek c.cpp:2   Decoy::pick c.cpp:5, Decoy::peek c.cpp:6
PFIX="$TMP/paramfix"
mkdir -p "$PFIX"
cat >"$PFIX/c.cpp" <<'EOF'
struct Target { int pick( int n ) { return n; } int peek( int n ) { return n; } };
struct Other { int pick( int n ) { return n; } int peek( int n ) { return n; } };
struct Decoy
{
    int pick( int n ) { return n; }
    int peek( int n ) { return n; }
    int plainCaller( Target& other ) { return other.pick( 1 ); }
    int ptrCaller( Target* other ) { return other->pick( 1 ); }
    int localCaller() { Target other; return other.pick( 1 ); }
    int nestedTyped( Target& other, Other* os[] ) { int n = 0; for( const Other* other : os ) { n += other->peek( 1 ); } return n + other.pick( 2 ); }
    int lambdaCaller() { auto f = []( Target& t ) { return t.pick( 1 ); }; Target held; return f( held ); }
};
struct Box
{
    Other* item;
    Target ts[ 2 ];
    Other* os[ 2 ];
    int loopLeak() { int n = 0; for( const Target& t : ts ) { n += t.pick( 1 ); } for( auto t : os ) { n += t->peek( 2 ); } return n; }
    int fieldLeak() { int n = 0; for( const Target& item : ts ) { n += item.pick( 1 ); } return n + item->peek( 2 ); }
    int untypedShadow( Target& other ) { int n = 0; for( auto other : os ) { n += other->peek( 1 ); } return n + other.pick( 2 ); }
};
EOF

# one caller's callee rows as sorted `name@line` words, restricted to one method name. The probe must RUN:
# a missing <callees> element (unknown flag, refused selector, crash) prints a marker no assertion accepts.
rowsOf(){
    local out
    out="$( "$BIN" "$PFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="\([^"]*\)".* p="c\.cpp:\([0-9]*\)".*/\1@\2/p' \
        | grep "^$2@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectRows(){   # arm label, caller, method, the exact expected row set
    local got
    got="$( rowsOf "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2(): $3 -> [$got]"
    else
        no "$1 $2(): $3 -> [$got], want [$4]"
    fi
}
expectIncludes(){   # arm label, caller, method, a row the honest split must keep
    local got
    got="$( rowsOf "$2" "$3" )"
    case " $got " in
        *" $4 "*) ok "$1 $2(): $3 keeps $4 in its split -> [$got]" ;;
        *)        no "$1 $2(): $3 -> [$got] has no $4 — a declaration's type leaked past its scope" ;;
    esac
}

# presence guard: every probed caller and every candidate def is indexed, or the arms below prove nothing
PMAP="$( "$BIN" "$PFIX" --no-cache 2>/dev/null | tr '>' '\n' )"
pmiss=0
for want in 'n="pick" sc="Target"' 'n="peek" sc="Target"' 'n="pick" sc="Other"' 'n="peek" sc="Other"' 'n="pick" sc="Decoy"' 'n="peek" sc="Decoy"' \
            'n="plainCaller" sc="Decoy"' 'n="ptrCaller" sc="Decoy"' 'n="localCaller" sc="Decoy"' 'n="nestedTyped" sc="Decoy"' \
            'n="lambdaCaller" sc="Decoy"' 'n="loopLeak" sc="Box"' 'n="fieldLeak" sc="Box"' 'n="untypedShadow" sc="Box"'; do
    printf '%s\n' "$PMAP" | grep -qF "$want" || { no "presence guard: paramfix symbol $want not indexed"; pmiss=1; }
done
[ "$pmiss" = 0 ] && ok "presence: all paramfix symbols indexed"

# ── 7) THE DEFECT: a reference parameter's method call pins to the parameter's type — not the enclosing class's
#       same-named method (Decoy::pick, line 5), which the locality tie-break used to hand it. ────────────────
expectRows "(7)" plainCaller pick "pick@1"
# ── 8) a POINTER parameter, `other->pick( 1 )` — same fact, other declarator shape. ────────────────────────────
expectRows "(8)" ptrCaller pick "pick@1"
# ── 9) control: the typed LOCAL of the same name already narrowed through Rule 2's Type record. ──────────────
expectRows "(9)" localCaller pick "pick@1"
# ── 10) a typed range-for variable shadows the parameter INSIDE the loop only: peek goes to Other, the pick after
#        the loop to the parameter's Target. A flat per-function table would tombstone both (split). ──────────
expectRows "(10)" nestedTyped peek "peek@2"
expectRows "(10)" nestedTyped pick "pick@1"
# ── 11) a LAMBDA parameter types the call inside the lambda body. ────────────────────────────────────────────
expectRows "(11)" lambdaCaller pick "pick@1"
# ── 12) scope leak, sibling loop: `for( const Target& t : ts )` narrows its own pick, and must NOT type the
#        later `for( auto t : os )` — that t is untyped, so its peek stays the honest split (Other::peek in it).
expectRows "(12)" loopLeak pick "pick@1"
expectIncludes "(12)" loopLeak peek "peek@2"
# ── 13) scope leak, field: `item->peek( 2 )` after the loop names the FIELD `Other* item`, not the loop variable.
expectRows "(13)" fieldLeak pick "pick@1"
expectIncludes "(13)" fieldLeak peek "peek@2"
# ── 14) an UNTYPED nested redeclaration (`for( auto other : os )`) hides the Target parameter inside the loop:
#        no narrow there; after the loop the parameter is back in scope and narrows. ───────────────────────────
expectIncludes "(14)" untypedShadow peek "peek@2"
expectRows "(14)" untypedShadow pick "pick@1"

# ── 15) the mechanism, not just the answer: the census names Rule 2 (receiver-rule) for plainCaller's site, where
#        the unfixed binary names the locality tie-break. ─────────────────────────────────────────────────────────
"$BIN" "$PFIX" --no-cache --pin-census="$TMP/census.tsv" >/dev/null 2>&1
mech="$( awk -F '\t' '$1 == "C" && $6 ~ /::Decoy::plainCaller#/ && $7 == "pick" { print $2 }' "$TMP/census.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$mech" = "receiver-rule" ] \
    && ok "(15) plainCaller's pick site is decided by receiver-rule (Rule 2), not the locality tie-break" \
    || no "(15) plainCaller's pick site mech=[${mech:-NO-CENSUS-ROW}], want [receiver-rule]"

# ── 16) determinism + cache transparency on the parameter fixture: the declaration byte Rule 2 now matches on is
#        re-derived from the cached record, so warm must equal cold. ─────────────────────────────────────────────
"$BIN" "$PFIX" --callees=nestedTyped --no-cache >"$TMP/p1" 2>/dev/null
"$BIN" "$PFIX" --callees=nestedTyped --no-cache >"$TMP/p2" 2>/dev/null
rm -f "$TMP/pc"
"$BIN" "$PFIX" --cache="$TMP/pc" >/dev/null 2>&1
"$BIN" "$PFIX" --callees=nestedTyped --cache="$TMP/pc" >"$TMP/pwarm" 2>/dev/null
if [ -s "$TMP/p1" ] && cmp -s "$TMP/p1" "$TMP/p2" && cmp -s "$TMP/p1" "$TMP/pwarm"; then
    ok "(16) paramfix --callees=nestedTyped byte-identical: cold, cold again, and warm"
else
    no "(16) paramfix --callees=nestedTyped differs across runs or warm vs cold"; diff "$TMP/p1" "$TMP/pwarm" | head -6
fi

# ── Arms 17-24: a written type is only its FINAL segment (`std::map<int, int>` records `map`), and class names carry no
#    namespace, so a type written in namespace `std` cannot be told apart from an unrelated same-named in-repo class by
#    its name — measured on a private C++ corpus as precise wrong edges from `const std::map<K, V>& ref; ref.lower_bound()`
#    and six `std::map<…> m; m.find()` LOCALS to an in-repo `map`. `std` is reserved to the implementation
#    ([namespace.std]: a program adds no declaration to it but a specialization), so no in-repo class IS `std::map`, and
#    a `std::`-led written type never narrows (the qualified text rides the record: kParserVer 97, and 98 for the
#    assignment). EVERY OTHER QUALIFIER KEEPS ITS NARROW, and that is measured, not assumed: refusing any qualifier —
#    this gate's rule for parameters until 2026-09-16 — refused 424 in-repo narrows on rocksdb (`ROCKSDB_NAMESPACE::
#    Status s; s.ok()`, `test::SleepingBackgroundTask`) and 9 on this repo's src/ (`rw::notes::NoteIndex`), every
#    sampled one correct, while fixing no wrong edge outside `std` on any of the three corpora. An include-visibility
#    guard was measured and rejected before that: path-precise includes miss include-root spellings. Candidates live in
#    two directories apart from the caller, so a refused narrow declines (no edge) instead of landing on a same-file or
#    same-directory guess.
VFIX="$TMP/visfix"
mkdir -p "$VFIX/lib" "$VFIX/lib2" "$VFIX/lib3" "$VFIX/app"
printf 'struct map { int find( int k ) { return k; } };\n'  >"$VFIX/lib/map.h"
printf 'struct dict { int find( int k ) { return k; } };\n' >"$VFIX/lib2/dict.h"
printf 'namespace store { struct tree { int find( int k ) { return k; } }; }\n' >"$VFIX/lib3/tree.h"
printf 'int lookupHidden( std::map<int, int>& table ) { return table.find( 1 ); }\n' >"$VFIX/app/hidden.cpp"
printf '#include "../lib/map.h"\nint lookupSeen( map& table ) { return table.find( 1 ); }\n' >"$VFIX/app/seen.cpp"
printf 'int lookupLocal() { std::map<int, int> table; return table.find( 1 ); }\n' >"$VFIX/app/local.cpp"
printf 'int lookupCtor() { auto table = std::map<int, int>(); return table.find( 1 ); }\n' >"$VFIX/app/ctor.cpp"
printf 'std::map<int, int> cache;\nint lookupAssign() { cache = std::map<int, int>(); return cache.find( 1 ); }\n' >"$VFIX/app/assign.cpp"
printf 'int lookupInRepoLocal() { store::tree table; return table.find( 1 ); }\nint lookupInRepoParam( const store::tree& table ) { return table.find( 1 ); }\n' >"$VFIX/app/inrepo.cpp"
printf 'int lookupExternal( ext::map<int, int>& table ) { return table.find( 1 ); }\n' >"$VFIX/app/external.cpp"
printf 'int helperOnly() { return 1; }\nint callsHelper() { return helperOnly(); }\n' >"$VFIX/app/plain.cpp"
visRows(){   # the find@<file> rows one caller's callees answer; NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$VFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="find".* p="\([^"]*\)".*/find@\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectNoStdNarrow(){   # arm label, caller, what the declaration writes
    local got
    got="$( visRows "$2" )"
    case "$got" in
        NO-CALLEES-ANSWER) no "$1 $2(): --callees did not answer" ;;
        "find@lib/map.h:1") no "$1 $2(): $3 narrowed to the unrelated in-repo lib/map.h map::find" ;;
        *) ok "$1 $2(): $3 is not a narrow -> [${got:-no edge}]" ;;
    esac
}
expectNarrow(){   # arm label, caller, the one expected row
    local got
    got="$( visRows "$2" )"
    if [ "$got" = "$3" ]; then
        ok "$1 $2(): narrows -> [$got]"
    else
        no "$1 $2(): -> [$got], want [$3]"
    fi
}
# ── 17) a PARAMETER written `std::map<int, int>&`: no narrow to the unrelated in-repo lib/map.h `map`. ────────────────
expectNoStdNarrow "(17)" lookupHidden "a std::-qualified parameter type"
# ── 18) control — the same call shape with an UNQUALIFIED `map&` narrows to lib/map.h exactly. ──────────────────────
expectNarrow "(18)" lookupSeen "find@lib/map.h:1"
# ── 19) a typed LOCAL `std::map<int, int> table;` — Rule 2's flat per-function table, not the lexical one. ──────────
expectNoStdNarrow "(19)" lookupLocal "a std::-qualified local type"
# ── 20) a local typed by its constructor, `auto table = std::map<int, int>()`. ──────────────────────────────────────
expectNoStdNarrow "(20)" lookupCtor "a std::-qualified constructor"
# ── 21) a C++ ASSIGNMENT from a constructor, `cache = std::map<int, int>()` (its record carried no qualified text
#        until kParserVer 98). ───────────────────────────────────────────────────────────────────────────────────────
expectNoStdNarrow "(21)" lookupAssign "a std::-qualified constructor assignment"
# ── 22) control — an IN-REPO namespace qualifier narrows a typed local, as it always did. ───────────────────────────
expectNarrow "(22)" lookupInRepoLocal "find@lib3/tree.h:1"
# ── 23) the same in-repo qualifier on a PARAMETER narrows too (RED while a parameter refused every qualifier). ──────
expectNarrow "(23)" lookupInRepoParam "find@lib3/tree.h:1"
# ── 24) STATED FLOOR, pinned so it stays a decision: a qualifier that is neither `std` nor the class's own namespace
#        (`ext::map<int, int>&`, an external or aliased type whose final segment an unrelated in-repo class shares) still
#        narrows on the final segment. Measured once on a private corpus (an alias template); closing it needs the
#        namespace chain in Symbol::scope, planned on its own. If this arm goes red, the floor moved: rewrite it to
#        assert the fixed behaviour, never delete it. ────────────────────────────────────────────────────────────────
expectNarrow "(24)" lookupExternal "find@lib/map.h:1"

# ── 25) DISCLOSURE (2026-09-16): the narrows arms 22-24 keep matched a QUALIFIED written type by its final segment alone —
#        the qualifier is never checked against the class's namespace (arm 24's is wrong) — so their edges must not read
#        as uniquely resolved. Each carries prov="final-segment"; arm 18's unqualified narrow and a uniquely named call
#        carry no prov=; the map legend and the compact legend define the value on the document that carries it. RED
#        before the attribute existed: (25) rows a, b, c and both legend rows. ─────────────────────────────────────────
"$BIN" "$VFIX" --no-cache >"$TMP/vis.map" 2>/dev/null
"$BIN" "$VFIX" --no-cache --legend=compact >"$TMP/vis.compact" 2>/dev/null
provOf(){   # the prov= of caller $1's <c n="$2"> edge in the map: a word, "none" when absent, NO-EDGE when the row or edge is missing
    local row
    row="$( tr '<' '\n' <"$TMP/vis.map" | awk -v c="$1" '$1 == "s" && index( $0, " n=\"" c "\"" ) { on = 1; next } $1 == "s" || $1 == "/s>" { on = 0 } on' )"
    row="$( printf '%s\n' "$row" | grep "^c n=\"$2\"" | head -1 )"
    if [ -z "$row" ]; then
        printf 'NO-EDGE'
    elif printf '%s' "$row" | grep -q ' prov="'; then
        printf '%s' "$row" | sed -n 's/.* prov="\([^"]*\)".*/\1/p'
    else
        printf 'none'
    fi
}
expectProv(){   # arm label, caller, callee, expected prov word ("none" = absent)
    local got
    got="$( provOf "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "$1 $2() -> $3: prov=[$got]"
    else
        no "$1 $2() -> $3: prov=[$got], want [$4]"
    fi
}
expectProv "(25a)" lookupExternal find final-segment      # the floor's WRONG edge is disclosed, never precise
expectProv "(25b)" lookupInRepoParam find final-segment   # a CORRECT qualified parameter narrow: still a final-segment match
expectProv "(25c)" lookupInRepoLocal find final-segment   # the typed LOCAL twin says the same
expectProv "(25d)" lookupSeen find none                   # an unqualified narrow: no qualifier was ever skipped
expectProv "(25e)" callsHelper helperOnly none            # a uniquely named call
if grep -q 'final-segment(' "$TMP/vis.map"; then
    ok "(25f) the map legend defines prov=final-segment on the map that carries it"
else
    no "(25f) the map legend does not define prov=final-segment"
fi
if grep -q 'final-segment' "$TMP/vis.compact"; then
    ok "(25g) the compact legend defines prov=final-segment"
else
    no "(25g) the compact legend does not define prov=final-segment"
fi

# ── Arms 52-60 (2026-09-17): a DIRECT-INITIALIZED local whose every argument is a plain name — `IRBuilder<> Builder(Rem);`,
#    `std::lock_guard<std::mutex> Lock(Mtx);`, `Slice end(end_str);` — is the most-vexing-parse shape. The grammar cannot
#    tell a name from a type, so it reads the statement as a local FUNCTION declaration, and the tags query minted a
#    function symbol `Builder` whose span is the declaration. The local's type binding was attributed to that symbol (the
#    innermost span covering the declaration byte), not to the function the local lives in, so Rule 2 looked up
#    `<enclosing fn>#Builder`, found nothing, and `Builder.CreateSExt()` fell to the name ladder. A body-local declarator
#    now mints no symbol unless something in it can only be written in a prototype. Candidates live two directories away
#    from the caller, and nothing is #included, so a site no rule decides DECLINES (no edge) instead of reaching Rule 3.
#    LINE NUMBERS ARE ASSERTED BELOW: Widget/Box/store::Shelf at lib/widget.h:1/2/3, the vexing locals at vexing.cpp:2-8.
XFIX="$TMP/vexingfix"
mkdir -p "$XFIX/lib" "$XFIX/lib2" "$XFIX/app"
printf 'struct Widget { Widget( int n ) {} Widget( int a, int b ) {} int pick( int k ) { return k; } };\ntemplate <typename T = int> struct Box { Box( int n ) {} int pick( int k ) { return k; } };\nnamespace store { struct Shelf { Shelf( int n ) {} int pick( int k ) { return k; } }; }\n' >"$XFIX/lib/widget.h"
printf 'struct Other { int pick( int k ) { return k + 1; } };\n' >"$XFIX/lib2/other.h"
cat >"$XFIX/app/vexing.cpp" <<'EOF'
int nextSeed() { return 3; }
int pickOne( int seed ) { Widget w( seed ); return w.pick( 1 ); }
int pickTwo( int a, int b ) { Widget w( a, b ); return w.pick( 2 ); }
int pickCall() { Widget w( nextSeed() ); return w.pick( 3 ); }
int pickIndex( int* seeds ) { Widget w( seeds[ 0 ] ); return w.pick( 4 ); }
int pickQualified( int seed ) { store::Shelf s( seed ); return s.pick( 5 ); }
int pickTemplate( int seed ) { Box<> b( seed ); return b.pick( 6 ); }
int pickProduct( int a, int b ) { Widget w( a * b ); return w.pick( 7 ); }
int pickLiteral() { Widget w( 8 ); return w.pick( 8 ); }
int prototypes()
{
    void helperVoid( Widget );
    Widget helperPrim( int );
    Widget helperNamed( Widget other );
    Widget helperPtr( Other* );
    Widget helperNone();
    extern Widget helperExtern( Other );
    Widget helperConst( const Other& );
    return 0;
}
EOF
# a class body the grammar misreads as a FUNCTION body (an export macro before the class name): its member declarations
# arrive as body-local declarators too, and their trailing `const` / `override` is what keeps them.
cat >"$XFIX/app/misparse.h" <<'EOF'
#define API_MACRO
class API_MACRO Stream : public Other
{
public:
    int count( Widget ) const;
    Widget copy( Other ) override;
};
EOF
xRows(){   # the pick@<file:line> rows one caller's callees answer; NO-CALLEES-ANSWER when the probe did not run
    local out
    out="$( "$BIN" "$XFIX" "--callees=$1" --no-cache 2>/dev/null )"
    printf '%s' "$out" | grep -q "<callees [^>]*of=\"$1\" defs=\"1\"" || { printf 'NO-CALLEES-ANSWER'; return; }
    printf '%s' "$out" | grep -o '<s [^>]*>' | sed -n 's/.* n="pick".* p="\([^"]*\)".*/pick@\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//'
}
expectX(){   # arm label, caller, the exact expected row set ("" = no edge), what the declaration writes
    local got
    got="$( xRows "$2" )"
    if [ "$got" = "$3" ]; then
        ok "$1 $2(): $4 -> [${got:-no edge}]"
    else
        no "$1 $2(): $4 -> [${got:-no edge}], want [${3:-no edge}]"
    fi
}
"$BIN" "$XFIX" --no-cache --pin-census="$TMP/xcensus.tsv" >/dev/null 2>&1
xSymLines(){   # the census S-row lines of every symbol named $2 in file $1, sorted; empty when none
    awk -F '\t' -v id="$1::$2#" '$1 == "S" && index( $2, id ) == 1 { print $4 }' "$TMP/xcensus.tsv" 2>/dev/null | sort -n | tr '\n' ' ' | sed 's/ $//'
}
# presence guard: the census ran and indexed every probed caller, or the symbol-absence arms below prove nothing
xmiss=0
for want in nextSeed pickOne pickTwo pickCall pickIndex pickQualified pickTemplate pickProduct pickLiteral prototypes; do
    [ -n "$( xSymLines app/vexing.cpp "$want" )" ] || { no "presence guard: vexingfix caller $want has no census S row"; xmiss=1; }
done
[ "$xmiss" = 0 ] && ok "presence: the vexingfix census lists all ten callers"

# ── 52) THE DEFECT: `Widget w( seed ); w.pick( 1 )` pins to Widget::pick. (52c) is the same local with a LITERAL argument,
#        which never parsed as a function and always narrowed — the only difference between the two is the argument. ──
expectX "(52)" pickOne "pick@lib/widget.h:1" "Widget w( seed )"
expectX "(52c)" pickLiteral "pick@lib/widget.h:1" "Widget w( 8 )"
# ── 53) two plain-name arguments. ───────────────────────────────────────────────────────────────────────────────────────
expectX "(53)" pickTwo "pick@lib/widget.h:1" "Widget w( a, b )"
# ── 54) a CALL argument, `nextSeed()` — the grammar reads it as a parameter of type nextSeed returning a function. ────────
expectX "(54)" pickCall "pick@lib/widget.h:1" "Widget w( nextSeed() )"
# ── 55) a SUBSCRIPT argument, `seeds[ 0 ]` — read as an array parameter. ──────────────────────────────────────────────────
expectX "(55)" pickIndex "pick@lib/widget.h:1" "Widget w( seeds[ 0 ] )"
# ── 56) a namespace-qualified written type keeps its narrow (arm 22's rule) once the declaration is a local again. ────────
expectX "(56)" pickQualified "pick@lib/widget.h:3" "store::Shelf s( seed )"
# ── 57) EXTRACTION: none of those declarations mints a function symbol — including the template-id one `Box<> b( seed )`
#        (`IRBuilder<> Builder(Rem)`'s own shape), whose narrow waits on the template-id receiver type. ────────────────────
for xs in "w 2 3 4 5" "s 6" "b 7"; do
    set -- $xs
    xname="$1"; shift
    xgot=" $( xSymLines app/vexing.cpp "$xname" ) "
    for xline in "$@"; do
        case "$xgot" in
            *" $xline "*) no "(57) vexing.cpp:$xline declares a local '$xname', yet it is indexed as a function symbol" ;;
            *)            ok "(57) vexing.cpp:$xline local '$xname' mints no symbol" ;;
        esac
    done
done
# ── 58) the mechanism: the census names Rule 2 (receiver-rule, flags r) for pickOne's site. ──────────────────────────────
xmech="$( awk -F '\t' '$1 == "C" && $6 ~ /^app\/vexing\.cpp::pickOne#/ && $7 == "pick" { print $2 "/" $5 }' "$TMP/xcensus.tsv" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//' )"
[ "$xmech" = "receiver-rule/r" ] \
    && ok "(58) pickOne's pick site is decided by receiver-rule/r (Rule 2)" \
    || no "(58) pickOne's pick site mech/flags=[${xmech:-NO-CENSUS-ROW}], want [receiver-rule/r]"
# ── 59) PROTOTYPE CONTROLS: a body-local declarator carrying anything a variable cannot write stays a function symbol —
#        a void return, a primitive or const-qualified or pointer or NAMED parameter, empty parentheses (a function by the
#        language's own rule), `extern`, and the misread class body's trailing `const` / `override`. RED on a naive fix
#        that refuses every body-local declarator (observed, see the commit). ─────────────────────────────────────────────
for xp in "helperVoid 12" "helperPrim 13" "helperNamed 14" "helperPtr 15" "helperNone 16" "helperExtern 17" "helperConst 18"; do
    set -- $xp
    [ "$( xSymLines app/vexing.cpp "$1" )" = "$2" ] \
        && ok "(59) vexing.cpp:$2 prototype '$1' stays a function symbol" \
        || no "(59) vexing.cpp:$2 prototype '$1' -> S lines [$( xSymLines app/vexing.cpp "$1" )], want [$2]"
done
for xp in "count 5" "copy 6"; do
    set -- $xp
    [ "$( xSymLines app/misparse.h "$1" )" = "$2" ] \
        && ok "(59) misparse.h:$2 member declaration '$1' stays a function symbol" \
        || no "(59) misparse.h:$2 member declaration '$1' -> S lines [$( xSymLines app/misparse.h "$1" )], want [$2]"
done
# ── 60) STATED FLOOR, pinned so it stays a decision: `Widget w( a * b )` parses as a POINTER parameter `a* b`, which a
#        prototype writes too, so it is still a function symbol and its call still declines. If this arm goes red, the floor
#        moved: rewrite it to assert the fixed behaviour, never delete it. ──────────────────────────────────────────────────
case " $( xSymLines app/vexing.cpp w ) " in
    *" 8 "*) ok "(60) floor: vexing.cpp:8 'Widget w( a * b )' is still a function symbol" ;;
    *)       no "(60) floor moved: no symbol named w at vexing.cpp:8 (lines [$( xSymLines app/vexing.cpp w )])" ;;
esac
expectX "(60)" pickProduct "" "floor: Widget w( a * b )"
# ── 60d) determinism + cache transparency on the vexing fixture: the dropped symbol must not come back warm. ────────────────
"$BIN" "$XFIX" --no-cache >"$TMP/x1" 2>/dev/null
"$BIN" "$XFIX" --no-cache >"$TMP/x2" 2>/dev/null
rm -f "$TMP/xc"
"$BIN" "$XFIX" --cache="$TMP/xc" >/dev/null 2>&1
"$BIN" "$XFIX" --cache="$TMP/xc" >"$TMP/xwarm" 2>/dev/null
if [ -s "$TMP/x1" ] && cmp -s "$TMP/x1" "$TMP/x2" && cmp -s "$TMP/x1" "$TMP/xwarm"; then
    ok "(60d) vexingfix map byte-identical: cold, cold again, and warm"
else
    no "(60d) vexingfix map differs across runs or warm vs cold"; diff "$TMP/x1" "$TMP/xwarm" | head -6
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
