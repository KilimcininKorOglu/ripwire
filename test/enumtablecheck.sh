#!/usr/bin/env bash
# enumtablecheck.sh — no table with a LITERAL extent is indexed by an enum.
#
# THE DEFECT CLASS. A table indexed by an enum must be as long as the enum, and a literal extent says nothing about
# the enum. Append an enumerator and the table is one short: a read past its end, or a write (search.h's per-tier hit
# counter was `tierHitCount[3]` beside a SpanTier that a corrupt memo byte could push past 2, found by the cache-enum
# lane's ASan sweep as a stack-buffer-overflow). skilleval.h's provenance counters were `[3]` for a four-value Prov,
# with only a debug check between Prov::Neg and the end of the array. The compile-time answer is the house pattern:
# size the table by the enum's count constant, prove the count exact beside the enum (infra/enumcount.h), and
# static_assert a name table's DEDUCED size against it. This gate is the fence that keeps a literal from coming back.
#
# HOW, and what it cannot see (a text scan, not a compiler; its limits are stated rather than implied):
#   tables   — a C array whose FIRST extent is a decimal literal (`T k[ 3 ]`, `T k[3][14]`), or `std::array< T, 3 >`;
#   enum-indexed — the subscript names an enumerator (`SpanTier::Code`), a member of an unscoped enum (`kFamState`),
#              a member declared with an enum type (`rows[i].prov`), or an identifier whose NEAREST declaration above
#              the use has an enum type or is initialised from one of those (`const std::size_t p = rows[i].prov`).
#   Scope is approximated by "nearest declaration above", so a name re-declared inside a nested scope after the use
#   is not seen; a typedef'd enum is not an enum here; an index computed in another function is not followed. So a
#   ZERO here means "none found", never "none exists". Each exemption below carries its reason.
#
# ARMS: (1) presence — the scan reads a real population (enums, literal-extent tables, subscripts); (2) no stale
# exemption; (3) the rule, 0 violations; (4) THREE POSITIVE CONTROLS over a copy of src/, each turning one real table
# back into the literal it replaced — one per detection path (enumerator, unscoped enumerator, initialised from a
# member) — and each must report exactly that table. A scan that cannot fail is not a fence.
#
# Usage: test/enumtablecheck.sh   (no ripwire binary: the subject is the source tree)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "enumtablecheck: no ripwire binary (source scan of $ROOT/src)"

# ── the exemptions: file:table, each with the reason it is not the defect ─────────────────────────────────────────
EXEMPT=(
    # the index is a 2-bit composition of two bools; `Verdict` there is queryshape's STRUCT, not crossref's enum
    "filter.h:kDocTierTags"
)

