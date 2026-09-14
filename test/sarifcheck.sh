#!/usr/bin/env bash
# sarifcheck.sh — W1-SARIF (board Track A P0-7): --lint --sarif serializes lint findings as SARIF
# 2.1.0 (github.com/oasis-tcs/sarif-spec), the shape github/codeql-action/upload-sarif consumes for
# the code-scanning UI. Pure re-serialization of the SAME findings --lint's native XML already
# computes — no new analysis, so this gate is a PARITY + SHAPE gate, not a new-findings gate.
#
# Arms:
#   1. --lint --sarif exists and exits 0 on a real corpus
#   2. output parses as JSON (python3 json.load)
#   3. the SARIF-minimum-viable fields for GitHub code scanning are present: version, $schema,
#      runs[0].tool.driver.name, runs[0].tool.driver.rules, runs[0].results
#   4. PARITY — results count == the SAME run's native --lint findings="N" count (serialization
#      must not drop or invent findings)
#   5. deterministic — two runs byte-identical (the same contract every other lint verb carries)
#   6. relative URIs — every result's artifactLocation.uri is relative to the scanned root (no
#      leading '/', no drive letter, no '..' escape)
#   7. a known fixture (test/lintfix/bad.cpp's typedef-over-using at line 9) produces the expected
#      ruleId at the expected line
#   8. SELECTION crosses over. The XML path drops a --lint-select=/--lint-ignore= deselected rule's row
#      entirely and states selected="K of N" + the raw select= on its root; the SARIF path emitted the
#      full 39-rule catalogue BYTE-IDENTICAL whether a rule was selected in or out, and said nothing at
#      the run level. A consumer reading that document could not tell a filtered run from an unfiltered
#      one. SARIF's own field for "in the catalogue but not enabled this run" is
#      defaultConfiguration.enabled — present-and-false on a deselected rule, ABSENT (SARIF's own
#      default of true) on a kept one — and the run-level mirror rides properties beside findingsCapped.
#   9. INERTNESS crosses over. A rule row's applicable="0" in the XML means NONE of its registered
#      languages exist in this corpus, so its count="0" is structural, never a measurement. In SARIF
#      those rules read as ran-and-found-nothing. properties.applicable carries the same fact, and it is
#      emitted for EVERY rule (true as well as false) so its absence can never be read as "true".
#  10. MUTATION CONTROL for 8+9 — the unfiltered run over a C-family corpus must show the negative of
#      both: no rule disabled, and the C-family rules applicable. Without it, a serializer that hard-coded
#      enabled:false / applicable:false everywhere would pass arms 8 and 9.
#  11. THE FILESYSTEM ROOT (U) — arm 6 above proves no URI starts with '/' for the roots a gate can hand a
#      BINARY, and `/` is not one of them: a corpus at the filesystem root means crawling the whole machine,
#      so no end-to-end arm can ever reach it. The defect lives in a pure function, so the arm is a unit
#      driver over that function instead — the recipe extentcheck.sh (U) and jsonwalkcheck.sh already use,
#      compiled with the exact flags CMake gave $BIN. It pins BOTH halves of the contract together: the
#      predicate the document's envelope claims (testmap.h runsAreRootRelative, TRUE for any single
#      non-empty root, "/" included) and the URI the relativizer actually returns. A root of "/" IS its own
#      separator, so the general prefix+'/' shape could not match it and an absolute path shipped inside a
#      document declaring its rows root-relative. Regression rows for every non-root prefix are in the same
#      table, so a fix that over-strips fails here rather than on a consumer's machine.
#
#   RIPWIRE_BIN=build/ripwire bash test/sarifcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/sarifcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/lintfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/lintfix dir — fixture missing"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "sarifcheck: python3 missing (gate cannot run)"; exit 2; }

echo "sarifcheck: BIN=$BIN  CORPUS=$CORPUS"

