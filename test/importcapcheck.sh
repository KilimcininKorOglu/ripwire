#!/usr/bin/env bash
# importcapcheck.sh — the gate for the shared import-capture vocabulary (issue #358), C-family slice.
#
# WHAT THIS PINS. `#include` / `#import` for c, cpp, objc (and the .h/.hpp/.cu/.cuh/.metal extensions
# that ride those grammars) no longer come from a per-language extractor in src/ingest_relations.h. They
# come from ONE capture name — `@import.path`, declared in queries/{c,cpp,objc}/tags.scm — normalised by
# the ONE DepDialect::CFamily specifier normaliser in src/ingest_importcap.h. This gate pins that the
# EMITTED dependency edges are exactly the ones the extractor emitted, for every shape the round touches:
#
#   1  the vocabulary is LIVE      — an @import.path capture is what produces the edge, so dropping the
#                                    patterns from tags.scm must make these rows disappear (the control for
#                                    "the query is not decoration").
#   2  quote vs angle              — the isAngle bit, from the delimiter. Resolution leaves <x.h> alone.
#   3  #import under BOTH spellings — the C and C++ grammars have no #import rule (it parses as a generic
#                                    preproc_call, argument-gated in C++); the ObjC grammar HAS one.
#   4  the C++ gate on directive TEXT — `#pragma once` / `#error` / `#warning` are captured by the same
#                                    pattern and MUST NOT become edges. This is the arm a query predicate
#                                    would have written and the tags pass cannot evaluate.
#   5  a macro include              — `#include HEADER` carries no delimiter; the target stays the bare
#                                    macro name (a disclosed floor, unchanged by the round).
#   6  an include inside a guard    — `#if`/`#else`/`#elif`/`#ifdef`, the union-over-arms posture.
#   7  a DEAD arm                   — `#if 0` / `#elif 0` includes must be DROPPED. This is the arm the
#                                    round could most easily have broken: captureTagsFacts never ran
#                                    dropPreprocDead over `includes` before, and a query cannot know an
#                                    arm is dead. Measured without the filter: dep_dead_if.h and
#                                    dep_elif.h both come back as edges.
#   8  the use-site half            — every Include has its ABS-3 import-role use-site ref, so --uses
#                                    still reports the include site of a header by its importable name.
#   9  cache round-trip             — cold == warm byte-identically, and warm == --no-cache.
#  10  determinism                  — two independent cold runs byte-identical.
#
# Usage:  test/importcapcheck.sh
#         RIPWIRE_BIN=asan/ripwire test/importcapcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "importcapcheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"

# The fixture: one C++ file carrying every C-family spelling, one plain-C file, one ObjC file. The ten
# headers are one-line stubs — the round is about the EDGE, and an edge resolves to a real file, so every
# spelled target must exist on disk or the row would vanish for the wrong reason.
for h in dep_quoted dep_angle dep_imported dep_imported_angle dep_if dep_else dep_ifdef dep_elif \
         dep_dead_if dep_dead_ifdef; do
    printf 'int %s_helper( void );\n' "$h" > "$WORK/$h.h"
done
printf 'int HEADER_MACRO_PATH_helper( void );\n' > "$WORK/HEADER_MACRO_PATH.h"

cat > "$WORK/main.cpp" <<'CPP'
#include "dep_quoted.h"
#include <dep_angle.h>
#import "dep_imported.h"
#import <dep_imported_angle.h>
#include HEADER_MACRO_PATH
#pragma once
#error "not an include at all"
#define GUARD 1
#if defined(GUARD)
#include "dep_if.h"
#else
#include "dep_else.h"
#endif
#ifdef GUARD
#include "dep_ifdef.h"
#elif 0
#include "dep_elif.h"
#endif
#if 0
#include "dep_dead_if.h"
#endif
#ifdef DEAD
#include "dep_dead_ifdef.h"
#endif
int use( void ) { return dep_quoted_helper(); }
CPP

