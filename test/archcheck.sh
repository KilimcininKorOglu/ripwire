#!/usr/bin/env bash
# archcheck.sh — gate test for P3-B: built-in layers as --arch `layer()` predicate.
#
# Verifies that built-in layer names (game/infra/render/math/audio/ai/test) resolve in
# deny/allow rules WITHOUT explicit `layer NAME = ...` declarations.
#
# Usage:
#   bash test/archcheck.sh                          |  bash test/archcheck.sh asan/ripwire
#   RIPWIRE_BIN=asan/ripwire bash test/archcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.
#
# Checks 1-9 run from INSIDE the fixture dir (test/archfix/) — historically because they HAD to. The note
# that used to sit here called that an implementation detail: paths came out as `./render/shader.h` and
# `./test/main.cpp` rather than repo-relative spellings starting with `test/`, "which would cause the `test/`
# built-in layer to falsely match render/shader.h". That was the bug, not a detail. Layer substrings are now
# matched against the ROOT-RELATIVE path, so the cwd cannot change a verdict — and check 10 is what proves it,
# by running the identical rules file from the repo root and demanding the same violations= and the same exit
# code. The other checks keep their cwd so that what they assert is unchanged.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# BOTH seams. `bash test/<gate>.sh asan/ripwire` is how regression.sh and every differential run pass a
# binary; this gate read only RIPWIRE_BIN, so a positional argument was accepted and silently ignored and
# a red-first run against a BASE binary came back ALL PASS against the binary already in build/.
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN

FIXTURE="$ROOT/test/archfix"
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# run every ripwire invocation from inside the fixture dir so paths are `./render/…` `./test/…`
cd "$FIXTURE"

echo "archcheck: BIN=$BIN  FIXTURE=$FIXTURE"

# ── check 1: built-in-layer violation detected (exit 2) ───────────────────────────────────────────
# rules.txt uses `deny test -> render` — both are BUILT-IN layer names with no `layer` declarations.
# test/main.cpp includes render/shader.h, so ripwire must detect the crossing and exit 2.
"$BIN" . --arch=rules.txt --no-cache >"$TMP/viol.xml" 2>/dev/null
rc_viol=$?
if [ "$rc_viol" -eq 2 ]; then
    ok "built-in-layer deny rule: exit 2 (violation detected)"
else
    no "built-in-layer deny rule: expected exit 2, got $rc_viol"
fi

# ── check 2: violation output mentions the crossing edge ──────────────────────────────────────────
# The arch XML must reference the violating files (non-zero violations count) so the user can act.
if grep -q 'violations="[^0]' "$TMP/viol.xml" 2>/dev/null; then
    ok "violation output reports non-zero violation count"
else
    no "violation output missing non-zero violations (got: $(head -1 "$TMP/viol.xml"))"
fi

# ── check 3: clean rules file (allow test -> render) exits 0 ──────────────────────────────────────
# The same fixture with an allow rule must not exit 2 — built-in layers also work for `allow`.
"$BIN" . --arch=clean_rules.txt --no-cache >/dev/null 2>/dev/null
rc_clean=$?
if [ "$rc_clean" -eq 0 ]; then
    ok "clean built-in-layer allow rule: exit 0 (no violation)"
else
    no "clean built-in-layer allow rule: expected exit 0, got $rc_clean"
fi

# ── check 4: user-declared layer wins over built-in on name clash ─────────────────────────────────
# A rules file that declares `layer test = /no-such-path/` means NO files match `test` → 0 violations.
# If the built-in overwrote the user layer, test/main.cpp would still match and exit 2.
cat >"$TMP/override.txt" <<'EOF'
# user overrides the built-in `test` layer with a non-matching path
layer test = /no-such-path-xyz/
deny test -> render
EOF
"$BIN" . --arch="$TMP/override.txt" --no-cache >/dev/null 2>/dev/null
rc_over=$?
if [ "$rc_over" -eq 0 ]; then
    ok "user-defined layer wins over built-in (no false violation when user redefines 'test')"
else
    no "user-defined layer lost to built-in (expected exit 0 with user override, got $rc_over)"
fi

# ── check 5: determinism — two runs with built-in layers produce byte-identical output ────────────
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_a.xml" 2>/dev/null || true
"$BIN" . --arch=rules.txt --no-cache >"$TMP/det_b.xml" 2>/dev/null || true
if diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null 2>&1; then
    ok "determinism: byte-identical output across two runs with built-in layers"
