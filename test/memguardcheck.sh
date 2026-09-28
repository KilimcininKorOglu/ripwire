#!/usr/bin/env bash
# memguardcheck.sh — #350 layers 1 + 3: a root nobody chose is refused, and memory is bounded on every root.
#
# The incident: an MCP server started in a home directory that is not a git repository crawled it for 7 hours
# and reached a 67 GB footprint. Two layers are pinned here (layer 2, the non-git crawl budget, is separate):
#
#   (A) layer 1 — an IMPLICIT root that is $HOME itself (git repo or not), "/" or a system directory is refused
#       with one honest line, on the CLI (no positional root, cwd there) and on the MCP server (launch cwd, no
#       path= in the request); the server stays up. An EXPLICIT path is honoured, the home directory included.
#   (B) layer 3 — the memory guard. A tiny --max-memory stops the crawl or the parse and the map answers from
#       what was built, DISCLOSED in its header (memory_stop=), well-formed and deterministic; a limit no partial
#       answer fits under is a clean exit 5 naming the limit and the override; a verb that cannot carry the
#       disclosure refuses rather than answering from a partial index.
#   (C) a default run is byte-identical to the same run with the guard's limit made huge (flag and env).
#   (D) bad --max-memory / RIPWIRE_MAX_MEMORY values are refused with a message.
#
# Real footprints are machine-dependent, so the partial arms inject the trip instead: RIPWIRE_TEST_MEMGUARD=
# crawl:N makes the crawl's Nth guarded entry read as over its line, parse:N the Nth parsed file, request:N the
# Nth MCP tool call's pre-check; the 5 s time gate is off under it. The stop, the partial answer and the
# disclosure are the real code paths; only the footprint reading is replaced. Nothing here crawls a real home
# directory or a system tree: every home is a fake one under a temp dir, and the system-directory arms only
# ever reach the refusal (a regression that crawled instead would still be a tiny /dev walk).
#
#   bash test/memguardcheck.sh [path/to/ripwire]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMP="$( cd "$TMP" && pwd -P )"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "memguardcheck: BIN=$BIN"
unset RIPWIRE_MAX_MEMORY RIPWIRE_TEST_MEMGUARD_UNIT

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────
# FX: 72 C files in 4 directories, each function calling the previous one (a real call graph to rank).
FX="$TMP/fx"
for d in a b c d; do
    mkdir -p "$FX/$d"
    for i in $( seq -w 0 17 ); do
        printf 'int %s%s( int x );\nint %s_%s( int x ) { return x > 0 ? %s_%s( x - 1 ) : 0; }\n' \
            "p" "$i" "$d" "$i" "$d" "$i" >"$FX/$d/f$i.c"
    done
done

HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR/proj"
printf 'int hp( void ) { return 1; }\nint hq( void ) { return hp(); }\n' >"$HOMEDIR/proj/p.c"
printf 'int dot( void ) { return 0; }\n' >"$HOMEDIR/dot.c"
GITHOME="$TMP/githome"; mkdir -p "$GITHOME/proj"
cp "$HOMEDIR/proj/p.c" "$GITHOME/proj/p.c"
git -C "$GITHOME" init -q 2>/dev/null

