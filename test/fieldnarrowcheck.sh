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
# arm t, 2026-09-17, is the second: a C++ typedef / using alias records its target class, kParserVer 112 — declared 105, assigned on integration/train-4).
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

# ── (u) a using-declaration names the base a member comes from (2026-09-17). C++ lookup stops at the first class that
#        declares the name, and `using Base::m;` declares it in the class itself. The type-side probe Rules 2b/2c and Rule 1's
#        base walk share (resolve.h methodOnTypeOrBases) never read it: a class with no `m` of its own went straight to its
#        bases, where two bases both defining `m` REFUSE — clang's CGNonTrivialStruct.cpp writes `using
#        StructVisitor<Derived>::asDerived;` for exactly that tie, and its five asDerived() calls split across unrelated
#        classes. Now the using-declaration answers: (u2) through a field, (u3) through Rule 1's bare call, (u5) with the
#        qualifier's template arguments stripped. (u4) is the contrast: UTie differs from UPick ONLY by the using line.
#        (u6) is the floor for a re-export the index cannot reach: ExtBase is not in the tree, so the unchanged walk runs.
#        (u1) is the DECIDED floor: a class that also defines `m` answers its own definitions alone, though C++ adds the
#        re-exported base overloads to the same set. That union was built and graded net-worse against source (17 sites on
#        rocksdb + llvm-project: 5 better, 4 same, 8 worse — resolve.h ownMethodSet says why); flipping (u1) needs that
#        measurement redone, not this arm deleted. Separate corpus: (h)'s ambiguous= gauge is counted over $FIX.
#        LINE NUMBERS in u.cpp are asserted below. ──
FIX5="$TMP/usingfix"
mkdir -p "$FIX5"
cat >"$FIX5/u.cpp" <<'EOF'
struct UBase { void emit( int a ) { } void emit( double d ) { } };
struct UDecoy { void emit( int a ) { } };
struct UDerived : UBase {
    using UBase::emit;
    void emit( const char* s ) { }
};
struct UB1 { void dual() { } };
struct UB2 { void dual() { } };
struct UPick : UB1, UB2 { using UB1::dual; void selfPick() { dual(); } };
struct UTie : UB1, UB2 { void selfTie() { dual(); } };
struct UExt : ExtBase, UB1, UB2 { using ExtBase::dual; };
template <typename T> struct UTB { void grab( T t ) { } };
struct UTC { void grab( int t ) { } };
struct UTD : UTB<int>, UTC { using UTB<int>::grab; };
struct UOwner {
    UDerived m_d;
    UPick    m_k;
    UTie     m_i;
    UExt     m_e;
    UTD      m_t;
    void viaReexport() { m_d.emit( 1 ); }
    void viaPick()     { m_k.dual(); }
    void viaTie()      { m_i.dual(); }
    void viaExt()      { m_e.dual(); }
    void viaTemplate() { m_t.grab( 1 ); }
};
EOF
"$BIN" "$FIX5" --no-cache --pin-census="$TMP/u.tsv" >/dev/null 2>&1
UTSV="$TMP/u.tsv"   # the census uRow reads; (u8)/(u9) point it at their own corpus
uRow(){  # uRow CLASS::METHOD LINE — "mech/flags|targets": that caller's census row in $UTSV at LINE, target ids without #NODEID, sorted ("" = no row)
    local rows
    rows="$( awk -F '\t' -v c="::$1#" -v l="$2" '$1 == "C" && index( $6, c ) && $9 == l { print $2 "/" $5; n = split( $8, t, "|" ); for( i = 1; i <= n; ++i ) { sub( /#[0-9]+$/, "", t[ i ] ); print t[ i ] } }' "$UTSV" 2>/dev/null )"
    [ -n "$rows" ] || return 0
    printf '%s|%s' "$( printf '%s\n' "$rows" | head -1 )" "$( printf '%s\n' "$rows" | tail -n +2 | sort | paste -sd , - )"
}
uMissing=""
for want in '::UOwner::viaReexport#' '::UOwner::viaPick#' '::UOwner::viaTie#' '::UOwner::viaExt#' '::UOwner::viaTemplate#' '::UPick::selfPick#' '::UTie::selfTie#' 'dispositions calls=7 '; do
    grep -qF "$want" "$TMP/u.tsv" 2>/dev/null || uMissing="$uMissing [$want]"
done
for site in 'emit|p="u.cpp:4" in_id="u.cpp::UDerived::UDerived"' 'dual|p="u.cpp:9" in_id="u.cpp::UPick::UPick"' 'dual|p="u.cpp:11" in_id="u.cpp::UExt::UExt"' 'grab|p="u.cpp:14" in_id="u.cpp::UTD::UTD"'; do
    "$BIN" "$FIX5" "--uses=${site%%|*}" --no-cache 2>/dev/null | grep -qF "<u role=\"import\" ${site#*|}/>" \
        || uMissing="$uMissing [--uses=${site%%|*} has no import row ${site#*|}]"
