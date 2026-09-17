#!/usr/bin/env bash
# fieldnarrowcheck.sh — gate for P2-D Rule 2b: FIELD-typed member narrowing (W1-P1-12).
#
# The gap this closes: a member call whose receiver is a bare FIELD of the enclosing class
# (`m_pool.acquire()` / `m_p->tune()` inside a method of Owner) used to resolve `acquire` by BARE NAME
# against every same-named definition in the corpus — inflating per-symbol `amb=` and the header
# `ambiguous=` gauge. Rule 2b: when the receiver names a field whose DECLARED TYPE is a type the index
# knows (the S5-E HAS-A field capture), narrow the candidate set to that type's members, walking direct
# bases (chaUp) when the type itself does not define the method. RESOLVE-stage only — no kParserVer bump
# (arm q, 2026-09-16, is the exception: the field capture records the namespace a type was written in, kParserVer 99;
# arm t, 2026-09-17, is the second: a C++ typedef / using alias records its target class, kParserVer 105).
#
# Zero false edges is the bar — narrowing that guesses wrong is worse than ambiguity disclosed:
#   * a LOCAL (param / declared var) that shadows the field name vetoes the narrow (real C++ lookup);
#   * two same-NAMED classes (scope strings drop namespaces, so `n1::Dup` and `n2::Dup` collide) with a
#     same-named field of DIFFERENT types TOMBSTONE the field entry — neither narrows;
#   * an unknown/unindexed field type, a chained `this->f.m()` receiver, a receiver in a scope-less free
#     function, and multiple bases both defining the method all DEGRADE to the unchanged honest split;
#   * Python `self.member.m()` and TS `this.member.m()` receivers are NOT captured as named receivers
#     (chained member access; receiver capture is C++/ObjC+Python identifiers only) → UNCHANGED, and the
#     (e-py)/(e-ts) arms pin that honesty. Widening receiver capture is an EXTRACTION change (kParserVer)
#     and deliberately out of this round.
#
# The fixture is GENERATED here (self-contained; nothing committed under test/). Line numbers in the
# fixture are load-bearing: `--callees` rows carry p="file:LINE", which is how a Pool::acquire edge is
# told apart from the same-named Decoy::acquire decoy.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/fieldnarrowcheck.sh   (or asan/ripwire)
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fieldfix"; FIX2="$TMP/dupfix"
mkdir -p "$FIX" "$FIX2"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"

# LINE NUMBERS ARE ASSERTED BELOW — edit with care.
cat >"$FIX/a.cpp" <<'EOF'
struct Pool { void acquire() { } void tune() { } };
struct Decoy { void acquire() { } void tune() { } };

struct Owner {
    Pool m_pool;
    Pool* m_p;
    void run() { m_pool.acquire(); }
    void ptr() { m_p->tune(); }
    void expl() { this->m_pool.acquire(); }
};

struct Base { void helper() { } };
struct Derived : Base { };
struct DecoyH { void helper() { } };
struct Owner4 { Derived m_d; void inh_go() { m_d.helper(); } };

struct Owner5 { Pool m_x; void shadowParam( Decoy& m_x ) { m_x.acquire(); } };
struct Owner6 { Pool m_y; void shadowLocal() { Decoy m_y; m_y.acquire(); } };

struct Owner3 { UnknownT m_u; void unk() { m_u.acquire(); } };

struct B1 { void dual() { } };
struct B2 { void dual() { } };
struct D2 : B1, B2 { };
struct Owner7 { D2 m_dd; void multi() { m_dd.dual(); } };

Unknown gg;
void freeuse() { gg.acquire(); }
EOF

cat >"$FIX/p.py" <<'EOF'
class PHelper:
    def compute(self):
        return 1

class PDecoy:
    def compute(self):
        return 2

class POwner:
    member: PHelper
    def po_go(self):
        return self.member.compute()
EOF

cat >"$FIX/t.ts" <<'EOF'
class THelper { compute(): number { return 1; } }
class TDecoy { compute(): number { return 2; } }
class TOwner {
  member: THelper;
  to_go(): number { return this.member.compute(); }
}
EOF

# FIX2 — the same-named-class collision corpus, ISOLATED so its header ambiguous= gauge is exact.
# Symbol scopes drop the namespace (both classes read scope "Dup"), so the two same-named `m_f` fields
# with DIFFERENT types must tombstone the field-type entry: NEITHER go() may narrow.
cat >"$FIX2/ns.cpp" <<'EOF'
namespace n1 { struct Pool2 { void grab() { } };
               struct Dup { Pool2 m_f; void go() { m_f.grab(); } }; }
namespace n2 { struct Decoy2 { void grab() { } };
               struct Dup { Decoy2 m_f; void go() { m_f.grab(); } }; }
EOF

