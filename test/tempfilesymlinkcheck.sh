#!/usr/bin/env bash
# tempfilesymlinkcheck.sh — the TEMP file of a tmp+rename publish is created exclusively, refusing an
# existing entry at its own name (rw::pathguard::createExclTempFile).
#
# THE PROPERTY THIS GATE ASSERTS. Three "atomic" publish writers reach their final name only through a
# rename() of a temp file they create beside it:
#
#     mcpedit::atomicWrite        (an edited source file)
#     quality::atomicWriteFile    (.ripwire_quality_acks, qsnap / qbody / …)
#     ingest::saveCache           (an in-tree --cache= / --index-out= blob)
#
# Each now creates that temp with O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC under a CSPRNG-drawn name: an existing
# entry at the chosen name — a symlink or a regular file — yields EEXIST and is never opened, followed or
# truncated, and a fresh draw simply picks another name so a stray entry cannot block the write either. The
# temp lives next to the target (a rename is atomic only within one filesystem). The mechanism (the open
# flags, one shared helper) is pinned by sidecarsymlinkcheck.sh arms (f6)/(f7); this gate is the behavioural,
# end-to-end half over the three writers.
#
# HOW THE ARM ADDRESSES A TEMP NAME. The temp-name shape is derived from the WRITER's getpid(), and a shell
# that `exec`s ripwire keeps its pid, so a fixture that places `ln -s outside <path>.$$.tmp` and then execs
# the tool has put an existing entry at a name of that exact shape. Deterministic, no race, drives the REAL
# binary. atomicWriteFile also appends a process-wide counter that the same run's cache writes advance, so
# the ack arm covers the low range of that counter.
#
# ARMS, per writer:
#   (a) the outside file the temp-name symlink points at is byte-identical after the writer runs
#   (b) the outside file's MODE is unchanged (mcpedit fchmods the temp; it must not reach the link target)
#   (c) the target is a REGULAR file afterwards, not a symlink left in place over it
#   (d) POSITIVE CONTROL: with no symlink present, the same writer still publishes its file with real content
#
# Red on main, green after.
#
# Usage:  bash test/tempfilesymlinkcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/tempfilesymlinkcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required";     exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME"   # never the user's cache, never the checkout
echo "tempfilesymlinkcheck: BIN=$BIN  TMP=$TMP"

OUTSIDE_BYTES='important user data'
OUTSIDE_MODE=700

# place_outside FILE — a distinctive file at a known mode, outside any tree the writer indexes.
place_outside(){ printf '%s' "$OUTSIDE_BYTES" > "$1"; chmod "$OUTSIDE_MODE" "$1"; }

# filemode FILE — permission bits in octal (GNU coreutils stat, else BSD / macOS stat).
if stat --version >/dev/null 2>&1; then filemode(){ stat -c %a "$1" 2>/dev/null; }
else                                    filemode(){ stat -f %Lp "$1" 2>/dev/null; }
fi

# assert_outside TAG OUTSIDE_FILE — (a) bytes and (b) mode are unchanged.
assert_outside(){
    local tag="$1" v="$2" got mode
    got="$( cat "$v" 2>/dev/null )"
    [ "$got" = "$OUTSIDE_BYTES" ] \
        && ok "($tag a) the outside file the temp-name symlink points at is byte-identical (never followed)" \
        || no "($tag a) the outside file was overwritten through the temp-name symlink: '$( printf '%s' "$got" | head -c 40 )'"
    mode="$( filemode "$v" )"
    [ "$mode" = "$OUTSIDE_MODE" ] \
        && ok "($tag b) the outside's mode is unchanged ($OUTSIDE_MODE)" \
        || no "($tag b) the outside's mode changed $OUTSIDE_MODE → $mode (an fchmod reached the link target)"
}

# ── writer 1: mcpedit::atomicWrite via --replace-symbol-body (temp <file>.<pid>.tmp) ──────────────────────
E="$TMP/edit"; mkdir -p "$E/tree"
printf 'int helper( int x ) { return x + 1; }\nint main( void ) { return helper( 1 ); }\n' > "$E/tree/a.c"; chmod 0644 "$E/tree/a.c"
printf 'int helper( int x ) { return x + 2; }\n' > "$E/payload.c"
place_outside "$E/outside"
( cd "$E" && sh -c 'ln -s "$1" "tree/a.c.$$.tmp" && exec "$2" tree --replace-symbol-body=helper --edit-payload=payload.c' _ "$E/outside" "$BIN" ) > "$E/out" 2> "$E/err"
assert_outside "mcpedit" "$E/outside"
[ -L "$E/tree/a.c" ] \
    && no "(mcpedit c) the edited file was left as a symlink to the outside (the temp link was renamed over it)" \
    || ok "(mcpedit c) the edited file is a regular file, not a symlink left over it"

# ── writer 2: quality::atomicWriteFile via --quality-ack (temp <ledger>.tmp.<pid>.0) ──────────────────────
Q="$TMP/ack"; mkdir -p "$Q/w"
printf 'def qComplex( a, b ):\n    if a > b:\n        return a\n    return b\n' > "$Q/w/q.py"
( cd "$Q/w" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init ) >/dev/null 2>&1
python3 - "$Q/w" <<'PY'
import sys, os
lines = [ "def qComplex( a, b ):" ]
for i in range( 24 ):
    lines += [ "    if a > %d and b < %d:" % ( i, i + 1 ), "        a = a + %d" % ( i + 2 ),
               "    elif a < %d or b > %d:" % ( i + 3, i ), "        b = b - %d" % ( i + 1 ) ]
