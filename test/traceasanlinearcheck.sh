#!/usr/bin/env bash
# traceasanlinearcheck.sh — --from-trace's ASan frame parser (src/tracein.h detail::parseAsan) is LINEAR
# in the trace text's size, not quadratic.
#
# THE DEFECT. parseAsan finds the source location on an ASan/UBSan frame line (`#0 0x.. in FUNC
# path:line:col`) by trying the LAST space-separated token first, then the last two, then the last
# three, … — because a demangled C++ function name can itself contain spaces
# (`rw::alpha(int const&)`), so the split cannot just be the first space. The original implementation
# re-derived the whole candidate on every widening try (rfind(':')/rfind(' ')/looksLikePath over a
# substring that only grows), which redoes the SAME work at every step: O(k^2) in the space-separated
# word count k. A line built from thousands of short, non-path-shaped "words" with no valid trailing
# location anywhere (the pattern a fuzzer, a minified diagnostic dump, or a pasted non-stack-trace blob
# produces) turned 160 KB of trace text into ~4 s of one --from-trace call.
#
# THE FIX. Every quantity the naive rescan recomputed is actually INVARIANT once the growing window
# first reaches it (a colon's position never moves; "does this stretch contain '.'/'/'" can only flip
# false->true as the window grows left, never back), so parseAsan now computes each ONCE and walks word
# boundaries in a single backward pass — O(after.size()) total, not O(words^2) — landing on the exact
# same candidate the original per-word rescan would have found first.
#
# Arms:
#   (A) CORRECTNESS — a real multi-word demangled frame (`rw::alpha(int const&) src/mod.cpp:8:1`, the
#       same shape test/tracecheck.sh's (A2a) fixture uses) still extracts path=src/mod.cpp, line=8 and
#       the whole func string, not a naive first-space split.
#   (B) NEAR-LINEAR TIMING — a PATHOLOGICAL line (many thousands of short, non-path-shaped words, one
#       lone path character planted in the very FIRST word so every candidate up to the last is tried
#       and fails, ending in a real `:digits` so the trailing-digit check alone cannot short-circuit) at
#       roughly 40 KB / 160 KB / 640 KB / 2.5 MB: each ~4x size step must cost roughly a ~4x time step,
#       not the ~16x a real O(k^2) would show. Generous slack (8x) keeps this off CI noise while still
#       catching a genuine quadratic regression, which blows the ratio by 100x+ at the top end.
#   (C) REGRESSION — an ordinary single-space ASan frame (test/tracecheck.sh's own fixture) still parses.
#
# MUTATION CONTROL: arm B is exactly what a revert to the per-candidate rescan trips — arm A and C still
# pass (the algorithm is a rewrite, not a capability change), only the TIMING ratio in B goes red. Run
# against a pre-fix binary — RIPWIRE_BIN=<base>/ripwire bash test/traceasanlinearcheck.sh — arm B must FAIL.
#
# Usage:  bash test/traceasanlinearcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/traceasanlinearcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "traceasanlinearcheck: python3 required"; exit 2; }
echo "traceasanlinearcheck: BIN=$BIN"

mkdir -p "$TMP/corpus"
run_trace(){ # $1 = trace file NAME, written under $TMP (an absolute --from-trace path, so this never
             # depends on the corpus cwd the way a relative one silently would if the fixture and the
             # corpus root ever drift apart)
    ( cd "$TMP/corpus" && "$BIN" . --from-trace="$TMP/$1" --no-cache 2>/dev/null )
}
attr(){ printf '%s' "$2" | grep -o "$1=\"[^\"]*\"" | head -1; }

# ===================================================================================================
# (A) a demangled, space-carrying function name — the exact shape tracecheck.sh (A2a) exercises
# ===================================================================================================
echo "-- (A) a demangled 'rw::alpha(int const&)' frame still splits on the RIGHT boundary"
cat > "$TMP/demangled.txt" <<'EOF'
    #0 0x1 in rw::alpha(int const&) src/mod.cpp:8:1
EOF
OUT_A="$( run_trace demangled.txt )"
if printf '%s' "$OUT_A" | grep -q '<skipped p="src/mod.cpp" line="8"'; then
    ok "A1: path=src/mod.cpp line=8 extracted correctly from a space-carrying func name"
else
    no "A1: the demangled frame did not extract path=src/mod.cpp line=8"; printf '%s\n' "$OUT_A" | head -c 400
fi