echo "fieldnarrowcheck: BIN=$BIN  CORPUS=$FIX + $FIX2 (generated)"

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null | tr '>' '\n' )"
callees(){ "$BIN" "$FIX" "--callees=$1" --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n'; }

# ── presence guards (a gate that cannot observe what it asserts is green-while-inert) ──
# TS symbols carry no scope string (no sc= attribute), so to_go is matched by its n= name. Row 6: a scoped row
# prints n= then sc= (the short id; the canonical id composes as p::sc::n with the enclosing <f p=>).
for want in 'n="acquire" sc="Pool"' 'n="acquire" sc="Decoy"' 'n="run" sc="Owner"' 'n="helper" sc="Base"' 'n="helper" sc="DecoyH"' 'n="inh_go" sc="Owner4"' 'n="po_go" sc="POwner"' 'n="to_go"'; do
    printf '%s\n' "$MAP" | grep -qF "$want" || no "presence guard: fixture symbol $want not indexed"
done
[ "$fail" = 0 ] && ok "presence: all fixture symbols indexed"

# ── (a) value field, type known: `m_pool.acquire()` → Pool::acquire (a.cpp:1) ONLY, decoy (a.cpp:2) unlinked ──
RUN="$( callees run )"
printf '%s\n' "$RUN" | grep -q 'a.cpp:1"' \
    && ok "(a) run() → Pool::acquire (field m_pool's declared type)" \
    || no "(a) run() has NO edge to Pool::acquire — field-typed narrow missing or dropped the correct edge"
printf '%s\n' "$RUN" | grep -q 'a.cpp:2"' \
    && no "(a/d) run() still linked to Decoy::acquire — the same-named decoy on an unrelated class must not be linked" \
    || ok "(d) run() decoy Decoy::acquire NOT linked"

# ── (a2) the narrow is visible in amb=: Owner::run's map row carries no ambiguous-call count ──
printf '%s\n' "$MAP" | grep 'id="[^"]*::Owner::run"' | grep -q 'amb=' \
    && no "(a2) Owner::run row still carries amb= — the field-typed call still counts ambiguous" \
    || ok "(a2) Owner::run row has no amb= (call resolved, honestly unambiguous)"

# ── (f) pointer field: `m_p->tune()` narrows exactly like a value field ──
PTR="$( callees ptr )"
printf '%s\n' "$PTR" | grep -q 'a.cpp:1"' \
    && ok "(f) ptr() → Pool::tune (pointer field m_p)" \
    || no "(f) ptr() has NO edge to Pool::tune — pointer-field narrow missing"
printf '%s\n' "$PTR" | grep -q 'a.cpp:2"' \
    && no "(f) ptr() still linked to Decoy::tune" \
    || ok "(f) ptr() decoy Decoy::tune NOT linked"

# ── (c) inheritance: field type Derived defines no helper — the DIRECT-base walk finds Base::helper (a.cpp:12);
#        the same-named DecoyH::helper (a.cpp:14) stays unlinked ──
INH="$( callees inh_go )"
printf '%s\n' "$INH" | grep -q 'a.cpp:12"' \
    && ok "(c) inh_go() → Base::helper (member found on the field type's base)" \
    || no "(c) inh_go() has NO edge to Base::helper — base walk missing"
printf '%s\n' "$INH" | grep -q 'a.cpp:14"' \
    && no "(c) inh_go() still linked to DecoyH::helper — decoy reached through the base walk" \
    || ok "(c) inh_go() decoy DecoyH::helper NOT linked"

# ── (b) unchanged-degrade arms: every uncertain shape keeps the honest 2-way split ──
EXPL="$( callees expl )"
( printf '%s\n' "$EXPL" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$EXPL" | grep -q 'a.cpp:2"' ) \
    && ok "(b) expl() this->m_pool.acquire() chained receiver stays honestly split (receiver capture limit, disclosed)" \
    || no "(b) expl() lost its honest split — a chained this->field receiver must not narrow (capture is None)"
UNK="$( callees unk )"
( printf '%s\n' "$UNK" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$UNK" | grep -q 'a.cpp:2"' ) \
    && ok "(b) unk() unknown field type UnknownT stays honestly split" \
    || no "(b) unk() lost its honest split — an unindexed field type must degrade, not narrow"
FREE="$( callees freeuse )"
( printf '%s\n' "$FREE" | grep -q 'a.cpp:1"' ) && ( printf '%s\n' "$FREE" | grep -q 'a.cpp:2"' ) \
    && ok "(b) freeuse() scope-less receiver stays honestly split" \
    || no "(b) freeuse() lost its honest split — a free function has no enclosing class to look fields up in"
MULTI="$( callees multi )"
( printf '%s\n' "$MULTI" | grep -q 'a.cpp:22"' ) && ( printf '%s\n' "$MULTI" | grep -q 'a.cpp:23"' ) \
    && ok "(b) multi() two bases both define dual() → ambiguous base walk refuses, split kept" \
    || no "(b) multi() lost its honest split — a 2-way base hit must refuse to narrow"

# ── (s) shadowing: a LOCAL that shadows the field name vetoes the narrow (real C++ lookup order) ──
SHP="$( callees shadowParam )"
printf '%s\n' "$SHP" | grep -q 'a.cpp:2"' \
    && ok "(s1) shadowParam( Decoy& m_x ) keeps its Decoy::acquire edge — the param shadows field m_x" \
    || no "(s1) shadowParam lost Decoy::acquire — the field type was wrongly narrowed over the shadowing param"
# since 2026-09-16 Rule 2 reads the parameter's written type (narrowcheck arms 7-18), so the parameter's Decoy is
# the WHOLE answer — main's binary still linked the field's Pool::acquire here as half of a split
printf '%s\n' "$SHP" | grep -q 'a.cpp:1"' \
    && no "(s1) shadowParam linked to Pool::acquire — the FIELD type beat the shadowing Decoy& parameter" \
    || ok "(s1) shadowParam field type Pool NOT linked (the typed parameter shadows the field)"
SHL="$( callees shadowLocal )"
printf '%s\n' "$SHL" | grep -q 'a.cpp:2"' \
    && ok "(s2) shadowLocal's local Decoy m_y still wins (Rule 2 narrow preserved)" \
    || no "(s2) shadowLocal lost its Rule-2 edge to Decoy::acquire"
printf '%s\n' "$SHL" | grep -q 'a.cpp:1"' \
    && no "(s2) shadowLocal linked to Pool::acquire — the FIELD type beat the shadowing local" \
    || ok "(s2) shadowLocal field type Pool NOT linked (local shadows field)"

# ── (e) cross-language honesty: Python/TS field receivers are chained accesses — NOT narrowed, stays split ──
PY="$( callees po_go )"
( printf '%s\n' "$PY" | grep -q 'p.py:2"' ) && ( printf '%s\n' "$PY" | grep -q 'p.py:6"' ) \
    && ok "(e-py) po_go() self.member.compute() stays honestly split (annotated attr NOT narrowed — disclosed limit)" \
    || no "(e-py) po_go() lost its honest split — Python receiver behavior must be unchanged this round"
TS="$( callees to_go )"
( printf '%s\n' "$TS" | grep -q 't.ts:1"' ) && ( printf '%s\n' "$TS" | grep -q 't.ts:2"' ) \
    && ok "(e-ts) to_go() this.member.compute() stays honestly split (TS receivers uncaptured — disclosed limit)" \
    || no "(e-ts) to_go() lost its honest split — TS receiver behavior must be unchanged this round"

# ── (h) the header gauge agrees with the arms above: exactly the 6 honest splits remain ambiguous
#        (expl, unk, freeuse, multi, po_go, to_go — run/ptr/inh_go narrowed, shadowLocal and shadowParam are
#        Rule 2; shadowParam was a split until Rule 2 read parameter types, 2026-09-16, which moved this from 7).
#        Counted from the fixture, not guessed: flip arms above before touching this number. ──
AMB="$( printf '%s\n' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB" = "ambiguous=6" ] \
    && ok "(h) header gauge ambiguous=6 — only the honest splits remain" \
    || no "(h) header gauge is '$AMB', expected ambiguous=6 (3 field-typed calls narrowed, 6 honest splits kept)"

# ── (n) same-NAMED class collision (FIX2): conflicting same-named fields tombstone — NEITHER Dup::go narrows ──
MAP2="$( "$BIN" "$FIX2" --no-cache 2>/dev/null | tr '>' '\n' )"
printf '%s\n' "$MAP2" | grep -qF 'n="go" sc="Dup"' || no "(n) presence guard: Dup::go not indexed in FIX2"
AMB2="$( printf '%s\n' "$MAP2" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB2" = "ambiguous=2" ] \
    && ok "(n) both n1::Dup::go and n2::Dup::go stay ambiguous (conflicting field types tombstoned)" \
    || no "(n) FIX2 header gauge is '$AMB2', expected ambiguous=2 — a name-collided field type must never narrow"
GO2="$( "$BIN" "$FIX2" --callees=go --no-cache 2>/dev/null | grep -o '<callees.*</callees>' | tr '/' '\n' )"
( printf '%s\n' "$GO2" | grep -q 'ns.cpp:1"' ) && ( printf '%s\n' "$GO2" | grep -q 'ns.cpp:3"' ) \
    && ok "(n) both grab() defs stay linked across the collision" \
    || no "(n) a grab() edge vanished — the tombstone dropped a correct edge"

# ── (q) a field type written in namespace `std` (2026-09-16) — an EXTRACTION change, unlike the rest of this gate. The
#        field capture keeps a qualified type's final segment, so `std::string name_;` recorded `string`, and three
#        readers of that record took it for an in-repo class of that name: Rule 2b pinned `name_.size()` to it
#        (census mech=receiver-rule), the HAS-A block drew Record → string, and the member index pinned `name_.len`
#        to string.len. `std` is reserved to the implementation, so no in-repo class IS a std:: type — the sibling
#        rule for locals and parameters (resolve.h namesStdType, test/narrowcheck.sh arms 17-24). Every other
#        qualifier keeps narrowing on its final segment: store::Text is the control (q2/q4/q6).
#        (q7) is the trap the obvious fix walks into. Skipping the std field at capture UN-TOMBSTONES a same-named
#        class's differently-typed field — measured on rocksdb: test_util/testutil.h's `std::string contents_` and
#        db/log_test.cc's `Slice& contents_` share the key StringSource#contents_, and the skip pinned four
#        testutil.h `contents_.size()` calls to Slice::size. So the std field must still tombstone the entry; the
#        fixture holds the collision in BOTH record orders (StringSink's std side sorts first, StringSource's last).
#        LINE NUMBERS in app/rec.cpp are asserted below. ──
FIX3="$TMP/stdfix"; FIX4="$TMP/tombfix"
mkdir -p "$FIX3/lib" "$FIX3/lib2" "$FIX3/store" "$FIX3/app" "$FIX4/0" "$FIX4/a" "$FIX4/b" "$FIX4/c"
cat >"$FIX3/lib/str.h" <<'EOF'
struct string { int size() { return 0; } int len; };
EOF
cat >"$FIX3/lib2/blob.h" <<'EOF'
struct Blob { int size() { return 1; } };
EOF
cat >"$FIX3/store/text.h" <<'EOF'
namespace store { struct Text { int size() { return 4; } int len; }; }
EOF
cat >"$FIX3/app/rec.cpp" <<'EOF'
struct Record {
    std::string name_;
    store::Text body_;
    int nameLength() { return name_.size(); }
    int bodyLength() { return body_.size(); }
    int nameLen() { return name_.len; }
    int bodyLen() { return body_.len; }
    int thisNameLen() { return this->name_.len; }
};
EOF
cat >"$FIX4/0/pipe.h" <<'EOF'
struct StringSink { std::string contents_; int drained() { return contents_.size(); } };
EOF
cat >"$FIX4/a/slice.h" <<'EOF'
struct Slice { int size() const { return 2; } };
struct Other { int size() const { return 3; } };
EOF
cat >"$FIX4/a/log_test.cc" <<'EOF'
struct StringSource { Slice& contents_; int left() { return contents_.size(); } };
EOF
cat >"$FIX4/b/testutil.h" <<'EOF'
struct StringSource { std::string contents_; int used() { return contents_.size(); } };
EOF
cat >"$FIX4/c/sink.cc" <<'EOF'
struct StringSink { Slice& contents_; int filled() { return contents_.size(); } };
EOF
"$BIN" "$FIX3" --no-cache --pin-census="$TMP/q3.tsv" >/dev/null 2>&1
"$BIN" "$FIX4" --no-cache --pin-census="$TMP/q4.tsv" >/dev/null 2>&1
qMechs(){  # qMechs TSV CALLER — the distinct deciding mechanisms of CALLER's size() census rows ("" = no row: declined)
    awk -F '\t' -v c="$2" '$1 == "C" && index( $6, c ) && $7 == "size" { print $2 }' "$1" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'
}
qHas(){ grep -qF "$2" "$1" 2>/dev/null; }
qMissing=""
for want in '::Record::nameLength#' '::Record::bodyLength#' '::Record::nameLen#' '::Record::bodyLen#' 'dispositions calls=2 '; do
    qHas "$TMP/q3.tsv" "$want" || qMissing="$qMissing [stdfix $want]"
done
for want in '0/pipe.h::StringSink::drained#' 'a/log_test.cc::StringSource::left#' 'b/testutil.h::StringSource::used#' 'c/sink.cc::StringSink::filled#' 'dispositions calls=4 '; do
    qHas "$TMP/q4.tsv" "$want" || qMissing="$qMissing [tombfix $want]"
done
[ -z "$qMissing" ] && ok "(q0) presence: both census files name every fixture caller and count every size() call" \
    || no "(q0) presence guard:$qMissing — every (q) arm below would be vacuous"

# (q1) the defect; (q2) the in-repo qualified control
Q1="$( qMechs "$TMP/q3.tsv" '::Record::nameLength#' )"
Q1PIN="$( awk -F '\t' '$1 == "C" && index( $6, "::Record::nameLength#" ) && $7 == "size" && $8 ~ /^lib\/str\.h::string::size#[0-9]+$/' "$TMP/q3.tsv" 2>/dev/null )"
if [ "$Q1" != "receiver-rule" ] && [ -z "$Q1PIN" ]; then
    ok "(q1) std::string name_; name_.size() is NOT pinned to the in-repo string::size (mech=[${Q1:-declined}])"
else
    no "(q1) std::string name_; name_.size() pinned to the in-repo lib/str.h string::size (mech=[${Q1:-none}]) — a std:: field type named an in-repo class"
fi
Q2="$( awk -F '\t' '$1 == "C" && index( $6, "::Record::bodyLength#" ) && $7 == "size" { print $2 "|" $8 }' "$TMP/q3.tsv" 2>/dev/null )"
case "$Q2" in
    "receiver-rule|store/text.h::Text::size#"*) ok "(q2) control: store::Text body_; body_.size() still narrows to store/text.h Text::size (receiver-rule)" ;;
    *) no "(q2) control: store::Text body_; body_.size() lost its narrow to Text::size — an in-repo qualifier was refused: [${Q2:-no row}]" ;;
