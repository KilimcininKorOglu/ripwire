#!/usr/bin/env bash
# mcptwinclaimscheck.sh — three MCP answers that claimed more than they checked (0.6.6 command sweep).
#
# The sweep ran every CLI verb and its MCP twin over three repositories and graded each answer against the
# source. Three MCP answers were FALSE or self-contradictory where the CLI was right:
#
#   (A) whereis   — the MCP twin passed the tree scan no index evidence, so its HEAD rows kept the lexical
#                   shape test and a CALL SITE read kind="def" (`const auto ep = rw::escapeXml( …` in
#                   src/mcpverbs.h), with head_labels="lexical" beside it. The CLI, holding the index,
#                   labelled the same row kind="ref". Contract: both surfaces label HEAD from the index, so
#                   the (p, l, kind) set of HEAD rows and head_labels= are identical.
#   (B) uses      — for a name with no indexed definition and no indexed REFERENCE, the refusal said "no
#                   use-site under that spelling". The scan behind it reads indexed reference edges only; a
#                   member access on an unindexed field (a TypeScript interface property, `row.valueToken`)
#                   is a use-site it never looks at. The CLI says only "matched no indexed definition".
#                   Contract: the refusal names what was checked and never claims "no use-site".
#   (C) find_symbol — `count` / `hop_tested` / `hop_untested` describe the CALLS array, and sat unlabelled next
#                   to `calledBy_total` ("count":0 beside "calledBy_total":67 on a leaf). Contract: the payload
#                   names the array count= describes (count_of="calls"), and count equals that array's total.
#
# Usage: bash test/mcptwinclaimscheck.sh [path/to/ripwire]     (default build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

FIX="$( mktemp -d )"
trap 'rm -rf "$FIX"' EXIT

# One C pair: helper() is defined in lib.c and CALLED in use.c on a line that wraps after its closing ')', which
# is the shape the lexical test reads as a definition. One TypeScript interface property read via a member access.
mkdir -p "$FIX/ts"
cat > "$FIX/lib.c" <<'EOF'
int helper( int x ) { return x + 1; }
EOF
cat > "$FIX/use.c" <<'EOF'
int helper( int x );
int caller( int x )
{
    int ep = helper( x )
        + 1;
    return ep;
}
EOF
cat > "$FIX/ts/display.ts" <<'EOF'
interface Row { valueToken: string; }
export function show( row: Row ): string { return row.valueToken; }
EOF
( cd "$FIX" && git init -q -b main . && git add -A \
    && git -c user.name=fx -c user.email=fx@example.invalid commit -qm seed ) >/dev/null 2>&1 \
    || { echo "  FAIL  fixture: git commit failed"; echo "1 CHECK(S) FAILED"; exit 1; }

python3 - "$BIN" "$FIX" <<'PY'
import json, re, subprocess, sys

BIN, FIX = sys.argv[1], sys.argv[2]
fails = 0
def ok( m ):   print( "  PASS  " + m )
def no( m ):
    global fails
    fails += 1
    print( "  FAIL  " + m )

def mcp( verb, args ):
    msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize" },
             { "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": { "name": verb, "arguments": args } } ]
    p = subprocess.run( [ BIN, "--mcp" ], input = "".join( json.dumps( m ) + "\n" for m in msgs ),
                        capture_output = True, text = True, timeout = 300 )
    last = [ l for l in p.stdout.splitlines() if l.strip() ][ -1 ]
    d = json.loads( last )
    if "error" in d:
        return None, d[ "error" ].get( "message", "" )
    res = d.get( "result", {} )
    text = res.get( "content", [ {} ] )[ 0 ].get( "text", "" )
    return ( None, text ) if res.get( "isError" ) else ( text, None )

def cli( args ):
    p = subprocess.run( [ BIN, FIX ] + args + [ "--no-cache" ], capture_output = True, text = True, timeout = 300 )
    return p.stdout, p.stderr, p.returncode

def headRows( xml ):
    rows = set()
    for m in re.finditer( r'<hit ref="HEAD"[^>]*/>', xml ):
        h = m.group( 0 )
        g = lambda k: ( re.search( r'\b' + k + r'="([^"]*)"', h ) or [ None, "" ] )[ 1 ]
        rows.add( ( g( "p" ), g( "l" ), g( "kind" ) ) )
    return rows

