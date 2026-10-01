#!/usr/bin/env bash
# editcheckdeclcheck.sh — --edit-check on C/C++: a declaration and the definition it declares are ONE contract.
#
# The field report: a header declares `int scale( int x, int factor = 2 )`, the .cpp defines it, three callers pass 1, 1
# and 2 arguments, and a trailing `int bias = 0` is added to both. Every call still compiles. The verb answered:
#   R1  --edit-check=scale           refused as "2 distinct contracts" (the prototype and its definition);
#   R2  --edit-check=./lib.cpp:scale incompatible="3" — the defaults live on the HEADER declaration and the arity test
#                                    read the definition's parameter list only;
#   R3  --edit-check=./lib.h:scale   refused again — the handle the refusal itself suggested.
#
# Arms:
#   (A) R1: the bare name answers (exit 0) about the definition, no refusal.
#   (B) R2: the definition's handle reports incompatible="0", flags no caller, and says where the defaults came from
#       (defaults_from="decl", defined in the same document's legend).
#   (C) R3: the header handle answers too, with the same contract as (B).
#   (D) the field-report shape on the MCP twin (edit_check symbol=scale): incompatible="0".
#   (E) CONTROL — defaults never make a wildcard: a call with MORE arguments than the parameter list is still flagged,
#       and only that caller is.
#   (F) E3 decoy — two real overloads, scale(int,int=2,int=3) and scale(double,double,double,double): they stay two
#       definitions (defs="2"), each takes defaults only from ITS declaration (a 1-argument call is accepted by the int
#       overload alone, a 5-argument call by neither).
#   (G) a declaration whose parameter TYPES match no definition is not folded and lends no defaults: the 1-argument
#       call against `scale( double, int )` stays flagged, and the bare name stays refused.
#   (H) E2 — every handle printed after "Qualify one contract:" is accepted on a rerun, on (G) and on a two-platform
#       corpus (one declaration, two .cpp definitions, which is two contracts and must stay refused).
#   (I) an unproven declaration (the definition's file does not include the header) lends no defaults.
#
# Operates on private temp git repos. Needs git and python3.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "editcheckdeclcheck: BIN=$BIN"

commit(){ ( cd "$1" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1 \
              || no "could not commit $1 — every arm on it would read no-baseline"; }
# ec <corpus> <selector> → the document on stdout (full legend), stderr to $TMP/err, exit code to $TMP/rc
ec(){ ( cd "$1" && "$BIN" . --no-cache --edit-check="$2" --legend=full 2>"$TMP/err"; echo $? >"$TMP/rc" ); }
rc(){ cat "$TMP/rc"; }
# the <edit-check …> root element, and one attribute off it (empty when absent)
root(){ printf '%s' "$1" | grep -oE '<edit-check [^>]*>' | head -1; }
attr(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.search(r"(?<![A-Za-z0-9_])"+re.escape(sys.argv[1])+r"=\"([^\"]*)\"",sys.stdin.read()); sys.stdout.write(m.group(1) if m else "")' "$2"; }
# the caller names flagged incompatible="1", comma-joined in document order
flagged(){ printf '%s' "$1" | python3 -c 'import re,sys; print(",".join(re.findall(r"<c n=\"([^\"]*)\"[^>]*incompatible=\"1\"",sys.stdin.read())))'; }
legend(){ printf '%s' "$1" | python3 -c 'import re,sys; m=re.match(r"\A(?:\s*<!--.*?-->)+",sys.stdin.read(),re.S); sys.stdout.write(m.group(0) if m else "")'; }

# ── the field-report corpus ───────────────────────────────────────────────────────────────────────────────
F="$TMP/field"; mkdir -p "$F"
printf 'int scale( int x, int factor = 2 );\n' >"$F/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor )\n{\n    return x * factor;\n}\n' >"$F/lib.cpp"
printf '#include "lib.h"\nint a() { return scale( 1 ); }\nint b() { return scale( 2 ); }\nint c() { return scale( 3, 4 ); }\n' >"$F/use.cpp"
commit "$F"
printf 'int scale( int x, int factor = 2, int bias = 0 );\n' >"$F/lib.h"
printf '#include "lib.h"\nint scale( int x, int factor, int bias )\n{\n    return x * factor + bias;\n}\n' >"$F/lib.cpp"

echo "=== (A) R1: the bare name is one contract, not two ==="
OA="$( ec "$F" scale )"; RCA="$( rc )"; RA="$( root "$OA" )"
if [ "$RCA" = 0 ] && [ -n "$RA" ]; then
    ok "(A) --edit-check=scale answers (exit 0) instead of refusing a prototype and its definition as two contracts"
    case "$( attr "$RA" p )" in
        lib.cpp:2) ok "(A) the answer is about the definition (p=\"lib.cpp:2\")" ;;
        *)         no "(A) p=\"$( attr "$RA" p )\", expected the definition lib.cpp:2" ;;
    esac
    [ "$( attr "$RA" incompatible )" = 0 ] \
        && ok "(A) incompatible=\"0\": every call still binds through the header's defaults" \
        || no "(A) incompatible=\"$( attr "$RA" incompatible )\", expected 0 — flags: $( flagged "$OA" )"