done
[ -z "$uMissing" ] && ok "(u0) presence: the census names all 7 callers and counts 7 calls, and all four using-declarations are indexed import sites of their class" \
    || no "(u0) presence guard:$uMissing — every (u) arm below would be vacuous"
uExpect(){  # uExpect ARM CLASS::METHOD LINE WANT WHAT — that caller's row must be exactly WANT
    local got; got="$( uRow "$2" "$3" )"
    if [ "$got" = "$4" ]; then
        ok "($1) $5: [$got]"
    else
        no "($1) $5 — expected [$4], got [${got:-no row}]"
    fi
}
uExpect u1 UOwner::viaReexport 21 'receiver-rule/r|u.cpp::UDerived::emit' \
    "decided floor: m_d.emit( 1 ) on UDerived (own emit + using UBase::emit) keeps UDerived's own emit — the union graded net-worse"
uExpect u2 UOwner::viaPick 22 'receiver-rule/r|u.cpp::UB1::dual' \
    "m_k.dual() on UPick (no own dual, bases UB1 and UB2 both define it, using UB1::dual) pins UB1::dual through the field"
uExpect u3 UPick::selfPick 9 'receiver-rule/r|u.cpp::UB1::dual' \
    "bare dual() inside UPick pins UB1::dual through Rule 1's base walk"
uExpect u4 UOwner::viaTie 23 'split/-|u.cpp::UB1::dual,u.cpp::UB2::dual' \
    "control: m_i.dual() on UTie (the same two bases, NO using-declaration) keeps the refused tie's honest split"
uExpect u5 UOwner::viaTemplate 25 'receiver-rule/r|u.cpp::UTB::grab' \
    "m_t.grab( 1 ) on UTD (bases UTB<int> and UTC both define grab, using UTB<int>::grab) pins UTB::grab — the qualifier's template arguments are stripped"
uExpect u6 UOwner::viaExt 24 'split/-|u.cpp::UB1::dual,u.cpp::UB2::dual' \
    "floor: m_e.dual() on UExt (using ExtBase::dual, ExtBase not indexed) adds nothing and keeps the walk's split"
"$BIN" "$FIX5" --no-cache --pin-census="$TMP/u2.tsv" >/dev/null 2>&1
rm -f "$TMP/uc"
"$BIN" "$FIX5" --cache="$TMP/uc" >/dev/null 2>&1
"$BIN" "$FIX5" --cache="$TMP/uc" --pin-census="$TMP/uw.tsv" >/dev/null 2>&1
if [ -s "$TMP/u.tsv" ] && cmp -s "$TMP/u.tsv" "$TMP/u2.tsv" && cmp -s "$TMP/u.tsv" "$TMP/uw.tsv"; then
    ok "(u7) usingfix census byte-identical: cold, cold again, and warm (the re-export fact survives the cache)"
else
    no "(u7) usingfix census differs across runs or warm vs cold"; diff "$TMP/u.tsv" "$TMP/uw.tsv" | head -6
fi

# (u8) a using-declaration must name a BASE (review 2026-09-17). `using NotABase::m;` in a class that does not derive from
#      NotABase is ill-formed C++ — mid-refactor or partial input — and the first cut pinned NotABase::m alone through
#      receiver-rule, dropping the tie between the two real bases. A named class outside the class's base closure (chaUp)
#      is ignored, so the walk's refusal and the ladder's split stand exactly as on main. (u9) is the control that the
#      closure is transitive: `using GB::n;` names a GRAND-base and is honoured. Own corpus: the (u) line pins do not move.
FIX6="$TMP/usingbasefix"
mkdir -p "$FIX6"
cat >"$FIX6/v.cpp" <<'EOF'
struct RealBase1 { void m() { } };
struct RealBase2 { void m() { } };
struct NotABase { void m() { } };
struct FakeDerived : RealBase1, RealBase2 { using NotABase::m; };
struct GB { void n() { } };
struct Mid : GB { };
struct Mid2 { void n() { } };
struct Leaf : Mid, Mid2 { using GB::n; };
struct Holder {
    FakeDerived f_;
    Leaf        l_;
    void viaFake() { f_.m(); }
    void viaGrand() { l_.n(); }
};
EOF
"$BIN" "$FIX6" --no-cache --pin-census="$TMP/v.tsv" >/dev/null 2>&1
UTSV="$TMP/v.tsv"
if grep -qF '::Holder::viaFake#' "$UTSV" 2>/dev/null && grep -qF '::Holder::viaGrand#' "$UTSV" && grep -qF 'dispositions calls=2 ' "$UTSV" \
   && "$BIN" "$FIX6" --uses=m --no-cache 2>/dev/null | grep -qF '<u role="import" p="v.cpp:4" in_id="v.cpp::FakeDerived::FakeDerived"/>'; then
    ok "(u8/u9 presence) the census names both Holder callers and counts 2 calls, and FakeDerived's using-declaration is an indexed import site"
else
    no "(u8/u9 presence) usingbasefix fixture not observed — (u8)/(u9) would be vacuous"