mcp_call(){   # $1 = cwd, $2.. = extra argv; stdin = request lines (after initialize)
    local cwd="$1"; shift
    { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'; cat; } | ( cd "$cwd" && "$BIN" --mcp "$@" 2>/dev/null )
}
mcp_field(){  # $1 = response file, $2 = id, $3 = error|text|<envelope key>
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, want_id, what = sys.argv[1], int( sys.argv[2] ), sys.argv[3]
for line in open( path, encoding="utf-8", errors="replace" ):
    line = line.strip()
    if not line.startswith( "{" ):
        continue
    try:
        r = json.loads( line )
    except ValueError:
        continue
    if r.get( "id" ) != want_id:
        continue
    res = r.get( "result", {} )
    if what == "error":
        e = r.get( "error" )
        if e:
            print( e.get( "message", "" ) ); break
        if res.get( "isError" ):
            print( "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ) ); break
        print( "" ); break
    if what == "text":
        print( "".join( c.get( "text", "" ) for c in res.get( "content", [] ) ) ); break
    print( res.get( what, "" ) ); break
PY
}

echo "=== (A) layer 1: an implicit home/system root is refused; an explicit one is honoured ==="

# (A1) CLI, no positional root, cwd = $HOME (not a git repo): one honest line, exit 1
( cd "$HOMEDIR" && HOME="$HOMEDIR" "$BIN" --grep=dot >"$TMP/a1.out" 2>"$TMP/a1.err" ); rc=$?
if [ "$rc" = 1 ] && grep -q "no project root: $HOMEDIR is a home/system directory; pass a project path" "$TMP/a1.err" && [ ! -s "$TMP/a1.out" ]; then
    ok "(A1) CLI with no root in \$HOME refuses with the no-project-root line (exit 1, empty stdout)"
else
    no "(A1) rc=$rc stderr: $( head -c 300 "$TMP/a1.err" )"
fi

# (A2) the same when $HOME is itself a git repository (a dotfiles repo is still nobody's project root)
( cd "$GITHOME" && HOME="$GITHOME" "$BIN" --grep=hp >"$TMP/a2.out" 2>"$TMP/a2.err" ); rc=$?
if [ "$rc" = 1 ] && grep -q "no project root: $GITHOME is a home/system directory" "$TMP/a2.err"; then
    ok "(A2) a git-repo \$HOME is refused as an implicit root too"
else
    no "(A2) rc=$rc stderr: $( head -c 300 "$TMP/a2.err" )"
fi

# (A3) CLI, no root, cwd = a directory that is neither home nor system: the usage refusal, unchanged
( cd "$HOMEDIR/proj" && HOME="$HOMEDIR" "$BIN" --grep=hp >/dev/null 2>"$TMP/a3.err" ); rc=$?
if [ "$rc" = 1 ] && ! grep -q "no project root" "$TMP/a3.err"; then
    ok "(A3) a missing root in an ordinary directory keeps the plain usage refusal"
else
    no "(A3) rc=$rc stderr: $( head -c 200 "$TMP/a3.err" )"
fi

# (A4) MCP launched in $HOME, request omits path: the tool answers "no project root", the server stays up
printf '%s\n' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"hp"}}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$HOMEDIR/proj\",\"symbol\":\"hp\"}}}" \
    | HOME="$HOMEDIR" mcp_call "$HOMEDIR" >"$TMP/a4.out"
e2="$( mcp_field "$TMP/a4.out" 2 error )"; t3="$( mcp_field "$TMP/a4.out" 3 text )"
case "$e2" in *"no project root: $HOMEDIR is a home/system directory; pass a project path"*) a4=ok;; *) a4=no;; esac
if [ "$a4" = ok ]; then
    ok "(A4) MCP in \$HOME: a path-less request answers no-project-root"
else
    no "(A4) id=2 answered: ${e2:0:300}"
fi
case "$t3" in *hp*) ok "(A4b) the server stayed up: the next request (explicit subfolder) answers";; *) no "(A4b) id=3: ${t3:0:200}";; esac

# (A5) MCP launched in a git-repo $HOME: refused the same way
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"pattern":"hp"}}}' \
    | HOME="$GITHOME" mcp_call "$GITHOME" >"$TMP/a5.out"
case "$( mcp_field "$TMP/a5.out" 2 error )" in *"no project root: $GITHOME is a home/system directory"*) ok "(A5) MCP in a git-repo \$HOME refuses too";;
    *) no "(A5) id=2: $( mcp_field "$TMP/a5.out" 2 error | head -c 300 )";; esac

# (A6) MCP launched in "/" and in a system directory (/dev): refused, naming the directory
for sysdir in / /dev; do
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"find_symbol","arguments":{"symbol":"hp"}}}' \
        | HOME="$HOMEDIR" mcp_call "$sysdir" >"$TMP/a6.out"
    case "$( mcp_field "$TMP/a6.out" 2 error )" in
        *"missing required field: path"*"no project root: $sysdir is a home/system directory"*) ok "(A6) MCP launched in $sysdir refuses with no-project-root";;
        *) no "(A6) MCP in $sysdir: $( mcp_field "$TMP/a6.out" 2 error | head -c 300 )";; esac
done

# (A7) an EXPLICIT path is honoured: the home directory itself on the CLI and over MCP, and a subfolder
HOME="$HOMEDIR" "$BIN" "$HOMEDIR" --no-cache >"$TMP/a7.out" 2>/dev/null; rc=$?
if [ "$rc" = 0 ] && grep -q 'n="dot"' "$TMP/a7.out"; then
    ok "(A7) CLI: an explicit path to \$HOME is honoured (map, exit 0)"
