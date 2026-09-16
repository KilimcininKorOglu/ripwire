# cxxflags.sh — the ONE parse of a CMake-generated flags.make into bash arrays. SOURCED, not run.
#
# WHY THIS FILE EXISTS — CWE-78, command injection on the CI runner.
#
# Six gates (extentcheck, jsonwalkcheck, decltodefcheck, includeprecisecheck, macroreparsecheck and
# rustimportprecisecheck) compile a unit driver against the exact flags CMake produced for $BIN, because the
# flags are front-end specific and guessing `c++` breaks a clang-configured Release tree. Each of them spelled
# the parse of those flags the same way, eighteen sites in all:
#
#     eval "CXX_FLAGS=( $( grep -m1 '^CXX_FLAGS =' "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
#
# flags.make is GENERATED, and it is reachable from a pull request. CI runs test/pargates.py on PRs and passes
# the binary under test through RIPWIRE_BIN; every one of those gates derives BUILD_DIR from that binary and
# FLAGS_MK from BUILD_DIR. Anything a PR can put into a CMake flag — a compile definition, an include
# directory, an append to CMAKE_CXX_FLAGS — lands on one of these three lines and is then handed to `eval`,
# which is a request to run it. Fork-PR workflow runs are approved by hand during a release, so the trigger is
# a maintainer who believes they are approving a test change.
#
# WHICH SHAPES ARE ACTUALLY VECTORS — measured, not assumed. Arm (P) of cxxflags_selfproof re-derives every
# line of this table on every run, each shape with its own key and its own control:
#
#     -DA="$( … )"          EXECUTES                 command substitution
#     -DB="` … `"           EXECUTES                 backticks
#     <( … )                EXECUTES, ASYNCHRONOUSLY process substitution — the sentinel can land AFTER the
#                                                    eval has returned, so a same-instant test reads it as
#                                                    "not a vector". It is one. Arm (P3) settles for it.
#     x ) ; … ; ZZ=(        EXECUTES                 close the array, run a statement, reopen a valid empty
#                                                    one. `… ; (` alone is a syntax error; `… ; ZZ=(` is not.
#     bare ;  &&  |  >      does NOT execute         each is a bash SYNTAX ERROR inside an array assignment,
#                                                    so the eval aborts having run nothing at all
#
# That last row is why every shape above gets its OWN key and its OWN control, and it is the trap this file
# exists to keep out of the next gate. A syntax-error shape and a working shape on the SAME flags line MASK
# each other: bash parses the whole assignment before running any of it, so the parse dies before it ever
# reaches the payload, nothing executes, and a single-line multi-shape arm reports "no execution" for a
# spelling that is wide open. Measured, and held by arm (P6): `-DA="$( touch S1 )" ; touch S2` fires NOTHING
# and exits 1, while `-DA="$( touch S1 )"` alone fires S1 and exits 0. A proof built on the first line would
# have certified the vulnerability as absent.
#
# THE FIX. cxxflags_words parses one flags.make line with Python's shlex.split — POSIX word splitting that
# honours quotes and backslashes and executes nothing — and emits the words NUL-terminated. cxxflags_load
# reads them back into CXX_FLAGS / CXX_DEFINES / CXX_INCLUDES, the three arrays every caller already used.
# Arm (S) holds it to byte-for-byte agreement with the old eval on a benign synthetic flags.make, including
# the make-escaped `-DX=\"str\"` defines and quoted spaced includes that a naive split mangles.
#
# Three spellings were rejected. Each is a regression if it comes back, and each has an arm:
#   * `read -ra` splits on IFS and destroys the quoting that carries the argument boundary. Real CXX_INCLUDES
#     hold `-I"/path with spaces/inc"`; read -ra turns that one argument into two and the driver stops
#     compiling. Arm (Q) measures it rather than asserting it — 4 words correct, 6 from read -ra.
#   * `mapfile -d ''` is the natural reader for NUL-terminated words and does not exist here: macOS ships
#     bash 3.2, whose mapfile has no -d. `while IFS= read -r -d ''` is the portable form.
#   * a PIPE into that loop runs the loop in a subshell, so the arrays populate and then vanish. Arm (R)
#     catches a pipe: all three arrays come back empty.
#   * a PROCESS SUBSTITUTION keeps the loop in the caller's shell and was the first spelling here, but it
#     discards the parser's exit status by construction — see _cxxflags_slurp, which reads through a scratch
#     file for exactly that reason, and arm (U), which holds the rc-4 path open. This was a real bug in this
#     file's first version: an unbalanced quote parsed to zero words and the loader returned success.
#
# THE COMPILER NAME, judged and deliberately LEFT ALONE. Every caller also takes the compiler itself from a
# generated file, one line above the parse this file replaced:
#
#     CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
#     [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
#
# It reads like the same defect and is not. Assigning the output of a command substitution does not
# interpret that output, `command -v "$CXX"` is quoted, and `"$CXX" …` expands to exactly one word, so
# nothing in link.txt is ever parsed as shell syntax: there is no injection here, only the execution of a
# program the file names. And that capability is not new — CI ran that same compiler to build the binary the
# gate is handed, so a link.txt naming a hostile compiler means the build already executed it. Hardening the
# line would move no boundary while risking the clang/gcc mismatch the comment above it exists to prevent.
# The eval was different in kind: it turned DATA into CODE, which the build never did.
#
# One real defect was found in that line and is also left alone, on purpose: `print $1` takes the first
# whitespace-delimited token, so a compiler path containing a space (`/Applications/Xcode 16.app/…`) is
# truncated. The `command -v` guard then falls back to `c++`, which is the documented mismatch failure — a
# correctness bug, not a security one, and not this change's to fix while five gates sit on the release path.
#
# Usage (inside a gate, after its own FLAGS_MK presence check):
#     . "$ROOT/test/lib/cxxflags.sh"
#     cxxflags_load "$FLAGS_MK" || { no "..."; }      # populates CXX_FLAGS, CXX_DEFINES, CXX_INCLUDES
#
# This file sets no traps (gates own their EXIT trap), defines no reporting helper, and writes only inside a
# directory the caller hands it. cxxflags_selfproof prints PASS/FAIL/NOTE rows on stdout and never calls the
# caller's ok/no, so each gate maps the rows onto its own reporters and stays independent of the others.