fi
uExpect u8 Holder::viaFake 12 'split/-|v.cpp::NotABase::m,v.cpp::RealBase1::m,v.cpp::RealBase2::m' \
    "f_.m() on FakeDerived (bases RealBase1, RealBase2; using NotABase::m, NOT a base) ignores the using-declaration and keeps main's split"
uExpect u9 Holder::viaGrand 13 'receiver-rule/r|v.cpp::GB::n' \
    "control: l_.n() on Leaf (using GB::n, GB a base of its base Mid) honours the grand-base re-export"
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

# ── (r) prov="final-segment" reaches FIELD narrows (2026-09-17). Test/narrowcheck.sh arm 25 marks an edge that a parameter's
#        or local's QUALIFIED written type chose by its last name alone: that match never checked the qualifier against the
#        class's namespace, so the edge must not read as uniquely resolved. Rule 2b makes exactly the same guess for a field —
#        `store::Text body_; body_.size()` narrows on `Text` — and the field record carries the namespace it was written in
#        (arm q), so its edge is marked too. An UNQUALIFIED field narrow skipped no qualifier and stays unmarked, and a
#        `std::` field never narrows at all (arm q), so it has no edge to mark. ──
"$BIN" "$FIX3" --no-cache >"$TMP/r.map" 2>/dev/null
"$BIN" "$FIX3" --no-cache --legend=compact >"$TMP/r.compact" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/r.fix.map" 2>/dev/null
fieldProvOf(){   # MAP CALLER CALLEE — the prov= of CALLER's <c n="CALLEE"> edge: a word, "none" when absent, NO-EDGE when missing
    local row
    row="$( tr '<' '\n' <"$1" | awk -v c="$2" '$1 == "s" && index( $0, " n=\"" c "\"" ) { on = 1; next } $1 == "s" || $1 == "/s>" { on = 0 } on' )"
    row="$( printf '%s\n' "$row" | grep "^c n=\"$3\"" | head -1 )"
    if [ -z "$row" ]; then
        printf 'NO-EDGE'
    elif printf '%s' "$row" | grep -q ' prov="'; then
        printf '%s' "$row" | sed -n 's/.* prov="\([^"]*\)".*/\1/p'
    else
        printf 'none'
    fi
}
expectFieldProv(){   # LABEL MAP CALLER CALLEE WANT
    local got
    got="$( fieldProvOf "$2" "$3" "$4" )"
    if [ "$got" = "$5" ]; then
        ok "$1 $3() -> $4: prov=[$got]"
    else
        no "$1 $3() -> $4: prov=[$got], want [$5]"
    fi
}
expectFieldProv "(r1)" "$TMP/r.map" bodyLength size final-segment   # store::Text body_: a qualified field type's last name decided it
expectFieldProv "(r2)" "$TMP/r.map" nameLength size NO-EDGE         # std::string name_: refused (arm q), nothing to mark
expectFieldProv "(r3)" "$TMP/r.fix.map" run acquire none            # Pool m_pool: unqualified, no qualifier was skipped
# the narrow itself is unchanged — the mark is a disclosure, never a demotion: the census still names Rule 2b for it
R4="$( awk -F '\t' '$1 == "C" && index( $6, "::Record::bodyLength#" ) && $7 == "size" { print $2 "|" $8 }' "$TMP/q3.tsv" 2>/dev/null )"
case "$R4" in
    "receiver-rule|store/text.h::Text::size#"*) ok "(r4) the marked narrow is still Rule 2b's single edge to store/text.h Text::size (census receiver-rule)" ;;
    *) no "(r4) the marked narrow changed its decision — the attribute must disclose, never demote: [${R4:-no row}]" ;;
esac
if grep -q 'final-segment' "$TMP/r.compact"; then
    ok "(r5) the compact legend defines prov=final-segment on the field fixture's map"
else
    no "(r5) the compact legend does not define prov=final-segment on a map whose field edge carries it"
fi