# ── 1. flag exists, exits 0 ──────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --lint --sarif --no-cache >"$TMP/out1.json" 2>"$TMP/err1"; rc=$?
if [ "$rc" -eq 0 ]; then ok "--lint --sarif exits 0"
else no "--lint --sarif exit $rc"; sed 's/^/          /' "$TMP/err1"; fi

# presence guard: a later arm reading an empty/absent file must not read as a silent pass
[ -s "$TMP/out1.json" ] && ok "--lint --sarif produced non-empty stdout" \
    || { no "--lint --sarif produced EMPTY stdout — every arm below is meaningless"; printf 'sarifcheck: FAILURES ABOVE\n'; exit 1; }

# ── 2. output parses as JSON ─────────────────────────────────────────────────────────────────────
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/out1.json" 2>"$TMP/jsonerr"; then
    ok "output parses as JSON (python3 json.load)"
else
    no "output does NOT parse as JSON:"; sed 's/^/          /' "$TMP/jsonerr"
fi

# ── 3. SARIF-minimum-viable fields present ───────────────────────────────────────────────────────
FIELDS="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); sys.exit( 0 )
ok = True
def need( cond, label ):
    global ok
    print( ( "HAVE " if cond else "MISS " ) + label )
    if not cond:
        ok = False
need( d.get( "version" ) == "2.1.0", "version=2.1.0" )
need( isinstance( d.get( "$schema" ), str ) and d[ "$schema" ], "$schema" )
runs = d.get( "runs" )
need( isinstance( runs, list ) and len( runs ) >= 1, "runs[0]" )
if isinstance( runs, list ) and runs:
    r0 = runs[0]
    driver = r0.get( "tool", {} ).get( "driver", {} )
    need( isinstance( driver.get( "name" ), str ) and driver[ "name" ], "runs[0].tool.driver.name" )
    need( isinstance( driver.get( "rules" ), list ), "runs[0].tool.driver.rules" )
    results = r0.get( "results" )
    need( isinstance( results, list ), "runs[0].results" )
    if isinstance( results, list ) and results:
        r = results[0]
        need( isinstance( r.get( "ruleId" ), str ) and r[ "ruleId" ], "results[0].ruleId" )
        need( isinstance( r.get( "level" ), str ) and r[ "level" ], "results[0].level" )
        need( isinstance( r.get( "message", {} ).get( "text" ), str ), "results[0].message.text" )
        loc = r.get( "locations", [ {} ] )[0].get( "physicalLocation", {} )
        need( isinstance( loc.get( "artifactLocation", {} ).get( "uri" ), str ), "results[0].locations[0].physicalLocation.artifactLocation.uri" )
        need( isinstance( loc.get( "region", {} ).get( "startLine" ), int ), "results[0].locations[0].physicalLocation.region.startLine" )
print( "ALLOK" if ok else "SOMEMISSING" )
PY
)"
echo "$FIELDS" | sed 's/^/          /'
if echo "$FIELDS" | grep -q '^ALLOK$'; then
    ok "all SARIF-minimum-viable fields present (version, \$schema, tool.driver.name/rules, results[].ruleId/level/message/locations)"
else
    no "at least one SARIF-minimum-viable field is missing (see HAVE/MISS above)"
fi

# ── 4. PARITY — results count == native --lint findings count, same run ─────────────────────────
"$BIN" "$CORPUS" --lint --no-cache >"$TMP/native.xml" 2>/dev/null
NATIVE_N="$( grep -oE '<lint findings="[0-9]+"' "$TMP/native.xml" | head -1 | grep -oE '[0-9]+' )"
SARIF_N="$( python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['runs'][0]['results']))" "$TMP/out1.json" 2>/dev/null )"
if [ -n "${NATIVE_N:-}" ] && [ -n "${SARIF_N:-}" ] && [ "$NATIVE_N" = "$SARIF_N" ]; then
    ok "parity — SARIF results ($SARIF_N) == native --lint findings ($NATIVE_N)"
else
    no "parity FAILED — SARIF results (${SARIF_N:-unreadable}) != native --lint findings (${NATIVE_N:-unreadable})"
fi

