#!/usr/bin/env bash
# qualitykindscheck.sh — gate for the THREE GitClear-2026-backed --quality-delta kinds (§D#4 / §E-17):
#   error-masking            — a NEW error-masking construct (empty catch / bare-pass except / swallowed .catch)
#   short-horizon-churn      — a symbol whose FILE had ≥2 commits in the last 14 days (from git commit
#                              TIMESTAMPS vs HEAD's epoch, NOT wall-clock) that this diff rewrites again
#   new-clone-of-reused-helper — a NEW clone of an existing helper with fan-in ≥ 3 (reuse-connectivity decline)
#
# Each kind must fire ONLY on a regression vs baseline (never on pre-existing debt) and preserve the
# quality-delta exit-2 contract. Uses git-init fixtures + the auto-vs-HEAD baseline path (same idiom as
# qualitycheck.sh §7). Operates entirely in temp dirs; the repo is never touched.
#
# Usage:  RIPWIRE_BIN=build_w3/ripwire bash test/qualitykindscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolutize BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualitykindscheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qualitykindscheck: BIN=$BIN  (temp corpora)"

# ── 1) ERROR-MASKING ────────────────────────────────────────────────────────────────────────────────────
#   Baseline (committed): handle() catches AND logs; a SEPARATE pre-existing empty catch lives in legacy() —
#   committed too, so it is pre-existing debt. Working-tree edit adds an EMPTY catch to handle() (the
#   regression) and does NOT touch legacy(). Assert: handle flagged, legacy NOT flagged, exit 2.
EM="$WORK/em"; mkdir -p "$EM/src"
( cd "$EM" && git init -q && git config user.email t@t && git config user.name t )
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) { log_it(); } }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
( cd "$EM" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dem(){  ( cd "$EM" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecem(){ ( cd "$EM" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 1a) clean tree (== HEAD) → zero regressions, exit 0 (the pre-existing empty catch in legacy() is NOT flagged)
[ "$( ecem )" = 0 ] && dem | grep -q 'regressions="0"' \
    && ok "error-masking: clean tree → exit 0 (pre-existing empty catch in legacy() NOT flagged)" \
    || { no "error-masking: clean tree should be clean (exit $( ecem ))"; dem | tr '>' '\n' | grep '<r '; }

# 1b) add an EMPTY catch to handle() (uncommitted) → regression fires, exit 2
printf 'void log_it(){}\nvoid handle(){ try { risky(); } catch( ... ) {} }\nvoid legacy(){ try { risky(); } catch( ... ) {} }\nvoid risky(){}\nvoid drive(){ handle(); legacy(); }\n' > "$EM/src/a.cpp"
OEM="$( dem )"
if [ "$( ecem )" = 2 ]; then ok "error-masking: new empty catch → exit 2"; else no "error-masking: new empty catch should exit 2 (got $( ecem ))"; fi
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking: handle() flagged (empty catch added)" || { no "error-masking: handle() not flagged"; printf '%s\n' "$OEM" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OEM" | grep -q 'kind="error-masking" sym="legacy"' \
    && no "error-masking: legacy() wrongly flagged (its empty catch is pre-existing, untouched)" \
    || ok "error-masking: pre-existing empty catch in untouched legacy() NOT flagged (contract)"

# 1c) determinism + xml
if [ "$OEM" = "$( dem )" ]; then ok "error-masking: delta byte-identical run-to-run"; else no "error-masking: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OEM" | xmllint --noout - 2>/dev/null; then ok "error-masking: xml well-formed"; else no "error-masking: xml malformed"; fi
fi

# 1d) Python bare/pass except — a second-language sanity check on the rule table.
PY="$WORK/empy"; mkdir -p "$PY"
( cd "$PY" && git init -q && git config user.email t@t && git config user.name t )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        log_it()\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
( cd "$PY" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
printf 'def handle():\n    try:\n        risky()\n    except Exception:\n        pass\n\ndef risky():\n    pass\n\ndef log_it():\n    pass\n' > "$PY/a.py"
OPY="$( cd "$PY" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OPY" | grep -q 'kind="error-masking" sym="handle"' \
    && ok "error-masking (python): except: pass flagged on handle()" || { no "error-masking (python): except-pass not flagged"; printf '%s\n' "$OPY" | tr '>' '\n' | grep '<r '; }

# ── 2) SHORT-HORIZON CHURN ───────────────────────────────────────────────────────────────────────────────
#   A file committed TWICE (both within the 14-day window measured from HEAD's own commit epoch), then
#   rewritten a THIRD time in the working tree. Its symbol must flag short-horizon-churn (file ≥2 in-window
#   commits AND rewritten again). A DIFFERENT file committed only ONCE and edited must NOT flag (churn<2).
SH="$WORK/shc"; mkdir -p "$SH/src"
( cd "$SH" && git init -q && git config user.email t@t && git config user.name t )
# hot.cpp: two commits (both recent) → will be edited a third time. cold.cpp: one commit → edited once.
# hot() is MULTI-LINE and gets TWO in-window commits on TWO DIFFERENT lines, because that is what the kind
# gates on since the 2026-09-10 dial round: churn="self" (the edit touches a line committed inside the window)
# is informational, and only "rewritten by >= 2 COMMITTED in-window commits, the working edit not counted"
# fires exit 2. A one-line hot() rewritten by a single commit can never show more than ONE blamed commit, so
# the old fixture could no longer exercise the gating arm at all (see test/qddialscheck.sh §1 for the pair).
printf 'int hot(){\n    int x = 1;\n    return x;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c1 >/dev/null 2>&1 )
printf 'int hot(){\n    int x = 2;\n    return x;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c2 >/dev/null 2>&1 )
printf 'int hot(){\n    int x = 2;\n    return x + 0;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c3 >/dev/null 2>&1 )
# a SEPARATE file with only ONE commit (churn == 1 < 2 → never flags short-horizon-churn even when edited)
printf 'int lone(){ return 0; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
( cd "$SH" && git add -A >/dev/null 2>&1 && git commit -qm c3single >/dev/null 2>&1 )
dsh(){  ( cd "$SH" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecsh(){ ( cd "$SH" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 2a) clean tree (== HEAD) → nothing rewritten → zero short-horizon-churn regressions.
[ "$( ecsh )" = 0 ] && dsh | grep -q 'regressions="0"' \
    && ok "short-horizon-churn: clean tree → exit 0 (nothing rewritten)" \
    || { no "short-horizon-churn: clean tree should be clean (exit $( ecsh ))"; dsh | tr '>' '\n' | grep '<r '; }

# 2b) rewrite hot() (its file has 2 in-window commits) AND lone() (its file has 1) in the working tree.
printf 'int hot(){\n    int x = 3;\n    return x + 1;\n}\nint cold(){ return 1; }\nint drive(){ return hot()+cold(); }\n' > "$SH/src/f.cpp"
printf 'int lone(){ return 9; }\nint uselone(){ return lone(); }\n' > "$SH/src/g.cpp"
OSH="$( dsh )"
if [ "$( ecsh )" = 2 ]; then ok "short-horizon-churn: rewrite of lines TWO in-window commits wrote → exit 2"; else no "short-horizon-churn: should exit 2 (got $( ecsh ))"; fi
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="hot"' \
    && ok "short-horizon-churn: hot() flagged (file had ≥2 recent commits, rewritten again)" || { no "short-horizon-churn: hot() not flagged"; printf '%s\n' "$OSH" | tr '>' '\n' | grep '<r '; }
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="lone"' \
    && no "short-horizon-churn: lone() wrongly flagged (its file had only 1 commit < 2)" \
    || ok "short-horizon-churn: single-commit file NOT flagged even when edited (min-commits gate)"
printf '%s' "$OSH" | grep -q 'kind="short-horizon-churn" sym="cold"' \
    && no "short-horizon-churn: cold() wrongly flagged (in a churny file but NOT rewritten this diff)" \
    || ok "short-horizon-churn: untouched symbol in a churny file NOT flagged (rewrite gate)"
if [ "$OSH" = "$( dsh )" ]; then ok "short-horizon-churn: delta byte-identical run-to-run (deterministic)"; else no "short-horizon-churn: non-deterministic delta"; fi

# ── 3) NEW-CLONE-OF-REUSED-HELPER ────────────────────────────────────────────────────────────────────────
#   A helper accumulate() with fan-in ≥ 3 (called from three sites) is committed. The working tree adds a
#   NEW function reinvent() whose body is a Type-1/2 clone of accumulate() — reuse-connectivity decline.
#   Assert the new-clone-of-reused-helper kind fires (exit 2) and names the clone pair.
#   3a/3b is also the CONTROL for 3c/3d below: a genuine reuse-decline (no recognized idiom, no shared
#   test-script path) must keep gating at full severity — the fix must not blunt the kind, only narrow it.
#   3c/3d extend this section to give reuse-decline the SAME two demotions `duplication` already has
#   (src/quality.h reportReusedClones, which reads reportNewClones's own CloneIdiomVerdict/isTestScriptPath
#   rather than a second copy of either test): idiom-class collisions demote to minor instead of gating, and
#   a clone group entirely made of test SCRIPTS is skipped outright, the same as `duplication`.
RC="$WORK/reuse"; mkdir -p "$RC/src"
( cd "$RC" && git init -q && git config user.email t@t && git config user.name t )
# accumulate() has a distinctive ≥18-token body; it is called from c1/c2/c3 → in-edge fan-in = 3.
printf 'int accumulate(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\n' >  "$RC/src/h.cpp"
printf 'int c1(){ return accumulate(); }\nint c2(){ return accumulate(); }\nint c3(){ return accumulate(); }\n' >> "$RC/src/h.cpp"
( cd "$RC" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
drc(){  ( cd "$RC" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecrc(){ ( cd "$RC" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

# 3a) clean tree → exit 0 (no clone group yet)
[ "$( ecrc )" = 0 ] && drc | grep -q 'regressions="0"' \
    && ok "reuse-connectivity: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity: clean tree should be clean (exit $( ecrc ))"; drc | tr '>' '\n' | grep '<r '; }

# 3b) add reinvent() — a byte-for-byte body clone of accumulate() (which has fan-in 3) in a new file.
printf 'int reinvent(){ int x=0; x+=1; x+=2; x+=3; x+=4; x+=5; x+=6; return x*x+7; }\nint user(){ return reinvent(); }\n' > "$RC/src/dup.cpp"
ORC="$( drc )"
if [ "$( ecrc )" = 2 ]; then ok "reuse-connectivity: new clone of a reused helper → exit 2"; else no "reuse-connectivity: should exit 2 (got $( ecrc ))"; fi
printf '%s' "$ORC" | grep -q 'kind="new-clone-of-reused-helper"' && printf '%s' "$ORC" | grep -q 'accumulate' \
    && ok "reuse-connectivity: new-clone-of-reused-helper flagged (reinvent duplicates accumulate, fan-in≥3)" \
    || { no "reuse-connectivity: new-clone-of-reused-helper missing"; printf '%s\n' "$ORC" | tr '>' '\n' | grep '<r '; }
# CONTROL (3b, strengthened): accumulate()/reinvent() share no recognized idiom and no test-script path, so
# this genuine reuse-decline must gate at FULL severity — gating="1", no sev="minor", no idiom= — proving the
# demotions added in 3c/3d below narrow the kind and do not blunt it.
RCROW="$( printf '%s' "$ORC" | tr '<' '\n' | grep '^r kind="new-clone-of-reused-helper"' )"
printf '%s' "$RCROW" | grep -q 'gating="1"' \
    && ok "reuse-connectivity CONTROL: a genuine (non-idiom, non-test-script) clone still gates at full severity" \
    || no "reuse-connectivity CONTROL: genuine reuse-decline lost its gating attribute: $RCROW"
printf '%s' "$RCROW" | grep -qE 'sev="minor"|idiom="' \
    && no "reuse-connectivity CONTROL: genuine reuse-decline was wrongly demoted (sev=minor/idiom= present): $RCROW" \
    || ok "reuse-connectivity CONTROL: no sev=\"minor\", no idiom= on the genuine finding"
if [ "$ORC" = "$( drc )" ]; then ok "reuse-connectivity: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$ORC" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity: xml well-formed"; else no "reuse-connectivity: xml malformed"; fi
fi

# 3c) IDIOM-CLASS COLLISION on a reused helper: altitudeBandOf() (a scalar threshold-ladder over a 4-band
#     enum, fan-in=3 via 3 baseline callers) is committed. The working tree adds tankStateFor() — the SAME
#     threshold-ladder shape in a different namespace/file, sharing NOT ONE non-keyword identifier with
#     altitudeBandOf — the exact shape src/cloneidiom.h demotes for `duplication` (test/cloneidiomcheck.sh's
#     ladder_demote fixture). Because the group also contains a fan-in≥3 PREEXISTING helper, this is ALSO a
#     new-clone-of-reused-helper candidate; the fix requires it to demote (sev="minor", no gating) exactly
#     like `duplication` does, via the SAME CloneIdiomVerdict — not a second idiom test of its own.
ID="$WORK/idiom"; mkdir -p "$ID/src"
( cd "$ID" && git init -q && git config user.email t@t && git config user.name t )
cat > "$ID/src/altitude.cpp" <<'EOF'
namespace flight
{
enum class AltitudeBand : unsigned char { Low, Mid, High, Danger };
AltitudeBand altitudeBandOf( float y )
{
    if( y <  6.0f ) return AltitudeBand::Low;
    if( y < 12.0f ) return AltitudeBand::Mid;
    if( y < 16.0f ) return AltitudeBand::High;
    return AltitudeBand::Danger;
}
int callA( float y ) { return int( altitudeBandOf( y ) ); }
int callB( float y ) { return int( altitudeBandOf( y ) ); }
int callC( float y ) { return int( altitudeBandOf( y ) ); }
}
EOF
( cd "$ID" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
did(){  ( cd "$ID" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecid(){ ( cd "$ID" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

[ "$( ecid )" = 0 ] && did | grep -q 'regressions="0"' \
    && ok "reuse-connectivity idiom: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity idiom: clean tree should be clean (exit $( ecid ))"; did | tr '>' '\n' | grep '<r '; }

cat > "$ID/src/tank.cpp" <<'EOF'
namespace supply
{
enum class TankState : unsigned char { Empty, Reserve, Cruise, Brimming };
TankState tankStateFor( float litres )
{
    if( litres <  20.0f ) return TankState::Empty;
    if( litres <  90.0f ) return TankState::Reserve;
    if( litres < 140.0f ) return TankState::Cruise;
    return TankState::Brimming;
}
}
EOF
OID="$( did )"
if [ "$( ecid )" = 0 ]; then ok "reuse-connectivity idiom: idiom collision on a reused helper does NOT gate (exit 0)"; else no "reuse-connectivity idiom: should stay exit 0, an idiom collision must demote not gate (got $( ecid ))"; fi
IDROW="$( printf '%s' "$OID" | tr '<' '\n' | grep '^r kind="new-clone-of-reused-helper"' )"
printf '%s' "$IDROW" | grep -q . \
    && ok "reuse-connectivity idiom: new-clone-of-reused-helper still PRINTS (demoted, not deleted)" \
    || { no "reuse-connectivity idiom: new-clone-of-reused-helper row missing entirely (demotion must still print)"; printf '%s\n' "$OID" | tr '>' '\n' | grep '<r '; }
printf '%s' "$IDROW" | grep -q 'sev="minor"' \
    && ok "reuse-connectivity idiom: row carries sev=\"minor\" (demoted)" \
    || no "reuse-connectivity idiom: row is not sev=\"minor\": $IDROW"
printf '%s' "$IDROW" | grep -q 'idiom="threshold-ladder"' \
    && ok "reuse-connectivity idiom: row names its idiom (threshold-ladder)" \
    || no "reuse-connectivity idiom: row does not name idiom=\"threshold-ladder\": $IDROW"
printf '%s' "$IDROW" | grep -q 'gating="1"' \
    && no "reuse-connectivity idiom: demoted row still carries gating=\"1\"" \
    || ok "reuse-connectivity idiom: demoted row carries no gating=\"1\""
if [ "$OID" = "$( did )" ]; then ok "reuse-connectivity idiom: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity idiom: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OID" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity idiom: xml well-formed"; else no "reuse-connectivity idiom: xml malformed"; fi
fi

# 3d) ALL-TEST-SCRIPT SKIP on a reused helper: mcp_call() (a shell test-harness helper, fan-in=3 via 3
#     baseline callers, ALL under test/) is committed. The working tree adds a sibling gate script whose
#     helper is a Type-1/2 clone of mcp_call() — the house "every sibling gate repeats mcp_call()-style
#     boilerplate" convention `duplication` already exempts (isTestScriptPath). Because every member of the
#     group is a test script, the fix requires the row to be SKIPPED OUTRIGHT (never printed, not even
#     minor) — the same continue `reportNewClones` takes, reused rather than re-implemented.
TS="$WORK/testscript"; mkdir -p "$TS/test"
( cd "$TS" && git init -q && git config user.email t@t && git config user.name t )
cat > "$TS/test/hcheck.sh" <<'EOF'
#!/usr/bin/env bash
mcp_call() {
    local a="$1"
    local n=0
    n=$(( n + 1 ))
    n=$(( n + 2 ))
    n=$(( n + 3 ))
    n=$(( n + 4 ))
    n=$(( n + 5 ))
    n=$(( n + 6 ))
    echo "$a:$n"
}
siteA() { mcp_call "x"; }
siteB() { mcp_call "y"; }
siteC() { mcp_call "z"; }
siteA; siteB; siteC
EOF
( cd "$TS" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
dts(){  ( cd "$TS" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ects(){ ( cd "$TS" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

[ "$( ects )" = 0 ] && dts | grep -q 'regressions="0"' \
    && ok "reuse-connectivity test-script: clean tree → exit 0 (no duplicate yet)" \
    || { no "reuse-connectivity test-script: clean tree should be clean (exit $( ects ))"; dts | tr '>' '\n' | grep '<r '; }

cat > "$TS/test/dupcheck.sh" <<'EOF'
#!/usr/bin/env bash
mcp_call_dup() {
    local a="$1"
    local n=0
    n=$(( n + 1 ))
    n=$(( n + 2 ))
    n=$(( n + 3 ))
    n=$(( n + 4 ))
    n=$(( n + 5 ))
    n=$(( n + 6 ))
    echo "$a:$n"
}
EOF
OTS="$( dts )"
if [ "$( ects )" = 0 ]; then ok "reuse-connectivity test-script: all-test-script clone of a reused helper does NOT gate (exit 0)"; else no "reuse-connectivity test-script: should stay exit 0, all-test-script groups are skipped outright (got $( ects ))"; fi
printf '%s' "$OTS" | grep -q 'kind="new-clone-of-reused-helper"' \
    && no "reuse-connectivity test-script: new-clone-of-reused-helper fired on an all-test-script group (should be skipped outright)" \
    || ok "reuse-connectivity test-script: new-clone-of-reused-helper is SKIPPED (no row at all, not even minor)"
printf '%s' "$OTS" | grep -q 'regressions="0"' \
    && ok "reuse-connectivity test-script: regressions=\"0\" (the skip drops the row, not just its severity)" \
    || { no "reuse-connectivity test-script: expected regressions=\"0\""; printf '%s\n' "$OTS" | tr '>' '\n' | grep '<r '; }
if [ "$OTS" = "$( dts )" ]; then ok "reuse-connectivity test-script: delta byte-identical run-to-run (deterministic)"; else no "reuse-connectivity test-script: non-deterministic delta"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OTS" | xmllint --noout - 2>/dev/null; then ok "reuse-connectivity test-script: xml well-formed"; else no "reuse-connectivity test-script: xml malformed"; fi
fi

# ── 4) SELF vs AMBIENT CHURN (B10.2d, signal-to-noise round 2) ─────────────────────────────────────────────
#   A symbol that already clears the three short-horizon-churn gates above gets a further split: does THIS
#   uncommitted diff modify a pre-existing line that was itself last committed inside the churn window (SELF —
#   genuine thrash, stays major, facet churn="self"), or does it only ADD new lines / touch lines that predate
#   the window (AMBIENT — the file is hot but this edit isn't touching hot content) → sev="minor",
#   facet churn="ambient". Three sub-cases: 4a in-place edit of a recently-committed line (self, control — the
#   existing hot()-flagged assertions in §2 above already cover this shape, so this control just names the
#   facet); 4b a pure line-count-growing insertion into an already window-churned function (ambient: adds
#   lines); 4c an edit that touches a line whose real last commit predates the window even though the FILE
#   is churn-hot from unrelated recent activity (ambient: touches cold lines — needs a backdated commit via
#   GIT_AUTHOR_DATE/GIT_COMMITTER_DATE, same idiom rankbycheck.sh/ownerscheck.sh already use).
commit_at(){ local dir="$1" ts="$2" msg="$3"; git -C "$dir" add -A >/dev/null 2>&1
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_DATE="$ts" \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_DATE="$ts" \
        git -C "$dir" commit -q -m "$msg" >/dev/null 2>&1; }
NOW="$( date -u +%Y-%m-%dT%H:%M:%S )"

# 4a) SELF (control): in-place rewrite of a line committed in the last window commit, edited again now.
SF="$WORK/selfchurn"; mkdir -p "$SF/src"
( cd "$SF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){ return 1; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c1
printf 'int hot(){ return 2; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
commit_at "$SF" "$NOW" c2
printf 'int hot(){ return 3; }\nint drive(){ return hot(); }\n' > "$SF/src/f.cpp"
OSF="$( cd "$SF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*churn="self"' \
    && ok "self/ambient churn: in-place edit of a recently-committed line → facet churn=\"self\"" \
    || { no "self/ambient churn: expected churn=\"self\" on hot()"; printf '%s\n' "$OSF" | tr '>' '\n' | grep '<r '; }
# DIAL 2026-09-10 — this assertion is INVERTED on purpose, and the inversion is the finding: hot() here was
# rewritten by exactly ONE in-window commit (c2), which is a touch, not thrash. SELF names that the edit lands
# on hot content and stops there; what gates is 2 or more committed in-window rewrites (§2 above, and
# test/qddialscheck.sh §1 measures the pair side by side). Over twelve LANDED commits of this repo the old
# "SELF gates" rule supplied 135 of 171 gating rows at 0% precision (audit Q1 §2b/§2d).
printf '%s' "$OSF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"' \
    && ok "self/ambient churn: ONE in-window rewrite is informational — sev=\"minor\", facet still self" \
    || { no "self/ambient churn: a single in-window rewrite must not gate"; printf '%s\n' "$OSF" | tr '>' '\n' | grep '<r '; }
ESF="$( cd "$SF" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
if [ "$ESF" = 0 ]; then ok "self/ambient churn: a self-only finding does not gate exit 2"; else no "self/ambient churn: self-only run should exit 0 (got $ESF)"; fi

# 4b) AMBIENT — adds lines: the working-tree edit only INSERTS a new statement, touching no existing line.
AF="$WORK/ambientadd"; mkdir -p "$AF/src"
( cd "$AF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int y=1;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c1
printf 'int hot(){\n    int y=9;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
commit_at "$AF" "$NOW" c2
printf 'int hot(){\n    int y=9;\n    int z=2;\n    return y;\n}\nint drive(){ return hot(); }\n' > "$AF/src/f.cpp"
OAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
EAF="$( cd "$AF" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? )"
printf '%s' "$OAF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: pure line-insertion edit → sev=\"minor\" churn=\"ambient\" (adds lines)" \
    || { no "self/ambient churn: pure-insert edit not downgraded to ambient"; printf '%s\n' "$OAF" | tr '>' '\n' | grep '<r '; }
if [ "$EAF" = 0 ]; then ok "self/ambient churn: ambient-only finding does not gate exit 2"; else no "self/ambient churn: ambient-only run should exit 0 (got $EAF)"; fi

# 4c) AMBIENT — touches a cold line: the file is churn-hot (2 recent commits) via an UNRELATED line, but the
#     working tree edits a line whose real last commit is a backdated, out-of-window commit.
CF="$WORK/ambientcold"; mkdir -p "$CF/src"
( cd "$CF" && git init -q && git config user.email t@t && git config user.name t )
printf 'int hot(){\n    int a=1;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "2026-01-01T00:00:00" "c1 backdated (>14d before HEAD)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot(); }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c2 recent (touches a — the committed-thrash evidence)"
printf 'int hot(){\n    int a=9;\n    int b=2;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
commit_at "$CF" "$NOW" "c3 recent (2nd in-window file commit, does not touch hot())"
printf 'int hot(){\n    int a=9;\n    int b=20;\n    return a+b;\n}\nint drive(){ return hot()+0; }\n' > "$CF/src/f.cpp"
OCF="$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
printf '%s' "$OCF" | grep -q 'kind="short-horizon-churn" sym="hot"[^/]*sev="minor"[^/]*churn="ambient"' \
    && ok "self/ambient churn: edit of a line last committed outside the window → ambient (touches cold lines)" \
    || { no "self/ambient churn: cold-line edit not downgraded to ambient"; printf '%s\n' "$OCF" | tr '>' '\n' | grep '<r '; }
[ "$OCF" = "$( cd "$CF" && "$BIN" . --quality-delta --no-cache 2>/dev/null )" ] \
    && ok "self/ambient churn: delta byte-identical run-to-run" || no "self/ambient churn: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OSF" | xmllint --noout - 2>/dev/null && printf '%s' "$OAF" | xmllint --noout - 2>/dev/null && printf '%s' "$OCF" | xmllint --noout - 2>/dev/null \
        && ok "self/ambient churn: xml well-formed (self + both ambient outputs)" || no "self/ambient churn: xml malformed"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