# ── (p) a member held by a std smart pointer (2026-09-17) — an EXTRACTION change, like (q). The field capture read a qualified
#        type only when a plain name sat directly under the `::`, and in `std::unique_ptr<Widget> w_;` that name is a template,
#        so the member recorded no type at all and every `w_->read()` took the bare-name split. `->` on a std::unique_ptr or
#        std::shared_ptr reaches the pointee, so the member now records the FIRST template argument, marked as reached through
#        `->` only, and the call carries whether it was written with `->`: `w_.reset()` is the smart pointer's own member, never
#        Widget::reset. No other template is read through: std::vector has no `->`, and an in-repo Holder<T> or util::Box<T> may
#        overload it to reach anything (p6). (p8) is the tombstone rule both new facts need: a same-named class whose same-named
#        member is typed differently — a std pointee, or the same class reached through `.` instead of `->` — refuses both.
#        LINE NUMBERS in app/owner.cpp are asserted below. ──
FIX5="$TMP/ptrfix"; FIX6="$TMP/ptrtomb"
mkdir -p "$FIX5/lib" "$FIX5/app" "$FIX6/0" "$FIX6/a" "$FIX6/b" "$FIX6/c" "$FIX6/d" "$FIX6/e" "$FIX6/f"
cat >"$FIX5/lib/widget.h" <<'EOF'
struct Widget { int read() { return 1; } void reset() { } int size() { return 2; } int level; };
struct Decoy { int read() { return 3; } void reset() { } int size() { return 4; } int level; };
template <class T> struct Holder { T* operator->() { return p; } T* p; };
namespace util { template <class T> struct Box { T* operator->() { return p; } T* p; }; }
namespace store { struct Blob { int read() { return 5; } }; }
EOF
cat >"$FIX5/app/owner.cpp" <<'EOF'
struct Owner {
    std::unique_ptr<Widget> w_;
    std::shared_ptr<Widget> s_;
    std::unique_ptr<store::Blob> bl_;
    std::vector<Widget> v_;
    Holder<Widget> h_;
    util::Box<Widget> b_;
    int viaUnique() { return w_->read(); }
    int viaShared() { return s_->read(); }
    int viaQualified() { return bl_->read(); }
    void resetPointee() { w_->reset(); }
    void resetOwner() { w_.reset(); }
    int viaVector() { return v_.size(); }
    int viaHolder() { return h_->read(); }
    int viaBox() { return b_->read(); }
    int levelUnique() { return w_->level; }
};
EOF
cat >"$FIX6/a/types.h" <<'EOF'
struct Slice { int size() const { return 2; } };
struct Other { int size() const { return 3; } };
struct Widget2 { int read() { return 1; } void reset() { } };
struct Decoy2 { int read() { return 2; } void reset() { } };
EOF
cat >"$FIX6/b/src.cc" <<'EOF'
struct Source { Slice* buf_; int left() { return buf_->size(); } };
EOF
cat >"$FIX6/c/src.h" <<'EOF'
struct Source { std::unique_ptr<std::string> buf_; int used() { return buf_->size(); } };
EOF
cat >"$FIX6/0/sink.h" <<'EOF'
struct Sink { std::shared_ptr<std::string> buf_; int drained() { return buf_->size(); } };
EOF
cat >"$FIX6/f/sink.cc" <<'EOF'
struct Sink { Slice* buf_; int filled() { return buf_->size(); } };
EOF
cat >"$FIX6/d/keep.h" <<'EOF'
struct Keeper { Widget2 w_; int byValue() { return w_.read(); } };
struct Minder { std::unique_ptr<Widget2> w_; void dropOwned() { w_.reset(); } };
EOF
cat >"$FIX6/e/keep.h" <<'EOF'
struct Keeper { std::unique_ptr<Widget2> w_; void dropHeld() { w_.reset(); } };
struct Minder { Widget2 w_; int byValue2() { return w_.read(); } };
EOF
"$BIN" "$FIX5" --no-cache --pin-census="$TMP/p5.tsv" >/dev/null 2>&1
"$BIN" "$FIX6" --no-cache --pin-census="$TMP/p6.tsv" >/dev/null 2>&1
pRows(){  # pRows TSV CALLER CALLEE — "mech|targets" for each of CALLER's CALLEE census rows ("" = no row: declined)
    awk -F '\t' -v c="$2" -v n="$3" '$1 == "C" && index( $6, c ) && $7 == n { print $2 "|" $8 }' "$1" 2>/dev/null
}
pMissing=""
for want in '::Owner::viaUnique#' '::Owner::resetOwner#' '::Owner::viaBox#' '::Owner::levelUnique#' 'dispositions calls=8 '; do
    qHas "$TMP/p5.tsv" "$want" || pMissing="$pMissing [ptrfix $want]"
done
for want in 'c/src.h::Source::used#' '0/sink.h::Sink::drained#' 'e/keep.h::Keeper::dropHeld#' 'd/keep.h::Minder::dropOwned#' 'dispositions calls=8 '; do
    qHas "$TMP/p6.tsv" "$want" || pMissing="$pMissing [ptrtomb $want]"
done
[ -z "$pMissing" ] && ok "(p0) presence: both census files name every fixture caller and count every call" \
    || no "(p0) presence guard:$pMissing — every (p) arm below would be vacuous"

# (p1)-(p4) the defect: a call through the pointer narrows to the pointee's own member, the pointee written plain or qualified
pPinned(){  # pPinned ARM CALLER CALLEE TARGET-ERE WHAT
    local got; got="$( pRows "$TMP/p5.tsv" "$2" "$3" )"
    if printf '%s\n' "$got" | grep -qE "^receiver-rule\\|$4#[0-9]+\$"; then
        ok "($1) $5 narrows to the pointee's member (receiver-rule)"
    else
        no "($1) $5 did not narrow to the pointee's member: [${got:-no row}]"
    fi
}
pPinned p1 '::Owner::viaUnique#'    read  'lib/widget\.h::Widget::read'  'std::unique_ptr<Widget> w_; w_->read()'
pPinned p2 '::Owner::viaShared#'    read  'lib/widget\.h::Widget::read'  'std::shared_ptr<Widget> s_; s_->read()'
pPinned p3 '::Owner::viaQualified#' read  'lib/widget\.h::Blob::read'    'std::unique_ptr<store::Blob> bl_; bl_->read()'
pPinned p4 '::Owner::resetPointee#' reset 'lib/widget\.h::Widget::reset' 'std::unique_ptr<Widget> w_; w_->reset()'

