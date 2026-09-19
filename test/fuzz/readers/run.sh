#!/usr/bin/env bash
# run.sh — the reader fuzzers (test/fuzz/readers/): replay the committed seeds, or fuzz each reader time-boxed.
#
#   bash test/fuzz/readers/run.sh BUILD_DIR replay            # every seed through every reader, no mutation
#   bash test/fuzz/readers/run.sh BUILD_DIR fuzz SECONDS [R]  # R (or every reader) fuzzed for SECONDS, ONE AT A TIME
#
# BUILD_DIR is a RIPWIRE_FUZZ=ON tree with `cmake --build BUILD_DIR --target ripwire_reader_fuzzers` done. The reader
# list is read from CMakeLists.txt's RIPWIRE_FUZZ_READERS, never written here. Readers run one at a time on purpose:
# the build machines these run on are shared, and a crash fuzzer's value is in its time, not its parallelism.
#
# A replay that executed 0 inputs is a FAIL, not a pass, and so is one whose reader accepted none of its valid seeds
# (RWFUZZ_LIVENESS=1: each harness says whether its reader accepted the input — a wrong header shape refuses all).
# Seeds named regress-* are minimized inputs that once crashed a reader; they are expected to be refused and are exempt. Each reader's line says how many inputs it ran. Artifacts
# of a failing reader (the crashing input, libFuzzer's log) are kept under the printed directory; replay one with
#   BUILD_DIR/ripwire_fuzz_reader_<name> <artifact>
# and minimise it with -minimize_crash=1 before it becomes a seed and a regression arm.

set -u
ROOT="$( cd "$( dirname "$0" )/../../.." && pwd )"
BUILD_DIR="${1:?usage: run.sh BUILD_DIR replay|fuzz [SECONDS] [READER]}"
MODE="${2:?usage: run.sh BUILD_DIR replay|fuzz [SECONDS] [READER]}"
SECONDS_PER="${3:-300}"
ONLY="${4:-}"
case "$BUILD_DIR" in /*) ;; *) BUILD_DIR="$ROOT/$BUILD_DIR" ;; esac
SEEDS="$ROOT/test/fuzz/readers/seeds"
OUT="$( mktemp -d )"
FAILED=0

READERS="$( sed -n '/set(RIPWIRE_FUZZ_READERS/,/)/p' "$ROOT/CMakeLists.txt" | tr -d '()' | sed 's/setRIPWIRE_FUZZ_READERS//' | tr -s ' \n' ' ' )"
[ -n "${READERS// /}" ] || { echo "run.sh: no RIPWIRE_FUZZ_READERS list in CMakeLists.txt"; exit 2; }
[ -n "$ONLY" ] && READERS="$ONLY"

if [ "$( uname -s )" = "Darwin" ]; then DETECT_LEAKS=0; else DETECT_LEAKS=1; fi
export ASAN_OPTIONS="detect_leaks=$DETECT_LEAKS:halt_on_error=1:abort_on_error=1:handle_abort=1:handle_sigtrap=1"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
export LSAN_OPTIONS="suppressions=$ROOT/lsan_suppressions.txt"

for reader in $READERS; do
    bin="$BUILD_DIR/ripwire_fuzz_reader_$reader"
    seeds="$SEEDS/$reader"
    log="$OUT/$reader.log"
    if [ ! -x "$bin" ]; then
        printf 'FAIL  reader/%s: no target at %s\n' "$reader" "$bin"; FAILED=1; continue
    fi
    if [ ! -d "$seeds" ] || [ -z "$( ls -A "$seeds" 2>/dev/null )" ]; then
        printf 'FAIL  reader/%s: no seeds at %s\n' "$reader" "$seeds"; FAILED=1; continue
    fi
    mkdir -p "$OUT/artifacts/$reader"
    if [ "$MODE" = "replay" ]; then
        # a list of FILES (not a directory) makes libFuzzer run each once and mutate nothing
        RWFUZZ_LIVENESS=1 nice -n 10 "$bin" -timeout=20 -rss_limit_mb=4096 -artifact_prefix="$OUT/artifacts/$reader/" "$seeds"/* >"$log" 2>&1
        rc=$?
        ran="$( grep -c '^Executed ' "$log" )"
        # per seed, between libFuzzer's "Running: F" and "Executed F": every committed seed is valid by construction
        # (make_seeds.sh), so each one the reader refused names a harness that does not reach the parse it fuzzes
        refused="$( awk '/^Running: /{ f = substr( $0, 10 ); ok = 0; next } /^RWFUZZ accepted=1$/{ ok = 1; next }
                         /^Executed /{ n = split( f, parts, "/" ); if( !ok && parts[ n ] !~ /^regress-/ ) { printf "%s ", f } }' "$log" )"
        regress="$( ls "$seeds" | grep -c '^regress-' )"
        accepted=$(( ${ran:-0} - regress - $( printf '%s' "$refused" | wc -w | tr -d ' ' ) ))
        if [ "$rc" -eq 0 ] && [ -n "$refused" ]; then
            printf 'FAIL  reader/%s: its reader refused valid seed(s): %s— the harness does not reach the parse it fuzzes\n' "$reader" "$refused"
            FAILED=1; continue
        fi
    else
        corpus="$OUT/corpus/$reader"; mkdir -p "$corpus"
        cp "$seeds"/* "$corpus/"
        nice -n 10 "$bin" "$corpus" -max_total_time="$SECONDS_PER" -timeout=20 -rss_limit_mb=4096 -max_len=262144 \
            -print_final_stats=1 -artifact_prefix="$OUT/artifacts/$reader/" >"$log" 2>&1
        rc=$?
        ran="$( grep -oE 'stat::number_of_executed_units: *[0-9]+' "$log" | grep -oE '[0-9]+$' )"
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'FAIL  reader/%s: exit %s after %s input(s) — %s\n' "$reader" "$rc" "${ran:-?}" "$( grep -m1 -E 'ERROR:|runtime error|deadly signal|Trace/BPT|libc\+\+abi' "$log" | cut -c1-160 )"
        FAILED=1
    elif [ "${ran:-0}" -eq 0 ]; then
        printf 'FAIL  reader/%s: executed 0 inputs — nothing was tested\n' "$reader"; FAILED=1
    else
        printf 'PASS  reader/%s: %s input(s)%s, no report\n' "$reader" "$ran" "${accepted:+, $accepted accepted}"
    fi
done

if [ "$FAILED" = 0 ]; then rm -rf "$OUT"; printf 'ALL PASS\n'; else printf 'FAILURES ABOVE (logs and artifacts kept at %s)\n' "$OUT"; fi
exit "$FAILED"