lines.append( "    return a + b" )
open( os.path.join( sys.argv[1], "q.py" ), "w" ).write( "\n".join( lines ) + "\n" )
PY
place_outside "$Q/outside"
( cd "$Q/w" && sh -c 'i=0; while [ $i -lt 64 ]; do ln -s "$1" ".ripwire_quality_acks.tmp.$$.$i" || exit 9; i=$(( i + 1 )); done; exec "$2" . --quality-delta --quality-ack=accepted' _ "$Q/outside" "$BIN" ) > "$Q/out" 2> "$Q/err"
assert_outside "acks" "$Q/outside"
[ -L "$Q/w/.ripwire_quality_acks" ] \
    && no "(acks c) the ack ledger was left as a symlink to the outside" \
    || ok "(acks c) the ack ledger is a regular file, not a symlink left over it"

# ── writer 3: ingest::saveCache via --cache= into the tree (temp <blob>.<pid>.tmp) ────────────────────────
C="$TMP/cache"; mkdir -p "$C/tree"
printf 'int f( void ) { return 1; }\n' > "$C/tree/a.c"
place_outside "$C/outside"
( cd "$C" && sh -c 'ln -s "$1" "tree/.rwcache.$$.tmp" && exec "$2" tree --cache=tree/.rwcache' _ "$C/outside" "$BIN" ) > "$C/out" 2> "$C/err"
assert_outside "savecache" "$C/outside"
[ -L "$C/tree/.rwcache" ] \
    && no "(savecache c) the cache blob was left as a symlink to the outside" \
    || ok "(savecache c) the cache blob is a regular file, not a symlink left over it"

# ── (d) POSITIVE CONTROLS: with NO symlink present, each writer still publishes a real file ───────────────
PE="$TMP/pos_edit"; mkdir -p "$PE/tree"
printf 'int helper( int x ) { return x + 1; }\nint main( void ) { return helper( 1 ); }\n' > "$PE/tree/a.c"
printf 'int helper( int x ) { return x + 5; }\n' > "$PE/payload.c"
( cd "$PE" && "$BIN" tree --replace-symbol-body=helper --edit-payload=payload.c ) > "$PE/out" 2> "$PE/err"
{ [ ! -L "$PE/tree/a.c" ] && grep -q 'return x + 5' "$PE/tree/a.c"; } \
    && ok "(mcpedit d) with no symlink, the edit still lands (a.c holds the new body)" \
    || no "(mcpedit d) the normal edit did not land: $( head -1 "$PE/err" )"

PC="$TMP/pos_cache"; mkdir -p "$PC/tree"
printf 'int f( void ) { return 1; }\n' > "$PC/tree/a.c"
( cd "$PC" && "$BIN" tree --cache=tree/.rwcache ) >/dev/null 2>&1
{ [ -f "$PC/tree/.rwcache" ] && [ ! -L "$PC/tree/.rwcache" ] && [ -s "$PC/tree/.rwcache" ]; } \
    && ok "(savecache d) with no symlink, the cache blob is written as a regular non-empty file" \
    || no "(savecache d) the cache blob was not written normally"

PQ="$TMP/pos_ack"; mkdir -p "$PQ/w"
cp "$Q/w/q.py" "$PQ/w/q.py"
( cd "$PQ/w" && git init -q && git config user.email t@t && git config user.name t && printf 'def qComplex( a, b ):\n    return a\n' > q0.py && git add q0.py && git commit -qm init && mv q0.py q.py 2>/dev/null; cp "$Q/w/q.py" q.py ) >/dev/null 2>&1
( cd "$PQ/w" && "$BIN" . --quality-delta --quality-ack=accepted ) >/dev/null 2> "$PQ/err"
{ [ -f "$PQ/w/.ripwire_quality_acks" ] && [ ! -L "$PQ/w/.ripwire_quality_acks" ] && grep -q 'ripwire quality acks' "$PQ/w/.ripwire_quality_acks"; } \
    && ok "(acks d) with no symlink, the ack ledger is written as a regular file with real content" \
    || no "(acks d) the ack ledger was not written normally: $( head -1 "$PQ/err" )"

# ── (e) CENSUS: the cache-dir tmp+rename writers route through the shared exclusive helper ────────────────
# gitoracle::saveOracleCache and ingest_docpass::docTextViaBridgeCache publish to the per-user cache dir, so a
# behavioural CLI arm cannot address their sha-keyed temp name; a SOURCE census asserts each creates its temp
# through rw::pathguard::createExclTempFile and no longer opens a temp with std::fopen. (ingest_astquery's span
# memo is deliberately NOT folded — it streams structured POD through a std::ofstream rather than one blob, so
# it is not a mechanical swap; it too writes only inside the 0700 cache dir.)
census_writer(){
    local label="$1" file="$2" fn="$3"
    local body
    body="$( awk -v sig="$fn" 'index($0,sig){f=1} f{print} f&&/^}$/{exit}' "$ROOT/$file" )"
    if [ -z "$body" ]; then
        no "($label e) could not isolate $fn in $file — census void"
        return
    fi
    if printf '%s' "$body" | grep -q 'pathguard::createExclTempFile' \
       && ! printf '%s' "$body" | grep -qE 'std::fopen\(|std::ofstream'; then
        ok "($label e) $fn creates its temp via pathguard::createExclTempFile, with no std::fopen/ofstream temp open"
    else
        no "($label e) $fn does not route its temp through pathguard::createExclTempFile: $( printf '%s' "$body" | grep -nE 'std::fopen\(|std::ofstream|createExclTempFile' | head -3 | tr '\n' ';' )"
    fi
}
census_writer gitoracle src/gitoracle.h    'inline bool saveOracleCache('
census_writer docpass   src/ingest_docpass.h 'inline std::string docTextViaBridgeCache('

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