esac

# (q3) no HAS-A edge to the in-repo namesake; (q4) the in-repo qualified member keeps its edge
COMPOSE="$( "$BIN" "$FIX3" --around=Record --no-cache 2>/dev/null | grep -o '<compose>.*</compose>' )"
printf '%s' "$COMPOSE" | grep -qF 'name="name_"' \
    && no "(q3) HAS-A still draws Record → string for std::string name_: $COMPOSE" \
    || ok "(q3) no HAS-A edge from Record's std::string name_ to the in-repo string"
printf '%s' "$COMPOSE" | grep -qF '<field name="body_" type="Text" owner="Record" rel="creates"/>' \
    && ok "(q4) control: HAS-A keeps Record → Text for store::Text body_" \
    || no "(q4) control: HAS-A lost Record → Text for store::Text body_: [${COMPOSE:-no <compose> block}]"

# (q5) the member index reads the same field-type record: `name_.len` must not pin to string.len; (q6) body_.len still pins
STRLEN="$( "$BIN" "$FIX3" --uses=string.len --no-cache 2>/dev/null )"
for line in 6 8; do   # 6: `name_.len` (a bare receiver), 8: `this->name_.len` (through this) — both read the class#field entry
    USES5="$( printf '%s' "$STRLEN" | grep -oE "<u [^>]*p=\"app/rec.cpp:$line\"[^>]*/>" )"
    if [ -z "$USES5" ] || printf '%s' "$USES5" | grep -q 'owner_candidates='; then
        ok "(q5) --uses=string.len does not pin std::string name_'s .len read (app/rec.cpp:$line) to the in-repo string: [${USES5:-no row}]"
    else
        no "(q5) --uses=string.len PINS app/rec.cpp:$line (std::string name_.len) to the in-repo string: $USES5"
    fi