else
    no "(A) --edit-check=scale exited $RCA: $( cat "$TMP/err" )"
fi

echo "=== (B) R2: the definition's handle reads the defaults off its declaration ==="
OB="$( ec "$F" ./lib.cpp:scale )"; RB="$( root "$OB" )"
if [ "$( rc )" = 0 ] && [ -n "$RB" ]; then
    [ "$( attr "$RB" incompatible )" = 0 ] && [ -z "$( flagged "$OB" )" ] \
        && ok "(B) incompatible=\"0\" and no caller row flagged (callers=\"$( attr "$RB" callers )\")" \
        || no "(B) incompatible=\"$( attr "$RB" incompatible )\" flags=[$( flagged "$OB" )] — the defaults on lib.h admit all three calls"
    [ "$( attr "$RB" callers )" = 3 ] && ok "(B) premise: callers=\"3\" (the arm is about three real call sites)" \
                                       || no "(B) premise broken: callers=\"$( attr "$RB" callers )\", expected 3"
    [ "$( attr "$RB" status )" = contract-change ] && [ "$( attr "$RB" params_now )" = 3 ] \
        && ok "(B) the edit is still reported: status=\"contract-change\" params_was=\"$( attr "$RB" params_was )\" params_now=\"3\"" \
        || no "(B) status=\"$( attr "$RB" status )\" params_now=\"$( attr "$RB" params_now )\" — the widened list must still read as a contract change"
    [ "$( attr "$RB" defaults_from )" = decl ] \
        && ok "(B) defaults_from=\"decl\" names where the arity range came from" \
        || no "(B) defaults_from=\"$( attr "$RB" defaults_from )\", expected decl"
    case "$( legend "$OB" )" in
        *'defaults_from='*) ok "(B) the legend defines defaults_from=" ;;
        *)                  no "(B) defaults_from= is emitted but not defined in the document's legend" ;;
    esac
else
    no "(B) --edit-check=./lib.cpp:scale exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (C) R3: the header's handle is accepted and answers the same contract ==="
OC="$( ec "$F" ./lib.h:scale )"; RC3="$( root "$OC" )"
if [ "$( rc )" = 0 ] && [ -n "$RC3" ]; then
    ok "(C) --edit-check=./lib.h:scale answers (exit 0)"
    for k in p status incompatible callers defs; do
        [ "$( attr "$RC3" "$k" )" = "$( attr "$RB" "$k" )" ] \
            || no "(C) $k=\"$( attr "$RC3" "$k" )\" differs from the definition handle's \"$( attr "$RB" "$k" )\""
    done
    ok "(C) p/status/incompatible/callers/defs agree with --edit-check=./lib.cpp:scale"
else
    no "(C) --edit-check=./lib.h:scale exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (D) the MCP twin answers the field-report shape the same way ==="
