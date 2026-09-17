#!/usr/bin/env bash
# lspcheck.sh — gate for --lsp, the Phase 1 navigation-LSP PoC (plan + locked decisions: docs/LSP.md).
#
# The gap this closes: ripwire answered agents (MCP) and shells (the CLI map), but no editor. --lsp is the
# third front door onto the SAME warm index; this gate is the fake LSP client that proves the door opens —
# Content-Length framing in and out, the five navigation methods, the lifecycle, and the two refusals —
# without any editor in the loop.
#
# RED-FIRST PROOF SHAPE: every arm asserts response BYTES (a capability name, a location line number, a
# merged field row, a hover sentence) — never a bare exit code. The baseline binary has no --lsp at all: it
# answers "unknown flag" with an EMPTY stdout, so every framing arm fails against it. Arms (4) and (11)
# additionally pin decisions the baseline could not make: (4) fails without the D8 field-side-table merge
# (a field is not a symbol, so an outline built from symbols alone never names "sides"), and (11) fails on
# any implementation that read didChange content into its answer (D1 — saved-state only).
#
# Arms:
#   (1)  initialize: capabilities bytes — positionEncoding utf-8, all five providers, openClose sync
#   (2)  definition: the call site resolves to the def's signature line, in the right file
#   (3)  references: the name-based use-site floor (the call line) + includeDeclaration adds the def line
#   (4)  documentSymbol: defs AND the merged FIELD row (D8), nested under the struct ("children":[{"name":"sides")
#   (5)  hover: verbatim signature + CSR degrees (callers 1) + the used-at link list + the standing floor
#        sentence (D6/D7)
#   (6)  workspace/symbol exact name (D9 first tier)
#   (7)  workspace/symbol substring over names (D9 second tier)
#   (8)  didChange content is NEVER answered (D1): the post-change hover equals the pre-change hover
#   (9)  protocol shape: exactly 9 responses to the 14-message dialog (notifications answer nothing)
#   (10) pre-initialize request refused with -32002; unknown method refused with -32601
#   (11) --lsp --mcp and --lsp --listen refused — "one protocol per stdin" (D10)
#   (12) shutdown answers null, exit ends the process 0
#   (13) determinism (x2, byte-identical dialogs — the house pattern)
#   (14) hover, Ruby: a class with no call edges still lists its constant-load uses as links (the sibling
#        file's `Quota.limit` line)
#   (15) traversal (#279 review, folded in from the reviewer's adversary driver): hover, definition and
#        documentSymbol on a file URI OUTSIDE the root — absolute, `..`-escaped, through a symlink inside the root,
#        and percent-encoded `%2e%2e` — answer null or [], and no response carries a byte of the outside file
#   (16) framing: a missing, non-numeric, negative or over-cap Content-Length, and a header flood with no
#        terminator, each end the session at exit 1 with nothing on stdout and the framing refusal on stderr,
#        inside a wall-clock cap (no hang)
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/lspcheck.sh   |   bash test/lspcheck.sh path/to/ripwire

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"

# C++ fixture — line numbers below are load-bearing (the arms address them):
#   L5  int scale( int f )      -> the def signature line (0-based line 4)
#   L4  int sides = 0           -> the FIELD side-table row (D8 — absent from ing.symbols)
#   L13 s.scale( 2 )            -> the one call site (0-based line 12)
cat > "$WORK/src/geo.cpp" <<'EOF'
// lsp fixture
struct Shape
{
    int sides = 0;
    int scale( int f )
    {
        return sides * f;
    }
};

int twice( const Shape& s )
{
    return s.scale( 2 );
}
EOF

# ─── the fake LSP client: Content-Length frames in, one decoded JSON per line out ────────────────────
msg(){ printf 'Content-Length: %d\r\n\r\n%s' "${#1}" "$1"; }

decodeFrames(){ python3 - "$1" <<'PY'
import sys
data = open( sys.argv[ 1 ], "rb" ).read()
i = 0
while i < len( data ):
    j = data.find( b"\r\n\r\n", i )
    if j == -1: sys.exit( "unterminated frame at %d" % i )
    cl = None
    for ln in data[ i : j ].decode().split( "\r\n" ):
        if ln.lower().startswith( "content-length:" ): cl = int( ln.split( ":", 1 )[ 1 ] )
    if cl is None: sys.exit( "frame without Content-Length" )
    body = data[ j + 4 : j + 4 + cl ]
    if len( body ) != cl: sys.exit( "short body" )
    print( body.decode() )
    i = j + 4 + cl
PY
}

uriInit="file://$WORK"
uriGeo="file://$WORK/src/geo.cpp"

