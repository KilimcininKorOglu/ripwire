#!/usr/bin/env bash
# overbudgetcommentcheck.sh — A4-F9 gate: a symbol NAME containing "--" must never break the XML when it
# lands on the packBodies over-budget OMISSION path.
#
# packBodies, when a def does not fit the remaining --pack-budget-bytes AND something was already emitted,
# skips the whole def and leaves a visible marker:  <!-- body omitted (over budget): NAME -->.  A NAME with
# a "--" run (C++ operator--, a markdown "-- heading") is ill-formed inside an XML comment and xmllint
# rejects the whole document (the G4 gate). The fix collapses every '-' run to a single '-' before splicing.
#
# This gate feeds test/overbudgetfix/ (a struct with a big `bump()` method + an `operator--`), forces the
# omission path with a tiny budget, and asserts:
#   - the output passes xmllint --noout (would FAIL pre-fix: the raw "operator--" in the comment)
#   - the omission marker for operator-- is present but with the '--' run collapsed (contains "operator-",
#     never a raw "operator--")
#
# THE REST OF THE OVER-BUDGET CONTRACT (lane/cutfix-bodies, 2026-09-23; arms B1-B5, generated fixture):
#   (B1) RANK FIRST: packBodies walks the budget in the CALLER'S order and groups only the survivors by file.
#        It used to regroup by file BEFORE the budget, so --expand=alpha,gamma,beta (alpha and beta sharing a
#        file) shipped beta and dropped gamma, the second thing asked for. RED on 60b65f02.
#   (B2) NEVER SILENT: every body the budget drops is named, including those met after the budget was
#        spent (the old `break`s named none of them) — those in ONE `<!-- bodies omitted (budget spent): a, b -->`
#        list. Names == total - shown. RED on 60b65f02.
#   (B3) A TRUNCATED FIRST BODY says so outside its CDATA: <bodies capped="1">, <b lines="lo-hi/T"
#        truncated="1" next=…>, no `<!-- truncated -->` inside the CDATA, and following next= at the same
#        budget reassembles the whole body byte for byte. RED on 60b65f02 (capped="0", marker in the CDATA).
#   (B4) determinism and well-formedness of every B-arm document.
#
# Usage:  test/overbudgetcommentcheck.sh   [ RIPWIRE_BIN=path/to/ripwire ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/overbudgetfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "overbudgetcommentcheck: BIN=$BIN  FIX=$FIX"

# fixture sanity: operator-- is actually captured as a symbol with a "--" in its name
"$BIN" "$FIX" --no-cache 2>/dev/null | grep -q 'n="operator--"' \
    && ok "fixture sanity: operator-- captured as a symbol name" \
    || no "fixture sanity: operator-- not captured (name check)"

# force the omission path: expand bump (fills the budget) then operator-- (over budget → omitted)
OUT="$TMP/out.xml"
"$BIN" "$FIX" --expand=bump,operator-- --pack-budget-bytes=60 --no-cache >"$OUT" 2>/dev/null

# the omission marker for operator-- must be present (proves we hit the over-budget path)
grep -q 'body omitted (over budget): operator-' "$OUT" \
    && ok "over-budget omission marker for operator-- is present" \
    || no "expected over-budget omission marker for operator-- (did the path trigger?)"

# G4: the whole document must be well-formed — the crux of A4-F9 (pre-fix: xmllint rejects the raw '--')
xmllint --noout "$OUT" 2>"$TMP/lint.err" \
    && ok "over-budget comment: passes xmllint --noout (no ill-formed '--' in the comment)" \
    || no "over-budget comment: xmllint FAILED: $( cat "$TMP/lint.err" )"

# the omission COMMENT must carry the collapsed 'operator-', never the raw 'operator--' ('--' is only
# legal elsewhere — e.g. the map's id="…::operator--" attribute, which xmllint already accepted above).
if grep -qF 'body omitted (over budget): operator--' "$OUT"; then
    no "raw 'operator--' ('--' run) survived into the XML comment — collapse did not apply"