else
    no "determinism: output differs between runs with built-in layers"
    diff "$TMP/det_a.xml" "$TMP/det_b.xml" | head -8
fi

# ── check 6: existing behavior unchanged — rules that only use user-declared layers still work ────
# A fully user-declared rule file must be unaffected by the built-in auto-add logic.
cat >"$TMP/userlayers.txt" <<'EOF'
# all layers are user-declared — no built-in auto-add should trigger
layer myrender = render
layer mytest   = test
deny mytest -> myrender
EOF
"$BIN" . --arch="$TMP/userlayers.txt" --no-cache >/dev/null 2>/dev/null
rc_user=$?
if [ "$rc_user" -eq 2 ]; then
    ok "user-declared-only rules still detect violations (no regression)"
else
    no "user-declared-only rules: expected exit 2, got $rc_user (regression in existing behavior)"
fi

# ── check 7 (D9): a malformed rules line must REJECT the whole file loudly — not silently disarm ──
# `deny: test -> render` (colon typo) used to tokenize "deny:" as the keyword, match neither "allow" nor
# "deny", and get silently ignored — the file "parsed" to zero rules/violations and exited 0, quietly
# turning off a CI gate. It must now behave like --lint-rules: refuse the file, print a specific
# path:lineNo message, and exit 1 (not 0, not 2 — a REFUSAL, distinct from "ran clean" and "found debt").
cat >"$TMP/typo_colon.txt" <<'EOF'
deny: test -> render
EOF
"$BIN" . --arch="$TMP/typo_colon.txt" --no-cache >"$TMP/typo_colon.out" 2>"$TMP/typo_colon.err"
rc_typo=$?
if [ "$rc_typo" -eq 1 ]; then
    ok "malformed rules line ('deny:' colon typo): exit 1 (refused, not silently disarmed)"
else
    no "malformed rules line ('deny:' colon typo): expected exit 1, got $rc_typo"
fi
if grep -q 'typo_colon.txt:1' "$TMP/typo_colon.err" 2>/dev/null; then
    ok "malformed rules line: stderr names the file and line number"
else
    no "malformed rules line: stderr missing a path:lineNo diagnostic (got: $(cat "$TMP/typo_colon.err"))"
fi
if [ ! -s "$TMP/typo_colon.out" ]; then
    ok "malformed rules line: no XML emitted on refusal"
else
    no "malformed rules line: unexpectedly emitted XML on refusal: $(cat "$TMP/typo_colon.out")"
fi

# ── check 8 (D9): other malformed-line shapes are refused the same way ────────────────────────────
cat >"$TMP/bad_layer.txt" <<'EOF'
layer test
EOF
"$BIN" . --arch="$TMP/bad_layer.txt" --no-cache >/dev/null 2>"$TMP/bad_layer.err"
rc_badlayer=$?
[ "$rc_badlayer" -eq 1 ] && grep -q 'bad_layer.txt:1' "$TMP/bad_layer.err" \
    && ok "malformed 'layer' line (missing '= subs'): exit 1 with a line diagnostic" \
    || no "malformed 'layer' line: expected exit 1 + diagnostic, got exit $rc_badlayer, stderr: $(cat "$TMP/bad_layer.err")"

cat >"$TMP/bad_kw.txt" <<'EOF'
denyy test -> render
EOF
"$BIN" . --arch="$TMP/bad_kw.txt" --no-cache >/dev/null 2>"$TMP/bad_kw.err"
rc_badkw=$?
[ "$rc_badkw" -eq 1 ] && grep -q 'bad_kw.txt:1' "$TMP/bad_kw.err" \
    && ok "unrecognized keyword ('denyy'): exit 1 with a line diagnostic" \
    || no "unrecognized keyword: expected exit 1 + diagnostic, got exit $rc_badkw, stderr: $(cat "$TMP/bad_kw.err")"