# ── cxxflags_words: one flags.make line -> NUL-terminated words on stdout, executing nothing ─────────────────
# The file path and the key travel in the environment, never spliced into the Python source, so a hostile
# FLAGS_MK path cannot reach the parser either. An unbalanced quote is an honest failure (rc 4, one line on
# stderr), never a silent half-parse.
cxxflags_words()
{
    local _mk="$1" _key="$2"
    CXXFLAGS_MK="$_mk" CXXFLAGS_KEY="$_key" python3 -c '
import os, re, shlex, sys

mk  = os.environ[ "CXXFLAGS_MK" ]
key = os.environ[ "CXXFLAGS_KEY" ]
pat = re.compile( r"^" + re.escape( key ) + r"[ \t]*=" )

line = ""
with open( mk, "r", errors = "replace" ) as fh:
    for raw in fh:
        if pat.match( raw ):
            line = pat.sub( "", raw, count = 1 )
            break

try:
    words = shlex.split( line )
except ValueError:
    sys.stderr.write( "cxxflags: %s: unbalanced quoting on the %s line -- parsed nothing\n" % ( mk, key ) )
    sys.exit( 4 )

out = sys.stdout.buffer
for w in words:
    out.write( w.encode( "utf-8", "surrogateescape" ) + b"\0" )
'
}

