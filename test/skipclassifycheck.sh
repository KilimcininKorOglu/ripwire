#!/usr/bin/env bash
# skipclassifycheck.sh — test/pargates.py's SKIPPED-vs-PASSED classification is a function of the gate's
# VERDICTS, not of where the checkout happens to live on disk.
#
# WHY THIS GATE EXISTS — the red it was written from (2026-09-13).
# The harness classified a gate as skipped with
#     skipped = rc == 0 and "SKIP" in out[:400]
# — a fixed byte window over the transcript. Every gate in this tree opens with a banner naming its own
# absolute paths (`<name>: BIN=<abs>  ROOT=<abs>`) — 515 of the 628 transcripts in one full run carry the
# crawl root in their FIRST line — so for those the window's CONTENTS are a function of the checkout's
# path length, and every offset after the banner moves with it. The window was 400 CHARACTERS of decoded
# text, not bytes: the harness decodes the capture (`raw.decode("utf-8","replace")`) and slices the str
# afterwards, so any offset quoted against it has to be in code points too. Measured on
# test/w3fixlegendcheck.sh, whose transcript is byte-identical after line 1 at both paths:
#     an 87-char worktree root (a checkout nested under .claude/worktrees/)   banner 217 B
#     a 12-char root (the same tree reached through a short symlink)         banner  67 B
# — a 150 B shift from a 75-char rename, ~2 B per character, because the root is spelled twice. A gate
# whose first skip row lands near byte 400 is therefore classified one way in one checkout and the other
# way in another, on the SAME commit, with the SAME binary and byte-identical gate output. That is what
# was observed: `skip=2` from a 137-char worktree and `skip=3` from a 38-char checkout on 3c191bdf, a
# commit on lane/recent-scope and NOT on main, differing only in how w3fixlegendcheck's honest arm-level
# tie SKIP fell relative to the window. Reproduced on that tree, same binary, arm output byte-identical
# after line 1: at a 38-char root the tie row starts at 308 and the old rule called it SKIP; at a 138-char
# root it starts at 408 and the old rule called it PASS — it straddles the window by 8 bytes. On main the
# same arm does NOT tie (N=3 passes), so the symptom cannot be shown there at any path length, and an
# absolute offset quoted anywhere in this file belongs to a NAMED tree rather than to the gate.
#
# It is not one gate's curiosity, and the dangerous direction is the other one. Measured over all 628
# transcripts of one full suite run on main: 24 gates print a skip MARKER downstream of at least one
# absolute-root mention — 28 by the bare substring the old rule actually looked for, the four extra being
# gates that only narrate the word — so their classification moves with the checkout. The nearest is a REAL
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
# The nearest gate-side contract is test/gateexitcheck.sh arm (D) ("skip is not pass": a skip prints a skip
# marker and a reason and NO failure marker) — but it holds LESS than the rule above, because it flags an
# `exit 0` only where both a skip word and "ALL PASS" appear within three lines of it, and so does not police
# marker ORDER at all. This is the harness side of it. The sibling gate for
# test/pargates.py's budget/stop/stdout mechanisms is test/pargatescheck.sh, and this gate follows its
# house pattern: run the REAL pargates.py over a synthetic corpus, never a reimplementation of its logic.
#
# ARMS
#   (0) FIXTURE CONTRAST — the two corpus roots really do straddle the old 400-character boundary: the SAME
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
#  (D2) A FAIL MARKER IS A VERDICT TOO, WHEREVER IT SITS — a gate that prints a FAIL row, then a SKIP row,
#       and still exits 0 claimed a verdict before it skipped, so it is not "proved nothing". Reds when the
#       failure marker is matched against the whole transcript as one line instead of per line.
#   (E) THE SANCTIONED SKIPS STILL SKIP — the two shapes this tree actually ships must not regress:
#       argvdiffcheck's (the skip is the opening line, nothing else runs) and namingcalibrationcheck's
#       (a skip banner up front, then an instrument arm that still prints PASS rows). The second is the
#       load-bearing one: a rule that only counted gates with NO pass rows would silently stop counting
#       it, which is the green-while-inert failure this whole mechanism exists to prevent.
#   (F) DETERMINISM — the same corpus classified twice is classified the same way.
#   (G) STATIC: NO RULER — the classification is a named function of (rc, out), and no fixed-size prefix
#       slice survives in it OR AT ITS CALL SITE. A window reintroduced as out[:800] would pass every arm
#       above on this fixture and red here. The call site is checked because scoping the rule to the
#       function's own body leaves `classify_skipped(rc, out[:800])` passing a gate that claims no ruler
#       survives anywhere.
#   (I) AN NDEBUG SKIP FROM A BUILD WITHOUT NDEBUG IS A FAILURE (2026-09-16) — DISCLOSE is compiled out
#       only where NDEBUG is defined, and CMake defines it for the Release / RelWithDebInfo / MinSizeRel build
#       types that --version names. A gate that skips an alert arm "because alerts are compiled out" on any other
#       flavour asserted nothing and said something false about why. Three gates did exactly that on every plain
#       run after e7688981 turned their `--since=notadate` probe into a refusal (churnjoincheck G2,
#       preproccondcheck, w3fixlegendcheck arm 6), and the suite stayed green because an arm-level skip inside a
#       passing gate is a pass. The harness now reads the build type once and FAILS such a gate, whole-gate or
#       arm-level. Pinned both ways (a Release binary makes the same transcripts honest), against a control
#       whose skip blames something else, and with the DISARMED disclosure when no build type can be read.
#
# WHAT THIS GATE DOES NOT HOLD. The rule counts a WHOLE-GATE skip that prints any PASS row before its skip
# marker as a PASS — it is indistinguishable in a transcript from a gate that proved an arm and then skipped
# one. No gate does that today and arm (E) pins the two sanctioned shapes, but nothing ENFORCES the
# convention: a gate that grew a `  PASS  fixture present` row above its skip banner would flip from skip to
# pass silently. Enforcing it needs a static sweep of every gate's skip path, which belongs in
# test/gateexitcheck.sh beside arm (D) rather than here; until then the convention is unenforced and said so.
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