# 2026-09-06 (stranger audit): a `deny path` rule whose FROM regex does not compile used to be KEPT (pathRules=
# counted it) and skipped — one stray paren turned a CI gate's exit 2 into exit 0 with violations="0". Same
# refusal as the two shapes above, naming the line.
printf 'deny path src/a\\.cpp( -> src/b\\.cpp\n' >"$TMP/bad_regex.txt"
"$BIN" . --arch="$TMP/bad_regex.txt" --no-cache >"$TMP/bad_regex.out" 2>"$TMP/bad_regex.err"
rc_badre=$?
[ "$rc_badre" -eq 1 ] && grep -q 'bad_regex.txt:1' "$TMP/bad_regex.err" && grep -q 'does not compile' "$TMP/bad_regex.err" \
    && ok "uncompilable FROM path-regex: exit 1 with a line diagnostic (the rule is not silently disarmed)" \
    || no "uncompilable FROM path-regex: expected exit 1 + diagnostic, got exit $rc_badre, stderr: $(cat "$TMP/bad_regex.err")"
[ ! -s "$TMP/bad_regex.out" ] \
    && ok "uncompilable FROM path-regex: no XML emitted on refusal" \
    || no "uncompilable FROM path-regex: XML emitted alongside the refusal (violations=\"0\" would read as a pass)"

# a well-formed file is UNAFFECTED by the tightened parser (no false-positive rejection).
"$BIN" . --arch=rules.txt --no-cache >/dev/null 2>"$TMP/wellformed.err"
rc_wf=$?
[ "$rc_wf" -eq 2 ] && [ ! -s "$TMP/wellformed.err" ] \
    && ok "well-formed rules file: still exits 2 on a real violation, no spurious stderr" \
    || no "well-formed rules file: regressed (exit $rc_wf, stderr: $(cat "$TMP/wellformed.err"))"

# ── check 10: THE SAME RULES FILE MUST GIVE THE SAME VERDICT FROM ANY WORKING DIRECTORY ───────────
# Every check above runs from INSIDE the fixture. The header used to explain why as an implementation
# note — `./render/shader.h` and `./test/main.cpp` are "real dir-component-first paths", where the
# repo-relative spelling starting with `test/` "would cause the `test/` built-in layer to falsely match
# render/shader.h". That is not an implementation note, it is the bug: the layer substrings were matched
# against the path as EMITTED, so `/…/test/archfix/render/shader.h` contains `/test/` and first-match-wins
# put the render file in the test layer, both endpoints landed in one layer, and `deny test -> render`
# reported violations="0" at exit 0. Measured on the pre-fix binary: violations="1" from inside the fixture
# and violations="0" from the repo root, same fixture, same rules file, same binary.
#
# Rules are now matched against the ROOT-RELATIVE path, so the workaround is no longer load-bearing — and
# this arm is what keeps it that way: the verdict must be identical whether the corpus is named `.` from
# inside or by an absolute path from outside. A CI gate that reports clean because of where it was invoked
# from is worse than no gate.
ARCH_OUT_INSIDE="$( "$BIN" . --arch=rules.txt --no-cache 2>/dev/null | grep -oE '<arch [^>]*' )"
rc_inside=$?
ARCH_OUT_OUTSIDE="$( cd "$ROOT" && "$BIN" "$FIXTURE" --arch="$FIXTURE/rules.txt" --no-cache 2>/dev/null | grep -oE '<arch [^>]*' )"
v_inside="$(  printf '%s' "$ARCH_OUT_INSIDE"  | grep -oE 'violations="[0-9]+"' )"
v_outside="$( printf '%s' "$ARCH_OUT_OUTSIDE" | grep -oE 'violations="[0-9]+"' )"
if [ -z "$v_inside" ] || [ -z "$v_outside" ]; then
    no "check 10 could not read violations= from one of the two runs (inside='$v_inside' outside='$v_outside')"
elif [ "$v_inside" = "$v_outside" ] && [ "$v_inside" != 'violations="0"' ]; then
    ok "layer rules give the same verdict from inside the fixture and from the repo root ($v_inside)"
else
    no "layer verdict depends on the working directory: inside=$v_inside outside=$v_outside — an unanchored layer substring bound to the checkout path"
fi
# and the EXIT CODE, which is what CI reads, must agree too.
( cd "$ROOT" && "$BIN" "$FIXTURE" --arch="$FIXTURE/rules.txt" --no-cache >/dev/null 2>&1 )
rc_outside=$?
[ "$rc_outside" -eq 2 ] \
    && ok "…and the CI exit code is 2 from outside the fixture too (not a silent 0)" \
    || no "running the same rules from outside the fixture exits $rc_outside, not 2 — the gate disarms itself off-cwd"