done
USES6="$( "$BIN" "$FIX3" --uses=Text.len --no-cache 2>/dev/null | grep -oE '<u [^>]*p="app/rec.cpp:7"[^>]*/>' )"
if [ -n "$USES6" ] && ! printf '%s' "$USES6" | grep -q 'owner_candidates='; then
    ok "(q6) control: --uses=Text.len still pins store::Text body_'s .len read (app/rec.cpp:7)"
else
    no "(q6) control: --uses=Text.len lost its pin on app/rec.cpp:7: [${USES6:-no row}]"
fi

# (q7) the tombstone survives in both record orders: no StringSource/StringSink contents_.size() narrows to Slice::size
for caller in '0/pipe.h::StringSink::drained#' 'a/log_test.cc::StringSource::left#' 'b/testutil.h::StringSource::used#' 'c/sink.cc::StringSink::filled#'; do
    M7="$( qMechs "$TMP/q4.tsv" "$caller" )"
    [ "$M7" != "receiver-rule" ] \
        && ok "(q7) tombstone: $caller contents_.size() is not narrowed (mech=[${M7:-declined}]) — same-named classes, contents_ typed std::string vs Slice&" \
        || no "(q7) tombstone lost: $caller contents_.size() narrowed by receiver-rule — the std field no longer tombstones StringSource/StringSink#contents_"