# (p5) `.` reaches the smart pointer itself; (p6) no other template is read through, std or in-repo
pNotPinned(){  # pNotPinned ARM TSV CALLER CALLEE TARGET-ERE WHAT
    local got; got="$( pRows "$2" "$3" "$4" )"
    if printf '%s\n' "$got" | grep -qE "^receiver-rule\\|$5#[0-9]+\$"; then
        no "($1) $6 was narrowed by the field's type: [$got]"
    else
        ok "($1) $6 is not narrowed by the field's type: [${got:-no row}]"
    fi
}
pNotPinned p5 "$TMP/p5.tsv" '::Owner::resetOwner#' reset 'lib/widget\.h::Widget::reset' "std::unique_ptr<Widget> w_; w_.reset() — the smart pointer's own reset"
pNotPinned p6 "$TMP/p5.tsv" '::Owner::viaVector#'  size  'lib/widget\.h::Widget::size'  'control: std::vector<Widget> v_; v_.size()'
pNotPinned p6 "$TMP/p5.tsv" '::Owner::viaHolder#'  read  'lib/widget\.h::Widget::read'  'control: in-repo Holder<Widget> h_; h_->read()'
pNotPinned p6 "$TMP/p5.tsv" '::Owner::viaBox#'     read  'lib/widget\.h::Widget::read'  'control: in-repo util::Box<Widget> b_; b_->read()'

# (p7) the member index reads the same record: `w_->level` is Widget's level, and no longer every owner's
USES7="$( "$BIN" "$FIX5" --uses=Widget.level --no-cache 2>/dev/null | grep -oE '<u [^>]*p="app/owner.cpp:16"[^>]*/>' )"
if [ -n "$USES7" ] && ! printf '%s' "$USES7" | grep -q 'owner_candidates='; then
    ok "(p7) --uses=Widget.level pins w_->level (app/owner.cpp:16) through the unique_ptr"
else
    no "(p7) --uses=Widget.level does not pin w_->level (app/owner.cpp:16): [${USES7:-no row}]"
fi
DECOY7="$( "$BIN" "$FIX5" --uses=Decoy.level --no-cache 2>/dev/null | grep -oE '<u [^>]*p="app/owner.cpp:16"[^>]*/>' )"
if [ -z "$DECOY7" ] || printf '%s' "$DECOY7" | grep -q 'owner_candidates='; then
    ok "(p7) control: --uses=Decoy.level does not pin app/owner.cpp:16: [${DECOY7:-no row}]"
else
    no "(p7) control: --uses=Decoy.level PINS w_->level (app/owner.cpp:16): $DECOY7"
fi

# (p8) tombstones, each collision in both record orders: a std pointee (std::string) against Slice*, and the same
#      class reached through `->` against `.` — a `.reset()` that took the value member's type would bind Widget2::reset
pNotPinned p8 "$TMP/p6.tsv" 'c/src.h::Source::used#'      size  'a/types\.h::Slice::size'    'std::unique_ptr<std::string> buf_ (sorts after Source'"'"'s Slice* buf_); buf_->size()'
pNotPinned p8 "$TMP/p6.tsv" '0/sink.h::Sink::drained#'    size  'a/types\.h::Slice::size'    'std::shared_ptr<std::string> buf_ (sorts before Sink'"'"'s Slice* buf_); buf_->size()'
pNotPinned p8 "$TMP/p6.tsv" 'e/keep.h::Keeper::dropHeld#' reset 'a/types\.h::Widget2::reset' 'std::unique_ptr<Widget2> w_ (after Keeper'"'"'s Widget2 w_); w_.reset()'
pNotPinned p8 "$TMP/p6.tsv" 'd/keep.h::Minder::dropOwned#' reset 'a/types\.h::Widget2::reset' 'std::unique_ptr<Widget2> w_ (before Minder'"'"'s Widget2 w_); w_.reset()'

# (p9) determinism + cache transparency: the pointee fact and the call's `->` both ride the cached records
"$BIN" "$FIX5" --no-cache --pin-census="$TMP/p5b.tsv" >/dev/null 2>&1
rm -f "$TMP/pc"
"$BIN" "$FIX5" --cache="$TMP/pc" >/dev/null 2>&1
"$BIN" "$FIX5" --cache="$TMP/pc" --pin-census="$TMP/p5w.tsv" >/dev/null 2>&1
if [ -s "$TMP/p5.tsv" ] && cmp -s "$TMP/p5.tsv" "$TMP/p5b.tsv" && cmp -s "$TMP/p5.tsv" "$TMP/p5w.tsv" \
   && pRows "$TMP/p5w.tsv" '::Owner::viaUnique#' read | grep -qE '^receiver-rule\|lib/widget\.h::Widget::read#[0-9]+$'; then
    ok "(p9) ptrfix census byte-identical cold, cold again and warm, and the warm run still narrows w_->read()"
