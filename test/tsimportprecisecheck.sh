#!/usr/bin/env bash
# tsimportprecisecheck.sh — LEVER-B B2 gate: path-precise TS/JS import resolution.
#
# The precise SameInclude tier now has a TS/JS Step-A (resolve.h::resolveTsImport): a RELATIVE specifier
# `import {Z} from './x'` / `'../a/b'` resolves to the ONE repo file it names by PATH relative-to-includer,
# trying a FIXED extension list (.ts/.tsx/.js/.jsx/…) then index files, on a UNIQUE hit — else it degrades.
# A BARE specifier (`from 'react'` — node_modules/external) is left UNRESOLVED (the angle-include analogue).
# Same "unique-or-degrade" discipline as the C-family quote-include tier.
#
# Fixture test/tsimportprecisefix — the soundness cases:
#   caller.ts        import {helper} from './x'   → helper() binds x.ts::helper       (NOT the decoy other/x.ts)
#                    import {widget} from './a/b'  → widget() binds a/b.ts::widget      (NOT the decoy other/b.ts)
#                    import {idxfn} from './idx'   → idxfn() binds idx/index.ts::idxfn  (index-file resolution)
#                    import React from 'react'     → createElement() UNRESOLVED         (bare/external, no false edge)
#   other/caller2.ts import {helper} from './x'    → helper() binds other/x.ts::helper  (path, not basename)
#
# Also asserts B0 clean-specifier capture (--deps shows `./x`, not the clause), MONOTONICITY, determinism,
# warm==cold, and well-formed XML.
#
# Usage:  test/tsimportprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/tsimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tsimportprecisefix"
. "$ROOT/test/lib/headbinlib.sh"                       # shared sha-keyed cache of the HEAD comparison binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "tsimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

callee_binds(){  # $1 caller  $2 expected-path-substr  $3 must-NOT-contain-substr (decoy)
  "$BIN" "$FIX" --callees="$1" --no-cache >"$TMP/$1.out" 2>/dev/null
  if grep -q "$2" "$TMP/$1.out" && { [ -z "${3:-}" ] || ! grep -q "$3" "$TMP/$1.out"; }; then
    ok "$1 → $2 (unique, precise${3:+; not $3})"
  else
    no "$1 did not bind $2 alone"; cat "$TMP/$1.out"
  fi
}
callee_count(){  # $1 caller  $2 expected count=
  local c; c="$( grep -oE 'count="[0-9]+"' "$TMP/$1.out" | head -1 )"
  if [ "$c" = "count=\"$2\"" ]; then ok "$1 has $c callee(s)"; else no "$1 callee count wrong (got $c, want count=\"$2\")"; fi
}

# ── B2 path-precise resolution ────────────────────────────────────────────────────────────────────
callee_binds useHelper      'x.ts:'         'other/x.ts'  ; callee_count useHelper 1
callee_binds useWidget      'a/b.ts:'       'other/b.ts'  ; callee_count useWidget 1
callee_binds useIdx         'idx/index.ts:' ''            ; callee_count useIdx 1
callee_binds useOtherHelper 'other/x.ts:'   ''            ; callee_count useOtherHelper 1

# bare `from 'react'` → NO false edge (createElement is not an in-repo def).
"$BIN" "$FIX" --callees=useReact --no-cache >"$TMP/useReact.out" 2>/dev/null
callee_count useReact 0

# ── B0 clean specifier: --deps carries the quoted-path stripped to `./x`, not the whole clause ────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="./x"' "$TMP/deps.out" \
  && ok 'B0: import {helper} from "./x" → clean specifier t="./x"' \
  || { no 'B0: ./x specifier not captured cleanly'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }
grep -q '<inc t="react"' "$TMP/deps.out" \
  && ok 'B0: bare `react` captured (and left external at resolve time)' \
  || no 'B0: bare react specifier missing'