# ── _cxxflags_slurp: one key's words into _CXXFLAGS_WORDS, carrying the parser's OWN exit status ──────────────
# THE READ GOES THROUGH A FILE, and that is the whole point of this function. The obvious spelling is a
# process substitution:
#
#     while IFS= read -r -d '' _w; do A+=( "$_w" ); done < <( cxxflags_words "$_mk" "$_key" )
#
# and it CANNOT report that the parser failed. A process substitution's exit status never reaches `$?` — after
# the loop `$?` belongs to `read` (1 at EOF), the redirection's status is discarded, and `< <(…)` sets no `$!`
# on bash 3.2, so there is nothing to `wait` on either. The failure that matters is rc 4, an unbalanced quote
# in the generated file: the parser writes its stderr line, exits 4, and emits ZERO words — so the loop reads
# nothing, the array comes back empty, and the loader returns 0. A gate would then compile against an empty
# flag set and report a result. That is a check succeeding over a population it never examined, which is the
# same defect class as the eval this file removes, so it gets the same treatment rather than a comment.
#
# A plain redirection to a scratch file makes `$?` the producer's real status. Command substitution is not an
# option: a shell variable cannot hold a NUL, and NUL is what keeps the argument boundaries.
_cxxflags_slurp()
{
    local _mk="$1" _key="$2" _w _rc _tmp
    _CXXFLAGS_WORDS=()
    _tmp="$( mktemp -t cxxflags.XXXXXX )" || return 5
    cxxflags_words "$_mk" "$_key" > "$_tmp"; _rc=$?
    if [ "$_rc" -ne 0 ]; then
        rm -f "$_tmp"
        return "$_rc"
    fi
    while IFS= read -r -d '' _w; do _CXXFLAGS_WORDS+=( "$_w" ); done < "$_tmp"
    rm -f "$_tmp"
    return 0
}

# ── cxxflags_load: populate CXX_FLAGS / CXX_DEFINES / CXX_INCLUDES from a flags.make ─────────────────────────
# Fixed array names on purpose: a name passed as a parameter would need `eval` to assign in bash 3.2, and this
# file exists to delete an eval, not to move one.
#
# Returns, each with one `cxxflags:` line on stderr, and a caller turns ANY of them into a FAIL, never a
# silent skip: 2 no such file, 3 no python3, 4 a line did not parse (unbalanced quoting), 5 no scratch file.
# A partial parse is refused outright — two of the three keys reading correctly is not a flag set.
cxxflags_load()
{
    local _mk="$1" _rc
    if [ ! -f "$_mk" ]; then
        printf 'cxxflags: no such flags file: %s\n' "$_mk" >&2
        return 2
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        printf 'cxxflags: python3 is not on PATH -- cannot parse %s without executing it\n' "$_mk" >&2
        return 3
    fi

    CXX_FLAGS=(); CXX_DEFINES=(); CXX_INCLUDES=()

    _cxxflags_slurp "$_mk" CXX_FLAGS || { _rc=$?; printf 'cxxflags: %s: the CXX_FLAGS line did not parse (rc %s) -- refusing a partial flag set\n' "$_mk" "$_rc" >&2; return "$_rc"; }
    CXX_FLAGS=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )

    _cxxflags_slurp "$_mk" CXX_DEFINES || { _rc=$?; printf 'cxxflags: %s: the CXX_DEFINES line did not parse (rc %s) -- refusing a partial flag set\n' "$_mk" "$_rc" >&2; return "$_rc"; }
    CXX_DEFINES=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )

    _cxxflags_slurp "$_mk" CXX_INCLUDES || { _rc=$?; printf 'cxxflags: %s: the CXX_INCLUDES line did not parse (rc %s) -- refusing a partial flag set\n' "$_mk" "$_rc" >&2; return "$_rc"; }
    CXX_INCLUDES=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )

    return 0
}