done

# (q8) determinism + cache transparency on the std fixture: the written scope rides the cached compose record
"$BIN" "$FIX3" --no-cache --pin-census="$TMP/q3b.tsv" >/dev/null 2>&1
rm -f "$TMP/qc"
"$BIN" "$FIX3" --cache="$TMP/qc" >/dev/null 2>&1
"$BIN" "$FIX3" --cache="$TMP/qc" --pin-census="$TMP/q3w.tsv" >/dev/null 2>&1
if [ -s "$TMP/q3.tsv" ] && cmp -s "$TMP/q3.tsv" "$TMP/q3b.tsv" && cmp -s "$TMP/q3.tsv" "$TMP/q3w.tsv"; then
    ok "(q8) stdfix census byte-identical: cold, cold again, and warm"
else
    no "(q8) stdfix census differs across runs or warm vs cold"; diff "$TMP/q3.tsv" "$TMP/q3w.tsv" | head -6
fi

# ── (t) a base or member type reached through a C++ TYPE ALIAS (2026-09-17) — an EXTRACTION change like (q). The base walk
#        keys classes by name, and an alias names no class: `class CGBuilderTy : public CGBuilderBaseTy` where
#        `typedef llvm::IRBuilder<…> CGBuilderBaseTy;` dead-ended at CGBuilderBaseTy, so a member `CGBuilderTy Builder;` never
#        reached IRBuilderBase::CreateCall (llvm-project clang/lib/CodeGen, ~1,700 sites). The capture now records a plain
#        alias's target class and the walk continues there: a namespace-scope typedef base (t1), a class-scope typedef member
#        type (t2), a class-scope `using` (t3), a namespace-qualified target (t4). (t5) a target written in `std` is refused
#        like a std:: field type (arm q) — an in-repo `vector` is not std::vector. (t6) the alias is not an inheritance or
#        HAS-A fact: no --lego implementor, no role="extends" use-site, no <compose> row. (t7) presence; (t8) warm == cold.
#        (t9) an alias NAMED like a real class elsewhere is not followed: the graph keys classes by bare name, so `using Base =
#        IRBuilder<int>;` inside one class would hand IRBase::CreateMul to Kid : Base, whose real Base defines nothing. (t10) an
#        alias local to a function body records nothing — it types no member, and the name graph has no scope to keep it local.
#        (t11) KNOWN FLOOR (independent review of #280): an alias records its target's class NAME without template arguments, so
#        `typedef SubT<marks> subtree;` — `marks` the enclosing template's own parameter — walks to the primary SubT::is_null
#        ALONE and drops the explicit specialization SubT<true>::is_null that the dependent argument can also select (rocksdb
#        omt_impl.h, subtree_templated<true>). A lost candidate, never a wrong-class pin; main split over both. The control
#        `typedef SubT<false> subtree;` names the primary, so its narrow is right.
#        The Decoy methods in decoy/ keep every unfixed answer a split, never an accidental receiver-rule pin. ──
FIX5="$TMP/aliasfix"
mkdir -p "$FIX5/ir" "$FIX5/decoy" "$FIX5/app"
cat >"$FIX5/ir/ir.h" <<'EOF'
struct IRBase { int CreateMul( int a ) { return a; } };
template <typename F> struct IRBuilder : IRBase { };
namespace ir { struct QBase { int Flush() { return 1; } }; }
EOF
cat >"$FIX5/decoy/other.h" <<'EOF'
struct Decoy { int CreateMul( int a ) { return a + 1; } int Flush() { return 2; } int size() { return 3; } };
struct vector { int size() { return 4; } };
EOF
cat >"$FIX5/app/owners.h" <<'EOF'
typedef IRBuilder<int> BaseTy;
struct CGB : public BaseTy { int CreateStore( int a ) { return a; } };
struct Owner1 { CGB Builder; int run() { return Builder.CreateMul( 1 ); } };
struct Owner2 { typedef IRBuilder<int> BuilderType; BuilderType Builder; int run() { return Builder.CreateMul( 2 ); } };
struct Owner3 { using BuilderTy = IRBuilder<int>; BuilderTy Builder; int run() { return Builder.CreateMul( 3 ); } };
typedef ir::QBase QAlias;
struct Owner4 { QAlias Q; int run() { return Q.Flush(); } };
using Vec = std::vector<int>;
struct Owner5 { Vec V; int run() { return V.size(); } };
struct Holder9 { using Base = IRBuilder<int>; };
struct Kid : Base { };
struct Owner9 { Kid K; int run() { return K.CreateMul( 9 ); } };
inline int localAlias() { using KidBase = IRBuilder<int>; return 0; }
struct Kid10 : KidBase { };
struct Owner10 { Kid10 K; int run() { return K.CreateMul( 10 ); } };
EOF
cat >"$FIX5/decoy/base.h" <<'EOF'
struct Base { int unrelated() { return 5; } };
EOF
"$BIN" "$FIX5" --no-cache --pin-census="$TMP/t.tsv" >/dev/null 2>&1
tRow(){ awk -F '\t' -v c="app/owners.h::$1::run#" -v n="$2" '$1 == "C" && index( $6, c ) == 1 && $7 == n { print $2 "|" $8 }' "$TMP/t.tsv" 2>/dev/null; }
tMissing=""
for want in '::Owner1::run#' '::Owner2::run#' '::Owner3::run#' '::Owner4::run#' '::Owner5::run#' '::Owner9::run#' '::Owner10::run#' 'dispositions calls=7 '; do
    qHas "$TMP/t.tsv" "$want" || tMissing="$tMissing [$want]"