scan(){ python3 - "$@" <<'PY'
import os, re, sys
src = sys.argv[1]
ALLOW = { tuple( a.split( ':', 1 ) ) for a in sys.argv[2:] }
texts = {}
for dirpath, _, files in os.walk( src ):
    for fn in sorted( files ):
        if fn.endswith( ( '.h', '.cpp', '.hpp', '.inl' ) ):
            path = os.path.join( dirpath, fn )
            texts[ os.path.relpath( path, src ) ] = open( path, encoding='utf-8', errors='replace' ).read()
def strip( t ):
    t = re.sub( r'/\*.*?\*/', lambda m: re.sub( r'[^\n]', ' ', m.group( 0 ) ), t, flags=re.S )
    t = re.sub( r'"(?:[^"\\\n]|\\.)*"', lambda m: '"' + ' ' * ( len( m.group( 0 ) ) - 2 ) + '"', t )
    return re.sub( r'//[^\n]*', '', t )
code = { rel: strip( t ) for rel, t in texts.items() }
# the enums: named types, and the members of UNSCOPED enums (an index without a cast)
enum_types, unscoped = set(), set()
for t in code.values():
    for m in re.finditer( r'\benum\s+(class\s+|struct\s+)?([A-Za-z_]\w*)?\s*(?::\s*[\w:]+\s*)?\{([^}]*)\}', t ):
        if m.group( 2 ):
            enum_types.add( m.group( 2 ) )
        if not m.group( 1 ):
            unscoped.update( x.split( '=' )[0].strip() for x in m.group( 3 ).split( ',' ) if x.strip() )
ENUM_ALT = '|'.join( sorted( enum_types ) )
# struct members declared with an enum type (`Lang lang;`, `Prov prov = Prov::Router;`)
enum_members = set()
for t in code.values():
    for m in re.finditer( r'(?m)^[ \t]*(?:' + ENUM_ALT + r')[ \t]+([A-Za-z_]\w*)[ \t]*(?:=[^;\n]*)?;', t ):
        enum_members.add( m.group( 1 ) )
def shallow( expr ):
    if re.search( r'\b(?:' + ENUM_ALT + r')::[A-Za-z_]\w*', expr ):
        return 'an enumerator'
    for m in re.finditer( r'\b([A-Za-z_]\w*)\b', expr ):
        if m.group( 1 ) in unscoped:
            return 'unscoped enumerator ' + m.group( 1 )
    for m in re.finditer( r'(?:\.|->)\s*([A-Za-z_]\w*)\b(?!\s*\()', expr ):
        if m.group( 1 ) in enum_members:
            return 'enum member .' + m.group( 1 )
    return None
DECL_HEAD = r'([A-Za-z_][\w:]*(?:<[^;{}()]*?>)?)\s*(?:const\s*)?[&*]?\s+'
DECL_TAIL = r'\s*(=|;|,|\)|\[|\{|:)'
DECLS = {}
def declarations( rel ):
    # every `Type name` declaration in the file, once: name -> [ ( position, type, separator, end ) ] in text order
    if rel not in DECLS:
        table = {}
        for d in re.finditer( DECL_HEAD + r'([A-Za-z_]\w*)' + DECL_TAIL, code[ rel ] ):
            table.setdefault( d.group( 2 ), [] ).append( ( d.start(), d.group( 1 ), d.group( 3 ), d.end() ) )
        DECLS[ rel ] = table
    return DECLS[ rel ]
def enum_typed( rel, pos, expr ):
    why = shallow( expr )
    if why:
        return why
    t = code[ rel ]
    for m in re.finditer( r'(?<![\w.>:])([A-Za-z_]\w*)\b(?!\s*[(:])', expr ):
        name = m.group( 1 )
        before = [ d for d in declarations( rel ).get( name, [] ) if d[0] < pos ]
        if not before:
            continue
        _, typ, sep, end = before[-1]      # the nearest declaration above the use stands in for its scope
        if typ.split( '::' )[-1] in enum_types:
            return 'enum-typed ' + name
        if sep == '=':
            inner = shallow( t[ end:t.find( ';', end ) ] )
            if inner:
                return name + ' initialised from ' + inner
    return None
DECL_C = re.compile( r'(?:^|[;{}(]|\n)[ \t]*(?:(?:static|inline|constexpr|const|thread_local|mutable)\s+)*[A-Za-z_][\w:]*(?:<[^;{}()]*?>)?(?:\s*(?:\*|&|const)\s*)*\s+([A-Za-z_]\w*)\s*\[\s*(\d+)\s*\](?:\s*\[[^\]]*\])*\s*(?=[=;{,])', re.M )
DECL_A = re.compile( r'std::array\s*<\s*[^;{}]*?,\s*(\d+)\s*>\s*([A-Za-z_]\w*)\s*[={;(]' )
tables, violations, subscripts, allowed = 0, [], 0, set()
for rel, t in sorted( code.items() ):
    found = {}
    for m in DECL_C.finditer( t ):
        found.setdefault( m.group( 1 ), ( int( m.group( 2 ) ), t.count( '\n', 0, m.start( 1 ) ) + 1 ) )
        for extra in re.finditer( r',\s*([A-Za-z_]\w*)\s*\[\s*(\d+)\s*\]', t[ m.end():t.find( ';', m.end() ) ] ):   # `a[3] = {…}, b[3] = {…};`
            found.setdefault( extra.group( 1 ), ( int( extra.group( 2 ) ), t.count( '\n', 0, m.start( 1 ) ) + 1 ) )
    for m in DECL_A.finditer( t ):
        found.setdefault( m.group( 2 ), ( int( m.group( 1 ) ), t.count( '\n', 0, m.start( 2 ) ) + 1 ) )
    tables += len( found )
    for name, ( extent, dline ) in found.items():
        for s in re.finditer( r'(?<![\w.>:])' + re.escape( name ) + r'\s*\[', t ):
            line = t.count( '\n', 0, s.start() ) + 1
            if line == dline:
                continue
            i = s.end(); depth = 1; j = i
            while j < len( t ) and depth:
                depth += { '[': 1, ']': -1 }.get( t[j], 0 ); j += 1
            expr = t[ i:j - 1 ]
            subscripts += 1
            why = enum_typed( rel, s.start(), expr )
            if not why:
                continue
            if ( rel, name ) in ALLOW:
                allowed.add( ( rel, name ) )
                continue
            violations.append( f'{rel}:{line}: {name}[{extent}] (declared line {dline}) indexed by `{" ".join( expr.split() )}` — {why}' )
print( f'enum_types={len( enum_types )} enum_members={len( enum_members )} literal_tables={tables} subscripts={subscripts} allowed_hit={len( allowed )} stale_allow={len( ALLOW - allowed )} violations={len( violations )}' )
for a in sorted( ALLOW - allowed ):
    print( 'STALE ' + ':'.join( a ) )
for v in violations:
    print( 'VIOLATION ' + v )
PY
}