# ── the proof ────────────────────────────────────────────────────────────────────────────────────────────────
# Every arm below prints PASS/FAIL/NOTE rows on stdout and returns 0 only when it printed no FAIL. They are
# separate functions rather than one body because each answers a DIFFERENT question and a reader auditing this
# file should be able to read one of them alone: (P) which shapes execute, (P6) why they are never combined,
# (Q) argument boundaries, (S) agreement with the spelling replaced, (R) the real file.

# _cxxflags_legacy runs the spelling this file replaced, on a flags.make the proof wrote itself, inside a
# subshell whose cwd is that scratch directory — so the payload's `touch FIRED` lands at a known path and a
# syntax error cannot take the calling gate down with it.
_cxxflags_legacy()
{
    local _d="$1"
    (
        cd "$_d" || exit 9
        # shellcheck disable=SC2086
        eval "CXX_FLAGS=( $( grep -m1 '^CXX_FLAGS =' "$_d/flags.make" | sed 's/^CXX_FLAGS =//' ) )"
    ) >/dev/null 2>&1
}

# _cxxflags_settle waits up to $2 tenths of a second for $1 to appear. Process substitution executes
# asynchronously, so the control for that shape cannot read the sentinel at the same instant the eval returns.
_cxxflags_settle()
{
    local _p="$1" _n="${2:-20}" _i=0
    while [ "$_i" -lt "$_n" ]; do
        [ -e "$_p" ] && return 0
        sleep 0.1
        _i=$(( _i + 1 ))
    done
    [ -e "$_p" ]
}

# _cxxflags_safe_words prints the safe parse of $1's CXX_FLAGS line as `<count>|<word>|<word>…`, so an arm
# can test both the word count and the payload's survival as literal text. The count travels in the STRING
# rather than a variable because every caller reads this through command substitution, and a subshell cannot
# hand a variable back.
_cxxflags_safe_words()
{
    local _mk="$1" _w _joined
    local -a _got=()
    _cxxflags_slurp "$_mk" CXX_FLAGS || { printf '0'; return 0; }
    _got=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )
    _joined="${#_got[@]}"
    if [ "${#_got[@]}" -gt 0 ]; then
        for _w in "${_got[@]}"; do _joined="${_joined}|${_w}"; done
    fi
    printf '%s' "$_joined"
}

# _cxxflags_write_mk writes a one-key flags.make carrying exactly one payload shape. ONE shape per file is
# the whole discipline — see arm (P6) and this file's header for what sharing a line costs.
_cxxflags_write_mk()
{
    local _d="$1" _payload="$2"
    rm -rf "$_d"; mkdir -p "$_d" || return 1
    printf 'CXX_DEFINES = -DPROOF=1\nCXX_INCLUDES = -I/proof\nCXX_FLAGS = %s\n' "$_payload" > "$_d/flags.make"
}

