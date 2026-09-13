#!/usr/bin/env bash
# runhintcheck.sh — gate for the run= runner hint on test rows.
#
# THE GAP: --affected / --situ / --test-gate NAME tests and cannot RUN them. They emit bare `.cpp` harness
# paths while this repo's runners are `test/*.sh`; --test-gate goes further and EXITS 4 on the obligation.
# So the one verb family whose whole job is "here is what you must run before you ship" produced an
# obligation that could not be discharged from its own output.
#
# THE CONTRACT, and the half that matters most: run= appears ONLY when the mapping is REAL, and its
# ABSENCE means "not derivable" — never a guess. A fallback to the repo's suite runner would be a
# plausible-looking command that may not execute the named harness at all: the §P0 fabricated-confidence
# shape, in command form, on a row an agent is being told to act on. The negative arms below are therefore
# as load-bearing as the positive ones.
#
# The two REAL evidence kinds (testmap.h TestRunnerIndex):
#   STEM     a runner whose basename stem equals the harness's        (samename.cpp  <-> samename.sh)
#   MENTION  a runner whose TEXT names the harness's basename         (mything_harness.cpp <- mythingcheck.sh)
# Mention is the shape that actually dominates: in THIS repo the four *_harness.cpp files are each named by
# exactly one *check.sh and NONE of them stem-matches.
#
# Usage:  bash test/runhintcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/runhintcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "runhintcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int leaf() { return 1; }\nint mid()  { return leaf(); }\n' > "$R/src/core.cpp"
# (a) MENTION: the gate script names the harness file; the stems do NOT match.
printf 'void drive_mid() { mid(); }\n'                            > "$R/test/mything_harness.cpp"
printf '#!/usr/bin/env bash\n# drives test/mything_harness.cpp\necho hi\n' > "$R/test/mythingcheck.sh"
# (b) STEM: same basename stem, no mention anywhere.
printf 'void drive_leaf() { leaf(); }\n'                          > "$R/test/samename.cpp"
printf '#!/usr/bin/env bash\necho hi\n'                           > "$R/test/samename.sh"
# (c) NEITHER: no script names it and no stem matches → run= must be ABSENT.
printf 'void drive_orphan() { leaf(); }\n'                        > "$R/test/orphan_unit.cpp"