done
[ -z "$tMissing" ] && ok "(t7) presence: the alias census names every Owner::run and counts all seven calls" \
    || no "(t7) presence guard:$tMissing — every (t) arm below would be vacuous"
for arm in 'Owner9 t9 an alias named like the real class Base (using Base = IRBuilder<int> inside Holder9)' \
           'Owner10 t10 a function-local alias (using KidBase = IRBuilder<int> inside localAlias)'; do
    set -- $arm; owner="$1"; label="$2"; shift 2; what="$*"
    R="$( tRow "$owner" CreateMul )"
    case "$R" in
        "receiver-rule|ir/ir.h::IRBase::CreateMul#"*) no "($label) $owner::run -> CreateMul pinned to IRBase::CreateMul through $what: [$R]" ;;
        *) ok "($label) $owner::run -> CreateMul is not pinned through $what: [${R:-no row}]" ;;
    esac
done
for arm in 'Owner1 CreateMul ir/ir.h::IRBase::CreateMul# t1 a namespace-scope typedef base (CGB : BaseTy, typedef IRBuilder<int> BaseTy)' \
           'Owner2 CreateMul ir/ir.h::IRBase::CreateMul# t2 a class-scope typedef member type (BuilderType Builder)' \
           'Owner3 CreateMul ir/ir.h::IRBase::CreateMul# t3 a class-scope using alias member type (BuilderTy Builder)' \
           'Owner4 Flush ir/ir.h::QBase::Flush# t4 a namespace-qualified alias target (typedef ir::QBase QAlias)'; do
    set -- $arm; owner="$1"; callee="$2"; want="$3"; label="$4"; shift 4; what="$*"
    R="$( tRow "$owner" "$callee" )"
    case "$R" in
        "receiver-rule|$want"*'|'*) no "($label) $owner::run -> $callee names more than the aliased class's method: [$R]" ;;
        "receiver-rule|$want"[0-9]*) ok "($label) $owner::run -> $callee narrows through $what: [$R]" ;;
        *) no "($label) $owner::run -> $callee does not reach ${want%#} through $what: [${R:-no row}]" ;;
    esac
done
T5="$( tRow Owner5 size )"
case "$T5" in
    "receiver-rule|decoy/other.h::vector::size#"*) no "(t5) Owner5::run -> V.size() pinned to the in-repo vector::size through using Vec = std::vector<int>: [$T5]" ;;
    *) ok "(t5) a std:: alias target names no in-repo class: Owner5::run -> V.size() is not pinned to vector::size [${T5:-no row}]" ;;
esac
FIX6="$TMP/aliasspecfix"
mkdir -p "$FIX6/lib" "$FIX6/decoy"
cat >"$FIX6/lib/sub.h" <<'EOF'
template <bool marks> struct SubT { int is_null() const { return 0; } };
template <> struct SubT<true> { int is_null() const { return 1; } };
EOF
cat >"$FIX6/lib/tree.h" <<'EOF'
template <typename D, bool marks> class Tree { typedef SubT<marks> subtree; subtree root; int f() { return root.is_null(); } };
struct Plain { typedef SubT<false> subtree; subtree root; int g() { return root.is_null(); } };
EOF
cat >"$FIX6/decoy/other.h" <<'EOF'
struct Other { int is_null() const { return 7; } };
EOF
"$BIN" "$FIX6" --no-cache --pin-census="$TMP/t11.tsv" >/dev/null 2>&1
t11Row(){ awk -F '\t' -v c="lib/tree.h::$1#" '$1 == "C" && index( $6, c ) == 1 && $7 == "is_null" { print $2 "|" $8 }' "$TMP/t11.tsv" 2>/dev/null; }
T11="$( t11Row Tree::f )"
case "$T11" in
    "receiver-rule|lib/sub.h::SubT::is_null#"[0-9]*) case "$T11" in *'|'*'|'*) T11MOVED=1 ;; *) T11MOVED=0 ;; esac ;;
    *) T11MOVED=1 ;;