else
    ok "omission comment carries the collapsed 'operator-' (no ill-formed '--' run in a comment)"
fi

# ── B arms: a generated fixture (three files) so no committed tree's counts move ─────────────────────────────
BFX="$TMP/bfx"; mkdir -p "$BFX/src"
{
    echo 'int alpha_head( int v )'; echo '{'; echo '    return v + 1;'; echo '}'
    echo 'int beta_tail( int v )'; echo '{'; echo '    int t = 0;'
    for r in 1 2 3 4; do printf '    t += v * %s1; t += v * %s2; t += v * %s3; t += v * %s4; t += v * %s5; t += v * %s6; t += v * %s7;\n' $r $r $r $r $r $r $r; done
    echo '    return t;'; echo '}'
} > "$BFX/src/a_first.cpp"
{
    echo 'int gamma_mid( int v )'; echo '{'; echo '    int t = 0;'
    for r in 1 2 3 4; do printf '    t -= v * %s1; t -= v * %s2; t -= v * %s3; t -= v * %s4; t -= v * %s5; t -= v * %s6; t -= v * %s7;\n' $r $r $r $r $r $r $r; done
    echo '    return t;'; echo '}'
} > "$BFX/src/b_second.cpp"
{
    echo 'int delta_wide( int alpha_parameter_one, int alpha_parameter_two, int alpha_parameter_three, int alpha_parameter_four, int alpha_parameter_five )'
    echo '{'; echo '    return alpha_parameter_one + alpha_parameter_two + alpha_parameter_three;'; echo '}'
} > "$BFX/src/c_long.cpp"
cat > "$TMP/bodies.py" <<'PY'
import sys, re, xml.etree.ElementTree as ET
doc = sys.stdin.read()
root = ET.fromstring( doc )
bs = next( root.iter( "bodies" ), None )
if bs is None:
    print( "NOBODIES" ); sys.exit( 0 )
mode = sys.argv[1]
if mode == "summary":
    names = [ b.attrib["n"] for b in bs.findall( "b" ) ]
    omitted = re.findall( r"<!-- body omitted \(over budget\): (.*?) -->", doc )          # skipped while budget remained
    for tail in re.findall( r"<!-- bodies omitted \(budget spent\): (.*?) -->", doc ):   # met after it was spent, one list
        omitted += tail.split( ", " )
    print( "shown=%s total=%s capped=%s names=%s omitted=%s" % ( bs.attrib.get( "shown" ), bs.attrib.get( "total" ), bs.attrib.get( "capped" ),
           ",".join( names ), ",".join( omitted ) ) )
elif mode == "body":            # the first <b>: its attributes a line each, then its CDATA text
    b = bs.find( "b" )
    for k in ( "lines", "truncated", "next" ):
        print( "%s=%s" % ( k, b.attrib.get( k, "" ) ) )
    sys.stdout.write( "TEXT=" + ( b.text or "" ) )
PY
bsum(){ "$BIN" "$BFX" --no-cache --top-k=0 --legend=full "$@" 2>/dev/null | python3 "$TMP/bodies.py" summary; }

# (B1) rank first: the caller asked for alpha, gamma, beta — in that order
B1="$( bsum --expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=500 )"
case "$B1" in
    *"names=alpha_head,gamma_mid omitted=beta_tail"*) ok "(B1) rank first: the budget kept alpha+gamma and named beta ($B1)" ;;
    *) no "(B1) the budget did not follow the caller's order — want alpha_head,gamma_mid kept, beta_tail omitted: $B1" ;;
esac
# presence guard: at a budget holding all three, all three ship (so B1's drop is the budget's, not a resolve miss)
case "$( bsum --expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=4000 )" in
    *"shown=3 total=3 capped=0"*) ok "(B1) guard: all three bodies ship when the budget holds them" ;;
    *) no "(B1) guard: the fixture's three bodies do not all ship at 4000 B — B1 measured a resolve miss" ;;