else
    no "(A7) rc=$rc"
fi
( cd "$HOMEDIR" && HOME="$HOMEDIR" "$BIN" proj --no-cache >"$TMP/a7b.out" 2>/dev/null ); rc=$?
if [ "$rc" = 0 ] && grep -q 'n="hq"' "$TMP/a7b.out"; then
    ok "(A7b) CLI: an explicit subfolder from inside \$HOME works"
else
    no "(A7b) rc=$rc"
fi
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$HOMEDIR\",\"symbol\":\"dot\"}}}" \
    | HOME="$HOMEDIR" mcp_call "$HOMEDIR" >"$TMP/a7c.out"
case "$( mcp_field "$TMP/a7c.out" 2 text )" in *dot*) ok "(A7c) MCP: an explicit path= to \$HOME is honoured";; *) no "(A7c) $( head -c 300 "$TMP/a7c.out" )";; esac
( cd "$HOMEDIR" && HOME="$HOMEDIR" "$BIN" "$HOMEDIR" --mcp </dev/null >/dev/null 2>&1 ); rc=$?
if [ "$rc" = 0 ]; then
    ok "(A7d) MCP: an explicit startup root equal to \$HOME starts"
else
    no "(A7d) rc=$rc"
fi

echo "=== (B) layer 3: the memory guard stops cleanly and says so ==="

run_trip(){ RIPWIRE_TEST_MEMGUARD="$1" "$BIN" "${@:2}"; }

# (B1) crawl stop at the 30th entry: the map answers from what the crawl saw, and says so
run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b1a.out" 2>"$TMP/b1a.err"; rc=$?
run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b1b.out" 2>/dev/null
hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b1a.out" | head -1 )"
files="$( printf '%s' "$hdr" | grep -oE 'files=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
if [ "$rc" = 0 ]; then
    ok "(B1) a crawl stop still answers (exit 0)"
else
    no "(B1) rc=$rc stderr: $( head -c 300 "$TMP/b1a.err" )"
fi
case "$hdr" in *"memory_stop=crawl"*"memory_limit=64M"*) ok "(B1b) the header discloses memory_stop=crawl and memory_limit=64M";; *) no "(B1b) header: $hdr";; esac
if [ -n "$files" ] && [ "$files" -gt 0 ] && [ "$files" -lt 30 ]; then
    ok "(B1c) files=$files: a partial corpus, not a total (72 in the tree)"
else
    no "(B1c) files=${files:-<none>}"
fi
if perl -ne 'print $1 if /^(<!-- ripwire map.*?-->)/' "$TMP/b1a.out" | grep -q 'memory_stop='; then
    ok "(B1d) the answer's own legend defines memory_stop="
else
    no "(B1d) the legend does not define memory_stop="
fi
if xmllint --noout "$TMP/b1a.out" 2>/dev/null; then
    ok "(B1e) the partial map is well-formed (xmllint)"
else
    no "(B1e) xmllint rejected the partial map"
fi
if cmp -s "$TMP/b1a.out" "$TMP/b1b.out"; then
    ok "(B1f) the partial map is byte-identical across two runs"
else
    no "(B1f) two runs differ"
fi
if [ "$( wc -l <"$TMP/b1a.err" | tr -d ' ' )" = 1 ] && grep -q "memory guard" "$TMP/b1a.err"; then
    ok "(B1g) stderr carries the one-line note too"
else
    no "(B1g) stderr: $( head -c 300 "$TMP/b1a.err" )"
fi

# (B2) parse stop at the 10th parsed file: the crawl was whole, the parse was not
run_trip parse:10 "$FX" --max-memory=64M --no-cache >"$TMP/b2.out" 2>"$TMP/b2.err"; rc=$?
hdr="$( grep -oE '<!-- files=[^>]*-->' "$TMP/b2.out" | head -1 )"
parsed="$( printf '%s' "$hdr" | grep -oE 'memory_parsed=[0-9]+' | grep -oE '[0-9]+' )"
if [ "$rc" = 0 ] && case "$hdr" in *"files=72 "*"memory_stop=parse"*) true;; *) false;; esac; then
    ok "(B2) a parse stop: the crawl was whole (files=72), the header says memory_stop=parse"
else
    no "(B2) rc=$rc header: $hdr"