# ══ F-B4 — a skipped path-rule subject refuses ONLY when a deny rule would have fired on it ═════════
# RIPWIRE_FAULT_REGEX_LINE_BOUND=1 forces src/regexguard.h's per-thread subject-length bound to (near) zero,
# so a FROM/TO regex that is not a bare literal (and so reaches the engine — a literal answers off the
# byte-search plan, which no subject is ever too long for) never gets a verdict on the same edge these earlier
# checks already know is a real violation (test/main.cpp -> render/shader.h). "test/(\w+)\.cpp" has a
# quantifier, so it is not a literal plan; "test/main\.cpp" IS one (an escaped literal dot is still a byte
# string), so it stays decided even under the fault — the control that makes arm 2 mean something.
echo
echo "--- F-B4: a skipped path-rule subject refuses only when a deny would have fired on it ---"

# (1) ONE deny rule, forced to skip, nothing else decides the edge → genuinely undecided → refuse.
cat >"$TMP/skip_only.txt" <<'EOF'
deny path test/(\w+)\.cpp -> render/(\w+)\.h
EOF
# RIPWIRE_FAULT_* switches are compiled out under NDEBUG (src/infra/emit.h faultSwitchOn), so on a Release leg the fault
# run IS the control run. Probe the switch itself (the regexguardcheck.sh (m) fixture: one line past the 64-byte forced bound).
FAULTS=0; mkdir -p "$TMP/faultprobe"
{ head -c 100 /dev/zero | tr '\0' 'x'; printf ' aab\naab\n'; } >"$TMP/faultprobe/f.md"
RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" "$TMP/faultprobe" --no-cache --regex='a+b' 2>/dev/null | grep -q 'regex_lines_skipped="[1-9]' && FAULTS=1
if [ "$FAULTS" -eq 1 ]; then
    RIPWIRE_FAULT_REGEX_LINE_BOUND=1 "$BIN" . --arch="$TMP/skip_only.txt" --no-cache >"$TMP/skip_only.out" 2>"$TMP/skip_only.err"
    rc_skiponly=$?
    [ "$rc_skiponly" -eq 1 ] \
        && ok "F-B4(1): a skip with nothing else to decide the edge refuses (exit 1)" \
        || no "F-B4(1): expected exit 1 (refusal), got $rc_skiponly: $( head -c 200 "$TMP/skip_only.err" )"
    [ ! -s "$TMP/skip_only.out" ] \
        && ok "F-B4(1): no XML emitted on refusal" \
        || no "F-B4(1): XML emitted alongside the refusal"
else
    printf '  INFO  F-B4(1): this binary compiles fault switches out (NDEBUG); the forced skip is proved on the plain-flavour leg\n'
fi
# control: the SAME rule with no fault decides normally (a real violation, exit 2) — proves (1) is a genuine skip,
# not a rule that was already broken.
"$BIN" . --arch="$TMP/skip_only.txt" --no-cache >/dev/null 2>"$TMP/skip_only_ctrl.err"
rc_skiponly_ctrl=$?
[ "$rc_skiponly_ctrl" -eq 2 ] \
    && ok "F-B4(1) control: the same rule with no fault finds the real violation (exit 2)" \
    || no "F-B4(1) control: expected exit 2 with no fault, got $rc_skiponly_ctrl — the fixture is not adversarial"