scan "$ROOT/src" "${EXEMPT[@]}" >"$TMP/live.txt" 2>&1
SUMMARY="$( head -1 "$TMP/live.txt" )"
num(){ sed -nE "s/.*[ ^]$1=([0-9]+).*/\1/p" "$TMP/live.txt" | head -1; }
ENUMS="$( sed -nE 's/^enum_types=([0-9]+).*/\1/p' "$TMP/live.txt" )"
TABLES="$( num literal_tables )"; SUBS="$( num subscripts )"; STALE="$( num stale_allow )"; VIOL="$( num violations )"
{ [ "${ENUMS:-0}" -ge 50 ] && [ "${TABLES:-0}" -ge 50 ] && [ "${SUBS:-0}" -ge 50 ]; } 2>/dev/null \
    && ok "(1) presence: the scan read $ENUMS enum types, $TABLES literal-extent tables and $SUBS subscripts of them ($SUMMARY)" \
    || no "(1) presence: enums=${ENUMS:-?} tables=${TABLES:-?} subscripts=${SUBS:-?} — the population is gone or a pattern stopped matching, so (3) would pass on nothing ($SUMMARY)"
[ "$STALE" = "0" ] \
    && ok "(2) every exemption still names a literal-extent table indexed by an enum (${#EXEMPT[@]} row(s))" \
    || no "(2) stale exemption(s), matching nothing: $( sed -n 's/^STALE //p' "$TMP/live.txt" | tr '\n' ' ')— retire the row"
[ "$VIOL" = "0" ] \
    && ok "(3) the rule: 0 literal-extent tables indexed by an enum outside the exemptions" \
    || no "(3) a literal-extent table indexed by an enum — size it by the enum's count: $( grep '^VIOLATION' "$TMP/live.txt" | sed 's/^VIOLATION //' | tr '\n' ';' )"

# ── (4) positive controls: the same scan, a copy of src/ with one real table turned back into its literal ─────────
control(){   # $1 label  $2 file  $3 python-literal FROM  $4 python-literal TO  $5 table-name pattern  $6 table name as printed
    rm -rf "$TMP/src"; cp -R "$ROOT/src" "$TMP/src"
    python3 -c 'import sys; p=sys.argv[1]; t=open(p).read(); u=t.replace(eval(sys.argv[2]), eval(sys.argv[3]), 1); open(p,"w").write(u)' "$TMP/src/$2" "$3" "$4"
    if cmp -s "$ROOT/src/$2" "$TMP/src/$2"; then
        no "(4) $1: the mutation did not take ($2 unchanged) — this control proves nothing"; return
    fi
    scan "$TMP/src" "${EXEMPT[@]}" >"$TMP/ctl.txt" 2>&1
    local hits total
    hits="$( grep -c "^VIOLATION $2:[0-9]*: $5\[" "$TMP/ctl.txt" )"; total="$( grep -c '^VIOLATION' "$TMP/ctl.txt" )"
    { [ "$hits" -ge 1 ] && [ "$hits" = "$total" ]; } \
        && ok "(4) $1: the scan reports exactly $2's $6 ($hits subscript(s)): $( grep '^VIOLATION' "$TMP/ctl.txt" | head -1 | sed 's/^VIOLATION //' )" \
        || no "(4) $1: expected only $2's $6, got $hits of $total violation(s) — the scan cannot see the defect it exists for"
}
control "enumerator path" search.h "'std::uint32_t             tierHitCount[kSpanTierCount] = {};'" "'std::uint32_t             tierHitCount[3] = { 0, 0, 0 };'" tierHitCount tierHitCount
control "unscoped-enumerator path" qualitypanel.h "'inline constexpr const char* kNewFamilyNames[] = { \"colocation\", \"state\" };'" "'inline constexpr std::array<const char*, 2> kNewFamilyNames = { { \"colocation\", \"state\" } };'" kNewFamilyNames kNewFamilyNames
control "initialised-from-a-member path" skilleval.h "'std::size_t provHit[kProvCount] = {}, provN[kProvCount] = {};'" "'std::size_t provHit[3] = { 0, 0, 0 }, provN[3] = { 0, 0, 0 };'" "prov\(Hit\|N\)" "provHit/provN"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