fi
if [ -n "$parsed" ] && [ "$parsed" -ge 10 ] && [ "$parsed" -lt 72 ]; then
    ok "(B2b) memory_parsed=$parsed of files=72"
else
    no "(B2b) memory_parsed=${parsed:-<none>}"
fi
if xmllint --noout "$TMP/b2.out" 2>/dev/null; then
    ok "(B2c) the parse-stopped map is well-formed"
else
    no "(B2c) xmllint rejected it"
fi
if perl -ne 'print $1 if /^(<!-- ripwire map.*?-->)/' "$TMP/b2.out" | grep -q 'memory_parsed='; then
    ok "(B2d) the legend defines memory_parsed="
else
    no "(B2d) the legend does not define memory_parsed="
fi
mkdir -p "$TMP/cachedir"
TMPDIR="$TMP/cachedir" run_trip parse:10 "$FX" --max-memory=64M >/dev/null 2>&1
TMPDIR="$TMP/cachedir" "$BIN" "$FX" >"$TMP/b2e.out" 2>/dev/null
"$BIN" "$FX" --no-cache >"$TMP/b2f.out" 2>/dev/null
if cmp -s "$TMP/b2e.out" "$TMP/b2f.out"; then
    ok "(B2e) a partial parse was never cached: the next run is whole"
else
    no "(B2e) a later run differs from a clean one"
fi

# (B3) nothing built yet when the guard trips: exit 5, one line naming the limit and both overrides, no map
run_trip crawl:1 "$FX" --max-memory=64M --no-cache >"$TMP/b3.out" 2>"$TMP/b3.err"; rc=$?
if [ "$rc" = 5 ]; then
    ok "(B3) no partial answer possible: exit 5"
else
    no "(B3) rc=$rc"
fi
if [ ! -s "$TMP/b3.out" ]; then
    ok "(B3b) nothing on stdout"
else
    no "(B3b) stdout: $( head -c 200 "$TMP/b3.out" )"
fi
if [ "$( wc -l <"$TMP/b3.err" | tr -d ' ' )" = 1 ] && grep -q 'memory limit' "$TMP/b3.err" && grep -q '64M' "$TMP/b3.err" && grep -q -- '--max-memory' "$TMP/b3.err" && grep -q 'RIPWIRE_MAX_MEMORY' "$TMP/b3.err"; then
    ok "(B3c) one stderr line naming the limit and both overrides"
else
    no "(B3c) stderr: $( cat "$TMP/b3.err" )"
fi

# (B4) a verb that cannot carry the disclosure refuses instead of answering from a partial index
run_trip crawl:30 "$FX" --max-memory=64M --no-cache --callers=a_03 >"$TMP/b4.out" 2>"$TMP/b4.err"; rc=$?
if [ "$rc" = 5 ] && [ ! -s "$TMP/b4.out" ] && grep -q -- '--callers' "$TMP/b4.err"; then
    ok "(B4) --callers under a crawl stop refuses (exit 5, names the verb)"
else
    no "(B4) rc=$rc stderr: $( head -c 300 "$TMP/b4.err" )"
fi

# (B5) the env var is the same knob; the flag wins over it
RIPWIRE_MAX_MEMORY=64M run_trip crawl:30 "$FX" --no-cache >"$TMP/b5.out" 2>/dev/null
if cmp -s "$TMP/b1a.out" "$TMP/b5.out"; then
    ok "(B5) RIPWIRE_MAX_MEMORY=64M == --max-memory=64M"
else
    no "(B5) env and flag differ"
fi
RIPWIRE_MAX_MEMORY=1G run_trip crawl:30 "$FX" --max-memory=64M --no-cache >"$TMP/b5b.out" 2>/dev/null
if cmp -s "$TMP/b1a.out" "$TMP/b5b.out"; then
    ok "(B5b) the flag wins over the env var"
else
    no "(B5b) the flag did not win"
fi

# (B6) MCP: a soft stop answers with the envelope disclosure, and every answer from that partial index keeps it
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$FX\",\"symbol\":\"a_02\"}}}" \
    | RIPWIRE_TEST_MEMGUARD=crawl:30 mcp_call "$TMP" --max-memory=64M >"$TMP/b6.out"