else
    no "(p9) ptrfix census differs across runs or warm vs cold, or the warm run lost w_->read()'s narrow"; diff "$TMP/p5.tsv" "$TMP/p5w.tsv" | head -6
fi

# ── TS/JS literal receivers (issue #163, first step on #59) ──
# A built-in method on a LITERAL must not bind an unrelated same-named user function. Covered calls
# (replace/split/padStart/map/test/toFixed/toString/join) go External; a builtin name with NO in-repo
# def (charCodeAt) is Undefined, not external=. A name that is NOT a member of the literal's type
# keeps today's ladder. RED on a pre-change binary. Separate corpora: (h)'s ambiguous=7 is over $FIX.
LIT="$TMP/tslitfix"; OBJ="$TMP/tsobjfix"; JSLIT="$TMP/jslitfix"; TSLIT="$TMP/tsxlitfix"; CTRL="$TMP/tsctrlfix"; POLY="$TMP/jspolyfix"
mkdir -p "$LIT/src" "$OBJ/src" "$JSLIT/src" "$TSLIT/src" "$CTRL/src" "$POLY"
cat >"$LIT/src/literals.ts" <<'EOF'
export function viaString(): string { return "a-b".replace(/-/g, " "); }
export function viaChain(): string[] { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n: number): string { return `n=${n}`.padStart(8); }
export function viaArray(): number[] { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s: string): boolean { return /x/.test(s); }
export function viaNumber(): string { return (1).toFixed(0); }
export function viaNegative(): string { return (-1).toFixed(0); }
export function viaPositive(): string { return (+2).toFixed(0); }
export function viaBoolean(): string { return true.toString(); }
export function viaJoin(): string { return "a b".split(" ").join("-"); }
export function viaCharCode(): number { return "x".charCodeAt(0); }
EOF
cat >"$LIT/src/unrelated.ts" <<'EOF'
export function replace(value: number): number { return value; }
export function split(value: number): number { return value; }
export function padStart(value: number): number { return value; }
export function map(value: number): number { return value; }
export function test(value: number): number { return value; }
export function toFixed(value: number): number { return value; }
export function toString(value: number): number { return value; }
export function join(value: number): number { return value; }
EOF
cat >"$JSLIT/src/literals.js" <<'EOF'
export function viaString() { return "a-b".replace(/-/g, " "); }
export function viaChain() { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n) { return `n=${n}`.padStart(8); }
export function viaArray() { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s) { return /x/.test(s); }
export function viaNumber() { return (1).toFixed(0); }
export function viaNegative() { return (-1).toFixed(0); }
export function viaPositive() { return (+2).toFixed(0); }
export function viaBoolean() { return true.toString(); }
export function viaJoin() { return "a b".split(" ").join("-"); }
export function viaCharCode() { return "x".charCodeAt(0); }
EOF
cat >"$JSLIT/src/unrelated.js" <<'EOF'
export function replace(value) { return value; }
export function split(value) { return value; }
export function padStart(value) { return value; }
export function map(value) { return value; }
export function test(value) { return value; }
export function toFixed(value) { return value; }
export function toString(value) { return value; }
export function join(value) { return value; }
EOF
cat >"$TSLIT/src/literals.tsx" <<'EOF'
export function viaString(): string { return "a-b".replace(/-/g, " "); }
export function viaChain(): string[] { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n: number): string { return `n=${n}`.padStart(8); }
export function viaArray(): number[] { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s: string): boolean { return /x/.test(s); }
export function viaNumber(): string { return (1).toFixed(0); }
export function viaNegative(): string { return (-1).toFixed(0); }
export function viaPositive(): string { return (+2).toFixed(0); }
export function viaBoolean(): string { return true.toString(); }
export function viaJoin(): string { return "a b".split(" ").join("-"); }
export function viaCharCode(): number { return "x".charCodeAt(0); }
EOF
cat >"$TSLIT/src/unrelated.ts" <<'EOF'
export function replace(value: number): number { return value; }
export function split(value: number): number { return value; }
export function padStart(value: number): number { return value; }
export function map(value: number): number { return value; }
export function test(value: number): number { return value; }
export function toFixed(value: number): number { return value; }
export function toString(value: number): number { return value; }
export function join(value: number): number { return value; }
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
cat >"$CTRL/src/widget.ts" <<'EOF'
export class Widget { render(): string { return ""; } }
export function transform(): number { return 1; }
export function replace(a: string): string { return a; }
EOF
cat >"$CTRL/src/user.ts" <<'EOF'
import { Widget } from "./widget";
import * as helpers from "./widget";
export function viaOwnLiteral(): string { return ({ replace(a: string) { return a; } }).replace("q"); }
export function viaFindRender(): string { return [new Widget()].find(w => true)!.render(); }
export class AMD { replace(s: string) { return s; } apply() { this.replace("x"); } }
export function viaNs(): number { return helpers.transform(); }
export function viaCast(): string { return ("x" as unknown as Widget).render(); }
EOF
cat >"$OBJ/src/proto.js" <<'EOF'
String.prototype.shout = function () { return "!"; };
function viaPrototypeExtension() { return "x".shout(); }
String.prototype.namedX = function namedX() { return "!"; };
function viaNamedProto() { return "x".namedX(); }
Object.assign(Array.prototype, { last() { return this[this.length - 1]; } });
function viaAssign() { return [1, 2].last(); }
Object.defineProperty(String.prototype, "defx", { value: function defx() { return "!"; } });
function viaDefine() { return "x".defx(); }
module.exports = { viaPrototypeExtension, viaNamedProto, viaAssign, viaDefine };
EOF
cat >"$POLY/proto.js" <<'EOF'
String.prototype.replace = function () { return "p"; };
function viaPolyfill() { return "x".replace("a", "b"); }
module.exports = { viaPolyfill };
EOF
cat >"$CTRL/src/loud.ts" <<'EOF'
declare global { interface String { loud(): string } }
export function viaLoud(): string { return "x".loud(); }
EOF
LITMAP="$( "$BIN" "$LIT" --no-cache 2>/dev/null )"
litMissing=""
for want in viaString viaChain viaTemplate viaArray viaRegex viaNumber viaNegative viaPositive viaBoolean viaJoin viaCharCode replace split padStart map test toFixed toString join; do
    printf '%s' "$LITMAP" | grep -q "n=\"$want\"" || litMissing="$litMissing $want"