# (2) TWO deny rules on the same edge, the first genuinely UNDECIDED, the second DECISIVE — the edge must stay
# forbidden and DISCLOSE the undecided one, never refuse for it. RIPWIRE_FAULT_REGEX_LINE_BOUND=1 forces every
# FROM/TO match on kCallerStackBytesFloor to Skip (524288 >> 22 == 0 under libc++; 8 MiB >> 22 == 2 B under libstdc++,
# shorter than any path here), which would skip BOTH rules' FROM evaluation and
# so cannot build a differential within one run. A per-edge TO-refusal (arch.h's own documented `a{2,\1}` shape)
# is undecided the same way — pathRuleForbids treats isRefused/isAbandoned/isSkipped identically — and unlike the
# fault it is deterministic and per-RULE, so it is used here to prove the scan-past-the-undecided-one behavior.
# A dedicated tiny corpus (not test/archfix) supplies a NUMERIC path segment for the interval's `\1`.
NUMFIX="$TMP/numfix"; mkdir -p "$NUMFIX/test/v25" "$NUMFIX/render"
: > "$NUMFIX/render/shader.h"
printf '#include "../../render/shader.h"\n' > "$NUMFIX/test/v25/main.cpp"
cat >"$TMP/skip_then_decide.txt" <<'EOF'
deny path test/v(\d+)/main\.cpp -> render/shader\.h{\1,20}
deny path test/(\w+)/main\.cpp  -> render/shader\.h
EOF
# control: rule 1 ALONE is genuinely undecided for this edge (25 > 20: an invalid interval only the real capture
# produces — the "9" placeholder toTemplateRefusal probes with gives {9,20}, valid, so the whole FILE still loads).
cat >"$TMP/skip_only2.txt" <<'EOF'
deny path test/v(\d+)/main\.cpp -> render/shader\.h{\1,20}
EOF
( cd "$NUMFIX" && "$BIN" . --arch="$TMP/skip_only2.txt" --no-cache >"$TMP/skip_only2.out" 2>"$TMP/skip_only2.err" )
rc_skiponly2=$?
[ "$rc_skiponly2" -eq 1 ] \
    && ok "F-B4(2) control: rule 1 alone (undecided on this edge) refuses (exit 1)" \
    || no "F-B4(2) control: expected exit 1 with rule 1 alone, got $rc_skiponly2: $( head -c 200 "$TMP/skip_only2.err" )"

( cd "$NUMFIX" && "$BIN" . --arch="$TMP/skip_then_decide.txt" --no-cache >"$TMP/skip_then_decide.out" 2>"$TMP/skip_then_decide.err" )
rc_skipdecide=$?
[ "$rc_skipdecide" -eq 2 ] \
    && ok "F-B4(2): a later decisive deny settles the edge despite the earlier undecided one (exit 2, not a refusal)" \
    || no "F-B4(2): expected exit 2 (a real, undeterred violation), got $rc_skipdecide: $( head -c 200 "$TMP/skip_then_decide.err" )"
grep -q 'violations="[^0]' "$TMP/skip_then_decide.out" \
    && ok "F-B4(2): the violation is reported (not silently dropped because a sibling rule was undecided)" \
    || no "F-B4(2): no non-zero violations= in $( head -c 200 "$TMP/skip_then_decide.out" )"
grep -qE 'edge\(s\) met an undecided' "$TMP/skip_then_decide.err" \
    && ok "F-B4(2): stderr discloses that an undecided evaluation occurred" \
    || no "F-B4(2): the undecided evaluation was not disclosed: $( head -c 300 "$TMP/skip_then_decide.err" )"

# ══ F-H9 (CodeRabbit on #277) — a TO-template interval's validity is judged PER EDGE, not guessed at parse ═══
# `a{10,\1}` used to be refused at PARSE TIME (rejecting the whole rules file) even though \1="20" makes it a
# perfectly valid interval — the parse-time probe tried \1="x" (non-numeric: {10,x} always fails, whatever the
# template) and \1="9" (9<10: {10,9} fails on ORDER, a fact about "9" specifically). Two edges, two capture
# values, prove the fix: v20 is a VALID instance (applies — a real verdict, not a refusal); v5 is INVALID for
# its own capture (refuses THAT edge by name).
echo
echo "--- F-H9: TO-template interval validity is decided per edge, with the real capture ---"
H9RULES="$TMP/h9_interval.txt"
cat >"$H9RULES" <<'EOF'
deny path test/v(\d+)/main\.cpp -> render/shader\.h{10,\1}
EOF

H9V20="$TMP/h9_v20"; mkdir -p "$H9V20/test/v20" "$H9V20/render"
: > "$H9V20/render/shader.h"
printf '#include "../../render/shader.h"\n' > "$H9V20/test/v20/main.cpp"
( cd "$H9V20" && "$BIN" . --arch="$H9RULES" --no-cache >"$TMP/h9_v20.out" 2>"$TMP/h9_v20.err" )
rc_h9v20=$?
[ "$rc_h9v20" -eq 0 ] \
    && ok "F-H9: a valid instance (\\1=\"20\": {10,20}) applies — a real verdict, not a parse-time refusal (exit 0)" \
    || no "F-H9: \\1=\"20\" should give a real verdict, got exit $rc_h9v20: $( head -c 300 "$TMP/h9_v20.err" )"