python3 - "$F" <<'PY' | "$BIN" --mcp >"$TMP/mcp.rpc" 2>/dev/null
import json, sys
print( json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ) )
print( json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": "edit_check", "arguments": { "path": sys.argv[1], "symbol": "scale", "legend": "full" } } } ) )
PY
OD="$( python3 -c '
import json,sys
lines=[l for l in open(sys.argv[1]).read().splitlines() if l.strip()]
r=json.loads(lines[-1]) if lines else {}
sys.stdout.write("__ERROR__:"+str(r.get("error",{}).get("message","no response")) if "result" not in r else r["result"]["content"][0]["text"])' "$TMP/mcp.rpc" 2>/dev/null )"
RD="$( root "$OD" )"
[ -n "$RD" ] && [ "$( attr "$RD" incompatible )" = 0 ] && [ "$( attr "$RD" defaults_from )" = decl ] \
    && ok "(D) MCP edit_check symbol=scale: incompatible=\"0\" defaults_from=\"decl\"" \
    || no "(D) MCP edit_check symbol=scale: ${OD:0:300}"

echo "=== (E) CONTROL: defaults never make a wildcard ==="
E="$TMP/over"; mkdir -p "$E"; cp "$F"/lib.h "$F"/lib.cpp "$F"/use.cpp "$E/"
printf 'int d() { return scale( 1, 2, 3, 4 ); }\n' >>"$E/use.cpp"
commit "$E"
OE="$( ec "$E" ./lib.cpp:scale )"; RE="$( root "$OE" )"
[ "$( attr "$RE" incompatible )" = 1 ] && [ "$( flagged "$OE" )" = d ] \
    && ok "(E) the 4-argument call to a 3-parameter scale is flagged, and only it (incompatible=\"1\", d)" \
    || no "(E) incompatible=\"$( attr "$RE" incompatible )\" flags=[$( flagged "$OE" )], expected 1 and [d]"

echo "=== (F) E3 decoy: real overloads stay two definitions, each with its own declaration's defaults ==="
D="$TMP/decoy"; mkdir -p "$D"
printf 'int scale( int x, int f = 2, int g = 3 );\ndouble scale( double x, double y, double z, double w );\n' >"$D/lib.h"
printf '#include "lib.h"\nint scale( int x, int f, int g ) { return x + f + g; }\ndouble scale( double x, double y, double z, double w ) { return x + y + z + w; }\n' >"$D/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\nint a3() { return scale( 1, 2, 3 ); }\ndouble a4() { return scale( 1.0, 2.0, 3.0, 4.0 ); }\nint a5() { return scale( 1, 2, 3, 4, 5 ); }\n' >"$D/use.cpp"
commit "$D"
OF="$( ec "$D" scale )"; RF="$( root "$OF" )"
if [ "$( rc )" = 0 ] && [ -n "$RF" ]; then
    [ "$( attr "$RF" defs )" = 2 ] && [ "$( printf '%s' "$OF" | grep -oE '<def [^>]*params="[0-9]+"' | grep -oE 'params="[0-9]+"' | tr '\n' ' ' )" = 'params="3" params="4" ' ] \
        && ok "(F) defs=\"2\": the two overloads stay two definitions (params 3 and 4), the declarations fold beside them" \
        || no "(F) defs=\"$( attr "$RF" defs )\" def rows: $( printf '%s' "$OF" | grep -oE '<def [^>]*>' | tr '\n' ' ' )"
    [ "$( flagged "$OF" )" = a5 ] \
        && ok "(F) only the 5-argument call is flagged; the 1-argument call binds the int overload through ITS defaults" \
        || no "(F) flags=[$( flagged "$OF" )], expected [a5] — a1 flagged means the int overload's defaults went to the double one"
else
    no "(F) --edit-check=scale on two overloads exited $( rc ): $( cat "$TMP/err" )"
fi

echo "=== (G) a declaration whose parameter TYPES match no definition lends nothing ==="
G="$TMP/mismatch"; mkdir -p "$G"
printf 'int scale( int x, int f = 2 );\n' >"$G/lib.h"
printf '#include "lib.h"\nint scale( double x, int f ) { return int( x ) * f; }\n' >"$G/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$G/use.cpp"
commit "$G"
OG="$( ec "$G" ./lib.cpp:scale )"; RG="$( root "$OG" )"
[ "$( flagged "$OG" )" = a1 ] && [ -z "$( attr "$RG" defaults_from )" ] \
    && ok "(G) scale( double, int ) takes no defaults from scale( int, int = 2 ): a1 stays flagged, no defaults_from=" \
    || no "(G) flags=[$( flagged "$OG" )] defaults_from=\"$( attr "$RG" defaults_from )\" — a different parameter-type list is a different contract"
ec "$G" scale >/dev/null
[ "$( rc )" = 1 ] && grep -q 'Qualify one contract' "$TMP/err" \
    && ok "(G) the bare name stays refused: the declaration and the definition are two contracts here" \
    || no "(G) --edit-check=scale exited $( rc ), expected the ambiguity refusal: $( cat "$TMP/err" )"

echo "=== (H) E2: every handle the refusal prints is accepted on a rerun ==="
P="$TMP/platform"; mkdir -p "$P"
printf 'int scale( int x, int f = 2 );\n' >"$P/lib.h"
printf '#include "lib.h"\nint scale( int x, int f ) { return x * f; }\n' >"$P/posix.cpp"
printf '#include "lib.h"\nint scale( int x, int f ) { return x + f; }\n' >"$P/win.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$P/use.cpp"
commit "$P"
roundTrip(){ # roundTrip <label> <corpus> <selector>
    ec "$2" "$3" >/dev/null
    if [ "$( rc )" != 1 ]; then no "$1: --edit-check=$3 exited $( rc ), expected the ambiguity refusal"; return; fi
    _list="$( sed -n 's/.*Qualify one contract: \(.*\) — e\.g\..*/\1/p' "$TMP/err" )"
    [ -n "$_list" ] || { no "$1: no handle list in the refusal: $( cat "$TMP/err" )"; return; }
    _n=0
    for _h in $( printf '%s' "$_list" | sed 's/ (+[0-9]* more contracts)//' | tr ',' ' ' ); do
        _n=$(( _n + 1 ))
        _o="$( ec "$2" "$_h" )"
        if [ "$( rc )" = 0 ] && [ -n "$( root "$_o" )" ]; then
            ok "$1: suggested handle '$_h' is accepted (exit 0)"
        else
            no "$1: suggested handle '$_h' is refused on rerun (exit $( rc )): $( cat "$TMP/err" )"
        fi
    done
    [ "$_n" -ge 2 ] || no "$1: the refusal listed $_n handle(s), expected at least 2"
}
roundTrip "(H) mismatched types" "$G" scale
roundTrip "(H) two platform definitions" "$P" scale
# the pre-apply preview keeps one contract per file, so it still refuses the field corpus; its handles must round-trip too
printf 'int scale( int x, int factor, int bias )\n{\n    return x;\n}\n' >"$TMP/payload.txt"
( cd "$F" && "$BIN" . --no-cache --edit-check=scale --edit-payload="$TMP/payload.txt" --dry-run >/dev/null 2>"$TMP/err" )
case "$( cat "$TMP/err" )" in
    *'./lib.h:scale'*) no "(H) the --dry-run refusal still offers ./lib.h:scale, which the preview refuses again: $( cat "$TMP/err" )" ;;
    *'Qualify one contract'*'@./lib.h:1'*) ok "(H) the --dry-run refusal offers @./lib.h:1 for the declaration, a handle that resolves to it alone" ;;
    *) no "(H) unexpected --dry-run answer: $( cat "$TMP/err" )" ;;