# ── 5. deterministic — two runs byte-identical ───────────────────────────────────────────────────
"$BIN" "$CORPUS" --lint --sarif --no-cache >"$TMP/out2.json" 2>/dev/null
diff -q "$TMP/out1.json" "$TMP/out2.json" >/dev/null \
    && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic SARIF output"; diff "$TMP/out1.json" "$TMP/out2.json" | head -8; }

# ── 6. relative URIs ──────────────────────────────────────────────────────────────────────────────
URI_BAD="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
bad = []
for r in d.get( "runs", [ {} ] )[0].get( "results", [] ):
    for loc in r.get( "locations", [] ):
        uri = loc.get( "physicalLocation", {} ).get( "artifactLocation", {} ).get( "uri", "" )
        if uri.startswith( "/" ) or ":" in uri.split( "/" )[0] or ".." in uri.split( "/" ):
            bad.append( uri )
print( "\n".join( bad ) )
PY
)"
if [ -z "$URI_BAD" ]; then
    ok "every result URI is relative to the scanned root"
else
    no "found non-relative URI(s):"; printf '%s\n' "$URI_BAD" | sed 's/^/          /'
fi

# ── 7. known fixture: typedef-over-using at test/lintfix/bad.cpp:9 ─────────────────────────────────
HIT="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
for r in d.get( "runs", [ {} ] )[0].get( "results", [] ):
    if r.get( "ruleId" ) != "typedef-over-using":
        continue
    for loc in r.get( "locations", [] ):
        pl = loc.get( "physicalLocation", {} )
        uri = pl.get( "artifactLocation", {} ).get( "uri", "" )
        line = pl.get( "region", {} ).get( "startLine" )
        if uri.endswith( "bad.cpp" ) and line == 9:
            print( "FOUND" ); sys.exit( 0 )
print( "MISSING" )
PY
)"
[ "$HIT" = "FOUND" ] && ok "typedef-over-using at test/lintfix/bad.cpp:9 present with the expected ruleId+line" \
    || no "typedef-over-using at bad.cpp:9 NOT found in SARIF results"

# ── 8. --lint-select= crosses over: deselected rules are disabled, and the run says so ───────────────
"$BIN" "$CORPUS" --lint --lint-select=cache- --sarif --no-cache >"$TMP/sel.json" 2>/dev/null
SEL="$( python3 - "$TMP/sel.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); raise SystemExit( 0 )
run   = d[ "runs" ][ 0 ]
rules = run[ "tool" ][ "driver" ][ "rules" ]
def enabled( r ):
    return r.get( "defaultConfiguration", {} ).get( "enabled", True )
offDisabled = [ r["id"] for r in rules if not r["id"].startswith( "cache-" ) and not enabled( r ) ]
offEnabled  = [ r["id"] for r in rules if not r["id"].startswith( "cache-" ) and     enabled( r ) ]
inDisabled  = [ r["id"] for r in rules if     r["id"].startswith( "cache-" ) and not enabled( r ) ]
print( "SELECTED_OUT_DISABLED", len( offDisabled ) )
print( "SELECTED_OUT_STILL_ENABLED", len( offEnabled ) )
print( "SELECTED_IN_DISABLED", len( inDisabled ) )
props = run.get( "properties", {} )
print( "PROP_SELECTED", props.get( "selected", "<absent>" ) )
print( "PROP_SELECT", props.get( "select", "<absent>" ) )
PY
)"
echo "$SEL" | sed 's/^/          /'
n(){ printf '%s' "$SEL" | grep "^$1 " | awk '{print $2}'; }
[ "$( n SELECTED_OUT_DISABLED )" -gt 0 ] 2>/dev/null \
    && ok "8. a selected-OUT rule carries defaultConfiguration.enabled=false ($( n SELECTED_OUT_DISABLED ) of them)" \
    || no "8. NO selected-out rule is marked disabled — the catalogue reads identical filtered or not"