done
[ -z "$litMissing" ] && ok "(kg-ts) presence: every literal-receiver fixture symbol is indexed" \
    || no "(kg-ts) presence guard: fixture symbols not indexed:$litMissing — every arm below would be vacuous"
litExt(){  # litExt ROOT EXPECTED — exact external=N on the files= stats line (not a substring of 60–69)
    local map stats ext
    map="$( "$BIN" "$1" --no-cache 2>/dev/null )"
    stats="$( printf '%s' "$map" | grep -oE 'files=[0-9]+ symbols=[0-9]+ edges=[0-9]+[^<]*' | head -1 )"
    ext="$( printf '%s' "$stats" | grep -oE 'external=[0-9]+' | head -1 )"
    if [ "$ext" = "external=$2" ]; then
        ok "(kg-ts) $3 external=$2 ($stats)"
    else
        no "(kg-ts) $3 external= want $2 got '${ext:-absent}': $stats"
    fi
    printf '%s' "$stats" | grep -q 'ambiguous=0' \
        && ok "(kg-ts) $3 ambiguous=0" \
        || no "(kg-ts) $3 ambiguous= moved: $stats"
}
# 12 = the 10 covered builtin calls, plus (-1).toFixed() and (+2).toFixed(): a SIGNED numeric literal is a number
# receiver too (CodeRabbit on #277 — a unary +/- over a number used to classify as no literal at all and could bind
# the unrelated toFixed below).
litExt "$LIT"   12 "TS literal corpus"
litExt "$JSLIT" 12 "JS literal corpus"
litExt "$TSLIT" 12 "TSX literal corpus"
litFixed(){  # litFixed ROOT FILE CALLER — no edge into unrelated, count="0", gauge at zero
    local out root
    out="$( "$BIN" "$1" "--callees=$2:$3" --no-cache 2>/dev/null )"
    root="$( printf '%s' "$out" | grep -oE '<callees [^>]*>' | head -1 )"
    if [ -z "$root" ]; then
        no "(kg-ts) $3: no <callees> root"; return
    fi
    if printf '%s' "$out" | grep -q 'unrelated\.' ; then
        no "(kg-ts) $3 still binds unrelated: $root $( printf '%s' "$out" | grep -oE '<s [^>]*/>' | tr '\n' ' ' )"
    elif printf '%s' "$root" | grep -q 'count="0"' && printf '%s' "$root" | grep -q 'graph_ambiguous="0"'; then
        ok "(kg-ts) $3: no edge into unrelated, count=\"0\", graph_ambiguous=\"0\""
    else
        no "(kg-ts) $3 expected count=\"0\" graph_ambiguous=\"0\": $root"
    fi
}
for caller in viaString viaChain viaTemplate viaArray viaRegex viaNumber viaNegative viaPositive viaBoolean viaJoin viaCharCode; do
    litFixed "$LIT"   src/literals.ts  "$caller"
    litFixed "$JSLIT" src/literals.js  "$caller"
    litFixed "$TSLIT" src/literals.tsx "$caller"
done
OBJOUT="$( "$BIN" "$OBJ" --callees=src/user.ts:viaObjectReceiver --no-cache 2>/dev/null )"
printf '%s' "$OBJOUT" | grep -q 'n="replace" p="src/rewriter.ts:2"' \
    && ok "(kg-ts control) a typed user-object receiver r.replace() keeps its edge to Rewriter.replace (rewriter.ts:2)" \
    || no "(kg-ts control) viaObjectReceiver lost its edge to Rewriter.replace — a literal-receiver rule over-reached: $( printf '%s' "$OBJOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
PROTOOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaPrototypeExtension --no-cache 2>/dev/null )"
printf '%s' "$PROTOOUT" | grep -q 'n="shout" p="src/proto.js:1"' \
    && ok "(kg-ts control) \"x\".shout() keeps its edge to the repo's own String.prototype.shout (proto.js:1) — a literal receiver can reach user code" \
    || no "(kg-ts control) \"x\".shout() lost its edge to String.prototype.shout — a literal-receiver veto must let prototype extensions through: $( printf '%s' "$PROTOOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
NAMEDOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaNamedProto --no-cache 2>/dev/null )"
printf '%s' "$NAMEDOUT" | grep -q 'n="namedX"' \
    && ok "(kg-ts control) String.prototype.x = function x(){} keeps its edge (named function, not a String builtin)" \
    || no "(kg-ts control) viaNamedProto lost namedX: $( printf '%s' "$NAMEDOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
POLYOUT="$( "$BIN" "$POLY" --callees=viaPolyfill --no-cache 2>/dev/null )"
printf '%s' "$POLYOUT" | grep -q 'n="replace"' \
    && ok "(kg-ts control) JS String.prototype.replace polyfill binds (JS-only; TS has no protomethod capture)" \
    || no "(kg-ts control) viaPolyfill lost the JS replace polyfill: $( printf '%s' "$POLYOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
ASSIGNOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaAssign --no-cache 2>/dev/null )"
printf '%s' "$ASSIGNOUT" | grep -q 'n="last"' \
    && ok "(kg-ts control) Object.assign(Array.prototype, { last(){} }) keeps its edge" \
    || no "(kg-ts control) viaAssign lost last: $( printf '%s' "$ASSIGNOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
DEFOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaDefine --no-cache 2>/dev/null )"
printf '%s' "$DEFOUT" | grep -q 'n="defx"' \
    && ok "(kg-ts control) Object.defineProperty(String.prototype, 'x', { value: function x(){} }) keeps its edge" \
    || no "(kg-ts control) viaDefine lost defx: $( printf '%s' "$DEFOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
LOUDOUT="$( "$BIN" "$CTRL" --callees=src/loud.ts:viaLoud --no-cache 2>/dev/null )"
printf '%s' "$LOUDOUT" | grep -q 'n="loud"' \
    && ok "(kg-ts control) TS declare global { interface String { loud() } } keeps its edge" \
    || no "(kg-ts control) viaLoud lost loud: $( printf '%s' "$LOUDOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
OWNOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaOwnLiteral --no-cache 2>/dev/null )"
printf '%s' "$OWNOUT" | grep -q 'n="replace" p="src/user.ts:3"' \
    && ok "(kg-ts control) object-literal own method ({ replace(){} }).replace() keeps its edge" \
    || no "(kg-ts control) viaOwnLiteral lost the object-literal replace edge: $( printf '%s' "$OWNOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
FINDOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaFindRender --no-cache 2>/dev/null )"
printf '%s' "$FINDOUT" | grep -q 'n="render" p="src/widget.ts:1"' \
    && ok "(kg-ts control) [new Widget()].find(...)!.render() keeps Widget.render — certainty ends at find/!" \
    || no "(kg-ts control) viaFindRender lost Widget.render: $( printf '%s' "$FINDOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
THISOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:apply --no-cache 2>/dev/null )"
printf '%s' "$THISOUT" | grep -q 'n="replace" p="src/user.ts:5"' \
    && ok "(kg-ts control) this.replace() inside a class that defines replace keeps its edge" \
    || no "(kg-ts control) AMD.apply lost this.replace() at user.ts:5: $( printf '%s' "$THISOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
NSOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaNs --no-cache 2>/dev/null )"
printf '%s' "$NSOUT" | grep -q 'n="transform"' \
    && ok "(kg-ts control) helpers.transform() namespace import keeps its edge" \
    || no "(kg-ts control) viaNs lost helpers.transform(): $( printf '%s' "$NSOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
CASTOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaCast --no-cache 2>/dev/null )"
printf '%s' "$CASTOUT" | grep -q 'n="render" p="src/widget.ts:1"' \
    && ok "(kg-ts control) (\"x\" as unknown as Widget).render() keeps Widget.render — a cast ends certainty" \
    || no "(kg-ts control) viaCast lost Widget.render: $( printf '%s' "$CASTOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"

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

rm -f "$TMP/litcc"
"$BIN" "$LIT" --cache="$TMP/litcc" >/dev/null 2>&1
"$BIN" "$LIT" --cache="$TMP/litcc" >"$TMP/litwarm" 2>/dev/null
"$BIN" "$LIT" --no-cache           >"$TMP/litcold" 2>/dev/null
diff -q "$TMP/litwarm" "$TMP/litcold" >/dev/null && ok "(kg-ts) literal corpus warm == cold (Lit* kinds round-trip the cache)" \
    || { no "(kg-ts) literal corpus warm != cold"; diff "$TMP/litcold" "$TMP/litwarm" | head -6; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