cat > "$WORK/main.c" <<'C'
#include "dep_quoted.h"
#include <dep_angle.h>
#import "dep_imported.h"
int c_use( void ){ return dep_quoted_helper(); }
C

cat > "$WORK/thing.m" <<'M'
#import "dep_imported.h"
#import <dep_imported_angle.h>
@interface Thing : NSObject
@end
M

deps() { "$BIN" "$1" --deps 2>/dev/null; }

# ── the captured edge set ───────────────────────────────────────────────────────────────────────────
OUT="$TMP/deps.xml"
deps "$WORK" > "$OUT"

# arm 1 + 2 + 3 + 5 + 6 + 7: the exact thirteen rows, in the exact spelling.
want='dep_quoted.h
dep_angle.h
dep_imported.h
dep_imported_angle.h
HEADER_MACRO_PATH
dep_if.h
dep_else.h
dep_ifdef.h
dep_dead_ifdef.h
dep_quoted.h
dep_angle.h
dep_imported.h
dep_imported.h
dep_imported_angle.h'
got=$(grep -o '<inc t="[^"]*"' "$OUT" | sed 's/<inc t="//; s/"$//')
if [ "$got" = "$want" ]; then
    ok "15 Include rows, exact set and order (quote/angle, three #import spellings, macro, guarded)"
else
    no "Include rows differ from the expected 15"
    printf '    expected:\n%s\n' "$(printf '%s\n' "$want" | sed 's/^/      /')"
    printf '    got:\n%s\n'      "$(printf '%s\n' "$got"   | sed 's/^/      /')"
fi

# arm 7 on its own, named: the dead arms must be ABSENT, not merely balanced by the total above.
for dead in dep_dead_if.h dep_elif.h; do
    if grep -q "<inc t=\"$dead\"" "$OUT"; then
        no "dead arm leaked an edge: $dead (dropPreprocDead no longer covers the includes window)"
    else
        ok "dead arm dropped: $dead"
    fi
done

# arm 4 on its own, named: the non-import preproc_calls. These are in the SAME query pattern as #import,
# and the fixture deliberately carries a `#pragma once` and an `#error` so the arm is not vacuous.
grep -q 't="once"' "$OUT" && no "#pragma once became a dependency" || ok "#pragma once is not a dependency"
grep -q 't="not an include at all"' "$OUT" && no "#error became a dependency" || ok "#error is not a dependency"

# ── arm 11: the extension families the C-family grammar table covers but a normal corpus does not ──────
# `.cu`/`.cuh` ride the VENDORED tree-sitter-cuda grammar on queries/cpp/tags.scm, and `.metal` rides cpp.
# A query that fails to COMPILE against a grammar does not error — every file of that language discloses
# extract-partial instead — so this arm is not redundant with the three above: it is the only place the
# cuda grammar's spelling of these patterns is exercised at all.
CT="$TMP/cuda"; mkdir -p "$CT"
printf 'int cu_helper();\n'   > "$CT/cu_helper.cuh"
printf 'int metal_helper();\n' > "$CT/metal_helper.h"
cat > "$CT/k.cu" <<'CU'
#include "cu_helper.cuh"
#include <vector>
#import "cu_helper.cuh"
#if 1
#include "cu_helper.cuh"
#endif
__global__ void k() {}
CU
printf '#include "metal_helper.h"\n#import "metal_helper.h"\n' > "$CT/s.metal"
"$BIN" "$CT" --deps --no-cache > "$TMP/cu.xml" 2> "$TMP/cu.err"
CU_EDGES=$(grep -o '<inc ' "$TMP/cu.xml" | wc -l)
if [ "$CU_EDGES" -eq 6 ] && ! grep -q 'extract-partial' "$TMP/cu.err"; then
    ok "cuda + metal: 6 edges, no extract-partial (the patterns compile against tree-sitter-cuda too)"
else
    no "cuda + metal: got ${CU_EDGES:-0} edges (want 6), stderr=[$(head -c 160 "$TMP/cu.err")]"