# The main dialog: 14 messages, 9 answers (notifications answer nothing — arm (9)).
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\",\"languageId\":\"cpp\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15},\"context\":{\"includeDeclaration\":true}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":4,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"scale\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"sha\"}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\",\"version\":2},\"contentChanges\":[{\"text\":\"ZZZ never re-parsed in Phase 1 ZZZ\"}]}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":4,\"character\":10}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/dialog"

"$BIN" --lsp < "$WORK/dialog" > "$WORK/raw" 2>"$WORK/err"; RC=$?
decodeFrames "$WORK/raw" > "$WORK/resp" 2>"$WORK/decode.err"; DRC=$?
[ "$DRC" = 0 ] || { no "framing decode failed"; cat "$WORK/decode.err"; }

R(){ grep "\"id\":$1," "$WORK/resp"; }

# ── (1) initialize capabilities ──────────────────────────────────────────────────────────────────────
R1="$( R 1 )"
printf '%s' "$R1" | grep -q '"positionEncoding":"utf-8"' \
    && printf '%s' "$R1" | grep -q '"definitionProvider":true' \
    && printf '%s' "$R1" | grep -q '"referencesProvider":true' \
    && printf '%s' "$R1" | grep -q '"documentSymbolProvider":true' \
    && printf '%s' "$R1" | grep -q '"workspaceSymbolProvider":true' \
    && printf '%s' "$R1" | grep -q '"hoverProvider":true' \
    && printf '%s' "$R1" | grep -q '"openClose":true' \
    && ok "(1) initialize: utf-8 positions, five providers, openClose sync" \
    || { no "(1) initialize capabilities missing bytes"; printf '%s\n' "$R1" | head -c 400; }

# ── (2) definition: the call site at (12,15) resolves scale to its signature line (0-based 4) ────────
R2="$( R 2 )"
printf '%s' "$R2" | grep -q '"uri":"file://.*geo.cpp"' \
    && printf '%s' "$R2" | grep -q '"line":4' \
    && ok "(2) definition: the call resolves to the def's line, in the indexed file" \
    || { no "(2) definition location wrong"; printf '%s\n' "$R2" | head -c 400; }

# ── (3) references: floor site (the call line 12) + declaration (the def line 4) ──────────────────────
R3="$( R 3 )"
printf '%s' "$R3" | grep -q '"line":12' \
    && printf '%s' "$R3" | grep -q '"line":4' \
    && ok "(3) references: the name-matched use-site plus includeDeclaration's def" \
    || { no "(3) references missing a site"; printf '%s\n' "$R3" | head -c 400; }

# ── (4) documentSymbol: defs AND the merged field, nested under the struct (D8) ───────────────────────
R4="$( R 4 )"
printf '%s' "$R4" | grep -q '"name":"Shape"' \
    && printf '%s' "$R4" | grep -q '"name":"scale"' \
    && printf '%s' "$R4" | grep -q '"children":\[{"name":"sides"' \
    && printf '%s' "$R4" | grep -q '"kind":8' \
    && ok "(4) documentSymbol: field row merged (children open with sides, kind 8)" \
    || { no "(4) documentSymbol missing the merged field or nesting"; printf '%s\n' "$R4" | head -c 400; }

# ── (5) hover: verbatim signature + degrees + used-at links + the floor sentence ─────────────────────
R5="$( R 5 )"
printf '%s' "$R5" | grep -q 'int scale( int f )' \
    && printf '%s' "$R5" | grep -q 'callers 1' \
    && printf '%s' "$R5" | grep -q '\*\*Used at\*\*' \
    && printf '%s' "$R5" | grep -q '#L13' \
    && printf '%s' "$R5" | grep -q 'floors, not totals' \
    && ok "(5) hover: verbatim signature, CSR callers=1, the call line as a #L13 used-at link, the standing floor sentence" \
    || { no "(5) hover gist incomplete"; printf '%s\n' "$R5" | head -c 400; }

# ── (6/7) workspace/symbol: exact, then substring over names ─────────────────────────────────────────
R6="$( R 6 )"
printf '%s' "$R6" | grep -q '"name":"scale"' \
    && ok "(6) workspace/symbol: exact name hit" \
    || { no "(6) workspace/symbol exact miss"; printf '%s\n' "$R6" | head -c 300; }
R7="$( R 7 )"
printf '%s' "$R7" | grep -q '"name":"Shape"' \
    && ok "(7) workspace/symbol: substring tier finds Shape from 'sha'" \
    || { no "(7) workspace/symbol substring miss"; printf '%s\n' "$R7" | head -c 300; }

