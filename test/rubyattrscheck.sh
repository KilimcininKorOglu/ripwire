#!/usr/bin/env bash
# rubyattrscheck.sh — parser version 121 gate: RUBY'S CLASS-LEVEL ATTRIBUTE DSL DEFINES SYMBOLS. An
# `attr_reader`/`attr_writer`/`attr_accessor`/`attribute`/`attributes` DSL call mints one
# Var def per simple_symbol argument (the name minus the leading ':'), plus the `<x>=` setter for
# attr_writer/attr_accessor/attribute/attributes — the exact spelling the setter-call rename produces,
# so `record.x = v` now BINDS. This reverses the floor queries/ruby/tags.scm used to state ("attr_accessor
# … define nothing in the source TEXT … a write against one is an honest nothing"): the family CALL stays
# an external-surface reference capture (same posture as the schema DSL rows), and only the symbol
# ARGUMENTS gain defs. The reversal is GLOBAL: every Ruby corpus gains Var defs (and with them call edges
# and PageRank weight — accepted, disclosed).
#
# Fixture test/rubyattrsfix (runtime semantics proven against a running Rails application — see
# USECASES.md beside the fixture — plus the hand-written
# attr_consumers.rb arm):
#   single_attr.rb      attr_accessor :name                      → Var name + Var name=
#   multi_attr.rb       attr_accessor :multi_a, :multi_b         → Var per symbol, getters AND setters
#   typed_attr.rb       attribute :quantity, :integer, default:  → singular takes ONE name; the type and
#                             keyword args are data, not defs (`integer` must stay undefinable)
#   block_attr.rb       attributes :block_a do … end             → the call's symbol gains defs; the BLOCK
#                             BODY is walked but defines nothing (`default=` stays external)
#   set_reader.rb / set_writer.rb / set_attribute.rb / set_def.rb  reader→name only; writer→name= only;
#                             attribute→both; `def name=` is the Method-side tenant of the setter space
#   pair_def_attr.rb / pair_attr_def.rb   def+attr collision in ONE file — BOTH defs stand (the dedup
#                             ladder only folds same-byte captures; Var and Method share the NAME, never
#                             the identity byte), in either declaration order
#   pair_attr_column.rb / attr_yaml.rb    attr+column and attr+yaml pair arms; spike_names.yml's `name:`
#                             key is the cross-language Section def (counted, never edgeable — Ruby<->Yaml
#                             is not langCompatible)
#   attr_consumers.rb   the use rows; and the NEGATIVE arms the class-DSL-position gate must keep green:
#                             a method body, a receiver-qualified call, and file top level define nothing
#   floor_attr.rb        DISCLOSED floors, all must stay undefinable: a `begin`/modifier-`if`-guarded call
#                             is not class-DSL position; quoted (`:"x"`/`:'x'`), string, and splat/`%i[]`
#                             arguments are not simple_symbol names; an `included`/`class_methods` (Concern),
#                             `Struct.new`/`Class.new`/`Module.new` do-block body and a non-modifier
#                             `if … then … end` block are not unwrapped — Ruby defines all of these, ripwire does not
#   priv_attr.rb         the Ruby 3 INLINE-VISIBILITY lift: `private attr_reader :x` / `protected attr_accessor`
#                             / `public attr_writer` / `module_function attr_accessor` DO define (the macro runs
#                             before visibility applies, so the family macro still decides which side exists)
#
# Usage:  test/rubyattrscheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyattrscheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rubyattrsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rubyattrsfix — fixture missing"; exit 2; }
echo "rubyattrscheck: BIN=$BIN  FIX=$FIX"

useshead(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>/dev/null | grep -oE "of=\"[^\"]*\" defs=\"[0-9]+\" external=\"[0-9]+\" count=\"[0-9]+\"" | head -1; }
undefinable(){ "$BIN" "$FIX" --uses="$1" --no-cache 2>&1 | grep -q "matched no indexed definition"; }
callershead(){ "$BIN" "$FIX" --callers="$1" --no-cache 2>/dev/null | grep -oE "of=\"[^\"]*\" defs=\"[0-9]+\" count=\"[0-9]+\"" | head -1; }

# ── 1. CAPTURE: the family mints Var defs, getter/setter pairs per the spec ───────────────────────────
[ "$( useshead name )"   = 'of="name" defs="10" external="0" count="2"' ] \
    && ok 'capture: name has 10 defs — 7 Var getters (attr x4 + reader + attribute + attr/column) + 2 Method (def+attr pair) + 1 yaml Section' \
    || no "capture: name defs: $( useshead name )"
[ "$( useshead 'name=' )" = 'of="name=" defs="8" external="0" count="2"' ] \
    && ok 'capture: name= has 8 defs — 7 Var setters (writer/accessor x5 + attribute + attr/column) + the def-name= Method; the setter space is SHARED' \
    || no "capture: name= defs: $( useshead 'name=' )"