[ "$( n SELECTED_OUT_STILL_ENABLED )" = "0" ] \
    && ok "8. EVERY selected-out rule is marked disabled (none left reading as enabled)" \
    || no "8. $( n SELECTED_OUT_STILL_ENABLED ) selected-out rule(s) still read as enabled"
[ "$( n SELECTED_IN_DISABLED )" = "0" ] \
    && ok "8. no selected-IN (cache-*) rule was disabled — the filter is not inverted" \
    || no "8. $( n SELECTED_IN_DISABLED ) selected-IN rule(s) were marked disabled"
printf '%s' "$SEL" | grep -q '^PROP_SELECTED [0-9]* of [0-9]*$' \
    && ok "8. run properties mirror the XML root's selected=\"K of N\"" \
    || no "8. run-level properties carry no selected=\"K of N\" mirror"
printf '%s' "$SEL" | grep -q '^PROP_SELECT cache-$' \
    && ok "8. run properties echo the raw select= you passed (cache-)" \
    || no "8. run-level properties do not echo the raw select= argument"

# ── 9. a Python-only corpus marks the C-family rules structurally inert ──────────────────────────────
mkdir -p "$TMP/pyonly"
printf 'def alpha( x ):\n    return x + 1\n' > "$TMP/pyonly/a.py"
"$BIN" "$TMP/pyonly" --lint --sarif --no-cache >"$TMP/py.json" 2>/dev/null
PY_APP="$( python3 - "$TMP/py.json" <<'PY'
import json, sys
try:
    d = json.load( open( sys.argv[1] ) )
except Exception as exc:
    print( "PARSE_FAIL", exc ); raise SystemExit( 0 )
rules = { r["id"]: r for r in d[ "runs" ][ 0 ][ "tool" ][ "driver" ][ "rules" ] }
r = rules.get( "typedef-over-using" )
print( "PRESENT", "yes" if r else "no" )
if r:
    print( "APPLICABLE", r.get( "properties", {} ).get( "applicable", "<absent>" ) )
print( "MISSING_PROP", sum( 1 for x in rules.values() if "applicable" not in x.get( "properties", {} ) ) )
PY
)"
echo "$PY_APP" | sed 's/^/          /'
printf '%s' "$PY_APP" | grep -q '^PRESENT yes$' \
    && ok "9. the C-family rule typedef-over-using is in the Python-only catalogue (guard for the arm below)" \
    || no "9. typedef-over-using absent from the Python-only catalogue — the arm below would pass vacuously"
printf '%s' "$PY_APP" | grep -q '^APPLICABLE False$' \
    && ok "9. it carries properties.applicable=false — inert here, not measured-clean" \
    || no "9. properties.applicable is not false on a C-family rule over a Python-only corpus"
printf '%s' "$PY_APP" | grep -q '^MISSING_PROP 0$' \
    && ok "9. every rule carries properties.applicable — absence can never be misread as true" \
    || no "9. some rules omit properties.applicable"

# ── 10. mutation control — the unfiltered C-family run must show the NEGATIVE of both ────────────────
MUT="$( python3 - "$TMP/out1.json" <<'PY'
import json, sys
d     = json.load( open( sys.argv[1] ) )
rules = d[ "runs" ][ 0 ][ "tool" ][ "driver" ][ "rules" ]
dis   = [ r["id"] for r in rules if not r.get( "defaultConfiguration", {} ).get( "enabled", True ) ]
inert = [ r["id"] for r in rules if r.get( "properties", {} ).get( "applicable" ) is False ]
print( "DISABLED", len( dis ) )
print( "CFAMILY_INERT", 1 if "typedef-over-using" in inert else 0 )
print( "PROPS", json.dumps( d[ "runs" ][ 0 ].get( "properties", {} ), sort_keys = True ) )
PY
)"
echo "$MUT" | sed 's/^/          /'
printf '%s' "$MUT" | grep -q '^DISABLED 0$' \
    && ok "10. an unfiltered run disables nothing (enabled:false is not hard-coded)" \
    || no "10. an unfiltered run marks rules disabled — the selection mirror is not reading the selection"