# ── (8) didChange content is NEVER answered (D1: saved-state only) ───────────────────────────────────
R8="$( R 8 )"
printf '%s' "$R8" | grep -q 'int scale( int f )' \
    && ! printf '%s' "$R8" | grep -q 'ZZZ' \
    && [ "$( printf '%s' "$R5" | sed 's/"id":[0-9]*//' )" = "$( printf '%s' "$R8" | sed 's/"id":[0-9]*//' )" ] \
    && ok "(8) post-didChange hover answers from disk, byte-equal to the pre-change one (D1)" \
    || { no "(8) didChange content leaked into the answer, or the hover moved"; printf '%s\n' "$R8" | head -c 300; }

# ── (9) protocol shape: 14 dialog messages, exactly 9 responses ──────────────────────────────────────
NRESP="$( grep -c . "$WORK/resp" 2>/dev/null || echo 0 )"
[ "$NRESP" = 9 ] \
    && ok "(9) exactly 9 responses to the 14-message dialog (notifications answered nothing)" \
    || { no "(9) response count wrong: got $NRESP, expected 9"; cat "$WORK/resp"; }

# ── (10) lifecycle refusals: pre-init request, unknown method ────────────────────────────────────────
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$uriGeo\"},\"position\":{\"line\":12,\"character\":15}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d2"
"$BIN" --lsp < "$WORK/d2" > "$WORK/raw2" 2>/dev/null
decodeFrames "$WORK/raw2" | grep -q '"code":-32002' \
    && ok "(10) pre-initialize request refused with -32002" \
    || { no "(10) pre-initialize not refused"; }
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"foo/bar\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d3"
"$BIN" --lsp < "$WORK/d3" > "$WORK/raw3" 2>/dev/null
decodeFrames "$WORK/raw3" | grep -q '"code":-32601' \
    && ok "(10) unknown method refused with -32601" \
    || { no "(10) unknown method not refused"; }

# ── (11) D10 refusals: --lsp beside the MCP transports ───────────────────────────────────────────────
E11="$( "$BIN" --lsp --mcp </dev/null 2>&1 >/dev/null )"; RC11=$?
[ "$RC11" = 1 ] && printf '%s' "$E11" | grep -q 'one protocol per stdin' \
    && ok "(11) --lsp --mcp refused, exit 1, the stdin sentence" \
    || { no "(11) --lsp --mcp not refused (exit $RC11)"; printf '%s\n' "$E11"; }
E11b="$( "$BIN" --lsp --listen=127.0.0.1:8765 </dev/null 2>&1 >/dev/null )"; RC11b=$?
[ "$RC11b" = 1 ] && printf '%s' "$E11b" | grep -q 'one protocol per stdin' \
    && ok "(11) --lsp --listen refused too" \
    || { no "(11) --lsp --listen not refused (exit $RC11b)"; printf '%s\n' "$E11b"; }

# ── (12) shutdown answered null and exit ended the session 0 ─────────────────────────────────────────
R99="$( R 99 )"
printf '%s' "$R99" | grep -q '"id":99,"result":null' \
    && [ "$RC" = 0 ] \
    && ok "(12) shutdown → null, exit → clean end (rc 0)" \
    || { no "(12) shutdown/exit wrong (rc $RC)"; printf '%s\n' "$R99" | head -c 200; }

# ── (13) determinism: two identical dialogs byte-identical ───────────────────────────────────────────
"$BIN" --lsp < "$WORK/dialog" > "$WORK/rawA" 2>/dev/null
"$BIN" --lsp < "$WORK/dialog" > "$WORK/rawB" 2>/dev/null
[ -s "$WORK/rawA" ] && cmp -s "$WORK/rawA" "$WORK/rawB" \
    && ok "(13) determinism: two dialogs byte-identical" \
    || { no "(13) dialogs differ (or empty)"; ls -l "$WORK/rawA" "$WORK/rawB"; }


# ── (14) hover: the Ruby constant floor — a class named only by another file's load directive ────────
mkdir -p "$WORK/rb"
cat > "$WORK/rb/ledger.rb" <<'EOF'
class Ledger
  def compute
    Quota.limit
  end
end
EOF
cat > "$WORK/rb/quota.rb" <<'EOF'
class Quota
  def self.limit
    100
  end

  def audit
    Ledger.new
  end