[ "$( useshead quantity )"  = 'of="quantity" defs="1" external="0" count="0"' ] \
    && ok 'capture: attribute :quantity, :integer, default: 0 — ONE def; type metadata defines nothing' \
    || no "capture: quantity defs: $( useshead quantity )"
[ "$( useshead multi_a )"   = 'of="multi_a" defs="1" external="0" count="1"' ] \
    && ok 'capture: multi-symbol attr_accessor defines each symbol; the consumer read is a counted use row' \
    || no "capture: multi_a defs: $( useshead multi_a )"
[ "$( useshead block_a )"   = 'of="block_a" defs="1" external="0" count="0"' ] \
    && ok 'capture: attributes :block_a do … end — the call arg defines; the do-block is a closure body' \
    || no "capture: block_a defs: $( useshead block_a )"
[ "$( useshead multi_p1 )"  = 'of="multi_p1" defs="1" external="0" count="0"' ] \
    && ok 'capture: plural attributes with TWO symbols defines EACH (third-party-DSL forward-compat, static-only posture)' \
    || no "capture: multi_p1 defs: $( useshead multi_p1 )"
[ "$( useshead multi_p2 )"  = 'of="multi_p2" defs="1" external="0" count="0"' ] \
    && ok 'capture: plural attributes — the SECOND symbol defines too (not first-symbol-only)' \
    || no "capture: multi_p2 defs: $( useshead multi_p2 )"
undefinable 'multi_p1=' \
    && ok 'floor: plural attributes is READERS-ONLY — multi_p1= stays undefinable (AMS/jsonapi-serializer/dry-struct define no setters; measured)' \
    || no 'floor: multi_p1= — plural attributes minted a setter'
undefinable 'multi_p2=' \
    && ok 'floor: plural attributes readers-only — multi_p2= stays undefinable' \
    || no 'floor: multi_p2= — plural attributes minted a setter'
[ "$( useshead priv_name )"  = 'of="priv_name" defs="1" external="0" count="0"' ] \
    && ok 'lift: private attr_reader :priv_name — the INLINE-VISIBILITY call IS class-DSL position; the reader defines (the macro runs before visibility applies)' \
    || no "lift: priv_name defs: $( useshead priv_name )"
undefinable 'priv_name=' \
    && ok 'lift: private attr_reader — still reader-only: no priv_name= setter (the MACRO, not the visibility, decides the pair)' \
    || no 'lift: priv_name= — attr_reader under a visibility call minted a setter'
[ "$( useshead prot_pair )"  = 'of="prot_pair" defs="1" external="0" count="0"' ] \
    && ok 'lift: protected attr_accessor — the accessor pair defines (reader side)' \
    || no "lift: prot_pair defs: $( useshead prot_pair )"
[ "$( useshead 'prot_pair=' )" = 'of="prot_pair=" defs="1" external="0" count="0"' ] \
    && ok 'lift: protected attr_accessor — prot_pair= setter defines (writer side of the pair)' \
    || no "lift: prot_pair= defs: $( useshead 'prot_pair=' )"
undefinable pub_set \
    && ok 'lift: public attr_writer — writer-only: no bare pub_set reader (the macro spells one side)' \
    || no 'lift: pub_set — attr_writer under a visibility call minted a reader'
[ "$( useshead 'pub_set=' )" = 'of="pub_set=" defs="1" external="0" count="0"' ] \
    && ok 'lift: public attr_writer — pub_set= setter defines' \
    || no "lift: pub_set= defs: $( useshead 'pub_set=' )"
[ "$( useshead mod_acc )"   = 'of="mod_acc" defs="1" external="0" count="0"' ] \
    && ok 'lift: module_function attr_accessor — both sides define (reader)' \
    || no "lift: mod_acc defs: $( useshead mod_acc )"
[ "$( useshead 'mod_acc=' )" = 'of="mod_acc=" defs="1" external="0" count="0"' ] \
    && ok 'lift: module_function attr_accessor — mod_acc= setter defines' \
    || no "lift: mod_acc= defs: $( useshead 'mod_acc=' )"
undefinable integer \
    && ok 'capture: the singular attribute stops at the first named child — :integer (type arg) defines nothing' \
    || no 'capture: integer — a type-metadata argument minted a def'
undefinable inside_method \
    && ok 'negative: a family call inside a METHOD BODY defines nothing (class-DSL-position gate)' \
    || no 'negative: inside_method — method-body family call minted a def'
undefinable qualified_target \
    && ok 'negative: a RECEIVER-QUALIFIED family call defines nothing (somebody'"'"'s own method, the directive posture)' \
    || no 'negative: qualified_target — receiver-qualified family call minted a def'
undefinable file_level_target \
    && ok 'negative: a family call at FILE TOP LEVEL defines nothing (would-be Object methods are not symbols here)' \
    || no 'negative: file_level_target — file-level family call minted a def'