# ── (A) whereis: the call site on use.c:4 is a reference on BOTH surfaces, labelled by the same mechanism ──
cx, _, _ = cli( [ "--whereis=helper" ] )
mx, merr = mcp( "whereis", { "path": FIX, "symbol": "helper" } )
if mx is None:
    no( "(A) MCP whereis refused: %s" % merr )
else:
    cr, mr = headRows( cx ), headRows( mx )
    ( ok if ( "use.c", "4", "ref" ) in cr else no )( "(A) CLI whereis: the wrapped call use.c:4 reads kind=\"ref\" (fixture sanity)" )
    ( ok if ( "use.c", "4", "ref" ) in mr else no )( "(A) MCP whereis: the wrapped call use.c:4 reads kind=\"ref\", not def (got %s)" % sorted( mr ) )
    ( ok if cr == mr and cr else no )( "(A) HEAD rows (p, l, kind) identical on CLI and MCP (cli=%s mcp=%s)" % ( sorted( cr ), sorted( mr ) ) )
    hl = lambda x: ( re.search( r'head_labels="([^"]*)"', x ) or [ None, "" ] )[ 1 ]
    ( ok if hl( cx ) == hl( mx ) == "index" else no )( "(A) head_labels= is index on both surfaces (cli=%s mcp=%s)" % ( hl( cx ), hl( mx ) ) )

# ── (B) uses: a refusal claims only what was checked ──
_, cerr, crc = cli( [ "--uses=valueToken" ] )
( ok if crc != 0 and "no indexed definition" in cerr else no )( "(B) CLI --uses=valueToken refuses on no indexed definition (fixture sanity; rc=%d)" % crc )
ut, uerr = mcp( "uses", { "path": FIX, "symbol": "valueToken" } )
if ut is not None:
    ok( "(B) MCP uses answers valueToken (field indexed): nothing to over-claim" )
else:
    ( ok if "no use-site" not in uerr else no )( "(B) MCP uses refusal does not claim \"no use-site\" (row.valueToken is one): %s" % uerr[ :240 ] )
    ( ok if "no indexed definition" in uerr else no )( "(B) MCP uses refusal still names the checked fact (no indexed definition)" )
# the batch verb speaks the same refusal
bt, berr = mcp( "batch", { "path": FIX, "queries": [ { "verb": "uses", "symbol": "valueToken" } ] } )
btxt = ( bt or "" ) + ( berr or "" )
( ok if "no use-site" not in btxt else no )( "(B) batch uses sub-answer does not claim \"no use-site\"" )

# ── (C) find_symbol: count= names its array and matches it ──
ft, ferr = mcp( "find_symbol", { "path": FIX, "symbol": "helper" } )
if ft is None:
    no( "(C) MCP find_symbol refused: %s" % ferr )
else:
    j = json.loads( ft )
    ( ok if j.get( "calledBy_total", len( j.get( "calledBy", [] ) ) ) >= 1 else no )( "(C) fixture sanity: helper has a caller" )
    ( ok if j.get( "count_of" ) == "calls" else no )( "(C) find_symbol names the array count= describes (count_of=%r)" % j.get( "count_of" ) )
    ( ok if j.get( "count" ) == len( j.get( "calls", [] ) ) and j.get( "hop_tested", 0 ) + j.get( "hop_untested", 0 ) == j.get( "count" ) else no )(
        "(C) count= (%r) and hop_tested+hop_untested equal the calls array's total (%d)" % ( j.get( "count" ), len( j.get( "calls", [] ) ) ) )
    rt, rerr = mcp( "find_referencing_symbols", { "path": FIX, "symbol": "helper" } )
    rj = json.loads( rt ) if rt else {}
    ( ok if rj.get( "count" ) == len( rj.get( "calledBy", [] ) ) and "count_of" not in rj else no )(
        "(C) find_referencing_symbols: count= is the calledBy total, its only array (no count_of needed)" )

print( "%d CHECK(S) FAILED" % fails if fails else "ALL CHECKS PASSED" )
sys.exit( 1 if fails else 0 )
PY
rc=$?
exit $rc