end
EOF
uriQuota="file://$WORK/rb/quota.rb"
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$uriQuota\",\"languageId\":\"ruby\",\"version\":1,\"text\":\"\"}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$uriQuota\"},\"position\":{\"line\":0,\"character\":7}}}"
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d4"
"$BIN" --lsp < "$WORK/d4" > "$WORK/raw4" 2>/dev/null
decodeFrames "$WORK/raw4" | grep '"id":20,' > "$WORK/r20"
grep -q '\*\*Referenced at\*\*' "$WORK/r20" \
    && grep -q 'ledger\.rb:3' "$WORK/r20" \
    && grep -q '#L3' "$WORK/r20" \
    && ok "(14) hover: the Ruby constant tier links Quota's use in the sibling file (ledger.rb:3)" \
    || { no "(14) hover Ruby constant tier missing"; head -c 400 "$WORK/r20"; }
# ── (15) traversal: a URI outside the root answers nothing, and never the outside file's bytes ─────────────
SECRET="$( mktemp -d )"; trap 'rm -rf "$WORK" "$SECRET"' EXIT
printf 'int leakMarkerFn() { return 42; } // LSP-TRAVERSAL-SECRET\n' > "$SECRET/secret.cpp"
ln -s "$SECRET" "$WORK/src/escape_link" 2>/dev/null
up=""; for _ in $( seq 1 24 ); do up="$up../"; done
enc=""; for _ in $( seq 1 24 ); do enc="$enc%2e%2e/"; done
i=10
{
  msg "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"$uriInit\",\"capabilities\":{}}}"
  for u in "file://$SECRET/secret.cpp" "file://$WORK/src/$up${SECRET#/}/secret.cpp" "file://$WORK/src/escape_link/secret.cpp" "file://$WORK/src/$enc${SECRET#/}/secret.cpp"; do
    msg "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$u\"},\"position\":{\"line\":0,\"character\":6}}}"
    msg "{\"jsonrpc\":\"2.0\",\"id\":$(( i + 1 )),\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$u\"},\"position\":{\"line\":0,\"character\":6}}}"
    msg "{\"jsonrpc\":\"2.0\",\"id\":$(( i + 2 )),\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"$u\"}}}"
    i=$(( i + 3 ))
  done
  msg "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}"
  msg "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}"
} > "$WORK/d15"
"$BIN" --lsp < "$WORK/d15" > "$WORK/raw15" 2>/dev/null; RC15=$?
decodeFrames "$WORK/raw15" > "$WORK/r15" 2>/dev/null
n15="$( grep -c '"id":\(1[0-9]\|2[01]\),' "$WORK/r15" )"
empty15="$( grep '"id":\(1[0-9]\|2[01]\),' "$WORK/r15" | grep -c '"result":\(null\|\[\]\)}' )"
if grep -q 'LSP-TRAVERSAL-SECRET\|leakMarkerFn' "$WORK/raw15"; then
    no "(15) traversal: a response carried the outside file's bytes"
elif [ "$RC15" = 0 ] && [ "$n15" = 12 ] && [ "$empty15" = 12 ]; then
    ok "(15) traversal: absolute, ..-escaped, symlinked and %2e%2e URIs outside the root answer null/[] (12 of 12), rc 0, no outside bytes"
else
    no "(15) traversal: rc=$RC15, $n15 responses, $empty15 empty (want 0 / 12 / 12)"; head -c 600 "$WORK/r15"
fi

# ── (16) framing refusals: bounded, silent on stdout, named on stderr ───────────────────────────────────────
CAPRUN="$ROOT/test/lib/caprun.py"
f16=""
printf 'Foo: bar\r\n\r\n{}' > "$WORK/f_missing"
printf 'Content-Length: abc\r\n\r\n{}' > "$WORK/f_nonnum"
printf 'Content-Length: -5\r\n\r\n{}' > "$WORK/f_negative"
{ printf 'Content-Length: 40000000\r\n\r\n'; head -c 1000 /dev/zero | tr '\0' x; } > "$WORK/f_overcap"
{ printf 'X-Pad: '; head -c 70000 /dev/zero | tr '\0' a; } > "$WORK/f_flood"
for case in missing nonnum negative overcap flood; do
    res="$( python3 "$CAPRUN" 10 --stdin "$WORK/f_$case" --stdout "$WORK/o_$case" --stderr "$WORK/e_$case" -- "$BIN" --lsp )"
    if [ "$res" = "${res#rc=1 }" ] || [ -s "$WORK/o_$case" ] || ! grep -q 'malformed Content-Length framing' "$WORK/e_$case"; then
        f16="$f16 $case[$res stdout=$( wc -c < "$WORK/o_$case" | tr -d ' ' )B]"
    fi
done
[ -z "$f16" ] && ok "(16) framing: missing / non-numeric / negative / over-cap Content-Length and a header flood each exit 1 within 10 s, stdout empty, the refusal named" \
             || no "(16) framing refusal wrong for:$f16"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