TMP="$( mktemp -d )"
# THE FIXTURE BRINGS ITS OWN PATH LENGTHS. Both roots below are built under a base of this gate's own
# making, never under $TMPDIR, and the long one is padded to a computed total — because the property under
# test IS path length, and a fixture that inherits it from the runner is a fixture that changes between
# runners. Measured slope on this gate's probe: the skip row starts at 177 + 2*len(root) CHARACTERS of decoded
# text — 181 + 2*len(root) in bytes, the 4 being the box-drawing rule in the row above it (the root is
# spelled twice in the banner), so the old 400-character boundary sits at a 112-character root. Inheriting $TMPDIR
# would have put the short root at 22 characters on a Linux runner and 52 on a macOS one and the long root
# at 153 and 183 — all four on the correct sides today, and all four a $TMPDIR change away from not being.
SHORTBASE="$( mktemp -d /tmp/rwskipXXXXXX )" || { echo "cannot create a short fixture base under /tmp — this gate measures PATH LENGTH and cannot conclude without one"; exit 2; }
[ -d "$SHORTBASE" ] || { echo "mktemp reported success but $SHORTBASE is not a directory — cannot conclude"; exit 2; }
trap 'rm -rf "$TMP" "$SHORTBASE"' EXIT
LONGTARGET=200                                       # comfortably past the 110-character boundary
padLen=$(( LONGTARGET - ${#SHORTBASE} - 1 ))
[ "$padLen" -lt 1 ] && padLen=1
[ "$padLen" -gt 200 ] && padLen=200                  # stay inside the 255-byte single-component limit
PAD="$( printf 'd%.0s' $( seq 1 "$padLen" ) )"
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

# ── (0) FIXTURE CONTRAST: the two roots straddle the old 400-character boundary ──────────────────────────
SHORTROOT="$SHORTBASE/s"
LONGROOT="$SHORTBASE/$PAD"
mkprobe "$SHORTROOT" probepathshiftgate "$TMP/body_passfirst"
mkprobe "$LONGROOT"  probepathshiftgate "$TMP/body_passfirst"

cmp -s "$SHORTROOT/test/probepathshiftgate.sh" "$LONGROOT/test/probepathshiftgate.sh" \
    && ok "(0) the two probes are byte-identical — only the path they are RUN from differs" \
    || no "(0) the two probe scripts differ in content; the arms below could not attribute a difference to the path"

# CHARACTERS, not bytes, and the distinction is load-bearing: the old classifier decoded the transcript and
# THEN sliced it (`out = raw.decode("utf-8","replace")` followed by `out[:400]`), so its ruler was 400 code
# points of decoded text. This suite prints box-drawing rules and em dashes liberally — this probe's own
# leading rows carry 6 bytes of them — so a byte offset compared against that threshold is a unit error.
skipoffset(){ bash "$1" 2>&1 | python3 -c 'import sys; print(sys.stdin.buffer.read().decode("utf-8","replace").find("  SKIP  "))'; }
offShort="$( skipoffset "$SHORTROOT/test/probepathshiftgate.sh" )"
offLong="$(  skipoffset "$LONGROOT/test/probepathshiftgate.sh" )"
if [ "$offShort" -ge 0 ] && [ "$offShort" -lt 400 ] && [ "$offLong" -ge 400 ]; then
    ok "(0) fixture contrast is real: the SAME probe's skip row starts at character $offShort from the short root and $offLong from the long one — opposite sides of the old 400-CHARACTER window (decoded text, which is what out[:400] sliced)"
else
    no "(0) fixture does not straddle the old boundary (short=$offShort chars at a ${#SHORTROOT}-char root, long=$offLong chars at a ${#LONGROOT}-char one; want short<400<=long) — raise LONGTARGET above the boundary this gate computes (177 + 2*len(root) characters = 400 at a 112-char root), or arm (A) proves nothing"
fi

# ── the harness's own answer, read machine-readably ──────────────────────────────────────────────────────
classify(){         # classify <corpus-root> <probe-name> [binary] -> "skip" | "pass" | "fail:<rc>" | "absent"
    local j="$TMP/j.$$.json"
    python3 "$PARGATES" "$1" "${3:-$FAKEBIN}" --only "$2" --json "$j" >/dev/null 2>&1
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
    ok "(A) byte-identical output, two checkout paths, ONE verdict: $vShort both times (skip row at $offShort / $offLong characters)"
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

# ── (D2) A FAIL MARKER IS A VERDICT TOO, WHEREVER IT SITS ──────────────────────────────────
# The rule says the first verdict decides, and FAIL is a verdict. (D) covers the rc != 0 case; this arm
# covers the one that hides: a gate that prints a FAIL row, then a SKIP row, and still exits 0. That gate
# is broken in the way test/gateexitcheck.sh exists to catch, but the classifier must not ALSO mislabel it
# as "proved nothing" — it claimed a verdict before it skipped, and its transcript says so.
#
# The probe deliberately does NOT print "SOME CHECKS FAILED": that is the one alternative in the shared
# failure-marker expression which carries no anchor, so a probe that printed it would be matched by
# accident and this arm would pass without testing anything (CONTRIBUTING shape 5, no contrast). What is
# left is a bare `  FAIL  ` row on a later line — visible only if that expression matches per LINE.
cat > "$TMP/body_failthenskip" <<'BODY'
printf '  FAIL  (3) the assertion that matters did not hold\n'
printf '  SKIP  an optional arm did not run here\n'
BODY
mkprobe "$ORDERROOT" probefailthenskipgate "$TMP/body_failthenskip"
vFailFirst="$( classify "$ORDERROOT" probefailthenskipgate )"
[ "$vFailFirst" = "pass" ] \
    && ok "(D2) a FAIL row on a later line is seen: a gate that claimed a verdict before it skipped is not counted as having proved nothing" \
    || no "(D2) a gate whose first verdict is a FAIL row was classified '$vFailFirst' — the failure marker is being matched against the whole transcript as ONE line, so any FAIL below the first is invisible to the rule"

# ── (H) THE SKIP'S REASON SURVIVES THE STORED REPORT ─────────────────────────────────────────────────────
# Classification reads the WHOLE transcript; the report kept for the SKIPPED section is a fixed prefix of it
# (`out[:2000]`). Those two windows disagree for any gate whose declaration sits past that prefix: the gate
# is correctly counted as skipped, and then listed with NO reason, which is the one thing the SKIPPED
# section exists to print. "ran, but proved nothing" with the why missing is a row nobody can act on.
#
# This arm reads pargates' OWN SKIPPED section rather than the --json verdict, because the verdict is right
# in both worlds and only the printed row is wrong. The probe pads with narration carrying no verdict marker
# — not a PASS row, not "SOME CHECKS FAILED" — so the first marker in its transcript really is the SKIP.
python3 - "$ORDERROOT" <<'PYMAKE'
import os, sys
root = sys.argv[ 1 ]
os.makedirs( os.path.join( root, "test" ), exist_ok=True )
pad = "\n".join( "probelatereason: narration line %03d, carrying no verdict marker of any kind" % i for i in range( 40 ) )
body = ( '#!/usr/bin/env bash\n'
         'PROOT="$( cd "$( dirname "$0" )/.." && pwd )"\n'
         'printf "probelatereason: BIN=%s/build/ripwire  ROOT=%s\\n" "$PROOT" "$PROOT"\n'
         "cat <<'NARRATION'\n" + pad + "\nNARRATION\n"
         "printf '  SKIP  no RIPWIRE_BASE reference binary — this is the declaration the summary must quote\\n'\n" )
path = os.path.join( root, "test", "probelatereason.sh" )
open( path, "w" ).write( body )
os.chmod( path, 0o755 )
PYMAKE
lateOff="$( bash "$ORDERROOT/test/probelatereason.sh" 2>&1 | python3 -c 'import sys; print(sys.stdin.buffer.read().decode("utf-8","replace").find("  SKIP  "))' )"
if [ "$lateOff" -gt 2000 ]; then
    ok "(H) fixture is real: the probe's declaration sits at character $lateOff, past the 2000-character report window"
else
    no "(H) probe declaration at $lateOff is INSIDE the 2000-character report window — lengthen the narration or this arm proves nothing"
fi
lateOut="$( python3 "$PARGATES" "$ORDERROOT" "$FAKEBIN" --only probelatereason 2>&1 )"
lateRow="$( printf '%s\n' "$lateOut" | grep -A2 '^SKIPPED' | grep 'probelatereason' || true )"
printf '%s' "$lateRow" | grep -q 'no RIPWIRE_BASE reference binary' \
    && ok "(H) the SKIPPED row quotes the gate's own declaration even though it sits past the stored report's window" \
    || no "(H) the SKIPPED row lost its reason (row: '$lateRow') — the gate is counted as having proved nothing, with nothing said about why"

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

# The CALL SITE too. A body with no slice in it still gets a ruler if its caller hands it one, so scoping this
# arm to the function would leave `classify_skipped( rc, out[ : 800 ] )` passing a gate whose own header claims
# no fixed-size prefix survives ANYWHERE. Every argument of every call must be a bare name, never a subscript.
calls = [ n for n in ast.walk( tree )
          if isinstance( n, ast.Call ) and isinstance( n.func, ast.Name ) and n.func.id == "classify_skipped" ]
if not calls:
    print( "  FAIL  (G) nothing calls classify_skipped() — the rule is defined but unreachable, so no arm above tested the shipped path" )
    sys.exit( 1 )
sliced = sorted( { ast.get_source_segment( src, a ) or "<arg>"
                   for c in calls for a in c.args if isinstance( a, ast.Subscript ) } )
if sliced:
    print( "  FAIL  (G) a call to classify_skipped() slices its argument (%s) — the ruler moved from the function to its caller" % ", ".join( sliced ) )
    sys.exit( 1 )
print( "  PASS  (G) classify_skipped() is a documented function of (rc, out) with no fixed-size prefix slice in it, and its %d call site(s) hand it the transcript whole" % len( calls ) )
PYEOF
[ $? -eq 0 ] || fail=1

# ── (I) AN NDEBUG SKIP FROM A BUILD WITHOUT NDEBUG IS A FAILURE ──────────────────────────────────────────
# Two fake binaries that differ ONLY in the build type their --version names, and the same probes run under both:
# whatever flips between them is the build type's doing. The arm-level probe's skip row is the line
# preproccondcheck printed on every plain run before 2026-09-16, byte for byte.
mkversionbin(){     # mkversionbin <path> <build-type>
    printf '#!/usr/bin/env bash\nif [ "${1:-}" = --version ]; then echo "ripwire 0.0.0 (%s, probe)"; fi\ntrue\n' "$2" > "$1"
    chmod +x "$1"
}
DEVBIN="$TMP/devbin";  mkversionbin "$DEVBIN" dev
RELBIN="$TMP/relbin";  mkversionbin "$RELBIN" Release
{ "$DEVBIN" --version | grep -q '(dev,' && "$RELBIN" --version | grep -q '(Release,' && [ -z "$( "$FAKEBIN" --version )" ]; } \
    && ok "(I) fixture: the dev and Release fake binaries name their build types, and the plain fake names none" \
    || no "(I) fixture: the fake binaries do not print the build types this arm depends on — every (I) row below proves nothing"

cat > "$TMP/body_ndebugarm" <<'BODY'
printf '  PASS  600-deep guard stack: exits 0 (degrades, does not fail)\n'
printf '  SKIP  600-deep guard stack: DISCLOSE compiled out of this binary (NDEBUG); the plain-flavour leg proves it\n'
printf 'probe: ALL PASS\n'
BODY
cat > "$TMP/body_ndebugwhole" <<'BODY'
printf '  SKIP  G2: alerts are compiled out on this build — the alert arm cannot observe anything\n'
BODY
cat > "$TMP/body_otherskip" <<'BODY'
printf '  PASS  instrument: the hand-derived answer reproduces\n'
printf '  SKIP  no RIPWIRE_BASE reference binary — nothing was compared\n'
printf 'probe: ALL PASS\n'
BODY
mkprobe "$ORDERROOT" probendebugarmgate   "$TMP/body_ndebugarm"
mkprobe "$ORDERROOT" probendebugwholegate "$TMP/body_ndebugwhole"
mkprobe "$ORDERROOT" probeotherskipgate   "$TMP/body_otherskip"

vArmDev="$( classify "$ORDERROOT" probendebugarmgate "$DEVBIN" )"
[ "$vArmDev" = "fail:1" ] \
    && ok "(I) an ARM-level 'compiled out (NDEBUG)' skip inside a passing gate FAILS on a dev build" \
    || no "(I) an arm-level NDEBUG skip on a dev build was classified '$vArmDev', want fail:1 — the shape that hid three dead alert arms still reads as green"
vWholeDev="$( classify "$ORDERROOT" probendebugwholegate "$DEVBIN" )"
[ "$vWholeDev" = "fail:1" ] \
    && ok "(I) a WHOLE-gate 'compiled out' skip FAILS on a dev build (a skip is not the escape hatch)" \
    || no "(I) a whole-gate 'compiled out' skip on a dev build was classified '$vWholeDev', want fail:1"
vArmRel="$( classify "$ORDERROOT" probendebugarmgate "$RELBIN" )"
vWholeRel="$( classify "$ORDERROOT" probendebugwholegate "$RELBIN" )"
{ [ "$vArmRel" = "pass" ] && [ "$vWholeRel" = "skip" ]; } \
    && ok "(I) the SAME two transcripts from a Release binary are honest: arm-level pass, whole-gate skip" \
    || no "(I) on a Release binary the probes were classified arm='$vArmRel' whole='$vWholeRel', want pass/skip — the check fires on the flavour that really compiles alerts out"
vOtherDev="$( classify "$ORDERROOT" probeotherskipgate "$DEVBIN" )"
[ "$vOtherDev" = "pass" ] \
    && ok "(I) control: a dev-build skip that blames something ELSE (no reference binary) is untouched — the check reads the reason, not the word SKIP" \
    || no "(I) control: an unrelated arm-level skip on a dev build was classified '$vOtherDev', want pass — the check is failing every skip"

ndOut="$( python3 "$PARGATES" "$ORDERROOT" "$DEVBIN" --only probendebugarmgate 2>&1 )"
printf '%s\n' "$ndOut" | grep -A12 '^FAILURES' | grep -q "build type 'dev'" \
    && printf '%s\n' "$ndOut" | grep -A12 '^FAILURES' | grep -qF 'DISCLOSE compiled out of this binary (NDEBUG)' \
    && ok "(I) the FAILURES report names the build type and quotes the offending skip row" \
    || { no "(I) the FAILURES report for an NDEBUG skip on a dev build does not name the build type and quote the row:"; printf '%s\n' "$ndOut" | grep -A8 '^FAILURES' | sed 's/^/        /'; }

vArmNone="$( classify "$ORDERROOT" probendebugarmgate "$FAKEBIN" )"
noneOut="$( python3 "$PARGATES" "$ORDERROOT" "$FAKEBIN" --only probendebugarmgate 2>&1 )"
{ [ "$vArmNone" = "pass" ] && printf '%s\n' "$noneOut" | grep -q '^ndebug-skip check: DISARMED'; } \
    && ok "(I) a binary whose --version names no build type leaves the verdict alone and says the check is DISARMED" \
    || no "(I) no build type: classified '$vArmNone' / disclosure: '$( printf '%s\n' "$noneOut" | grep 'ndebug-skip' )' — want pass plus a DISARMED line, never a guess in either direction"

[ "$fail" -eq 0 ] && echo "skipclassifycheck: ALL PASS" || { echo "skipclassifycheck: SOME CHECKS FAILED"; exit 1; }