# ── (P) one shape, one key, one control ──────────────────────────────────────────────────────────────────────
#   $1 work dir  $2 label  $3 the CXX_FLAGS payload  $4 marker expected to survive as literal text
#   $5 "vector" when the legacy eval is expected to EXECUTE it, "syntax" when it must abort instead
_cxxflags_shape()
{
    local _work="$1" _lab="$2" _pl="$3" _marker="$4" _kind="$5"
    local _d="$_work/$_lab" _rc _joined _n _bad=0

    _cxxflags_write_mk "$_d" "$_pl" || { printf 'FAIL (P:%s) cannot create %s\n' "$_lab" "$_d"; return 1; }

    # (1) CONTROL — without this the arms below are vacuous: they would pass on a payload that could never
    #     have run in the first place.
    _cxxflags_legacy "$_d"; _rc=$?
    if [ "$_kind" = vector ]; then
        if _cxxflags_settle "$_d/FIRED" 20; then
            printf 'PASS (P:%s control) the eval spelling EXECUTED the payload (sentinel written, rc=%s)\n' "$_lab" "$_rc"
        else
            printf 'FAIL (P:%s control) the eval spelling did NOT execute the payload (rc=%s) -- this arm proves nothing\n' "$_lab" "$_rc"
            _bad=1
        fi
    elif [ "$_rc" -ne 0 ] && [ ! -e "$_d/FIRED" ]; then
        printf 'NOTE (P:%s) measured NOT a vector in this spelling: the eval aborted (rc=%s) and ran nothing -- a bash syntax error inside an array assignment. On a shared line it MASKS a shape that would have run.\n' "$_lab" "$_rc"
    else
        printf 'FAIL (P:%s) expected a syntax-error abort, got rc=%s fired=%s -- the table in this file is wrong\n' "$_lab" "$_rc" "$( [ -e "$_d/FIRED" ] && echo yes || echo no )"
        _bad=1
    fi

    # (2) the fixed parse executes nothing. Re-armed from scratch so the control's sentinel cannot be
    #     mistaken for silence here.
    rm -f "$_d/FIRED"
    _joined="$( cd "$_d" && _cxxflags_safe_words "$_d/flags.make" )"
    _n="${_joined%%|*}"
    sleep 0.3                                       # a late async write would land inside this window
    if [ -e "$_d/FIRED" ]; then
        printf 'FAIL (P:%s fix) the shlex parse EXECUTED the payload\n' "$_lab"; _bad=1
    else
        printf 'PASS (P:%s fix) the shlex parse executed nothing\n' "$_lab"
    fi

    # (3) and it did not reach that answer by DROPPING the payload — a parse that silently discarded the
    #     line would satisfy (2) and be indistinguishable from a correct one.
    case "${_joined#*|}" in
        *"$_marker"*) printf 'PASS (P:%s literal) the payload survives the parse as literal text (%s word(s), marker "%s" intact)\n' "$_lab" "$_n" "$_marker" ;;
        *)            printf 'FAIL (P:%s literal) the payload was DROPPED, not neutralised (%s word(s): %s)\n' "$_lab" "$_n" "$_joined"; _bad=1 ;;
    esac

    return "$_bad"
}

# The table this file's header states, re-derived on every run rather than trusted.
_cxxflags_shape_arms()
{
    local _work="$1" _bad=0
    _cxxflags_shape "$_work" cmdsub   '-DA="$( touch FIRED )"'   'touch FIRED' vector || _bad=1
    _cxxflags_shape "$_work" backtick '-DB="`touch FIRED`"'      'touch FIRED' vector || _bad=1
    _cxxflags_shape "$_work" procsub  '<( touch FIRED )'         'FIRED'       vector || _bad=1
    _cxxflags_shape "$_work" parenout 'x ) ; touch FIRED ; ZZ=(' 'FIRED'       vector || _bad=1
    _cxxflags_shape "$_work" semi     '-DC=x ; touch FIRED'      'FIRED'       syntax || _bad=1
    _cxxflags_shape "$_work" andand   '-DD=x && touch FIRED'     'FIRED'       syntax || _bad=1
    _cxxflags_shape "$_work" pipeinto '-DE=x | touch FIRED'      'FIRED'       syntax || _bad=1
    _cxxflags_shape "$_work" redirect '-DF=x > FIRED'            'FIRED'       syntax || _bad=1
    return "$_bad"
}

# ── (P6) the masking effect itself, because it is the reason for one shape per key ───────────────────────────
_cxxflags_mask_arm()
{
    local _d="$1/masked" _rc
    _cxxflags_write_mk "$_d" '-DA="$( touch FIRED )" ; touch ALSO' || { printf 'FAIL (P6) cannot create %s\n' "$_d"; return 1; }
    _cxxflags_legacy "$_d"; _rc=$?
    if [ "$_rc" -ne 0 ] && [ ! -e "$_d/FIRED" ] && [ ! -e "$_d/ALSO" ]; then
        printf 'PASS (P6 masking) a working $( ) payload and a bare `;` on ONE line fire NOTHING (rc=%s) -- the syntax error aborts the parse before the substitution runs, and the cmdsub control proves that same payload DOES run alone. Several shapes per line manufacture a false all-clear.\n' "$_rc"
        return 0
    fi
    printf 'FAIL (P6 masking) expected the combined line to fire nothing; rc=%s FIRED=%s ALSO=%s\n' "$_rc" "$( [ -e "$_d/FIRED" ] && echo yes || echo no )" "$( [ -e "$_d/ALSO" ] && echo yes || echo no )"
    return 1
}

