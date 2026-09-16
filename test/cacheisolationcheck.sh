#!/usr/bin/env bash
# cacheisolationcheck.sh — Ripwire-owned cache artifacts stay out of the shared TMPDIR root.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) BIN="$ROOT/$BIN" ;;
esac
WINDOWS_GATE=0
case "$( uname -s 2>/dev/null || printf '%s' unknown )" in
    MINGW*|MSYS*|CYGWIN*) WINDOWS_GATE=1 ;;
esac
[ "${OS:-}" = Windows_NT ] && WINDOWS_GATE=1
if [ "$WINDOWS_GATE" -eq 1 ]; then
    # Native binaries must not inherit the agent's MSYS conversion opt-out: the temporary paths below
    # are intentionally passed through the normal Git-Bash boundary and become Win32 paths at exec time.
    unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
    PYTHON_NATIVE="${RIPWIRE_PYTHON:-${PYTHON_NATIVE:-$( command -v python.exe 2>/dev/null || command -v python 2>/dev/null || true )}}"
    [ -n "$PYTHON_NATIVE" ] || { echo "cacheisolationcheck: native Python is required on Windows"; exit 2; }
    PYTHON_EXEC="$PYTHON_NATIVE"
    if command -v cygpath >/dev/null 2>&1; then
        PYTHON_EXEC="$( cygpath -w "$PYTHON_NATIVE" )"
    fi
fi
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SHARED="$TMP/shared"; CORPUS="$TMP/corpus"; mkdir -p "$SHARED" "$CORPUS"
mkdir -m 0755 "$SHARED/ripwire"   # the binary must repair an existing permissive directory
printf 'int target( void ) { return 1; }\n' > "$CORPUS/code.cpp"
printf 'unrelated' > "$SHARED/not-ripwire"

echo "cacheisolationcheck: BIN=$BIN"

# Exercise the CLI parse cache, the MCP parse cache, and the per-target edit lock in one private TMPDIR.
TMPDIR="$SHARED" "$BIN" "$CORPUS" >/dev/null 2>"$TMP/cli.err"
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"'"$CORPUS"'","symbol":"target","new_body":"int target( void ) { return 2; }"}}}' \
    | TMPDIR="$SHARED" "$BIN" --mcp >"$TMP/mcp.out" 2>"$TMP/mcp.err"

PRIVATE="$SHARED/ripwire"
if [ -d "$PRIVATE" ]; then ok "creates a dedicated TMPDIR/ripwire directory"; else no "missing private directory: $PRIVATE"; fi

if [ -d "$PRIVATE" ]; then
    if [ "$WINDOWS_GATE" -eq 1 ]; then
        PYTHON="$PYTHON_EXEC"
        WINDOWS_PROBE="$ROOT/test/cacheisolationcheck_windows.py"
        if command -v cygpath >/dev/null 2>&1; then
            WINDOWS_PROBE="$( cygpath -w "$WINDOWS_PROBE" )"
        fi
        WINDOWS_PRIVATE="$PRIVATE"
        if command -v cygpath >/dev/null 2>&1; then
            WINDOWS_PRIVATE="$( cygpath -w "$WINDOWS_PRIVATE" )"
        fi
        if MSYS_NO_PATHCONV=1 "$PYTHON" "$WINDOWS_PROBE" "$WINDOWS_PRIVATE"; then
            ok "private directory has an owner/admin protected DACL"
        else
            no "private directory DACL is not owner/admin protected"
        fi
    else
        if stat --version >/dev/null 2>&1; then mode="$( stat -c %a "$PRIVATE" )"; else mode="$( stat -f %Lp "$PRIVATE" )"; fi
        if [ "$mode" = "700" ]; then ok "private directory mode is 0700"; else no "private directory mode is $mode, expected 700"; fi
    fi
fi

topArtifacts="$( find "$SHARED" -mindepth 1 -maxdepth 1 -name 'ripwire-*' -print 2>/dev/null )"
[ -z "$topArtifacts" ] && ok "shared TMPDIR root has no ripwire-* artifacts" \
    || { no "ripwire artifacts leaked into shared TMPDIR root"; printf '%s\n' "$topArtifacts"; }

cacheCount="$( find "$PRIVATE" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-mcp-*.cache' 2>/dev/null | wc -l | tr -d ' ' )"
lockCount="$( find "$PRIVATE/locks" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-edit-*.lock' 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$cacheCount" -ge 1 ]; then ok "MCP cache is sharded under the private directory"; else no "no sharded MCP cache found"; fi
if [ "$lockCount" -ge 1 ]; then ok "edit lock is sharded under the private locks subtree"; else no "no sharded edit lock found"; fi

if [ -f "$SHARED/not-ripwire" ]; then ok "unrelated TMPDIR content remains untouched"; else no "unrelated TMPDIR content was removed"; fi

if [ "$WINDOWS_GATE" -eq 1 ]; then
    # A pre-existing junction at the final cache component must be rejected before ACL or blob writes.
    REPARSE_SHARED="$TMP/reparse-shared"; REPARSE_OUTSIDE="$TMP/reparse-outside"; REPARSE_CORPUS="$TMP/reparse-corpus"
    mkdir -p "$REPARSE_SHARED" "$REPARSE_OUTSIDE" "$REPARSE_CORPUS"
    printf 'int reparse_target( void ) { return 1; }\n' > "$REPARSE_CORPUS/code.cpp"
    REPARSE_LINK_NATIVE="$( cygpath -w "$REPARSE_SHARED/ripwire" 2>/dev/null || printf '%s' "$REPARSE_SHARED/ripwire" )"
    REPARSE_OUTSIDE_NATIVE="$( cygpath -w "$REPARSE_OUTSIDE" 2>/dev/null || printf '%s' "$REPARSE_OUTSIDE" )"
    if MSYS_NO_PATHCONV=1 cmd.exe /c mklink /J "$REPARSE_LINK_NATIVE" "$REPARSE_OUTSIDE_NATIVE" >/dev/null 2>&1; then
        TMPDIR="$REPARSE_SHARED" "$BIN" "$REPARSE_CORPUS" --no-cache >"$TMP/reparse.out" 2>"$TMP/reparse.err"
        leaked="$( find "$REPARSE_OUTSIDE" -type f -print 2>/dev/null )"
        [ -z "$leaked" ] && ok "pre-existing cache junction is rejected without outside writes" \
            || { no "cache junction redirected artifacts outside the selected cache root"; printf '%s\n' "$leaked"; }
    else
        no "could not create the Windows junction needed by the reparse safety gate"
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
