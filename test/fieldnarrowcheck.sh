#!/usr/bin/env bash
# fieldnarrowcheck.sh — gate for P2-D Rule 2b: FIELD-typed member narrowing (W1-P1-12).
#
# The gap this closes: a member call whose receiver is a bare FIELD of the enclosing class
# (`m_pool.acquire()` / `m_p->tune()` inside a method of Owner) used to resolve `acquire` by BARE NAME
# against every same-named definition in the corpus — inflating per-symbol `amb=` and the header
# `ambiguous=` gauge. Rule 2b: when the receiver names a field whose DECLARED TYPE is a type the index
# knows (the S5-E HAS-A field capture), narrow the candidate set to that type's members, walking direct
# bases (chaUp) when the type itself does not define the method. RESOLVE-stage only — no kParserVer bump.
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

# ── (h) the header gauge agrees with the arms above: exactly the 7 honest splits remain ambiguous
#        (expl, unk, freeuse, multi, shadowParam, po_go, to_go — run/ptr/inh_go narrowed, shadowLocal was Rule 2).
#        Counted from the fixture, not guessed: flip arms above before touching this number. ──
AMB="$( printf '%s\n' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"
[ "$AMB" = "ambiguous=7" ] \
    && ok "(h) header gauge ambiguous=7 — only the honest splits remain" \
    || no "(h) header gauge is '$AMB', expected ambiguous=7 (3 field-typed calls narrowed, 7 honest splits kept)"

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

# ── TS/JS literal receivers (issue #163, first step on #59) ──
# A built-in method on a LITERAL must not bind an unrelated same-named user function. The five arms
# assert the FIXED behaviour: no edge into unrelated.ts, count="0", graph_ambiguous="0", and the
# corpus header's external= equals the covered call count (6). RED on a pre-change binary.
# Controls: typed user-object, String.prototype.shout, object-literal own method, find!.render
# (certainty ends), this.replace(), namespace import, cast, plus .js and .tsx twins of the five arms.
# Separate corpora on purpose: (h)'s ambiguous=7 is counted over $FIX and must not move.
LIT="$TMP/tslitfix"; OBJ="$TMP/tsobjfix"; JSLIT="$TMP/jslitfix"; TSLIT="$TMP/tsxlitfix"; CTRL="$TMP/tsctrlfix"
mkdir -p "$LIT/src" "$OBJ/src" "$JSLIT/src" "$TSLIT/src" "$CTRL/src"
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
cat >"$JSLIT/src/literals.js" <<'EOF'
export function viaString() { return "a-b".replace(/-/g, " "); }
export function viaChain() { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n) { return `n=${n}`.padStart(8); }
export function viaArray() { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s) { return /x/.test(s); }
EOF
cat >"$JSLIT/src/unrelated.js" <<'EOF'
export function replace(value) { return value; }
export function split(value) { return value; }
export function padStart(value) { return value; }
export function map(value) { return value; }
export function test(value) { return value; }
EOF
cat >"$TSLIT/src/literals.tsx" <<'EOF'
export function viaString(): string { return "a-b".replace(/-/g, " "); }
export function viaChain(): string[] { return "a b".replace(/x/g, "").split(" "); }
export function viaTemplate(n: number): string { return `n=${n}`.padStart(8); }
export function viaArray(): number[] { return [3, 1, 2].map(v => v * 2); }
export function viaRegex(s: string): boolean { return /x/.test(s); }
EOF
cat >"$TSLIT/src/unrelated.ts" <<'EOF'
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
cat >"$CTRL/src/widget.ts" <<'EOF'
export class Widget { render(): string { return ""; } }
export function transform(): number { return 1; }
export function decoyReplace(a: string): string { return a; }
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
module.exports = { viaPrototypeExtension };
EOF
LITMAP="$( "$BIN" "$LIT" --no-cache 2>/dev/null )"
litMissing=""
for want in viaString viaChain viaTemplate viaArray viaRegex replace split padStart map test; do
    printf '%s' "$LITMAP" | grep -q "n=\"$want\"" || litMissing="$litMissing $want"
done
[ -z "$litMissing" ] && ok "(kg-ts) presence: every literal-receiver fixture symbol is indexed" \
    || no "(kg-ts) presence guard: fixture symbols not indexed:$litMissing — every arm below would be vacuous"