# ── (Q) a quoted path with spaces stays ONE argument, and read -ra measurably does not ───────────────────────
_cxxflags_bound_arm()
{
    local _d="$1/spaces" _w _bad=0
    _cxxflags_write_mk "$_d" '-I"/opt/a b/inc" -I/plain/inc -isystem "/opt/c d/sys"' || { printf 'FAIL (Q) cannot create %s\n' "$_d"; return 1; }

    local -a _got=()
    _cxxflags_slurp "$_d/flags.make" CXX_FLAGS || { printf 'FAIL (Q) the parser refused the boundary fixture\n'; return 1; }
    _got=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )
    if [ "${#_got[@]}" -eq 4 ] && [ "${_got[0]}" = '-I/opt/a b/inc' ] && [ "${_got[3]}" = '/opt/c d/sys' ]; then
        printf 'PASS (Q) a quoted path containing spaces stays ONE argument (4 words; [%s] and [%s] intact)\n' "${_got[0]}" "${_got[3]}"
    else
        printf 'FAIL (Q) argument boundaries lost: %s word(s):' "${#_got[@]}"
        [ "${#_got[@]}" -gt 0 ] && printf ' [%s]' "${_got[@]}"
        printf '\n'; _bad=1
    fi

    local -a _ra=()
    read -ra _ra <<< "$( grep -m1 '^CXX_FLAGS =' "$_d/flags.make" | sed 's/^CXX_FLAGS =//' )"
    if [ "${#_ra[@]}" -gt 4 ]; then
        printf 'NOTE (Q) the rejected `read -ra` spelling splits that same line into %s words instead of 4 -- it neutralises the payload and breaks the build, so it is not a fix\n' "${#_ra[@]}"
    else
        printf 'FAIL (Q) `read -ra` produced %s words here; the reason this file gives for rejecting it no longer holds and the header must be corrected\n' "${#_ra[@]}"
        _bad=1
    fi
    return "$_bad"
}

# ── (S) byte-for-byte agreement with the spelling it replaced, on content we wrote ───────────────────────────
# The oracle runs on a BENIGN synthetic file, never on the real generated one: eval'ing the real flags.make to
# prove the parser matches would restore the very eval this file removes, in the one environment where that
# file is attacker-influenceable.
_cxxflags_parity_arm()
{
    local _d="$1/parity" _w _same=1 _i=0
    rm -rf "$_d"; mkdir -p "$_d" || { printf 'FAIL (S) cannot create %s\n' "$_d"; return 1; }
    printf 'CXX_FLAGS = -std=gnu++23 -DRW_NAME=\\"ripwire\\" -I"/opt/a b/inc" -O3\n' > "$_d/flags.make"

    local -a _safe=() _leg=()
    _cxxflags_slurp "$_d/flags.make" CXX_FLAGS || { printf 'FAIL (S) the parser refused the parity fixture\n'; return 1; }
    _safe=( ${_CXXFLAGS_WORDS[@]+"${_CXXFLAGS_WORDS[@]}"} )
    # shellcheck disable=SC2086
    eval "_leg=( $( grep -m1 '^CXX_FLAGS =' "$_d/flags.make" | sed 's/^CXX_FLAGS =//' ) )" 2>/dev/null

    if [ "${#_safe[@]}" -ne "${#_leg[@]}" ]; then
        _same=0
    else
        while [ "$_i" -lt "${#_safe[@]}" ]; do
            [ "${_safe[$_i]}" = "${_leg[$_i]}" ] || _same=0
            _i=$(( _i + 1 ))
        done
    fi

    if [ "$_same" -eq 1 ] && [ "${#_safe[@]}" -eq 4 ]; then
        printf 'PASS (S) the shlex parse agrees word-for-word with the old eval on a benign file (4 words, make-escaped define and spaced include included)\n'
        return 0
    fi
    printf 'FAIL (S) parse disagrees with the spelling it replaced: safe=%s legacy=%s words\n' "${#_safe[@]}" "${#_leg[@]}"
    return 1
}