ms2="$( mcp_field "$TMP/b6.out" 2 _memory_stop )"; ms3="$( mcp_field "$TMP/b6.out" 3 _memory_stop )"
case "$ms2" in *"memory guard"*crawl*64M*) ok "(B6) MCP grep under a crawl stop carries _memory_stop";; *) no "(B6) id=2 _memory_stop='${ms2:0:200}' resp: $( head -c 300 "$TMP/b6.out" )";; esac
case "$ms3" in *"memory guard"*) ok "(B6b) the next answer from the same partial index still carries it";; *) no "(B6b) id=3 _memory_stop='${ms3:0:200}'";; esac
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    | mcp_call "$TMP" >"$TMP/b6c.out"
if grep -q '_memory_stop' "$TMP/b6c.out"; then
    no "(B6c) a normal MCP answer carries _memory_stop"
else
    ok "(B6c) a normal MCP answer carries no _memory_stop"
fi

# (B7) MCP: over the hard limit a tool call is refused by name, and the server stays up
printf '%s\n' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"grep\",\"arguments\":{\"path\":\"$FX\",\"pattern\":\"a_01\"}}}" \
    '{"jsonrpc":"2.0","id":4,"method":"tools/list"}' \
    | RIPWIRE_TEST_MEMGUARD=request:2 mcp_call "$TMP" --max-memory=64M >"$TMP/b7.out"
if [ -z "$( mcp_field "$TMP/b7.out" 2 error )" ]; then
    ok "(B7) the first call is answered"
else
    no "(B7) id=2: $( mcp_field "$TMP/b7.out" 2 error | head -c 200 )"
fi
case "$( mcp_field "$TMP/b7.out" 3 error )" in *"memory limit"*64M*) ok "(B7b) over the hard limit the next tool call is refused by name";;
    *) no "(B7b) id=3: $( mcp_field "$TMP/b7.out" 3 error | head -c 300 )";; esac
if grep -q '"id":4' "$TMP/b7.out"; then
    ok "(B7c) the server stayed up (tools/list answered)"
else
    no "(B7c) no answer to id=4"
fi

echo "=== (C) a default run is byte-identical to the guard made huge ==="
for tree in "$FX" "$ROOT/test/fixture"; do
    "$BIN" "$tree" --no-cache >"$TMP/c_def.out" 2>&1
    "$BIN" "$tree" --no-cache --max-memory=1024G >"$TMP/c_big.out" 2>&1
    RIPWIRE_MAX_MEMORY=1024G "$BIN" "$tree" --no-cache >"$TMP/c_env.out" 2>&1
    if cmp -s "$TMP/c_def.out" "$TMP/c_big.out" && cmp -s "$TMP/c_def.out" "$TMP/c_env.out"; then
        ok "(C) $( basename "$tree" ): default == --max-memory=1024G == RIPWIRE_MAX_MEMORY=1024G"
    else
        no "(C) $( basename "$tree" ): the guard's limit changed a normal run's bytes"
    fi
    if grep -q 'memory_' "$TMP/c_def.out"; then
        no "(C) a default run mentions memory_"
    else
        ok "(C) no memory_ attribute on a normal run"
    fi
done

echo "=== (D) bad values are refused with a message ==="
for v in "" abc 0 10 64K -5 5X 1.5G 99999999999999999999G; do
    "$BIN" "$FX" --max-memory="$v" >/dev/null 2>"$TMP/d.err"; rc=$?
    if [ "$rc" = 1 ] && grep -q -- '--max-memory' "$TMP/d.err"; then
        ok "(D) --max-memory='$v' refused (exit 1, names the flag)"
    else
        no "(D) --max-memory='$v' rc=$rc stderr: $( head -c 200 "$TMP/d.err" )"
    fi
done
RIPWIRE_MAX_MEMORY=abc "$BIN" "$FX" >/dev/null 2>"$TMP/d2.err"; rc=$?
if [ "$rc" = 1 ] && grep -q 'RIPWIRE_MAX_MEMORY' "$TMP/d2.err"; then
    ok "(D) RIPWIRE_MAX_MEMORY=abc refused (exit 1, names the variable)"
else
    no "(D) RIPWIRE_MAX_MEMORY=abc rc=$rc stderr: $( head -c 200 "$TMP/d2.err" )"
fi
"$BIN" "$FX" --max-memory=64M >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ]; then
    ok "(D) the floor itself (64M) is accepted"
else
    no "(D) --max-memory=64M rc=$rc"
fi

echo
[ "$fail" = 0 ] && echo "memguardcheck: PASS" || echo "memguardcheck: FAIL"
exit "$fail"