esac
OP="$( ec "$P" ./posix.cpp:scale )"
[ "$( attr "$( root "$OP" )" defaults_from )" = decl ] && [ -z "$( flagged "$OP" )" ] \
    && ok "(H) each platform definition still takes the shared header's defaults (posix.cpp: defaults_from=\"decl\", nothing flagged)" \
    || no "(H) ./posix.cpp:scale: flags=[$( flagged "$OP" )] defaults_from=\"$( attr "$( root "$OP" )" defaults_from )\""

echo "=== (I) an UNPROVEN declaration (no #include of it) lends no defaults ==="
U="$TMP/unproven"; mkdir -p "$U"
printf 'int scale( int x, int f = 2 );\n' >"$U/lib.h"
printf 'int scale( int x, int f ) { return x * f; }\n' >"$U/lib.cpp"
printf '#include "lib.h"\nint a1() { return scale( 1 ); }\n' >"$U/use.cpp"
commit "$U"
OU="$( ec "$U" ./lib.cpp:scale )"
[ "$( flagged "$OU" )" = a1 ] && [ -z "$( attr "$( root "$OU" )" defaults_from )" ] \
    && ok "(I) lib.cpp does not include lib.h: no defaults are borrowed, a1 stays flagged (the safe direction)" \
    || no "(I) flags=[$( flagged "$OU" )] defaults_from=\"$( attr "$( root "$OU" )" defaults_from )\""

echo "=== determinism + well-formedness ==="
O2="$( ec "$F" ./lib.cpp:scale )"
if [ "$O2" = "$OB" ]; then ok "GUARD: two runs byte-identical"; else no "GUARD: two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OB" | xmllint --noout - 2>/dev/null; then ok "GUARD: XML well-formed"; else no "GUARD: XML malformed"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