# ── (R) the REAL flags.make still parses to the shape the drivers compile with ───────────────────────────────
# Also the arm that catches a pipe smuggled back into cxxflags_load in place of the process substitution: the
# loop would run in a subshell and all three arrays would come back empty.

# _cxxflags_words_match  $1 the key's name  $2 an ERE every word must match  $3 what a mismatch means
#                        $4… the parsed words
# One row, one return code. Callers pass the words with the `${A[@]+"${A[@]}"}` guard, because bash 3.2 under
# `set -u` treats "${EMPTY[@]}" as an unbound variable and would abort the calling gate instead of failing an
# arm; "$@" over no arguments is the one expansion that is always safe.
#
# An ERE and not a `case` glob, for a reason this arm caught in its own first draft: `|` inside a glob held in
# a VARIABLE is a literal bar, not an alternation — only a `|` written literally in the case statement
# separates patterns. So `case "$w" in $_glob)` with _glob='-I*|-isystem|/*' matched nothing and reported
# every real include as split. The bug was visible only because the arm runs against a real flags.make.
_cxxflags_words_match()
{
    local _key="$1" _re="$2" _meaning="$3"; shift 3
    local _off="" _x
    for _x in "$@"; do
        printf '%s' "$_x" | grep -qE "$_re" || _off="$_x"
    done
    if [ -z "$_off" ]; then
        printf 'PASS (R) every parsed %s argument matches /%s/ -- %s\n' "$_key" "$_re" "$_meaning"
        return 0
    fi
    printf 'FAIL (R) a parsed %s argument does not match /%s/: [%s] -- %s\n' "$_key" "$_re" "$_off" "$_meaning"
    return 1
}

_cxxflags_real_arm()
{
    local _real="$1" _bad=0

    if ! cxxflags_load "$_real"; then
        printf 'FAIL (R) cxxflags_load refused the real flags.make at %s\n' "$_real"
        return 1
    fi

    local _nf="${#CXX_FLAGS[@]}" _nd="${#CXX_DEFINES[@]}" _ni="${#CXX_INCLUDES[@]}"
    if [ "$_nf" -ge 1 ] && [ "$_nd" -ge 1 ] && [ "$_ni" -ge 1 ]; then
        printf 'PASS (R) the real flags.make parses to %s flag / %s define / %s include argument(s), all three arrays populated in the caller shell\n' "$_nf" "$_nd" "$_ni"
    else
        printf 'FAIL (R) the real flags.make parsed to %s/%s/%s arguments -- an empty array here is the subshell bug (a pipe where the process substitution belongs)\n' "$_nf" "$_nd" "$_ni"
        _bad=1
    fi

    # CXX_FLAGS is deliberately NOT pattern-checked: it legitimately carries bare VALUE words beside their
    # flags (`-arch arm64`, `-isysroot /path`), so "every word starts with -" is false on a healthy file and
    # such an arm would red every arm64 build. Its language-standard spelling is checked by name below instead.
    _cxxflags_words_match CXX_DEFINES  '^-D'                 'no define was split' \
        ${CXX_DEFINES[@]+"${CXX_DEFINES[@]}"}   || _bad=1
    _cxxflags_words_match CXX_INCLUDES '^(-I|-isystem$|/)'   'no include was split off its path' \
        ${CXX_INCLUDES[@]+"${CXX_INCLUDES[@]}"} || _bad=1

    # the one flag the drivers cannot compile without, named rather than assumed present
    case " ${CXX_FLAGS[*]-} " in
        *" -std="*|*" -clang:-std="*|*" /std:"*) printf 'PASS (R) CXX_FLAGS carries the language standard the drivers need\n' ;;
        *)          printf 'FAIL (R) no language-standard flag among the %s parsed CXX_FLAGS -- the drivers cannot compile with these\n' "$_nf"; _bad=1 ;;
    esac

    return "$_bad"
}