[ "$( useshead 'default=' )" = 'of="default=" defs="0" external="1" count="1"' ] \
    && ok 'floor: the do-block body (`sub.default = 1`) is walked but defines NOTHING — default= stays an external setter ref' \
    || no "floor: default=: $( useshead 'default=' )"
undefinable begin_guarded \
    && ok 'floor: a `begin`-wrapped class call is NOT unwrapped — begin_guarded stays undefinable (runtime defines it; the silence is now STATED, not silent)' \
    || no 'floor: begin_guarded — a begin-wrapped class call minted a def'
undefinable if_guarded \
    && ok 'floor: a modifier-`if`-guarded class call is NOT unwrapped — if_guarded stays undefinable' \
    || no 'floor: if_guarded — an if-guarded class call minted a def'
for dyn in dq_name sq_name string_name splat_a; do
    undefinable "$dyn" \
        && ok "floor: dynamic argument form — $dyn (quoted/string/splat) defines nothing; only simple_symbol does" \
        || no "floor: $dyn — a non-simple_symbol argument minted a def"
done
undefinable concern_included \
    && ok 'floor: an `included do … end` body (ActiveSupport::Concern) defines nothing — a do_block body is not unwrapped' \
    || no 'floor: concern_included — an included-block body minted a def'
undefinable concern_class_method \
    && ok 'floor: a `class_methods do … end` body (Concern) defines nothing' \
    || no 'floor: concern_class_method — a class_methods-block body minted a def'
undefinable struct_attr \
    && ok 'floor: a `Struct.new(:s) do … end` body defines nothing' \
    || no 'floor: struct_attr — a Struct.new-block body minted a def'
undefinable classnew_attr \
    && ok 'floor: a `Class.new do … end` body defines nothing' \
    || no 'floor: classnew_attr — a Class.new-block body minted a def'
undefinable ifthen_attr \
    && ok 'floor: a non-modifier `if … then … end` block in a class body defines nothing (same floor as the pinned modifier form)' \
    || no 'floor: ifthen_attr — an if-then block minted a def'

# ── 2. THE CALLS STAY REFERENCES (disclosed posture, not silently dropped) ───────────────────────────
for fam in attr_accessor attr_writer attr_reader attribute attributes; do
    [ "$( useshead "$fam" | grep -oE 'defs="[0-9]+"' )" = 'defs="0"' ] \
        && ok "posture: the DSL call \`$fam\` itself is still no def (reference capture posture)" \
        || no "posture: $fam gained a def — the family call must stay a reference: $( useshead "$fam" )"
done

# ── 3. BINDING: setter CALLS resolve to the def set; Var defs admit call edges ──────────────────────
[ "$( callershead 'name=' )" = 'of="name=" defs="8" count="2"' ] \
    && ok 'bind: `x.name = v` call sites reach the name= def set (attr_writer/attr_accessor/attribute/def-name= tenants + pair files)' \
    || no "bind: name= callers: $( callershead 'name=' )"
[ "$( callershead name )" = 'of="name" defs="10" count="2"' ] \
    && ok 'edges: attr NAMES are callable — Var defs admit call edges (the "columns/attributes are callable" consequence, disclosed per-PR)' \
    || no "edges: name callers: $( callershead name )"

# ── 4. MAP KINDS: the defs carry t="var" with their class scope ─────────────────────────────────────
"$BIN" "$FIX" --no-cache 2>/dev/null >"$TMP/map"
grep -q '<s t="var" n="quantity" sc="TypedAttr"' "$TMP/map" \
    && ok 'kind: attribute :quantity emits a Var row scoped to its class' \
    || no 'kind: quantity var row missing/malformed'
grep -q '<s t="var" n="name" sc="SetReader"' "$TMP/map" \
    && ok 'kind: attr_reader :name is a Var def — the getter exists, the setter does not' \
    || no 'kind: SetReader var row missing'
grep -q '<s t="var" n="name=" sc="SetWriter"' "$TMP/map" \
    && ! grep -q '<s t="var" n="name" sc="SetWriter"' "$TMP/map" \
    && ok 'kind: attr_writer :name defines ONLY name= (no bare-name Var row)' \
    || no 'kind: SetWriter rows wrong — attr_writer must define name= and NOT the bare name'
grep -q '<s t="method" n="name" sc="PairDefAttr"' "$TMP/map" && grep -q '<s t="var" n="name" sc="PairDefAttr"' "$TMP/map" \
    && ok 'collision: def+attr in ONE file — BOTH defs stand (Method 5 > Var 1 folds only SAME-identity captures; the pair is two identities)' \
    || no 'collision: pair_def_attr.rb lost the Method or the Var def'

# ── 5. determinism, warm == cold, well-formed XML ────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/m1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/m2" 2>/dev/null
if cmp -s "$TMP/m1" "$TMP/m2"; then ok "deterministic (two --no-cache runs byte-identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (attr defs survive the cache round-trip)"; else no "warm != cold"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/m1" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