esac

# (B2) never silent: delta's first line alone overruns 100 B, so the cut spends the WHOLE budget
B2="$( bsum --expand=delta_wide,alpha_head --pack-budget-bytes=100 )"
case "$B2" in
    *"shown=1 total=2 capped=1 names=delta_wide omitted=alpha_head") ok "(B2) the body met after the budget was spent is named ($B2)" ;;
    *) no "(B2) a body dropped after the budget was spent is not named (names must equal total - shown): $B2" ;;
esac

# (B3) the truncated body: capped="1", the cut stated outside the CDATA, and next= reassembles it
T1="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full --expand=beta_tail --pack-budget-bytes=150 2>/dev/null )"
case "$( printf '%s' "$T1" | python3 "$TMP/bodies.py" summary )" in
    *"shown=1 total=1 capped=1"*) ok "(B3) a truncated body's <bodies> says capped=\"1\"" ;;
    *) no "(B3) a truncated body's <bodies> does not say capped=\"1\": $( printf '%s' "$T1" | grep -o '<bodies [^>]*>' | tail -1 )" ;;
esac
printf '%s' "$T1" | grep -o '<b [^>]*truncated="1"[^>]*>' | grep -q 'lines="1-[0-9]*/[0-9]*".*next="--expand=' \
    && ok "(B3) the <b> carries lines= truncated=\"1\" next= outside the CDATA" \
    || no "(B3) the truncated <b> lacks lines=/truncated=/next= attributes"
printf '%s' "$T1" | grep -qF '<!-- truncated -->' \
    && no "(B3) a '<!-- truncated -->' marker is still written INSIDE the CDATA (paste-back carries it)" \
    || ok "(B3) nothing is appended inside the CDATA"
WHOLE="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full --expand=beta_tail 2>/dev/null | python3 "$TMP/bodies.py" body | sed -n '/^TEXT=/,$p' )"
ACC=""; NEXT="--expand=beta_tail"; hops=0
while [ -n "$NEXT" ] && [ "$hops" -lt 20 ]; do
    OUTB="$( "$BIN" "$BFX" --no-cache --top-k=0 --legend=full "$NEXT" --pack-budget-bytes=150 2>/dev/null | python3 "$TMP/bodies.py" body )"
    PART="$( printf '%s\n' "$OUTB" | sed -n '/^TEXT=/,$p' | sed '1s/^TEXT=//' )"
    ACC="${ACC:+$ACC
}$PART"
    NEXT="$( printf '%s\n' "$OUTB" | sed -n 's/^next=//p' )"
    hops=$(( hops + 1 ))
done
if [ "$hops" -lt 2 ]; then
    no "(B3) the 150 B budget did not cut beta_tail at all — the reassembly arm measured nothing"
elif [ "TEXT=$ACC" = "$WHOLE" ]; then
    ok "(B3) following next= at the same budget reassembles the whole body byte for byte ($hops calls)"
else
    no "(B3) the next= chain does not reassemble the body ($hops calls)"
fi

# (B4) determinism + well-formedness of the B documents
for a in "--expand=alpha_head,gamma_mid,beta_tail --pack-budget-bytes=500" "--expand=delta_wide,alpha_head --pack-budget-bytes=100" "--expand=beta_tail --pack-budget-bytes=150"; do
    # shellcheck disable=SC2086
    X1="$( "$BIN" "$BFX" --no-cache --top-k=0 $a 2>/dev/null )"; X2="$( "$BIN" "$BFX" --no-cache --top-k=0 $a 2>/dev/null )"
    [ "$X1" = "$X2" ] || no "(B4) not byte-identical across two runs: $a"
    printf '%s' "$X1" | xmllint --noout - 2>/dev/null || no "(B4) not well-formed: $a"
done
ok "(B4) the B documents are deterministic and well-formed (a failure above names the one that is not)"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
