#!/usr/bin/env bash
# skipclassifycheck.sh — test/pargates.py's SKIPPED-vs-PASSED classification is a function of the gate's
# VERDICTS, not of where the checkout happens to live on disk.
#
# WHY THIS GATE EXISTS — the red it was written from (2026-09-13).
# The harness classified a gate as skipped with
#     skipped = rc == 0 and "SKIP" in out[:400]
# — a fixed byte window over the transcript. Every gate in this tree opens with a banner naming its own
# absolute paths (`<name>: BIN=<abs>  ROOT=<abs>`, 506 gates print one), so the window's CONTENTS are a
# function of the checkout's path length, and every offset after the banner moves with it. Measured on
# test/w3fixlegendcheck.sh, whose transcript is byte-identical after line 1 at both paths:
#     an 87-char worktree root (a checkout nested under .claude/worktrees/)   banner 217 B
#     a 12-char root (the same tree reached through a short symlink)         banner  67 B
# — a 150 B shift from a 75-char rename, ~2 B per character, because the root is spelled twice. A gate
# whose first skip row lands near byte 400 is therefore classified one way in one checkout and the other
# way in another, on the SAME commit, with the SAME binary and byte-identical gate output. That is what
# was observed: `skip=2` from a 137-char worktree and `skip=3` from a 38-char checkout, differing only in
# how w3fixlegendcheck's honest arm-level tie SKIP fell relative to the window.
#
# It is not one gate's curiosity, and the dangerous direction is the other one. Measured over all 628
# transcripts of one full suite run on this tree: 28 gates print their skip marker downstream of at least
# one absolute-root mention, so their classification moves with the checkout. The nearest is a REAL
# standing skip — editchecknotecheck declares its skip at byte 145, and 255 more characters of checkout
# path (a 342-char root, ordinary for a nested worktree or a CI runner) push that declaration out of the
# window, at which point a gate that proved nothing is reported as a PASS. Which gates are in range is a
# property of the MACHINE, not of the commit. The window's test was also a bare SUBSTRING, so five gates
# that merely NARRATE the word SKIPPED (doctorcheck, formatgatecheck, headbinstagecheck, mcpreadloopcheck,
# releaseinstallcheck) are counted as having proved nothing whenever the prose falls inside it.
#
# `skip=` is read before every push — a suite summary that can report the same gate two ways on the same
# commit is not evidence. So the harness stops measuring position and reads the verdicts instead:
#
#     A GATE THAT PROVES NOTHING SAYS SO BEFORE IT CLAIMS ANYTHING. The gate's FIRST verdict marker
#     decides: a SKIP marker ahead of every PASS and FAIL marker is a WHOLE-GATE skip (it announced up
#     front that it would asserted nothing); a SKIP marker that follows one is an ARM-level skip inside a
#     gate that did prove something, and the gate is a pass.
#
# That is the rule the tree already followed, written down and made positional-free: namingcalibration-
# check.sh runs its live arm FIRST "so that its SKIP banner lands inside the first bytes of output", and
# argvdiffcheck.sh's skip is its opening line. Their classification is unchanged. Measured over the same
# 628 transcripts, the new rule and the old one disagree on ZERO gates — it reproduces today's answers on
# this tree exactly, and stops depending on the tree's pathname to do it.
#
# The gate side of the same contract is test/gateexitcheck.sh arm (D) ("skip is not pass": a skip prints a
# skip marker and a reason and NO failure marker). This is the harness side of it. The sibling gate for
# test/pargates.py's budget/stop/stdout mechanisms is test/pargatescheck.sh, and this gate follows its
# house pattern: run the REAL pargates.py over a synthetic corpus, never a reimplementation of its logic.
#
# ARMS
#   (0) FIXTURE CONTRAST — the two corpus roots really do straddle the old 400 B boundary: the SAME probe
#       gate's first skip row lands under 400 at the short root and over it at the long one. Without this
#       the path-independence arm below is a control whose two halves differ in nothing (CONTRIBUTING's
#       shape 5), and would pass on a classifier that never looked at the output at all.
#   (A) PATH INDEPENDENCE — that same probe, classified by the REAL harness from both roots, gets the SAME
#       verdict. THIS IS THE RED: on the byte-window classifier the short root says skip and the long root
#       says pass. It also pins WHICH verdict: the probe prints a PASS row before its SKIP row, so it
#       proved something and is a pass.
#   (B) THE RULE, BOTH DIRECTIONS — skip-first is classified SKIP, pass-first is classified PASS. Two
#       probes identical but for the ORDER of their two verdict rows, so nothing else can explain the
#       difference.
#   (C) PROSE IS NOT A VERDICT — a gate whose narration contains the word SKIPPED, and whose only verdicts
#       are PASS rows, is a pass. The substring test counts it as having proved nothing.
#   (D) A FAILING GATE IS NEVER A SKIP — rc != 0 outranks any marker (a red that printed a skip row is a
#       FAILURE, and must appear under FAILURES with its report).
#   (E) THE SANCTIONED SKIPS STILL SKIP — the two shapes this tree actually ships must not regress:
#       argvdiffcheck's (the skip is the opening line, nothing else runs) and namingcalibrationcheck's
#       (a skip banner up front, then an instrument arm that still prints PASS rows). The second is the
#       load-bearing one: a rule that only counted gates with NO pass rows would silently stop counting
#       it, which is the green-while-inert failure this whole mechanism exists to prevent.
#   (F) DETERMINISM — the same corpus classified twice is classified the same way.
#   (G) STATIC: NO RULER — the classification is a named function of (rc, out), and no fixed-size prefix
#       slice survives anywhere in it. A window reintroduced as out[:800] would pass every arm above on
#       this fixture and red here.
#
# Usage: bash test/skipclassifycheck.sh   (no ripwire binary needed — this tests test/pargates.py)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
PARGATES="$ROOT/test/pargates.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$PARGATES" ] || { echo "no test/pargates.py at $PARGATES"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

echo "skipclassifycheck: PARGATES=$PARGATES"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FAKEBIN="$TMP/fakebin"; printf '#!/usr/bin/env bash\ntrue\n' > "$FAKEBIN"; chmod +x "$FAKEBIN"

# ── the probes ───────────────────────────────────────────────────────────────────────────────────────────
# Every probe opens with the banner shape a real gate prints — the gate's own name, then its root spelled
# TWICE — because that banner is the mechanism under test: its length, and so every offset after it, is a
# property of where the corpus sits on disk and of nothing else.
mkprobe(){          # mkprobe <corpus-root> <probe-name> <body-file>
    mkdir -p "$1/test"
    { printf '#!/usr/bin/env bash\nPROOT="$( cd "$( dirname "$0" )/.." && pwd )"\n'
      printf 'printf "%%s: BIN=%%s/build/ripwire  ROOT=%%s\\n" "%s" "$PROOT" "$PROOT"\n' "$2"
      cat "$3"
    } > "$1/test/$2.sh"
    chmod +x "$1/test/$2.sh"
}

# pass-first: an arm that asserted something, THEN an arm-level skip — w3fixlegendcheck's shape in
# miniature. The skip row is deliberately the width a real one is, so its start offset is realistic.
cat > "$TMP/body_passfirst" <<'BODY'
printf '\xe2\x94\x80\xe2\x94\x80 1. partition root counters\n'
printf '  PASS  N=2: shared/union (7/75) == overlap_mean (0.093) — the pairwise identity the legend claims\n'
printf '  SKIP  N=3: shared/union == overlap_mean (TIE) — at this N the two readings select the SAME set, so this corpus cannot tell them apart. Refutes nothing; asserts nothing.\n'
printf '  PASS  N=4: shared/union (29/161) is strictly ABOVE overlap_mean (0.061)\n'
printf 'probe: ALL PASS\n'
BODY

# skip-first: the whole-gate skip — it announces up front that it will assert nothing.
cat > "$TMP/body_skipfirst" <<'BODY'
printf '  SKIP  no RIPWIRE_BASE reference binary — nothing was compared\n'
printf '  (set RIPWIRE_BASE=build_base/ripwire after building the pre-change source to activate)\n'
BODY

# ── (0) FIXTURE CONTRAST: the two roots straddle the old 400 B boundary ──────────────────────────────────
SHORTROOT="$TMP/s"
LONGDIR="$( printf 'deeply_nested_checkout_directory_%.0s' 1 2 3 4 )"      # ~132 chars of path
LONGROOT="$TMP/$LONGDIR"
mkprobe "$SHORTROOT" probepathshiftgate "$TMP/body_passfirst"
mkprobe "$LONGROOT"  probepathshiftgate "$TMP/body_passfirst"

cmp -s "$SHORTROOT/test/probepathshiftgate.sh" "$LONGROOT/test/probepathshiftgate.sh" \
    && ok "(0) the two probes are byte-identical — only the path they are RUN from differs" \
    || no "(0) the two probe scripts differ in content; the arms below could not attribute a difference to the path"

skipoffset(){ bash "$1" 2>&1 | python3 -c 'import sys; print(sys.stdin.buffer.read().find(b"  SKIP  "))'; }
offShort="$( skipoffset "$SHORTROOT/test/probepathshiftgate.sh" )"
offLong="$(  skipoffset "$LONGROOT/test/probepathshiftgate.sh" )"
if [ "$offShort" -ge 0 ] && [ "$offShort" -lt 400 ] && [ "$offLong" -ge 400 ]; then
    ok "(0) fixture contrast is real: the SAME probe's skip row starts at byte $offShort from the short root and $offLong from the long one — opposite sides of the old 400 B window"
else
    no "(0) fixture does not straddle the old boundary (short=$offShort, long=$offLong; want short<400<=long) — lengthen the long root or widen the probe's leading rows, or arm (A) proves nothing"
fi

# ── the harness's own answer, read machine-readably ──────────────────────────────────────────────────────
classify(){         # classify <corpus-root> <probe-name> -> "skip" | "pass" | "fail:<rc>" | "absent"
    local j="$TMP/j.$$.json"
    python3 "$PARGATES" "$1" "$FAKEBIN" --only "$2" --json "$j" >/dev/null 2>&1
    python3 - "$j" "$2.sh" <<'PYEOF'
import json, sys
try:
    d = json.load( open( sys.argv[ 1 ] ) )
except Exception:
    print( "absent" ); raise SystemExit
r = d.get( sys.argv[ 2 ] )
if r is None:
    print( "absent" )
elif r[ "rc" ] != 0:
    print( "fail:%s" % r[ "rc" ] )
else:
    print( "skip" if r[ "skipped" ] else "pass" )
PYEOF
    rm -f "$j"
}

# ── (A) PATH INDEPENDENCE — the red ──────────────────────────────────────────────────────────────────────
vShort="$( classify "$SHORTROOT" probepathshiftgate )"
vLong="$(  classify "$LONGROOT"  probepathshiftgate )"
if [ "$vShort" = "$vLong" ]; then
    ok "(A) byte-identical output, two checkout paths, ONE verdict: $vShort both times (skip row at $offShort B / $offLong B)"
else
    no "(A) the SAME gate output is classified '$vShort' from a $( printf '%s' "$SHORTROOT" | wc -c | tr -d ' ' )-char root and '$vLong' from a $( printf '%s' "$LONGROOT" | wc -c | tr -d ' ' )-char one — the verdict is a function of the pathname, not of what the gate proved"
fi
[ "$vShort" = "pass" ] && [ "$vLong" = "pass" ] \
    && ok "(A) and the verdict is PASS: the probe asserted an arm before it skipped one, so it proved something" \
    || no "(A) a gate that printed a PASS row before its arm-level SKIP was not classified pass (short=$vShort long=$vLong) — an arm-level skip is not a whole-gate skip"

# ── (B) THE RULE, BOTH DIRECTIONS ────────────────────────────────────────────────────────────────────────
# Same root, same banner, same two rows: only their ORDER differs.
ORDERROOT="$TMP/order"
mkprobe "$ORDERROOT" probeskipfirstgate "$TMP/body_skipfirst"
mkprobe "$ORDERROOT" probepassfirstgate "$TMP/body_passfirst"
vSkipFirst="$( classify "$ORDERROOT" probeskipfirstgate )"
vPassFirst="$( classify "$ORDERROOT" probepassfirstgate )"
[ "$vSkipFirst" = "skip" ] \
    && ok "(B) a SKIP ahead of every PASS/FAIL is a whole-gate skip — 'ran, but proved nothing'" \
    || no "(B) a gate whose first and only verdict is a SKIP was classified '$vSkipFirst' — a skip that reads as a pass is the green-while-inert failure this count exists to catch"
[ "$vPassFirst" = "pass" ] \
    && ok "(B) a SKIP after a PASS is an arm-level skip inside a gate that proved something" \
    || no "(B) a gate that proved arms and skipped one was classified '$vPassFirst'"

# ── (C) PROSE IS NOT A VERDICT ───────────────────────────────────────────────────────────────────────────
cat > "$TMP/body_prose" <<'BODY'
printf '=== (f) empty and whitespace-only lines are SKIPPED, exactly as before ===\n'
printf '  PASS  the reader skips blank frames without dropping the next one\n'
printf 'probe: ALL PASS\n'
BODY
mkprobe "$ORDERROOT" probeprosegate "$TMP/body_prose"
vProse="$( classify "$ORDERROOT" probeprosegate )"
[ "$vProse" = "pass" ] \
    && ok "(C) a gate that only NARRATES the word SKIPPED, and whose verdicts are all PASS, is a pass" \
    || no "(C) prose containing 'SKIPPED' classified the gate '$vProse' — the classifier is matching a substring, not a verdict"

# ── (D) A FAILING GATE IS NEVER A SKIP ───────────────────────────────────────────────────────────────────
cat > "$TMP/body_redskip" <<'BODY'
printf '  SKIP  an optional arm did not run here\n'
printf '  FAIL  (3) the assertion that matters did not hold\n'
printf 'probe: SOME CHECKS FAILED\n'
exit 1
BODY
mkprobe "$ORDERROOT" probeskipthenfailgate "$TMP/body_redskip"
vRed="$( classify "$ORDERROOT" probeskipthenfailgate )"
[ "$vRed" = "fail:1" ] \
    && ok "(D) a gate that exited non-zero is a FAILURE however it narrated itself — rc outranks every marker" \
    || no "(D) a red gate was classified '$vRed'"

# ── (E) THE SANCTIONED SKIPS STILL SKIP ──────────────────────────────────────────────────────────────────
# argvdiffcheck's shape: the skip is the opening line and nothing else runs.
cat > "$TMP/body_argvshape" <<'BODY'
printf 'probeopeningskipgate: SKIP — no RIPWIRE_BASE reference binary\n'
printf '  (set RIPWIRE_BASE=build_base/ripwire after building the pre-change source to activate)\n'
BODY
mkprobe "$ORDERROOT" probeopeningskipgate "$TMP/body_argvshape"
vOpening="$( classify "$ORDERROOT" probeopeningskipgate )"
[ "$vOpening" = "skip" ] \
    && ok "(E) the '<name>: SKIP — reason' opening line is a whole-gate skip (argvdiffcheck's shape)" \
    || no "(E) argvdiffcheck's shape was classified '$vOpening' — the tree's sanctioned skip would start reading as a pass"

# namingcalibrationcheck's shape: a skip banner up front, then an instrument arm that still prints PASSes.
# The live judgement was withheld; the gate is a skip DESPITE the pass rows that follow.
cat > "$TMP/body_bannerthenpass" <<'BODY'
printf 'probebannerskipgate: SKIP — 7 labelled pairs is below the declared floor of 30, so no per-rule proxy is estimable\n'
printf '  (the instrument arm below is still enforced.)\n'
printf '  PASS  (A) instrument: mine -> join -> score reproduces the hand-derived answer\n'
printf 'probebannerskipgate: SKIP stands — instrument arm verified, live judgement withheld\n'
BODY
mkprobe "$ORDERROOT" probebannerskipgate "$TMP/body_bannerthenpass"
vBanner="$( classify "$ORDERROOT" probebannerskipgate )"
[ "$vBanner" = "skip" ] \
    && ok "(E) a skip banner ahead of an instrument arm's PASS rows is still a whole-gate skip (namingcalibrationcheck's shape)" \
    || no "(E) namingcalibrationcheck's shape was classified '$vBanner' — a gate that withheld its judgement would be counted as having made it"

# ── (F) DETERMINISM ──────────────────────────────────────────────────────────────────────────────────────
vAgain="$( classify "$ORDERROOT" probepassfirstgate )"
[ "$vAgain" = "$vPassFirst" ] \
    && ok "(F) the same corpus classified twice gives the same verdict ($vAgain)" \
    || no "(F) two runs of the same corpus disagreed: '$vPassFirst' then '$vAgain'"

# ── (G) STATIC: NO RULER ─────────────────────────────────────────────────────────────────────────────────
# The functional arms above run on ONE fixture. A window widened to out[:800] would satisfy every one of
# them and still be a ruler; only reading the source can say that no fixed prefix decides a verdict.
python3 - "$PARGATES" <<'PYEOF'
import ast, re, sys
src = open( sys.argv[ 1 ] ).read()
tree = ast.parse( src )
fn = next( ( n for n in ast.walk( tree ) if isinstance( n, ast.FunctionDef ) and n.name == "classify_skipped" ), None )
if fn is None:
    print( "  FAIL  (G) test/pargates.py has no classify_skipped() — the rule has no single place to read, and no gate can pin it" )
    sys.exit( 1 )
seg = ast.get_source_segment( src, fn ) or ""
rulers = re.findall( r"\[\s*:\s*\d+\s*\]|\[\s*\d+\s*:", seg )
if rulers:
    print( "  FAIL  (G) classify_skipped() decides on a fixed byte window (%s) — a verdict must not depend on where the checkout lives" % ", ".join( sorted( set( rulers ) ) ) )
    sys.exit( 1 )
if not ast.get_docstring( fn ):
    print( "  FAIL  (G) classify_skipped() states no rule — the reader of skip= has nowhere to learn what it counts" )
    sys.exit( 1 )
print( "  PASS  (G) classify_skipped() is a documented function of (rc, out) with no fixed-size prefix slice in it" )
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && echo "skipclassifycheck: ALL PASS" || { echo "skipclassifycheck: SOME CHECKS FAILED"; exit 1; }
