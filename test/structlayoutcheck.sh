#!/usr/bin/env bash
# structlayoutcheck.sh — gate for cross-translation-unit layout records and --doctor.
#
# The fixture is deliberately deterministic: the same header is compiled into two
# translation units, but one sees an extra field through a test-only definition.
# No source header is edited and no build race is involved.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BUILD_DIR="$( dirname "$BIN" )"
CACHE="$BUILD_DIR/CMakeCache.txt"
cacheVar(){ [ -f "$CACHE" ] && sed -n "s/^$1:[A-Z]*=//p" "$CACHE" | head -1; return 0; }
CXX="${CXX:-$( cacheVar CMAKE_CXX_COMPILER )}"
CXX="${CXX:-c++}"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "structlayoutcheck: no ripwire binary at $BIN — build first"; exit 2; }
command -v "$CXX" >/dev/null 2>&1 || { echo "structlayoutcheck: no C++ compiler at $CXX"; exit 2; }
LAYOUT_TYPE_COUNT="$( grep -oF 'RIPWIRE_LAYOUT_TYPE_ENTRY(' "$ROOT/src/model.h" | wc -l | tr -d ' ' )"
[ "$LAYOUT_TYPE_COUNT" -gt 0 ] || { echo "structlayoutcheck: no registered layout types in $ROOT/src/model.h"; exit 2; }
. "$ROOT/scripts/cxxstd.sh"
if ! CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"; then
    echo "structlayoutcheck: $CXX accepts neither the C++23 standard flag nor its legacy spelling"; exit 2
fi

echo "structlayoutcheck: BIN=$BIN  CXX=$CXX"

CXXFLAGS=( "$CXXSTD" -O2 -flto -I"$ROOT/src" )
compile_unit(){
    local unit="$1"; shift
    "$CXX" "${CXXFLAGS[@]}" "-DRIPWIRE_LAYOUT_TU=\"$unit\"" "$@" \
        -c "$ROOT/test/structlayout_unit.cpp" -o "$TMP/$unit.o"
}

# ── A: mechanism, mixed layouts must be a hard disagreement ─────────────────────────────────────
fixture_ok=1
if compile_unit wide-fixture -DRIPWIRE_LAYOUT_FIXTURE_WIDE=1; then
    ok "mixed fixture wide translation unit compiles"
else
    no "mixed fixture wide translation unit did not compile"
    fixture_ok=0
fi
if compile_unit narrow-fixture; then
    ok "mixed fixture narrow translation unit compiles"
else
    no "mixed fixture narrow translation unit did not compile"
    fixture_ok=0
fi
if [ "$fixture_ok" = 1 ] && "$CXX" "${CXXFLAGS[@]}" "$ROOT/test/structlayout_probe.cpp" \
        "$TMP/wide-fixture.o" "$TMP/narrow-fixture.o" -o "$TMP/mixed"; then
    MIXED="$($TMP/mixed 2>&1)"; mixed_rc=$?
    echo "mixed fixture output: $MIXED"
    if [ "$mixed_rc" -eq 0 ]; then
        ok "mixed fixture reports a disagreement instead of agreeing"
    else
        no "mixed fixture did not report the expected disagreement (exit=$mixed_rc)"
    fi
    printf '%s' "$MIXED" | grep -q 'state=disagree' \
        && ok "mixed fixture state=disagree" \
        || no "mixed fixture did not name state=disagree"
    printf '%s' "$MIXED" | grep -q 'type=FixtureLayout' \
        && ok "mixed fixture names the disagreeing type" \
        || no "mixed fixture did not name FixtureLayout"
    printf '%s' "$MIXED" | grep -q 'wide-fixture' && printf '%s' "$MIXED" | grep -q 'narrow-fixture' \
        && ok "mixed fixture names both translation units" \
        || no "mixed fixture did not name both translation units"
else
    no "mixed fixture could not be linked"
fi

# ── B: one record is not a comparison and must not pass vacuously ─────────────────────────────────
if compile_unit single-fixture; then
    if "$CXX" "${CXXFLAGS[@]}" "$ROOT/test/structlayout_probe.cpp" "$TMP/single-fixture.o" -o "$TMP/single"; then
        SINGLE="$($TMP/single single 2>&1)"; single_rc=$?
        echo "single fixture output: $SINGLE"
        [ "$single_rc" -eq 0 ] \
            && ok "single fixture reports not-checked rather than passing vacuously" \
            || no "single fixture did not report not-checked (exit=$single_rc)"
        printf '%s' "$SINGLE" | grep -q 'state=not-checked units=1' \
            && ok "single fixture discloses state=not-checked and units=1" \
            || no "single fixture did not disclose the not-checked state"
    else
        no "single fixture could not be linked"
    fi
else
    no "single-record fixture did not compile"
fi

check_doctor(){
    local label="$1"; local binary="$2"; local output row rc
    output="$( PATH="$( dirname "$binary" ):$PATH" "$binary" "$ROOT" --doctor --no-cache 2>/dev/null )"; rc=$?
    row="$( printf '%s' "$output" | tr '<' '\n' | grep '^c n="layout" ' || true )"
    echo "$label doctor row: ${row:-<missing>} (exit=$rc)"
    [ "$rc" -eq 0 ] \
        && ok "$label --doctor exits 0" \
        || no "$label --doctor exited $rc"
    printf '%s' "$row" | grep -q 'ok="1"' \
        && ok "$label layout row agrees" \
        || no "$label layout row is not ok=\"1\""
    printf '%s' "$row" | grep -q 'checked="1"' \
        && ok "$label layout row is checked" \
        || no "$label layout row is not checked"
    printf '%s' "$row" | grep -Eq 'units="([2-9]|[1-9][0-9]+)"' \
        && ok "$label layout row compares at least two translation units" \
        || no "$label layout row has fewer than two translation units"
    printf '%s' "$row" | grep -q "types=\"$LAYOUT_TYPE_COUNT\"" \
        && ok "$label layout row reports all $LAYOUT_TYPE_COUNT registered model types" \
        || no "$label layout row did not report types=\"$LAYOUT_TYPE_COUNT\""
}

# ── C: the actual binary carries the records in the plain build ───────────────────────────────────
check_doctor plain "$BIN"

# ── D: the binary's own --version selects the Release arm ─────────────────────────────────────────
# Release matrix jobs pass this same binary as $BIN, so no workflow-specific environment is needed. A
# plain dev binary keeps the local SKIP; only an exact build-type token of Release can enter this arm.
BUILD_INFO="$( "$BIN" --version 2>/dev/null )"; BUILD_INFO_RC=$?
BUILD_TYPE="$( printf '%s\n' "$BUILD_INFO" | sed -nE 's/^ripwire [^ ]+ \(([^,]+),.*$/\1/p' | head -1 )"
if [ "$BUILD_INFO_RC" -ne 0 ]; then
    no "could not query $BIN --version to choose the Release arm"
elif [ "$BUILD_TYPE" = Release ]; then
    check_doctor release "$BIN"
elif [ "$BUILD_TYPE" = dev ]; then
    skip "Release binary not supplied ($BIN reports build type dev)"
elif [ -n "$BUILD_TYPE" ]; then
    skip "Release arm not run ($BIN reports build type $BUILD_TYPE)"
else
    no "$BIN --version did not disclose a build type"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES ABOVE"
fi
exit "$fail"