# ===================================================================================================
# (C) an ordinary single-space ASan frame — the plain case must be untouched
# ===================================================================================================
echo "-- (C) an ordinary ASan frame (single space before the location) still parses"
cat > "$TMP/plain.txt" <<'EOF'
    #0 0x108a in doWork src/engine.cpp:5:8
EOF
OUT_C="$( run_trace plain.txt )"
if printf '%s' "$OUT_C" | grep -q '<skipped p="src/engine.cpp" line="5"'; then
    ok "C1: path=src/engine.cpp line=5 extracted from an ordinary frame"
else
    no "C1: the ordinary frame did not extract path=src/engine.cpp line=5"; printf '%s\n' "$OUT_C" | head -c 400
fi

# ===================================================================================================
# (B) near-linear timing on a pathological, never-resolving line at 4 sizes
# ===================================================================================================
echo "-- (B) near-linear timing: 40 KB / 160 KB / 640 KB / 2.5 MB pathological ASan lines"

gen(){ # $1 = approx target size in bytes, $2 = output path
    python3 -c "
import sys
target = $1
# one lone path char in the FIRST word — every candidate up to the very last word must be tried and
# fail, so the whole line is walked; ends in a real ':digits' so the fast trailing-digit check alone
# cannot short-circuit the walk.
words = ['a.b']
n = 1
size = len('    #0 0x1 in ') + len(words[0])
while size < target:
    w = 'w%d' % n
    words.append(w)
    size += len(w) + 1
    n += 1
words[-1] = words[-1] + ':123'
line = '    #0 0x1 in ' + ' '.join(words) + chr(10)
open('$2', 'w').write(line)
"
}

gen 40000    "$TMP/patho_40k.txt"
gen 160000   "$TMP/patho_160k.txt"
gen 640000   "$TMP/patho_640k.txt"
gen 2500000  "$TMP/patho_2500k.txt"

nowms(){ python3 -c 'import time; print(int(time.time()*1000))'; }

# TIMED_OUT_MS: a hang is not "slow", it is the O(k^2) failure mode itself — a per-file 20s ceiling (the
# fixed implementation takes tens of MILLIseconds even at 2.5 MB) turns "the process never returned" into
# an explicit, ranked-huge timing number instead of killing this whole gate out from under the harness.
TIMED_OUT_MS=99999999
timed_trace(){ # $1 = fixture name -> prints elapsed ms on stdout
    local t0 t1 rc
    t0=$(nowms)
    timeout 20 bash -c "$( printf 'cd %q && %q . --from-trace=%q --no-cache' "$TMP/corpus" "$BIN" "$TMP/$1" )" >/dev/null 2>&1
    rc=$?
    t1=$(nowms)
    if [ "$rc" = 124 ]; then
        echo "$TIMED_OUT_MS"
    else
        local d=$(( t1 - t0 )); [ "$d" -lt 1 ] && d=1
        echo "$d"
    fi
}

ms40=$(timed_trace   patho_40k.txt)
ms160=$(timed_trace  patho_160k.txt)
ms640=$(timed_trace  patho_640k.txt)
ms2500=$(timed_trace patho_2500k.txt)

echo "     40 KB: ${ms40} ms   160 KB: ${ms160} ms   640 KB: ${ms640} ms   2.5 MB: ${ms2500} ms"

# linear ~= 4x per step; quadratic ~= 16x per step. 8x is generous slack over linear while still well
# below what even ONE quadratic doubling would show, so this does not flake on a loaded CI box.
if [ "$ms640" -le $(( ms160 * 8 )) ]; then
    ok "B1: 160 KB -> 640 KB (4x size) cost <= 8x time (${ms160}ms -> ${ms640}ms) — not quadratic"
else
    no "B1: 160 KB -> 640 KB cost ${ms160}ms -> ${ms640}ms, more than 8x — looks quadratic"
fi
if [ "$ms2500" -le $(( ms640 * 12 )) ]; then
    ok "B2: 640 KB -> 2.5 MB (~4x size) cost <= 12x time (${ms640}ms -> ${ms2500}ms) — not quadratic"
else
    no "B2: 640 KB -> 2.5 MB cost ${ms640}ms -> ${ms2500}ms, more than 12x — looks quadratic"
fi
# absolute ceiling: the whole point is that 2.5 MB must not take seconds
if [ "$ms2500" -le 3000 ]; then
    ok "B3: the 2.5 MB pathological trace parses in ${ms2500} ms (<=3000 ms)"
else
    no "B3: the 2.5 MB pathological trace took ${ms2500} ms — looks unbounded"
fi

if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