grep -q 'pathRules="1"' "$TMP/h9_v20.out" \
    && ok "F-H9: the rules file LOADED (pathRules=\"1\") — was rejected outright pre-fix" \
    || no "F-H9: the rules file did not load: $( head -c 200 "$TMP/h9_v20.out" )$( head -c 200 "$TMP/h9_v20.err" )"

H9V5="$TMP/h9_v5"; mkdir -p "$H9V5/test/v5" "$H9V5/render"
: > "$H9V5/render/shader.h"
printf '#include "../../render/shader.h"\n' > "$H9V5/test/v5/main.cpp"
( cd "$H9V5" && "$BIN" . --arch="$H9RULES" --no-cache >"$TMP/h9_v5.out" 2>"$TMP/h9_v5.err" )
rc_h9v5=$?
[ "$rc_h9v5" -eq 1 ] \
    && ok "F-H9: an invalid instance (\\1=\"5\": {10,5}) refuses THAT edge (exit 1)" \
    || no "F-H9: \\1=\"5\" should refuse the edge, got exit $rc_h9v5: $( head -c 300 "$TMP/h9_v5.err" )"
grep -q 'test/v5/main.cpp -> render/shader.h' "$TMP/h9_v5.err" \
    && ok "F-H9: the refusal names the specific edge, not just the template" \
    || no "F-H9: the refusal does not name the edge: $( head -c 300 "$TMP/h9_v5.err" )"
grep -q 'a TO template with a backreference is judged per edge' "$TMP/h9_v5.err" \
    && ok "F-H9: the per-edge refusal names why it was deferred to the edge (the template has a backreference)" \
    || no "F-H9: the per-edge refusal does not name the backreference deferral: $( head -c 300 "$TMP/h9_v5.err" )"
[ ! -s "$TMP/h9_v5.out" ] \
    && ok "F-H9: no XML emitted on the per-edge refusal" \
    || no "F-H9: XML emitted alongside the per-edge refusal"

# control: a template invalid for EVERY capture (an unmatched '(' has nothing to do with \1 at all) still
# refuses the whole rules file at parse time — the fix must not have over-relaxed the D9 rule generally.
cat >"$TMP/h9_structural.txt" <<'EOF'
deny path test/(\w+)\.cpp -> render/sha(der\.h{10,\1}
EOF
"$BIN" . --arch="$TMP/h9_structural.txt" --no-cache >"$TMP/h9_structural.out" 2>"$TMP/h9_structural.err"
rc_h9struct=$?
[ "$rc_h9struct" -eq 1 ] \
    && ok "F-H9 control: a template broken independent of any capture (unmatched '(') still refuses at parse time" \
    || no "F-H9 control: a genuinely-always-invalid template loaded (exit $rc_h9struct) — the D9 rule over-relaxed"

# CodeRabbit on #283: the interval deferral needs a backreference. `{2,1}` with no \1..\9 anywhere is out of order
# for every edge, so the rules file is refused at load even though its FROM side matches no file in the tree (a
# deferred rule would sit loaded and silently inert). The \1 template above is the control that still defers.
cat >"$TMP/h9_nobackref.txt" <<'EOF'
deny path nosuchdir/never\.cpp -> render/shader\.h{2,1}
EOF
"$BIN" . --arch="$TMP/h9_nobackref.txt" --no-cache >"$TMP/h9_nobackref.out" 2>"$TMP/h9_nobackref.err"
rc_h9nob=$?
[ "$rc_h9nob" -eq 1 ] && [ ! -s "$TMP/h9_nobackref.out" ] \
    && ok "F-H9: an out-of-order interval with NO backreference ({2,1}) refuses the rules file at load (exit 1), though no FROM path matches" \
    || no "F-H9: {2,1} without a backreference loaded (exit $rc_h9nob) — a rule no capture can make valid sits inert"

[ ! -s "$TMP/h9_structural.out" ] \
    && ok "F-H9 control: no XML emitted on the parse-time refusal" \
    || no "F-H9 control: XML emitted alongside the parse-time refusal"

# ── summary ───────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