printf '%s' "$MUT" | grep -q '^CFAMILY_INERT 0$' \
    && ok "10. typedef-over-using is APPLICABLE over the C-family fixture (applicable:false is not hard-coded)" \
    || no "10. typedef-over-using reads inert over a C++ corpus"
printf '%s' "$MUT" | grep -q '"selected"' \
    && no "10. an unfiltered run still emits a selected= mirror — absent must mean no selection was given" \
    || ok "10. no selection mirror on an unfiltered run (absent = nothing to say)"

# ── 11. the filesystem root, through a unit driver over the relativizer itself ──────────────────────
# See the header note: `/` is the one root no binary arm can reach, and the answer is a pure function, so
# this arm compiles that function with $BIN's own CMake flags rather than inventing a second toolchain.
BUILD_DIR="$( cd "$( dirname "$BIN" )" && pwd )"
FLAGS_MK="$BUILD_DIR/CMakeFiles/ripwire.dir/flags.make"
LINK_TXT="$BUILD_DIR/CMakeFiles/ripwire.dir/link.txt"
if [ ! -f "$FLAGS_MK" ] || [ ! -f "$LINK_TXT" ]; then
    no "11. cannot find CMake flags under $BUILD_DIR — the unit arm needs a CMake-built binary"
else
    cat >"$TMP/rooturi_unit.cpp" <<'CPP'
// The root-relative URI contract, at the granularity of the function that decides it. Every p=/uri=
// emitter in the tool routes through this ONE pair (sarif.h rootPrefixOf + rootRelativeUri), so a row
// here is a statement about the whole emission surface, not about SARIF alone.
#include "sarif.h"
#include "testmap.h"

#include <cstdio>
#include <string>
#include <string_view>

namespace
{

int g_failCount = 0;

void check( bool cond, const std::string& what )
{
    std::printf( "  %s  %s\n", cond ? "PASS" : "FAIL", what.c_str() );
    if( !cond )
    {
        ++g_failCount;
    }
}

// One row of the contract: the spelling ing.files[] stores, the raw root ARGUMENT (normalized through
// rootPrefixOf exactly as every emitter does), and the URI the document must carry. `underRoot` is the
// honesty half — when the path really does lie under the declared root, a leading '/' in the answer is
// not a cosmetic blemish but a row contradicting its own envelope.
struct UriCase
{
    const char* file;
    const char* rootArg;
    const char* want;
    bool        underRoot;
};

}   // namespace

