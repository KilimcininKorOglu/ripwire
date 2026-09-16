#!/usr/bin/env bash
# crashsweepcheck.sh — process crashes, hangs and descriptor leaks reachable from input ripwire does not control.
#
# THE DEFECTS, each reproduced on the base before its fix:
#   (B1) A FILE* LEAKED ON EVERY SHORT READ. ingest_crawl.h's readFile closed its stream inside
#        `( got == want ) && ( std::fclose( fp ) == 0 )`: a file that came up short (truncated between the size
#        probe and the read) skipped the close. A long-lived server re-ingesting such a tree ran out of
#        descriptors, and from then on every file it could not open dropped out of the answer with exit 0.
#        Measured with the interposed short-read shim below: 300 of 600 short-read streams were never closed, and
#        under `ulimit -n 200` all 20 ordinary files vanished from a --grep answer. Fixed by an owner type,
#        rw::OwnedFile (src/infra/ownedfile.h), whose destructor closes on every path.
#   (B2) A FIXED-NAME FILE THAT IS NOT A REGULAR FILE. `.ripwire_config` and `.ripwire_quality_acks` were read
#        with a blocking open on the name. A FIFO there hung --quality-delta before any output (timeout 124); a
#        committed symlink from the ledger to /dev/zero or /dev/urandom never reached end of file (hang); a
#        DIRECTORY at `.ripwire_config` opens on Linux, and where a directory's seek reports LLONG_MAX (overlayfs)
#        the string that length asks for aborts — the shape ingest_crawl.h's PathShape note measured for
#        --cache=<dir>. Both now go through docparse::detail::readRegularFile: open O_NONBLOCK, ask the
#        descriptor, refuse anything that is not a regular file with a stderr line, and read it as absent. Red on
#        the base: the FIFO and device-link shapes hang (killed at 30 s); every shape is read without disclosure.
#
# Usage:  bash test/crashsweepcheck.sh [BIN]      RIPWIRE_ASAN_BIN=asan/ripwire bash test/crashsweepcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ASAN_BIN="${RIPWIRE_ASAN_BIN:-}"
[ -n "$ASAN_BIN" ] && [ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }
skip(){ printf '  SKIP  %s\n' "$*"; }
bounded_run(){ if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else perl -e 'alarm 30; exec @ARGV' "$@"; fi; }
is_hang(){ [ "$1" -eq 124 ] || [ "$1" -eq 142 ]; }
is_sanitized(){ LC_ALL=C grep -q -a '__asan_init' "$1" 2>/dev/null; }
bin_tag(){ is_sanitized "$1" && printf 'asan' || printf 'plain'; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "crashsweepcheck: BIN=$BIN  ASAN_BIN=${ASAN_BIN:-none}"
RUN_BINS=( "$BIN" )   # the behavioural arms run once per distinct binary
[ -n "$ASAN_BIN" ] && [ "$ASAN_BIN" != "$BIN" ] && RUN_BINS+=( "$ASAN_BIN" )

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B1: a short read closes its stream (interposed short-read shim) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The shim shortens every fread on a stream opened on a path containing RWSHIM_MATCH by one byte and counts how
# many of those streams the program closed; the counts land in RWSHIM_LOG at exit. A plain binary only: the
# sanitizer runtime must come first in the preload order on Linux, and nothing here needs it.
SHIM_SRC="$TMP/shortread.c"
cat > "$SHIM_SRC" <<'SHIMC'
#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#ifndef __APPLE__
#include <dlfcn.h>
#endif
#define MAXS 8192
static FILE* marked[MAXS];
static unsigned long opened, closed, shorted;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static int logFd = -1;
#ifdef __APPLE__
static FILE* real_fopen( const char* p, const char* m ) { return fopen( p, m ); }
static size_t real_fread( void* b, size_t s, size_t n, FILE* f ) { return fread( b, s, n, f ); }
static int real_fclose( FILE* f ) { return fclose( f ); }
#else
static FILE* real_fopen( const char* p, const char* m ) { FILE* (*fn)( const char*, const char* ) = dlsym( RTLD_NEXT, "fopen" ); return fn( p, m ); }
static size_t real_fread( void* b, size_t s, size_t n, FILE* f ) { size_t (*fn)( void*, size_t, size_t, FILE* ) = dlsym( RTLD_NEXT, "fread" ); return fn( b, s, n, f ); }
static int real_fclose( FILE* f ) { int (*fn)( FILE* ) = dlsym( RTLD_NEXT, "fclose" ); return fn( f ); }
#endif
static int isMarked( FILE* f ) { int hit = 0; pthread_mutex_lock( &mu ); for( int i = 0; i < MAXS; ++i ) { if( marked[i] == f ) { hit = 1; break; } } pthread_mutex_unlock( &mu ); return hit; }
FILE* rw_fopen( const char* p, const char* m )
{
    FILE* f = real_fopen( p, m );
    const char* match = getenv( "RWSHIM_MATCH" );
    if( f && match && *match && strstr( p, match ) && m && m[0] == 'r' )
    {
        pthread_mutex_lock( &mu );
        for( int i = 0; i < MAXS; ++i ) { if( marked[i] == NULL ) { marked[i] = f; ++opened; break; } }
        pthread_mutex_unlock( &mu );
    }
    return f;
}
size_t rw_fread( void* b, size_t s, size_t n, FILE* f )
{
    if( n > 1 && isMarked( f ) ) { pthread_mutex_lock( &mu ); ++shorted; pthread_mutex_unlock( &mu ); return real_fread( b, s, n - 1, f ); }
    return real_fread( b, s, n, f );
}
int rw_fclose( FILE* f )
{
    pthread_mutex_lock( &mu );
    for( int i = 0; i < MAXS; ++i ) { if( marked[i] == f ) { marked[i] = NULL; ++closed; break; } }
    pthread_mutex_unlock( &mu );
    return real_fclose( f );
}
__attribute__((constructor)) static void openLog( void ) { const char* log = getenv( "RWSHIM_LOG" ); if( log ) { logFd = open( log, O_WRONLY | O_CREAT | O_TRUNC, 0644 ); } }
__attribute__((destructor)) static void report( void ) { if( logFd >= 0 ) { dprintf( logFd, "opened=%lu shorted=%lu closed=%lu\n", opened, shorted, closed ); close( logFd ); } }
#ifdef __APPLE__
#define INTERPOSE( r, o ) __attribute__((used)) static struct { const void* rep; const void* orig; } interpose_##o __attribute__((section( "__DATA,__interpose" ))) = { (const void*)&r, (const void*)&o };
INTERPOSE( rw_fopen, fopen )
INTERPOSE( rw_fread, fread )
INTERPOSE( rw_fclose, fclose )
#else
FILE* fopen( const char* p, const char* m ) { return rw_fopen( p, m ); }
FILE* fopen64( const char* p, const char* m ) { return rw_fopen( p, m ); }
size_t fread( void* b, size_t s, size_t n, FILE* f ) { return rw_fread( b, s, n, f ); }
size_t __fread_chk( void* b, size_t bl, size_t s, size_t n, FILE* f ) { (void)bl; return rw_fread( b, s, n, f ); }
int fclose( FILE* f ) { return rw_fclose( f ); }
#endif
SHIMC
CC_BIN="$( command -v cc || command -v clang || command -v gcc || true )"
if is_sanitized "$BIN" || LC_ALL=C grep -q -a '__tsan_init' "$BIN" 2>/dev/null; then
    skip "B1: $BIN is a sanitizer build — the preload shim needs a plain binary"
elif [ -z "$CC_BIN" ]; then
    skip "B1: no C compiler to build the short-read shim"
else
    if [ "$( uname -s )" = "Darwin" ]; then
        "$CC_BIN" -O1 -dynamiclib -o "$TMP/shortread.so" "$SHIM_SRC" 2>"$TMP/shim_cc.txt"; PRELOAD_VAR=DYLD_INSERT_LIBRARIES
    else
        "$CC_BIN" -O1 -shared -fPIC -o "$TMP/shortread.so" "$SHIM_SRC" -ldl -lpthread 2>"$TMP/shim_cc.txt"; PRELOAD_VAR=LD_PRELOAD
    fi
    if [ ! -f "$TMP/shortread.so" ]; then
        skip "B1: the short-read shim did not compile: $( head -2 "$TMP/shim_cc.txt" )"
    else
        FD="$TMP/fdtree"; mkdir -p "$FD"
        for i in $( seq 1 300 ); do printf 'int shortread_f%d( int x ) { return x + %d; }\n' "$i" "$i" > "$FD/a_shortread_$i.c"; done
        for i in $( seq 1 20 );  do printf 'int zkeep_%d( int x ) { return x; }\n' "$i" > "$FD/z_keep_$i.c"; done
        # 1: the counts, which do not depend on any limit — every stream the shim shortened must have been closed.
        env "$PRELOAD_VAR=$TMP/shortread.so" RWSHIM_MATCH=shortread_ RWSHIM_LOG="$TMP/shim1.txt" \
            "$BIN" "$FD" --no-cache --grep=zkeep_ >"$TMP/b1_out.txt" 2>"$TMP/b1_err.txt"; rc=$?
        COUNTS="$( cat "$TMP/shim1.txt" 2>/dev/null )"
        OPENED="$( printf '%s' "$COUNTS" | sed -nE 's/.*opened=([0-9]+).*/\1/p' )"
        SHORTED="$( printf '%s' "$COUNTS" | sed -nE 's/.*shorted=([0-9]+).*/\1/p' )"
        CLOSED="$( printf '%s' "$COUNTS" | sed -nE 's/.*closed=([0-9]+).*/\1/p' )"
        if [ -z "$COUNTS" ] || [ "${SHORTED:-0}" -eq 0 ]; then
            skip "B1: the shim did not intercept this binary's reads (log: '${COUNTS:-absent}') — nothing was shortened, so nothing is measured"
        elif [ "$rc" -ne 0 ]; then
            no "B1: exit $rc under the short-read shim"
        elif [ "$CLOSED" -eq "$OPENED" ]; then
            ok "B1: every stream that read short was closed (opened=$OPENED shorted=$SHORTED closed=$CLOSED)"
        else
            no "B1: $(( OPENED - CLOSED )) of $OPENED short-read streams were never closed (shorted=$SHORTED) — a descriptor leaks per short read"
        fi
        # 2: the consequence under a descriptor limit — the ordinary files must still be answered.
        if [ -n "$COUNTS" ] && [ "${SHORTED:-0}" -gt 0 ]; then
            ( ulimit -n 200 2>/dev/null; exec env "$PRELOAD_VAR=$TMP/shortread.so" RWSHIM_MATCH=shortread_ RWSHIM_LOG="$TMP/shim2.txt" \
                "$BIN" "$FD" --no-cache --grep=zkeep_ ) >"$TMP/b1_lim.txt" 2>/dev/null
            KEPT="$( grep -o '<f p="[^"]*z_keep_[0-9]*\.c"' "$TMP/b1_lim.txt" | sort -u | grep -c . )"
            [ "$KEPT" -eq 20 ] && ok "B1: under ulimit -n 200 all 20 ordinary files are still answered" \
                               || no "B1: under ulimit -n 200 only $KEPT of 20 ordinary files were answered — leaked descriptors starved the reads"
        fi
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B2: a fixed-name file that is not a regular file (FIFO, directory, device link) ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
B2="$TMP/b2repo"; mkdir -p "$B2/src"
printf 'int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i; } return s; }\n' > "$B2/src/lib.cpp"
git -C "$B2" init -q; git -C "$B2" config user.email x@y; git -C "$B2" config user.name x
git -C "$B2" add -A; git -C "$B2" commit -qm init
B2XDG="$TMP/b2xdg"; mkdir -p "$B2XDG"
b2run(){ bounded_run env -u TMPDIR XDG_CACHE_HOME="$B2XDG" "$1" "$B2" --quality-delta; }
normalize_at(){ sed -E 's/ at="[0-9a-f]+(\+dirty)?"/ at="AT"/'; }
b2run "$BIN" 2>/dev/null | normalize_at >"$TMP/b2_truth.txt"
[ -s "$TMP/b2_truth.txt" ] || no "B2: the clean --quality-delta produced nothing — cannot judge the shapes"
for name in .ripwire_config .ripwire_quality_acks; do
    for shape in fifo directory devzero urandom; do
        case "$shape" in
            fifo)      mkfifo "$B2/$name" ;;
            directory) mkdir "$B2/$name"; printf 'x\n' > "$B2/$name/inside" ;;
            devzero)   ln -s /dev/zero "$B2/$name" ;;
            urandom)   ln -s /dev/urandom "$B2/$name" ;;
        esac
        for bin in "${RUN_BINS[@]}"; do
            tag="$shape $name ($( bin_tag "$bin" ))"
            b2run "$bin" >"$TMP/b2_out.txt" 2>"$TMP/b2_err.txt"; rc=$?
            if is_hang "$rc"; then
                no "B2 [$tag]: --quality-delta HUNG (killed after 30 s)"
            elif [ "$rc" -ne 0 ]; then
                no "B2 [$tag]: exit $rc — $( grep -m1 -iE 'terminat|abort|error|sanitizer' "$TMP/b2_err.txt" | cut -c1-160 )"
            elif ! normalize_at <"$TMP/b2_out.txt" | cmp -s - "$TMP/b2_truth.txt"; then
                no "B2 [$tag]: the answer changed — a file that is not regular must read as absent"
            elif ! grep -q "at '$B2/$name': it is not a regular file" "$TMP/b2_err.txt"; then
                no "B2 [$tag]: exit 0, but nothing on stderr says the file was ignored"
            else
                ok "B2 [$tag]: refused before reading, disclosed, answer unchanged"
            fi
        done
        rm -rf "$B2/$name"
    done
done


echo
[ "$fail" -eq 0 ] && { echo "crashsweepcheck: ALL PASS"; exit 0; } || { echo "crashsweepcheck: SOME CHECKS FAILED"; exit 1; }