# ── RUNTIME-EXTENSION specifiers: `./x.js` names x.ts (node16/nodenext), `.mjs`→`.mts`, `.cjs`→`.cts` ─────────
# One importer file per case, so each row's instab= answers for exactly one specifier: a resolved import is an
# efferent edge (instab="1.00"), an unresolved one is not (instab="0.00"). Built under $TMP so the committed
# fixture's own arms above keep their counts. The two guards (dual, idx) hold on every binary: a tree carrying
# BOTH dual.js and dual.ts stays unresolved (unique-or-degrade), and `./lib.js` never lands on lib/index.ts —
# TypeScript resolves neither.
RX="$TMP/runtimeext"
mkdir -p "$RX/other" "$RX/lib"
printf 'export function helper() { return 1; }\n'  >"$RX/x.ts"
printf 'export function helper() { return 99; }\n' >"$RX/other/x.ts"
printf 'export function widget() { return 2; }\n'  >"$RX/w.tsx"
printf 'export function modfn() { return 3; }\n'   >"$RX/m.mts"
printf 'export function cjsfn() { return 4; }\n'   >"$RX/c.cts"
printf 'export function dual() { return 5; }\n'    >"$RX/dual.ts"
printf 'export function dual() { return 6; }\n'    >"$RX/dual.js"
printf 'export function libfn() { return 7; }\n'   >"$RX/lib/index.ts"
printf "import { helper } from './x.js';\nexport function useJs() { return helper(); }\n"     >"$RX/usejs.ts"
printf "import { widget } from './w.js';\nexport function useTsx() { return widget(); }\n"    >"$RX/usetsx.ts"
printf "import { modfn } from './m.mjs';\nexport function useMjs() { return modfn(); }\n"     >"$RX/usemjs.ts"
printf "import { cjsfn } from './c.cjs';\nexport function useCjs() { return cjsfn(); }\n"     >"$RX/usecjs.ts"
printf "import { dual } from './dual.js';\nexport function useDual() { return dual(); }\n"    >"$RX/usedual.ts"
printf "import { libfn } from './lib.js';\nexport function useLib() { return libfn(); }\n"    >"$RX/uselib.ts"
"$BIN" "$RX" --deps --no-cache >"$TMP/rx.deps" 2>/dev/null
rx_instab(){ grep -oE "<f p=\"$1\" [^>]*instab=\"[0-9.]+\"" "$TMP/rx.deps" | grep -oE 'instab="[0-9.]+"' | head -1; }
rx_expect(){  # $1 importer  $2 want instab  $3 what
  local got; got="$( rx_instab "$1" )"
  if [ "$got" = "instab=\"$2\"" ]; then ok "runtime-ext: $3 ($1 $got)"; else no "runtime-ext: $3 — $1 has '${got:-no row}', want instab=\"$2\""; fi
}
rx_expect usejs.ts   1.00 "./x.js resolves to x.ts"
rx_expect usetsx.ts  1.00 "./w.js resolves to w.tsx"
rx_expect usemjs.ts  1.00 "./m.mjs resolves to m.mts"
rx_expect usecjs.ts  1.00 "./c.cjs resolves to c.cts"
rx_expect usedual.ts 0.00 "./dual.js with BOTH dual.js and dual.ts stays unresolved"
rx_expect uselib.ts  0.00 "./lib.js does not resolve to lib/index.ts"
grep -qE '<f p="other/x.ts" afferent="[1-9]' "$TMP/rx.deps" \
  && no "runtime-ext: ./x.js bound the decoy other/x.ts" \
  || ok "runtime-ext: the decoy other/x.ts gains no importer"

# ── the fixture resolves everything → ambiguous=0 ─────────────────────────────────────────────────
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 )"
if [ "$famb" = "ambiguous=0" ]; then ok "fixture $famb"; else no "fixture $famb (expected 0)"; fi

# ── determinism + warm==cold ──────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (resolver order-stable through cache)"; else no "warm != cold"; fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture ────────────────────────────
monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    # pre-change binary from the shared sha-keyed cache (test/lib/headbinlib.sh): built at most once per
    # HEAD sha, then reused by all four monotonicity gates and every rerun until HEAD moves.
    local OLDBIN
    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" \
        || { headbin_refusal $? "monotonicity"; return; }

    local ao an
    ao="$( "$OLDBIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    an="$( "$BIN"    "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    if [ -n "$ao" ] && [ -n "$an" ] && [ "$an" -le "$ao" ]; then
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (TS narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

bash "$ROOT/test/lib/jsimportalias.sh" "$BIN" || fail=1
bash "$ROOT/test/lib/jsimportfacts.sh" "$BIN" || fail=1
bash "$ROOT/test/lib/jsdefaultimport.sh" "$BIN" || fail=1

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
