#!/usr/bin/env bash
# pyaliasincludecheck.sh — kParserVer 116 gate: a Python `import a.b as c` records the Include target `a.b`.
#
# tree-sitter-python gives import_statement a name:(dotted_name|aliased_import) field. For an aliased import
# that field is the WHOLE aliased_import node, so the capture read its span — `a.b as c` — as the module
# specifier. No resolver can find a module spelled that way, so every aliased plain import contributed no
# precise-include edge: --deps showed <inc t="pkg.mod as pm"/> with no edge behind it, and Rule 3 (the
# file-level include narrow) lost the file. `from a.b import x as y` reads module_name: and never had it.
#
# Fixture test/pyaliasincludefix:
#   pkg/mod.py, other/mod.py   both define pyai_helper — a bare call to it is AMBIGUOUS without an include
#   aliased.py                 `import pkg.mod as pm` + a bare pyai_helper() call  (the defect's shape)
#                              `import os.path as osp`  — external: recorded clean, resolves to nothing
#   plain.py                   `import pkg.mod`          + the same call              (control: always worked)
#   fromimp.py                 `from pkg.mod import pyai_helper as h`                (control: other branch)
#
# Usage:  test/pyaliasincludecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/pyaliasincludecheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pyaliasincludefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/pyaliasincludefix — fixture missing"; exit 2; }
echo "pyaliasincludecheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || { no "--deps exited $rc"; exit 1; }
grep -q '<deps ' "$TMP/deps" || { no "--deps printed no <deps> element — the query did not run"; exit 1; }
ROW="$( grep -oE '<f p="aliased.py"[^>]*>(<inc [^>]*>)*' "$TMP/deps" )"

# ── 1. CAPTURE: the Include target is the module, never the aliased clause ─────────────────────────────
printf '%s' "$ROW" | grep -qF '<inc t="pkg.mod"/>' \
    && ok 'capture: `import pkg.mod as pm` records <inc t="pkg.mod"/>' \
    || no "capture: aliased.py has no <inc t=\"pkg.mod\"/>: ${ROW:-<no aliased.py row>}"
printf '%s' "$ROW" | grep -qF '<inc t="os.path"/>' \
    && ok 'capture: external `import os.path as osp` records <inc t="os.path"/>' \
    || no "capture: aliased.py has no <inc t=\"os.path\"/>: ${ROW:-<no aliased.py row>}"
if grep -qE '<inc t="[^"]* as [^"]*"/>' "$TMP/deps"; then
    no "capture: an aliased clause leaked into a target: $( grep -oE '<inc t="[^"]* as [^"]*"/>' "$TMP/deps" | tr '\n' ' ' )"
else
    ok 'capture: no <inc t="… as …"/> row anywhere'
fi

# ── 2. RESOLUTION: the aliased import is an edge, counted with the two controls ───────────────────────
# afferent counts edge occurrences: plain.py + fromimp.py (controls) + aliased.py (the fix) = exactly 3.
grep -q '<f p="pkg/mod.py" afferent="3"/>' "$TMP/deps" \
    && ok 'resolve: pkg/mod.py afferent="3" (plain + from-import + aliased)' \
    || no "resolve: pkg/mod.py afferent wrong: $( grep -oE '<f p="pkg/mod.py" afferent="[0-9]*"/>' "$TMP/deps" )"
# includes= counts directive RECORDS (2 either way); transitive= counts the file's resolved cone: itself +
# pkg/mod.py = 2 (os.path is external). It read 1 while the aliased target resolved to nothing.
printf '%s' "$ROW" | grep -q 'transitive="2"' \
    && ok 'resolve: aliased.py transitive="2" (itself + pkg/mod.py; os.path is external)' \
    || no "resolve: aliased.py cone wrong: ${ROW:-<no aliased.py row>}"

# ── 3. RULE 3: the bare call in aliased.py binds through the include, not declined as ambiguous ───────
"$BIN" "$FIX" --callers=pkg/mod.py:pyai_helper --no-cache --legend=compact >"$TMP/callers" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q '<callers ' "$TMP/callers" || { no "--callers did not run (rc=$rc)"; exit 1; }
grep -q 'n="pyai_caller_aliased" p="aliased.py:5"' "$TMP/callers" \
    && ok 'rule 3: aliased.py:pyai_caller_aliased calls pkg/mod.py:pyai_helper' \
    || no "rule 3: pyai_caller_aliased is not a caller of pkg/mod.py:pyai_helper: $( grep -oE '<callers [^>]*>.*' "$TMP/callers" )"
grep -q 'n="pyai_caller_plain" p="plain.py:4"' "$TMP/callers" \
    && ok 'rule 3 control: plain.py:pyai_caller_plain calls pkg/mod.py:pyai_helper' \
    || no "rule 3 control: pyai_caller_plain lost its edge: $( grep -oE '<callers [^>]*>.*' "$TMP/callers" )"
"$BIN" "$FIX" --callers=other/mod.py:pyai_helper --no-cache --legend=compact >"$TMP/other" 2>/dev/null
grep -q '<callers [^>]* count="0"' "$TMP/other" \
    && ok 'rule 3 negative: other/mod.py:pyai_helper has no caller' \
    || no "rule 3 negative: other/mod.py:pyai_helper gained a caller: $( grep -oE '<callers [^>]*>.*' "$TMP/other" )"

if [ "$fail" -eq 0 ]; then echo "pyaliasincludecheck: ALL PASS"; else echo "pyaliasincludecheck: FAILED"; fi
exit "$fail"