LITSTATS="$( printf '%s' "$LITMAP" | grep -oE 'files=[0-9]+ symbols=[0-9]+ edges=[0-9]+[^<]*' | head -1 )"
printf '%s' "$LITSTATS" | grep -q 'external=6' \
    && ok "(kg-ts) corpus external=6 — six certain built-in calls counted, not dropped ($LITSTATS)" \
    || no "(kg-ts) corpus external= is not 6 (six covered calls must be counted): $LITSTATS"
printf '%s' "$LITSTATS" | grep -q 'ambiguous=0' \
    && ok "(kg-ts) corpus ambiguous=0 — the veto must not raise the gauge" \
    || no "(kg-ts) corpus ambiguous= moved: $LITSTATS"
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
litFixed "$LIT"   src/literals.ts  viaString
litFixed "$LIT"   src/literals.ts  viaChain
litFixed "$LIT"   src/literals.ts  viaTemplate
litFixed "$LIT"   src/literals.ts  viaArray
litFixed "$LIT"   src/literals.ts  viaRegex
litFixed "$JSLIT" src/literals.js  viaString
litFixed "$JSLIT" src/literals.js  viaChain
litFixed "$JSLIT" src/literals.js  viaTemplate
litFixed "$JSLIT" src/literals.js  viaArray
litFixed "$JSLIT" src/literals.js  viaRegex
litFixed "$TSLIT" src/literals.tsx viaString
litFixed "$TSLIT" src/literals.tsx viaChain
litFixed "$TSLIT" src/literals.tsx viaTemplate
litFixed "$TSLIT" src/literals.tsx viaArray
litFixed "$TSLIT" src/literals.tsx viaRegex
OBJOUT="$( "$BIN" "$OBJ" --callees=src/user.ts:viaObjectReceiver --no-cache 2>/dev/null )"
printf '%s' "$OBJOUT" | grep -q 'n="replace" p="src/rewriter.ts:2"' \
    && ok "(kg-ts control) a typed user-object receiver r.replace() keeps its edge to Rewriter.replace (rewriter.ts:2)" \
    || no "(kg-ts control) viaObjectReceiver lost its edge to Rewriter.replace — a literal-receiver rule over-reached: $( printf '%s' "$OBJOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
PROTOOUT="$( "$BIN" "$OBJ" --callees=src/proto.js:viaPrototypeExtension --no-cache 2>/dev/null )"
printf '%s' "$PROTOOUT" | grep -q 'n="shout" p="src/proto.js:1"' \
    && ok "(kg-ts control) \"x\".shout() keeps its edge to the repo's own String.prototype.shout (proto.js:1) — a literal receiver can reach user code" \
    || no "(kg-ts control) \"x\".shout() lost its edge to String.prototype.shout — a literal-receiver veto must let prototype extensions through: $( printf '%s' "$PROTOOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
OWNOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaOwnLiteral --no-cache 2>/dev/null )"
printf '%s' "$OWNOUT" | grep -q 'n="replace" p="src/user.ts:3"' \
    && ok "(kg-ts control) object-literal own method ({ replace(){} }).replace() keeps its edge" \
    || no "(kg-ts control) viaOwnLiteral lost the object-literal replace edge: $( printf '%s' "$OWNOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
FINDOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:viaFindRender --no-cache 2>/dev/null )"
printf '%s' "$FINDOUT" | grep -q 'n="render" p="src/widget.ts:1"' \
    && ok "(kg-ts control) [new Widget()].find(...)!.render() keeps Widget.render — certainty ends at find/!" \
    || no "(kg-ts control) viaFindRender lost Widget.render: $( printf '%s' "$FINDOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
THISOUT="$( "$BIN" "$CTRL" --callees=src/user.ts:apply --no-cache 2>/dev/null )"
printf '%s' "$THISOUT" | grep -q 'n="replace"' \
    && ok "(kg-ts control) this.replace() inside a class that defines replace keeps its edge" \
    || no "(kg-ts control) AMD.apply lost this.replace(): $( printf '%s' "$THISOUT" | grep -oE '<callees [^>]*>|<s [^>]*/>' | tr '\n' ' ' )"
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

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