# ── (U) a line that does not parse must REACH the caller as a failure ────────────────────────────────────────
# The regression this arm exists for: cxxflags_load read its words through a process substitution, whose exit
# status is unreachable, so an unbalanced quote in the generated file parsed to zero words and the loader
# returned 0. A gate then compiled against an empty flag set and reported a result. Both halves are asserted,
# because the negative alone would also pass on a loader that always fails.
_cxxflags_status_arm()
{
    local _d="$1/status" _rc _bad=0
    rm -rf "$_d"; mkdir -p "$_d" || { printf 'FAIL (U) cannot create %s\n' "$_d"; return 1; }

    # (U1) NEGATIVE: an unbalanced quote on one of the three lines
    printf 'CXX_DEFINES = -DA=1\nCXX_INCLUDES = -I/x\nCXX_FLAGS = -DB="unclosed\n' > "$_d/flags.make"
    cxxflags_load "$_d/flags.make" 2>/dev/null; _rc=$?
    if [ "$_rc" -ne 0 ]; then
        printf 'PASS (U1) an unparseable CXX_FLAGS line makes cxxflags_load FAIL (rc=%s), so the gate cannot compile against a flag set nothing read\n' "$_rc"
    else
        printf 'FAIL (U1) cxxflags_load returned 0 on an unbalanced quote (CXX_FLAGS=%s words) -- the parser exit status is being swallowed again\n' "${#CXX_FLAGS[@]}"
        _bad=1
    fi

    # (U2) POSITIVE CONTROL: the same arm on a well-formed file must succeed with words in every array
    printf 'CXX_DEFINES = -DA=1\nCXX_INCLUDES = -I/x\nCXX_FLAGS = -std=gnu++23 -O3\n' > "$_d/flags.make"
    cxxflags_load "$_d/flags.make" 2>/dev/null; _rc=$?
    if [ "$_rc" -eq 0 ] && [ "${#CXX_FLAGS[@]}" -eq 2 ] && [ "${#CXX_DEFINES[@]}" -eq 1 ] && [ "${#CXX_INCLUDES[@]}" -eq 1 ]; then
        printf 'PASS (U2 control) a well-formed file still loads (rc=0, 2/1/1 arguments) -- U1 is a real refusal, not a loader that always fails\n'
    else
        printf 'FAIL (U2 control) a well-formed file did not load: rc=%s %s/%s/%s arguments\n' "$_rc" "${#CXX_FLAGS[@]}" "${#CXX_DEFINES[@]}" "${#CXX_INCLUDES[@]}"
        _bad=1
    fi

    return "$_bad"
}

# cxxflags_selfproof  $1 = a scratch directory it may create under, $2 = the REAL flags.make
# Prints PASS/FAIL/NOTE rows on stdout. Returns 0 when no row is a FAIL.
cxxflags_selfproof()
{
    local _work="$1" _real="$2" _bad=0

    mkdir -p "$_work" || { printf 'FAIL (P) cannot create the proof scratch directory %s\n' "$_work"; return 1; }

    _cxxflags_shape_arms "$_work" || _bad=1
    _cxxflags_mask_arm   "$_work" || _bad=1
    _cxxflags_bound_arm  "$_work" || _bad=1
    _cxxflags_parity_arm "$_work" || _bad=1
    _cxxflags_status_arm "$_work" || _bad=1
    _cxxflags_real_arm   "$_real" || _bad=1

    [ "$_bad" -eq 0 ]
}