run(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
# the run= value carried by the row whose p= ends in $1 ("" when the row has no run=)
# F1 (H2H-Graft 2026-09-07): a row may carry seed_kind=/changed=/partner=/hops= between p= and run=.
runof(){ printf '%s' "$2" | grep -oE "<[a-z]+ p=\"[^\"]*$1\"( (seed_kind|changed|partner|hops)=\"[^\"]*\")*( run=\"[^\"]*\")?/>" | head -1 | grep -oE 'run="[^"]*"' | sed 's/run="//;s/"//'; }

A="$( run --affected=src/core.cpp )"

# ── 1) MENTION evidence: the *check.sh that names the harness becomes its run= ────────────────────────
[ "$( runof 'mything_harness.cpp' "$A" )" = "bash test/mythingcheck.sh" ] \
    && ok "--affected: mention-derived run= on mything_harness.cpp" \
    || no "--affected mention hint wrong: '$( runof 'mything_harness.cpp' "$A" )'"

# ── 2) STEM evidence: foo.cpp <-> foo.sh ─────────────────────────────────────────────────────────────
[ "$( runof 'samename.cpp' "$A" )" = "bash test/samename.sh" ] \
    && ok "--affected: stem-derived run= on samename.cpp" \
    || no "--affected stem hint wrong: '$( runof 'samename.cpp' "$A" )'"

# ── 2b) run= is spelled RELATIVE TO root=, exactly as the p= beside it is ────────────────────────────
# A hint whose path spelling disagreed with the p= beside it would be a second vocabulary for "where this
# file is" — the §P8 defect, in the one attribute meant to be pasted into a shell.
# A3 (2026-09-13, PLAN_OUTPUT_ROUTING_LOOP §1.5): this arm used to pin run= to "the root spelling the caller
# passed", which made an ABSOLUTE scan print the whole checkout prefix inside the command — one absolute
# path per ROW against a per-DOCUMENT fact (test/rootrelemitcheck.sh ARM 9 is the emission contract). run=
# is now root-relative under BOTH spellings, so the two runs agree byte-for-byte on the command and the
# document is independent of where the tree is checked out.
REL="$( cd "$R" && perl -e 'alarm 20; exec @ARGV' "$BIN" . --affected=src/core.cpp --no-cache 2>/dev/null )"
[ "$( runof 'mything_harness.cpp' "$REL" )" = "bash test/mythingcheck.sh" ] \
    && ok "run= is root-relative under a relative scan (run=\"bash test/mythingcheck.sh\")" \
    || no "run= root spelling wrong under a relative scan: '$( runof 'mything_harness.cpp' "$REL" )'"
[ "$( runof 'mything_harness.cpp' "$REL" )" = "$( runof 'mything_harness.cpp' "$A" )" ] \
    && ok "run= is the SAME command under an absolute and a relative root — no checkout prefix rides the row" \
    || no "run= differs between an absolute scan ('$( runof 'mything_harness.cpp' "$A" )') and a relative one ('$( runof 'mything_harness.cpp' "$REL" )')"
# …and it must still RUN from the root the document declares, which is the whole point of relativizing it.
# Review of #219: an EMPTY run= makes `eval ""` succeed, so this arm passed on the one outcome it exists to
# forbid — a row with no command at all. The emptiness is checked BEFORE anything is executed.
RUNCMD="$( runof 'mything_harness.cpp' "$A" )"
if [ -z "$RUNCMD" ]
then
    no "the row carries NO run= at all — there is no command to execute, and an empty eval would pass"
elif ( cd "$R" && eval "$RUNCMD" >/dev/null 2>&1 )
then
    ok "the printed run= executes from the declared root ($RUNCMD)"
else
    no "the printed run= does not execute from the declared root ($RUNCMD) — a relative command that cannot be pasted is worse than an absolute one"
fi

# ── 2c) EVERY spelling of one root names the SAME command ────────────────────────────────────────────
# Review of #219: `ripwire ./sub` stored "./sub/test/x.sh" and the relativizer stripped only the leading
# "./", so the document said run="bash sub/test/x.sh" — wrong from the root it declares. The root is one
# place, however the caller spells it, so the command must be one string.
PARENT="$( dirname "$R" )"; LEAF="$( basename "$R" )"
for spell in "$LEAF" "./$LEAF" "$LEAF/"; do
    GOT="$( cd "$PARENT" && perl -e 'alarm 20; exec @ARGV' "$BIN" "$spell" --affected=src/core.cpp --no-cache 2>/dev/null )"
    GOTRUN="$( runof 'mything_harness.cpp' "$GOT" )"
    if [ "$GOTRUN" = "bash test/mythingcheck.sh" ]
    then
        ok "root spelled '$spell' says run=\"$GOTRUN\""
    else
        no "root spelled '$spell' says run=\"$GOTRUN\", not the root-relative \"bash test/mythingcheck.sh\""
    fi
    if [ -n "$GOTRUN" ] && ( cd "$R" && eval "$GOTRUN" >/dev/null 2>&1 )
    then
        ok "the command printed under '$spell' executes from that root"
    else
        no "the command printed under '$spell' does not execute from that root"
    fi
done

# ── 2d) MULTI-ROOT: the absolute command stays, and no legend claims otherwise ────────────────────────
# There is no single root for a command to be relative to, so the spelling keeps the disk path — and the
# sentence that says "relative to root=" must not be spliced into a document that declares no root=.
MR2="$TMP/mr2"; rm -rf "$MR2"; mkdir -p "$MR2/src"
printf 'int other() { return 1; }\n' > "$MR2/src/other.cpp"
MRDOC="$( perl -e 'alarm 40; exec @ARGV' "$BIN" "$R" "$MR2" --affected=src/core.cpp --no-cache 2>/dev/null )"
MRRUN2="$( runof 'mything_harness.cpp' "$MRDOC" )"
if [ -z "$MRDOC" ]; then
    printf '  SKIP  2d the multi-root run emitted nothing on this fixture\n'
elif [ -z "$MRRUN2" ]; then
    printf '  SKIP  2d the multi-root run derived no run= for mything_harness.cpp\n'
else
    case "${MRRUN2##* }" in
        /*) ok "2d multi-root keeps the absolute command ($MRRUN2) — there is no single root to be relative to" ;;
        *)  no "2d multi-root printed a relative command ($MRRUN2) in a document with no single root" ;;
    esac
    case "$MRDOC" in
        *"relative to root="*) no "2d multi-root splices \"relative to root=\" into a document that declares no root=" ;;
        *)                     ok "2d multi-root does not claim a relativity it does not have" ;;
    esac
fi

# ── 3) NO evidence → NO run=. The half that keeps the attribute trustworthy. ──────────────────────────
case "$A" in
    *'orphan_unit.cpp" run='*) no "--affected invented a run= for orphan_unit.cpp (no derivable runner)" ;;
    *'orphan_unit.cpp'*)       ok "--affected: orphan_unit.cpp carries NO run= (absent = not derivable, never a guess)" ;;
    *)                         no "--affected did not emit orphan_unit.cpp at all — fixture broken" ;;
esac

# ── 4) the same hint on --test-gate, the verb that EXITS 4 on the obligation ──────────────────────────
G="$( run --test-gate=src/core.cpp )"
[ "$( runof 'mything_harness.cpp' "$G" )" = "bash test/mythingcheck.sh" ] \
    && ok "--test-gate <t> rows carry the same run= (the exit-4 obligation is now dischargeable)" \
    || no "--test-gate run= missing/wrong: '$( runof 'mything_harness.cpp' "$G" )'"

# ── 4b) …and in its --json sibling, under the same key ───────────────────────────────────────────────
GJ="$( run --test-gate=src/core.cpp --json )"
case "$GJ" in *'"run":"bash test/mythingcheck.sh"'*) ok "--test-gate --json tests_to_run rows carry \"run\"" ;;
              *) no "--test-gate --json has no run key: $GJ" ;; esac

# ── 4c) …and on --situ's text report ─────────────────────────────────────────────────────────────────
S="$( run --situ=src/core.cpp )"
case "$S" in *'(run: bash test/mythingcheck.sh)'*) ok "--situ tests-to-run lines carry the run command" ;;
             *) no "--situ tests-to-run lines have no run command" ;; esac

# ── 5) determinism + G4 ──────────────────────────────────────────────────────────────────────────────
[ "$( run --affected=src/core.cpp )" = "$A" ] \
    && ok "run= deterministic (byte-identical run-to-run)" || no "run= non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "--affected with run= xml well-formed"; else no "--affected with run= xml malformed"; fi
    if printf '%s' "$G" | xmllint --noout - 2>/dev/null; then ok "--test-gate with run= xml well-formed"; else no "--test-gate with run= xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 6) the REAL repo pair §P11.4 asks for, found by inspection: ──────────────────────────────────────
#      test/cloneband_harness.cpp is named by test/clonebandcheck.sh and by nothing else. Stems differ, so
#      this is the MENTION path on a corpus with 255 candidate runner scripts — where a wrong tie-break or
#      an over-eager match would show up immediately.
RA="$( perl -e 'alarm 90; exec @ARGV' "$BIN" "$ROOT" --affected=src/graph.h 2>/dev/null )"
[ "$( runof 'cloneband_harness.cpp' "$RA" )" = "bash test/clonebandcheck.sh" ] \
    && ok "repo: cloneband_harness.cpp -> run=\"bash test/clonebandcheck.sh\"" \
    || no "repo: cloneband_harness.cpp run= wrong: '$( runof 'cloneband_harness.cpp' "$RA" )'"
[ "$( runof 'connectcore_harness.cpp' "$RA" )" = "bash test/connectcorecheck.sh" ] \
    && ok "repo: connectcore_harness.cpp -> run=\"bash test/connectcorecheck.sh\"" \
    || no "repo: connectcore_harness.cpp run= wrong: '$( runof 'connectcore_harness.cpp' "$RA" )'"

# ── 7) §A9.5 — the TWO verbs that named the same test files and left the obligation undischargeable ────
#      --pr-context (the review lens) and --pack-task (the one-call bundle) derived their <test> rows from
#      the SAME transitive-callers walk --affected uses, and emitted bare paths. A reviewer told "run these"
#      by a bundle that also carries bodies, callers and notes should not have to leave the bundle to find
#      the command. Both now read the same TestRunnerIndex; absence still means "not derivable".
P="$( run --pack-task="drive mid through core" )"
[ "$( runof 'mything_harness.cpp' "$P" )" = "bash test/mythingcheck.sh" ] \
    && ok "--pack-task <test> rows carry run= (same index as affected/situ/test-gate/exercises)" \
    || no "--pack-task run= missing/wrong: '$( runof 'mything_harness.cpp' "$P" )'"

PJ="$( run --pack-task="drive mid through core" --json )"
case "$PJ" in *'"run":"bash test/mythingcheck.sh"'*) ok "--pack-task --json tests_to_run rows carry \"run\"" ;;
              *) no "--pack-task --json has no run key in tests_to_run" ;; esac

# --pr-context needs real git history, so the fixture becomes a repo HERE — after every arm above has run
# against the non-git tree, so none of their outputs move.
if command -v git >/dev/null 2>&1; then
    ( cd "$R" && git init -q . && git config user.email g@e && git config user.name g \
        && git add -A && git commit -qm base ) >/dev/null 2>&1
    printf 'int extra() { return mid(); }\n' >> "$R/src/core.cpp"
    PR="$( run --pr-context )"
    [ "$( runof 'mything_harness.cpp' "$PR" )" = "bash test/mythingcheck.sh" ] \
        && ok "--pr-context <test> rows carry run= (the review lens's obligation is dischargeable)" \
        || no "--pr-context run= missing/wrong: '$( runof 'mything_harness.cpp' "$PR" )'"
    case "$PR" in
        *'orphan_unit.cpp" run='*) no "--pr-context invented a run= for orphan_unit.cpp (no derivable runner)" ;;
        *)                         ok "--pr-context: no fabricated run= (absent stays absent when not derivable)" ;;
    esac
    if command -v xmllint >/dev/null 2>&1; then
        if printf '%s' "$PR" | xmllint --noout - 2>/dev/null; then ok "--pr-context with run= xml well-formed"; else no "--pr-context with run= xml malformed"; fi
    fi
else
    printf '  SKIP  --pr-context run= arms (no git)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