int main()
{
    // The predicate the envelope claims. An empty realPaths means one root, so any non-empty root —
    // "/" included — makes the document say "every path below is relative to root=".
    const rw::IngestResult ing;
    check(  rw::runsAreRootRelative( ing, "/" ), "runsAreRootRelative( single root, \"/\" ) is TRUE — root=\"/\" declares its rows relative" );
    check( !rw::runsAreRootRelative( ing, "" ),  "runsAreRootRelative( single root, \"\" ) is FALSE — no root declared, no claim made" );

    // rootPrefixOf keeps "/" (the one root whose trailing slash IS the whole path) and still strips
    // a trailing slash from every other spelling.
    check( rw::sarif::rootPrefixOf( "/" )     == "/",    "rootPrefixOf( \"/\" ) == \"/\"" );
    check( rw::sarif::rootPrefixOf( "//" )    == "/",    "rootPrefixOf( \"//\" ) == \"/\"" );
    check( rw::sarif::rootPrefixOf( "/abs/" ) == "/abs", "rootPrefixOf( \"/abs/\" ) == \"/abs\"" );

    static constexpr UriCase kCases[] =
    {
        // THE DEFECT — root "/" is its own separator, so the general prefix+'/' shape never matched it
        { "/test/check.sh",         "/",         "test/check.sh",         true  },
        { "/a.cpp",                 "/",         "a.cpp",                 true  },
        { "//a.cpp",                "/",         "a.cpp",                 true  },
        { "/",                      "/",         "/",                     false },   // the root itself: a path, never an empty URI
        { "a.cpp",                  "/",         "a.cpp",                 true  },   // already relative: nothing to strip
        // REGRESSION GUARDS — every non-root prefix keeps the exact answer it gave before
        { "./bad.cpp",              ".",         "bad.cpp",               true  },
        { "./corp/test/x.sh",       "./corp",    "test/x.sh",             true  },
        { "/abs/repo/src/main.cpp", "/abs/repo", "src/main.cpp",          true  },
        { "/other/x.cpp",           "/abs/repo", "/other/x.cpp",          false },   // outside the root: unrelativizable, unchanged
        { "/abs/repository/x.cpp",  "/abs/repo", "/abs/repository/x.cpp", false },   // separator guard: a sibling prefix steals nothing
    };

    for( const UriCase& c : kCases )
    {
        const std::string      prefix = rw::sarif::rootPrefixOf( c.rootArg );
        const std::string_view got    = rw::sarif::rootRelativeUri( c.file, prefix );
        check( got == std::string_view( c.want ),
               std::string( "rootRelativeUri( \"" ) + c.file + "\", root \"" + c.rootArg + "\" ) == \"" + c.want + "\" (got \"" + std::string( got ) + "\")" );
        if( c.underRoot )
        {
            check( !got.empty() && got.front() != '/',
                   std::string( "\"" ) + c.file + "\" under root \"" + c.rootArg + "\" emits a RELATIVE uri, as the envelope claims" );
        }
    }

    std::printf( g_failCount == 0 ? "UNIT ALL PASS\n" : "UNIT FAILURES: %d\n", g_failCount );
    return g_failCount == 0 ? 0 : 1;
}
CPP
    # The compiler CMake drove (link.txt's first token), never a guess — jsonwalkcheck.sh's recipe and reason.
    CXX="$( awk 'NR==1{ print $1; exit }' "$LINK_TXT" )"
    [ -n "$CXX" ] && command -v "$CXX" >/dev/null 2>&1 || CXX="$( command -v c++ || command -v clang++ )"
    eval "CXX_FLAGS=(    $( grep -m1 '^CXX_FLAGS ='    "$FLAGS_MK" | sed 's/^CXX_FLAGS =//' ) )"
    eval "CXX_DEFINES=(  $( grep -m1 '^CXX_DEFINES ='  "$FLAGS_MK" | sed 's/^CXX_DEFINES =//' ) )"
    eval "CXX_INCLUDES=( $( grep -m1 '^CXX_INCLUDES =' "$FLAGS_MK" | sed 's/^CXX_INCLUDES =//' ) )"
    # VERIFY's debug arm reports through the diagnostics TU, so the driver links that one object (when present).
    DIAG_OBJ="$BUILD_DIR/CMakeFiles/ripwire.dir/src/infra/diagnostics.cpp.o"
    DIAG_LINK=(); [ -f "$DIAG_OBJ" ] && DIAG_LINK=( "$DIAG_OBJ" )
    if "$CXX" "${CXX_FLAGS[@]}" "${CXX_DEFINES[@]}" "${CXX_INCLUDES[@]}" -I"$ROOT/src" \
         "$TMP/rooturi_unit.cpp" "${DIAG_LINK[@]}" -o "$TMP/rooturi_unit" >"$TMP/u_build.log" 2>&1; then
        "$TMP/rooturi_unit" >"$TMP/u_run.log" 2>&1; urc=$?
        sed 's/^/        /' "$TMP/u_run.log"
        if [ "$urc" -eq 0 ] && grep -q '^UNIT ALL PASS$' "$TMP/u_run.log"; then
            ok "11. root-uri unit driver: $( grep -c '  PASS  ' "$TMP/u_run.log" | tr -d ' ' ) cases hold, root \"/\" included"
        else
            no "11. root-uri unit driver reported failures (rc=$urc)"
        fi
    else
        no "11. the root-uri unit driver does not compile:"; grep -m4 -E 'error' "$TMP/u_build.log" | sed 's/^/          /'
    fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