esac
[ "$T11MOVED" = 0 ] \
    && ok "(t11) KNOWN FLOOR: typedef SubT<marks> (a dependent argument) narrows to the primary SubT::is_null alone and drops SubT<true>::is_null — a lost candidate, not a wrong pin: [$T11]" \
    || no "(t11) KNOWN FLOOR MOVED: Tree::f -> root.is_null() is no longer the primary alone: [${T11:-no row}] — if it now includes SubT<true>::is_null (and nothing else), rewrite this arm to assert that split"
T11C="$( t11Row Plain::g )"
case "$T11C" in
    "receiver-rule|lib/sub.h::SubT::is_null#"*'|'*) no "(t11) control: typedef SubT<false> names more than the primary: [$T11C]" ;;
    "receiver-rule|lib/sub.h::SubT::is_null#"[0-9]*) ok "(t11) control: typedef SubT<false> (a concrete argument) narrows to the primary SubT::is_null, which it names: [$T11C]" ;;
    *) no "(t11) control: Plain::g -> root.is_null() lost its narrow to SubT::is_null: [${T11C:-no row}]" ;;
esac
LEGO="$( "$BIN" "$FIX5" --lego=IRBuilder --no-cache 2>/dev/null )"
printf '%s' "$LEGO" | grep -qE '<impl n="(BaseTy|BuilderType|BuilderTy)"' \
    && no "(t6) --lego=IRBuilder lists an ALIAS as an implementor: $( printf '%s' "$LEGO" | grep -oE '<impl [^>]*>' | tr '\n' ' ' )" \
    || ok "(t6) --lego=IRBuilder lists no alias as an implementor"
USEST="$( "$BIN" "$FIX5" --uses=IRBuilder --no-cache 2>/dev/null )"
TEXT="$( printf '%s' "$USEST" | grep -oE '<u [^>]*role="extends"[^>]*/>' | tr '\n' ' ' )"   # rows only: the legend itself spells role="extends"
[ -n "$TEXT" ] \
    && no "(t6) --uses=IRBuilder reports an alias as role=\"extends\": $TEXT" \
    || ok "(t6) --uses=IRBuilder has no role=\"extends\" row — an alias is not a base clause"
# the two probes above can fire: the base clause `CGB : public BaseTy` IS an extends row and a --lego implementor
"$BIN" "$FIX5" --uses=BaseTy --no-cache 2>/dev/null | grep -qE '<u [^>]*role="extends"[^>]*p="app/owners.h:2"' \
    && "$BIN" "$FIX5" --lego=BaseTy --no-cache 2>/dev/null | grep -qE '<impl n="CGB"' \
    && ok "(t6) control: --uses=BaseTy shows CGB's base clause as role=\"extends\" and --lego=BaseTy lists CGB — both probes are live" \
    || no "(t6) control: CGB's base clause is missing from --uses=BaseTy or --lego=BaseTy — the two no-alias probes above cannot fire"
TCOMP=""
for owner in Owner2 Owner3 BaseTy BuilderType BuilderTy QAlias Vec; do
    TCOMP="$TCOMP$( "$BIN" "$FIX5" --around="$owner" --no-cache 2>/dev/null | grep -o '<compose>.*</compose>' )"
done
printf '%s' "$TCOMP" | grep -qE 'name=""|rel="alias"' \
    && no "(t6) an alias record reached the HAS-A block: $TCOMP" \
    || ok "(t6) no alias record in any <compose> block (Owner2, Owner3 and the alias names)"
printf '%s' "$TCOMP" | grep -qF '<field name="Builder" type="BuilderType" owner="Owner2" rel="creates"/>' \
    && ok "(t6) control: HAS-A keeps Owner2 → BuilderType for its member Builder" \
    || no "(t6) control: HAS-A lost Owner2's member Builder: [${TCOMP:-no <compose> block}]"
rm -f "$TMP/tc"
"$BIN" "$FIX5" --cache="$TMP/tc" >/dev/null 2>&1
"$BIN" "$FIX5" --cache="$TMP/tc" --pin-census="$TMP/tw.tsv" >/dev/null 2>&1
[ -s "$TMP/t.tsv" ] && cmp -s "$TMP/t.tsv" "$TMP/tw.tsv" && ok "(t8) aliasfix census byte-identical warm and cold — the alias record rides the cache" \
    || { no "(t8) aliasfix census differs warm vs cold"; diff "$TMP/t.tsv" "$TMP/tw.tsv" | head -6; }

# ── KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md) — issue #59, on receivers whose type is CERTAIN ──
# A built-in method called on a LITERAL binds an unrelated, same-named, never-imported user function — with the
# graph's ambiguity gauge at zero, so the answer reads as confident. `"a-b".replace(…)` can only be
# String.prototype.replace; today it binds src/unrelated.ts's `export function replace`. The arms below assert
# TODAY's behaviour, so they PASS now. Flipping them is the acceptance test for the prompt: no edge into
# unrelated.ts, and the call still COUNTED (a named, disclosed disposition — never a silent drop). A FAIL on a
# KNOWN GAP arm means the gap moved: rewrite that arm to assert the fixed behaviour, never delete it.
# The two CONTROLS are not gaps. They are TRUE edges any fix must keep: a typed user-object receiver, and a
# literal receiver whose method the repo itself defines on String.prototype (a literal CAN reach user code).
# Separate corpora on purpose: (h)'s ambiguous=6 is counted over $FIX and must not move.
LIT="$TMP/tslitfix"; OBJ="$TMP/tsobjfix"
mkdir -p "$LIT/src" "$OBJ/src"
cat >"$LIT/src/literals.ts" <<'EOF'
export function viaString(): string { return "a-b".replace(/-/g, " "); }
export function viaChain(): string[] { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n: number): string { return `n=${n}`.padStart(8); }
export function viaArray(): number[] { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s: string): boolean { return /x/.test(s); }
EOF
cat >"$LIT/src/unrelated.ts" <<'EOF'
export function replace(value: number): number { return value; }
export function split(value: number): number { return value; }
export function padStart(value: number): number { return value; }
export function map(value: number): number { return value; }
export function test(value: number): number { return value; }
EOF
cat >"$OBJ/src/rewriter.ts" <<'EOF'
export class Rewriter {
  replace(a: string, b: string): string { return a + b; }
}
EOF
cat >"$OBJ/src/user.ts" <<'EOF'
import { Rewriter } from "./rewriter";
export function viaObjectReceiver(r: Rewriter): string { return r.replace("a", "b"); }
EOF
cat >"$OBJ/src/proto.js" <<'EOF'
String.prototype.shout = function () { return "!"; };
function viaPrototypeExtension() { return "x".shout(); }
module.exports = { viaPrototypeExtension };
EOF
LITMAP="$( "$BIN" "$LIT" --no-cache 2>/dev/null )"
litMissing=""
for want in viaString viaChain viaTemplate viaArray viaRegex replace split padStart map test; do
    printf '%s' "$LITMAP" | grep -q "n=\"$want\"" || litMissing="$litMissing $want"
done
[ -z "$litMissing" ] && ok "(kg-ts) presence: every literal-receiver fixture symbol is indexed" \
    || no "(kg-ts) presence guard: fixture symbols not indexed:$litMissing — every arm below would be vacuous"
litGap(){  # litGap CALLER "LINE:NAME ..." — CALLER's literal-receiver calls each bind unrelated.ts:LINE, gauge at zero
    local out root want line name missed=""
    out="$( "$BIN" "$LIT" "--callees=src/literals.ts:$1" --no-cache 2>/dev/null )"
    root="$( printf '%s' "$out" | grep -oE '<callees [^>]*>' | head -1 )"
    if [ -z "$root" ]; then
        no "(kg-ts) $1: no <callees> root — the arm cannot observe the gap"; return
    fi
    for want in $2; do
        line="${want%%:*}"; name="${want#*:}"
        printf '%s' "$out" | grep -q "n=\"$name\" p=\"src/unrelated.ts:$line\"" || missed="$missed .$name()"
    done
    if [ -z "$missed" ] && printf '%s' "$root" | grep -q 'graph_ambiguous="0"'; then
        ok "KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md): $1's literal-receiver call(s) bind unrelated.ts ($2) with graph_ambiguous=\"0\" — flipping this is the acceptance test"
    else
        no "KNOWN GAP (help wanted: prompts/help-wanted/ts-literal-receivers.md) MOVED for $1:${missed:- the gauge} no longer binds unrelated.ts confidently — if the fix landed, rewrite this arm to assert no edge AND a counted disposition: $root"
    fi
}
litGap viaString   "1:replace"
litGap viaChain    "1:replace 2:split"
litGap viaTemplate "3:padStart"
litGap viaArray    "4:map"
litGap viaRegex    "5:test"
OBJOUT="$( "$BIN" "$OBJ" --callees=src/user.ts:viaObjectReceiver --no-cache 2>/dev/null )"
printf '%s' "$OBJOUT" | grep -q 'n="replace" p="src/rewriter.ts:2"' \
    && ok "(kg-ts control) a typed user-object receiver r.replace() keeps its edge to Rewriter.replace (rewriter.ts:2)" \
    || no "(kg-ts control) viaObjectReceiver lost its edge to Rewriter.replace — a literal-receiver rule over-reached: $( printf '%s' "$OBJOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
PROTOOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaPrototypeExtension --no-cache 2>/dev/null )"
printf '%s' "$PROTOOUT" | grep -q 'n="shout" p="src/proto.js:1"' \
    && ok "(kg-ts control) \"x\".shout() keeps its edge to the repo's own String.prototype.shout (proto.js:1) — a literal receiver can reach user code" \
    || no "(kg-ts control) \"x\".shout() lost its edge to String.prototype.shout — a literal-receiver veto must let prototype extensions through: $( printf '%s' "$PROTOOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"

# ── (i) determinism — narrowed candidate order must be byte-stable run-to-run ──
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
diff -q "$TMP/m1" "$TMP/m2" >/dev/null && ok "(i) deterministic (fieldfix map byte-identical across two runs)" \
    || { no "(i) non-deterministic fieldfix map"; diff "$TMP/m1" "$TMP/m2" | head -6; }

# ── (j) cache transparency — field-type facts round-trip the incremental cache: warm == cold ──
rm -f "$TMP/cc"
"$BIN" "$FIX" --cache="$TMP/cc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/cc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null && ok "(j) cache-transparent (warm == cold)" \
    || { no "(j) cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