fi

# arm 3 on its own: #import under all THREE grammars. The C and C++ grammars have no #import rule — it
# parses as a generic preproc_call and is gated on the directive TEXT in C++ — while the ObjC grammar has
# an #import rule and routes it through the preproc_include pattern instead. Three rows, three routes.
# The quoted form with its closing delimiter, so `dep_imported_angle.h` cannot ride in on the prefix.
if [ "$(grep -o 't="dep_imported\.h"' "$OUT" | wc -l)" -eq 3 ]; then
    ok "#import captured under all three grammars (c/cpp preproc_call + text gate, objc preproc_include)"
else
    no "#import rows missing for one of the three grammars (got $(grep -o 't="dep_imported\.h"' "$OUT" | wc -l), want 3)"
fi

# ── arm 1: the vocabulary is LIVE, and the extractors it replaces are GONE ─────────────────────────────
# There is no query-override seam (the tags queries are compiled into the binary), so "the capture is what
# produces the edge" is pinned two ways instead: the @import.path pattern must MATCH on a real parse —
# which is only true if it survived compilation into the embedded query — and the two extractor functions
# it replaced must name nothing in src/ any more (the issue's acceptance: "the per-language extractors
# removed as each language moves over").
MHITS=$("$BIN" "$WORK" --no-cache '--match=(preproc_include path: (_) @import.path)' 2>/dev/null \
        | grep -o 'hits="[0-9]*"' | head -1 | grep -o '[0-9]*')
if [ -n "$MHITS" ] && [ "$MHITS" -ge 3 ]; then
    ok "@import.path matches $MHITS sites on a real parse — the vocabulary is compiled in and live"
else
    no "@import.path matched ${MHITS:-0} sites; expected >= 3 (the pattern is not reaching the tags query)"
fi
for gone in preprocIncludeTarget preprocImportTarget; do
    if grep -rq "$gone" "$ROOT/src"; then
        no "extractor $gone still exists in src/ — it should have been removed with this language"
    else
        ok "extractor $gone removed from src/"
    fi
done

# ── arm 8: the use-site half ─────────────────────────────────────────────────────────────────────────
# importName() strips the extension and the directory, so the selector is the HEADER'S importable name
# (`dep_quoted`), not the symbol it declares — the same selector `--uses=geometry` uses for geometry.h.
USES="$("$BIN" "$WORK" --uses=dep_quoted --no-cache 2>/dev/null)"
if printf '%s' "$USES" | grep -q 'role="import"'; then
    ok "--uses reports the include site with role=\"import\" (the ABS-3 half survived the move)"
else
    no "--uses lost the import-role use-site ref for an included header"
fi

# ── arm 9: cache round-trip ───────────────────────────────────────────────────────────────────────────
CACHE="$TMP/c.bin"
"$BIN" "$WORK" --cache="$CACHE" --no-cache >/dev/null 2>&1   # populate
"$BIN" "$WORK" --cache="$CACHE"            > "$TMP/cold.xml" 2>/dev/null
"$BIN" "$WORK" --cache="$CACHE"            > "$TMP/warm.xml" 2>/dev/null
"$BIN" "$WORK" --no-cache                  > "$TMP/nocache.xml" 2>/dev/null
cmp -s "$TMP/cold.xml" "$TMP/warm.xml" \
    && ok "warm == cold (the Include round-trip, incl. isAngle, is byte-identical)" \
    || no "warm != cold — the Include cache round-trip changed"
cmp -s "$TMP/cold.xml" "$TMP/nocache.xml" \
    && ok "cache path == no-cache path" \
    || no "cache vs no-cache diverged"

# ── arm 10: determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" "$WORK" --no-cache > "$TMP/d1.xml" 2>/dev/null
"$BIN" "$WORK" --no-cache > "$TMP/d2.xml" 2>/dev/null
cmp -s "$TMP/d1.xml" "$TMP/d2.xml" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic output"

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/cold.xml" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }