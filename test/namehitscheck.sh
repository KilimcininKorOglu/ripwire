#!/usr/bin/env bash
# namehitscheck.sh — LB3x/N3 (routing-loop round 3, PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/13_round3_PREREG.md
# §2.1, Amendments 1/1b/1c, approved rv-r3-prereg.md 2026-09-19): the `--for` ranking-to-gold append, with its
# FULL definition moved OFF the top legend and onto a trailing comment after the element.
#
# THE CONTRACT THIS PINS (src/namehits.h, src/verbs_for.h, src/mcpverbs.h):
#   (1) <namehits n="K"><nh p=…/>…</namehits> appears on a default-regime --for answer, and is NEVER inside
#       <tail> (whose shown=/total= count a different population — trimmed rows, not unnamed files). It is
#       the last child of the root EXCEPT when --with-graph is also on — R8's own standing contract
#       (withgraphcheck.sh) is that <graph> sits immediately before </ctx>, predating this lever, so
#       namehits (element + its trailing comment together) rides immediately BEFORE <graph> in that
#       combination and is otherwise the true last child.
#   (2) APPEND-ONLY + DEDUPED: every <nh p=> names a file this SAME answer did not already emit a p= row
#       for (sigs + the deep tail); no existing row is re-ranked or reordered.
#   (3) HONESTY (Q6, round 3): n= is the count actually served (0..3), never padded — fewer than 3
#       qualifying files says so. ZERO qualifying files now emits NOTHING AT ALL: no element, no trailing
#       comment (round 2's self-closed <namehits n="0"/> is gone — superseded by the owner's Q6 answer).
#   (4) DEFINITION (N3): the definition is OUT of the top legend on every posture (CLI full/compact, MCP
#       `for`) and rides instead as ONE XML comment immediately after the element's own end — present iff
#       the element is present, never one without the other, and never inside the top legend.
#   (5) SCOPE: absent under an explicit --token-budget (the ceiling ladder does not price it yet — see
#       namehits.h) and on --json/--format=candidates/--format=columnar (namehits is an XML-bundle-only
#       enrichment, the T3/auto-bodies precedent).
#   (6) RED-FIRST / NO DISPLACEMENT (N3's whole point): everything BEFORE <namehits> is byte-identical to
#       the pre-lever binary's answer for the SAME query, INCLUDING on a query where round 2's binary
#       displaced a ranked row or a legend clause by charging the 205 B header definition into the sig
#       ladder's budget (Amendment 1c #1) — not just the tiny polyglot fixture, where nothing ever got
#       close enough to the ceiling to displace.
#   (7) DETERMINISM: two runs byte-identical (integer scoring, path tie-break — no floating point ever
#       reaches output).
#   (8) PARITY: the formula (name×3 + path×2 BM25, k1=1.2, b=0.75, lb3_sim.py's toks()) matches a python
#       mirror of $ORCH/sim/lb3_sim.py's toks()/bm25_rank(), copied verbatim, on >=10 real queries over
#       this repo's own src/ tree — exact file lists, not just counts.
#   (9) OVER_CEILING (Amendment 1c #2): the element carries ` over_ceiling="1"` iff the pinned code sum —
#       fixedBytes + sigsStr.size() + tailStr.size() + E (the element alone) — exceeds sigSideCeiling
#       (CLI) / forBudgetBytes (MCP); the trailing comment's present-only suffix rides iff the attribute
#       does, on both surfaces, on both dialects (never one without the other — clause 6/honesty).
#
# Usage:  bash test/namehitscheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/namehitscheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
cd "$ROOT" || exit 2
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
# G1 (trap-a-gates-printf-can-fail.md): a failed write must set the accumulator itself — a stdout write
# CAN fail (a full pipe, EINTR), and if ok() only prints, that failure is silent and the gate still exits 0.
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "namehitscheck: BIN=$BIN"

# ── (1)/(2)/(3)/(4) shape, dedup and honesty over the small polyglot fixture ────────────────────────────
out1="$( "$BIN" test/fixture --for='geometry area of a shape' --legend=compact 2>/dev/null )"
case "$out1" in
    *'<namehits n="2"><nh p="geometry.h"/><nh p="geometry.cpp"/></namehits><!--namehits/nh: <=3 unnamed files by name/path word match (not graph evidence); n= shown--></ctx>'*)
        ok "(4) N3: trailing comment (compact wording) rides immediately after the element, right before </ctx>" ;;
    *) no "(4) N3: compact trailing comment missing/misplaced: $( printf '%s' "$out1" | grep -o '<namehits.*' | head -c 220 )" ;;
esac
# (4) the definition must be GONE from the top legend (header comment), every posture — that is N3's whole point.
hdr1="${out1%%<namehits*}"
case "$hdr1" in
    *namehits*) no "(4) N3: the compact TOP LEGEND still mentions namehits — the definition did not move" ;;
    *) ok "(4) N3: compact top legend carries no namehits clause at all" ;;
esac
# (1b) --with-graph: <graph> is R8's own last-child contract (withgraphcheck.sh) and predates this lever —
# namehits (element + its trailing comment, N3) must ride immediately BEFORE <graph>, never after it.
outg="$( "$BIN" test/fixture --for='geometry area of a shape' --with-graph 2>/dev/null )"
case "$outg" in
    *'<namehits n="2"><nh p="geometry.h"/><nh p="geometry.cpp"/></namehits><!--namehits: up to 3 files this answer did not already name, ranked ONLY by how many query words their file name (x3) and directory path (x2) contain (BM25); a lookup, NOT graph evidence; n= shown--><graph '*'</graph></ctx>'*)
        ok "(1b) --with-graph: <namehits> + its trailing comment ride immediately before <graph>, which stays the true last child" ;;
    *) no "(1b) --with-graph: namehits/graph ordering wrong: $( printf '%s' "$outg" | grep -o '<namehits.*graph[^>]*>' | head -c 260 )" ;;
esac
if printf '%s' "$out1" | xmllint --noout - 2>"$TMP/xml1.err"; then
    ok "(1) fixture answer is well-formed XML"
else
    no "(1) fixture answer is NOT well-formed: $( cat "$TMP/xml1.err" )"
fi

out1f="$( "$BIN" test/fixture --for='geometry area of a shape' 2>/dev/null )"
case "$out1f" in
    *'<namehits n="2"><nh p="geometry.h"/><nh p="geometry.cpp"/></namehits><!--namehits: up to 3 files this answer did not already name, ranked ONLY by how many query words their file name (x3) and directory path (x2) contain (BM25); a lookup, NOT graph evidence; n= shown--></ctx>'*)
        ok "(4) N3: trailing comment (full wording) rides immediately after the element, right before </ctx>" ;;
    *) no "(4) N3: full trailing comment missing/misplaced: $( printf '%s' "$out1f" | grep -o '<namehits.*' | head -c 260 )" ;;
esac
hdr1f="${out1f%%<namehits*}"
case "$hdr1f" in
    *namehits*) no "(4) N3: the full TOP LEGEND still mentions namehits — the definition did not move" ;;
    *) ok "(4) N3: full top legend carries no namehits clause at all" ;;
esac

# dedup: geometry.h/geometry.cpp are NOT named by 'geometry area of a shape' (app.py/notes.md rank the
# ranked head there) — geometry.cpp/.h DO score for this query (they are the top namehits picks), so their
# absence from <sigs>/<tail> (everything BEFORE <namehits) and presence INSIDE <namehits> is the dedup
# contract, not coincidence. Anchored to the pre-<namehits prefix specifically — a loose substring test
# would also match the very <nh p="geometry.h"/> row this arm exists to require.
pre1="${out1%%<namehits*}"
if printf '%s' "$pre1" | grep -qE '<[dt][ >][^>]*p="geometry\.(h|cpp)"'; then
    no "(2) fixture 'geometry area of a shape': geometry.h/.cpp are named ELSEWHERE too (before <namehits) — the dedup fixture premise broke, re-pick a query"
else
    ok "(2) geometry.h/geometry.cpp are named ONLY inside <namehits> — dedup holds"
fi

# honesty at n=0 (Q6, round 3): an all-stopword query tokenizes to nothing (lb3_sim.py STOP), so
# rankNameHits returns empty and NOTHING rides — no element, no trailing comment (round 2's self-closed
# <namehits n="0"/> is gone; superseded by the owner's Q6 answer — see namehits.h renderNameHitsXml/
# finishNameHitsXml). Checked on both dialects since the trailing comment is dialect-specific text that
# must also be absent.
out0="$( "$BIN" test/fixture --for='how does the' 2>/dev/null )"
if printf '%s' "$out0" | grep -q namehits; then
    no "(3) Q6: all-stopword query still carries namehits somewhere: $( printf '%s' "$out0" | grep -o '.\{0,40\}namehits.\{0,80\}' )"
else
    ok "(3) Q6: all-stopword query emits NO namehits at all — no element, no trailing comment"
fi
out0c="$( "$BIN" test/fixture --for='how does the' --legend=compact 2>/dev/null )"
if printf '%s' "$out0c" | grep -q namehits; then
    no "(3) Q6 compact: all-stopword query still carries namehits somewhere"
else
    ok "(3) Q6 compact: all-stopword query emits NO namehits at all"
fi
printf '%s' "$out0" | xmllint --noout - >/dev/null 2>&1 && ok "(3) Q6: n=0 answer is still well-formed XML with the element gone" \
                                                          || no "(3) Q6: n=0 answer is not well-formed XML"

# the 3-row cap: a query naming few files leaves >=3 unnamed candidates.
out3="$( "$BIN" test/fixture --for='geometry consumer app' 2>/dev/null )"
n3="$( printf '%s' "$out3" | grep -o '<namehits n="[0-9]*"' | grep -o '[0-9]*' )"
if [ -n "${n3:-}" ] && [ "$n3" -le 3 ]; then
    ok "(3) 'geometry consumer app': n=\"$n3\" (<=3, the honest cap)"
else
    no "(3) 'geometry consumer app': n=\"${n3:-MISSING}\" — expected <=3"
fi

# ── (5) scope: absent under an explicit --token-budget, and on --json/candidates/columnar ────────────────
b1="$( "$BIN" . --for='lexical resolve pattern packtask' --token-budget=1500 2>/dev/null | grep -c namehits )"
if [ "$b1" = 0 ]; then
    ok "(5) --token-budget=1500: no namehits anywhere (the ladder does not price it yet)"
else
    no "(5) --token-budget=1500: namehits leaked in ($b1 hits) — unpriced bytes under an explicit ceiling"
fi
b2="$( "$BIN" . --for='lexical resolve pattern packtask' --json 2>/dev/null | grep -c namehits )"
if [ "$b2" = 0 ]; then ok "(5) --json: no namehits"; else no "(5) --json leaked namehits"; fi
b3="$( "$BIN" . --for='lexical resolve pattern packtask' --format=candidates 2>/dev/null | grep -c namehits )"
if [ "$b3" = 0 ]; then ok "(5) --format=candidates: no namehits"; else no "(5) --format=candidates leaked namehits"; fi

# ── (7) determinism ─────────────────────────────────────────────────────────────────────────────────────
r1="$( "$BIN" . --for='lexical resolve pattern packtask quality' 2>/dev/null )"
r2="$( "$BIN" . --for='lexical resolve pattern packtask quality' 2>/dev/null )"
if [ "$r1" = "$r2" ]; then ok "(7) two runs byte-identical"; else no "(7) two runs DIFFER"; fi

# ── (6) RED-FIRST: byte identity of everything before <namehits>, vs the pre-lever binary ─────────────────
# IN-GATE FIXTURE, not a live second build: test/namehitsfix_base/*.xml are the pre-lever binary's OWN
# output (origin/integration/train-7 @3bd3e8ae, unmodified), captured on a GIT-LESS copy of test/fixture
# (no `at=` commit stamp to go stale — the forrankordercheck.sh precedent) and committed verbatim. A live
# rebuild here cost binoverridecheck.sh's sentinel sweep a timeout (a second full ripwire link on every
# run of a gate this suite runs on every push) for a fact that does not change unless someone re-lands
# this lever — exactly what a committed fixture is for.
FXTMP="$TMP/fixture"; rm -rf "$FXTMP"; cp -R test/fixture "$FXTMP"
for pair in "geometry area of a shape|for_geometry.xml" "call a native function from python|for_call.xml"; do
    q="${pair%%|*}"; fx="${pair##*|}"
    newout="$( cd "$TMP" && "$BIN" fixture --for="$q" 2>/dev/null )"
    baseout="$( cat "test/namehitsfix_base/$fx" )"
    # base carries no namehits at all (RED: the feature did not exist at 3bd3e8ae)
    case "$baseout" in
        *namehits*) no "(6) RED-FIRST '$q': the committed base fixture ALREADY has namehits in it — re-capture it" ;;
        *) ok "(6) RED-FIRST '$q': the pre-lever fixture carries no namehits (genuinely red)" ;;
    esac
    if ! printf '%s' "$newout" | grep -q namehits; then
        # Q6 (round 3): this query's picked list is empty, so N3 appends NOTHING — no element, no header
        # clause, no trailing comment. The strongest honest claim IS available here: the whole document,
        # not just the payload prefix, must be byte-identical to the pre-lever answer.
        if [ "$newout" = "$baseout" ]; then
            ok "(6) '$q': n=0 (Q6) — the WHOLE document is byte-identical to the pre-lever answer"
        else
            no "(6) '$q': n=0 but the document still DIFFERS from the pre-lever answer — something rode anyway"
        fi
    else
        # append-only at the CONTENT level: N3 (round 3) moved the definition OFF the top legend entirely, so
        # on this small fixture the header is now byte-identical too (it never carried a namehits clause to
        # begin with here — see the separate no-displacement arm below for a corpus where round 2's HEADER
        # clause used to shrink the sig budget). The honest claim pinned here is that the PAYLOAD —
        # <sigs>/<lego>/<compose>/<tail>/bodies, everything from the first <sigs> up to (not including)
        # <namehits> — is untouched: no row moved, reordered or changed to make room for the append.
        newpayload="$( printf '%s' "$newout"  | sed 's/.*\(<sigs\)/\1/' )"; newpayload="${newpayload%%<namehits*}"
        basepayload="$( printf '%s' "$baseout" | sed 's/.*\(<sigs\)/\1/' )"; basepayload="${basepayload%</ctx>}"
        if [ "$newpayload" = "$basepayload" ]; then
            ok "(6) '$q': the payload (sigs/tail rows) is byte-identical to the pre-lever answer — append-only"
        else
            no "(6) '$q': the payload DIFFERS from the pre-lever answer — this is not append-only"
        fi
    fi
done
# (6b) other verbs byte-identical (namehits.h touches nothing outside --for's XML bundle path) — a FULL
# document compare, since neither --clones nor --callers carries a header this lever ever touches.
for pair in "--clones|clones.xml" "--callers=area_of_triangle|callers.xml"; do
    v="${pair%%|*}"; fx="${pair##*|}"
    a="$( cd "$TMP" && "$BIN" fixture $v 2>/dev/null )"
    c="$( cat "test/namehitsfix_base/$fx" )"
    if [ "$a" = "$c" ]; then
        ok "(6b) $v: byte-identical to the pre-lever answer"
    else
        no "(6b) $v: DIFFERS from the pre-lever answer"
    fi
done

# ── (6c) NO DISPLACEMENT on a query that DID displace under round 2 — the ceiling correction itself ────────
# The tiny polyglot fixture above never gets close enough to budget_bytes to displace a row, so it cannot
# red/green N3's actual fix (Amendment 1c #1: round 2's 205 B header DEFINITION shrank sigsBudget and
# trimmed a ranked row — clause 3c). This repo's OWN src/ tree, frozen at the round-2 landing commit via
# `git archive` (no extra fixture to commit, no `at=` stamp — archived trees carry no .git), reproduces it:
# round 2's binary (src/verbs_for.h @3cb6aa1b) genuinely displaces content on "hash map open addressing
# probe sequence" (verified live against wt/r2-LB3x's own build while this lever was written — RED evidence
# recorded in $ORCH/reports/r3-n3.md, not re-run here to avoid a second full build on every gate run, the
# same trade-off (6) above documents). test/namehitsfix_base/for_hashmap_prelever.xml is the PRE-LEVER
# binary's (3bd3e8ae) own answer for that query over that SAME frozen tree — the true no-namehits baseline
# clause 3c/(6) demands. est_tokens= is normalized on both sides before comparing: N3 honestly prices the
# appended element (Amendment 1c #1 — no change at the est_tokens fixpoint), so it is EXPECTED to differ,
# and separately asserted to have grown, never shrunk or stayed put with a namehits element attached.
if command -v git >/dev/null 2>&1 && git -C "$ROOT" cat-file -e 3cb6aa1b -- 2>/dev/null; then
    SNAP="$TMP/snap3cb"; rm -rf "$SNAP"; mkdir -p "$SNAP"
    if git -C "$ROOT" archive 3cb6aa1b -- src 2>/dev/null | tar -x -C "$SNAP" 2>/dev/null; then
        ndq="hash map open addressing probe sequence"
        live="$( cd "$SNAP" && "$BIN" src --for="$ndq" 2>/dev/null )"
        base="$( cat "$ROOT/test/namehitsfix_base/for_hashmap_prelever.xml" )"
        python3 - "$live" "$base" <<'PY'
import re, sys
live, base = sys.argv[1], sys.argv[2]
livepay = live.split("<namehits")[0]
base_nostamp = base[:-len("</ctx>")] if base.endswith("</ctx>") else base
live_n = re.sub(r'est_tokens="\d+"', 'est_tokens="X"', livepay)
base_n = re.sub(r'est_tokens="\d+"', 'est_tokens="X"', base_nostamp)
ok = live_n == base_n
live_est = re.search(r'est_tokens="(\d+)"', live)
base_est = re.search(r'est_tokens="(\d+)"', base)
grew = bool(live_est and base_est and int(live_est.group(1)) > int(base_est.group(1)))
has_nh = '<namehits n="0"' not in live and '<namehits n="' in live
print("PAYLOAD_MATCH" if ok else "PAYLOAD_DIFFERS")
print("EST_GREW" if grew else "EST_DID_NOT_GROW")
print("HAS_ELEMENT" if has_nh else "NO_ELEMENT")
PY
    else
        echo "SKIP_ARCHIVE"
    fi
else
    echo "SKIP_NOCOMMIT"
fi > "$TMP/nodisp.out"
if grep -q SKIP_ "$TMP/nodisp.out"; then
    no "(6c) NO-DISPLACEMENT: could not archive 3cb6aa1b -- src (shallow clone / commit missing?) — $( cat "$TMP/nodisp.out" )"
else
    if grep -q PAYLOAD_MATCH "$TMP/nodisp.out"; then
        ok "(6c) NO-DISPLACEMENT: 'hash map open addressing probe sequence' over the frozen src/ tree — payload byte-identical to the pre-lever baseline (round 2's binary displaces content here; N3 does not)"
    else
        no "(6c) NO-DISPLACEMENT: payload DIFFERS from the pre-lever baseline on the exact query that displaced under round 2"
    fi
    if grep -q HAS_ELEMENT "$TMP/nodisp.out"; then
        ok "(6c) the element actually rode on this query (n>0) — this is not a vacuously-empty pass"
    else
        no "(6c) the element did not ride (n=0) on this query any more — re-pick a displacing query"
    fi
    if grep -q EST_GREW "$TMP/nodisp.out"; then
        ok "(6c) est_tokens= grew vs the pre-lever baseline — the appended element+comment are still honestly priced"
    else
        no "(6c) est_tokens= did not grow although namehits rode — estchargecheck's contract (element still priced) broke"
    fi
fi

# ── (9') OVER_CEILING: the pinned code sum (Amendment 1c #2), one case strictly each side of the line ──────
# fixedBytes + sigsStr.size() + tailStr.size() + E > sigSideCeiling — a unit-level check of rw::nameHitsOverCeiling
# itself (src/namehits.h) is the only reliable way to pin "one case each side of that line": end-to-end queries
# over real corpora land wherever the ranking happens to put them, and a corpus tuned to sit exactly on a byte
# boundary is not stable against unrelated ranking changes. Compiling this against a namehits.h that predates
# N3 fails outright (no such function) — that IS this arm's red-first proof; no second binary needed.
NHOC_SRC="$TMP/nh_overceiling_test.cpp"
cat > "$NHOC_SRC" <<'CPPEOF'
#include "serialize.h"
#include "namehits.h"
#include <cstdio>
int main()
{
    // fixedBytes=1000, sigs=2000, tail=500, E=100 -> sum=3600; ceiling=3600 is NOT over ('>' is strict).
    bool atLine   = rw::nameHitsOverCeiling( 1000, 2000, 500, 100, 3600 );
    // same sum, ceiling=3599: exactly one byte past it.
    bool overLine = rw::nameHitsOverCeiling( 1000, 2000, 500, 100, 3599 );
    if( atLine ) { std::fprintf( stderr, "at-the-line case is true, expected false\n" ); return 1; }
    if( !overLine ) { std::fprintf( stderr, "one-byte-over case is false, expected true\n" ); return 1; }
    std::printf( "PASS\n" );
    return 0;
}
CPPEOF
CXX="${CXX:-c++}"
if "$CXX" -std=c++23 -I "$ROOT/src" -I "$ROOT/src/infra" -I "$ROOT/third_party" -O0 "$NHOC_SRC" -o "$TMP/nh_overceiling_test" 2>"$TMP/nhoc.err"; then
    if "$TMP/nh_overceiling_test" 2>>"$TMP/nhoc.err" | grep -q PASS; then
        ok "(9') over_ceiling: rw::nameHitsOverCeiling is false at sum==ceiling and true at sum==ceiling+1 (Amendment 1c #2's exact predicate)"
    else
        no "(9') over_ceiling: the boundary check ran but did not PASS: $( cat "$TMP/nhoc.err" )"
    fi
else
    no "(9') over_ceiling: could not compile the boundary check against src/namehits.h — rw::nameHitsOverCeiling missing or its signature changed: $( cat "$TMP/nhoc.err" | head -c 400 )"
fi
# honesty (clause 6, extended by rv-r3-prereg.md §4): the element's over_ceiling attribute and the trailing
# comment's suffix must ride TOGETHER, never one without the other, on every answer that carries either.
for probe in "$out1" "$out1f" "$out0" "$out0c"; do
    hasAttr=0; hasSuffix=0
    printf '%s' "$probe" | grep -q 'over_ceiling="1"' && hasAttr=1
    printf '%s' "$probe" | grep -q 'over_ceiling=1: past budget_bytes' && hasSuffix=1
    if [ "$hasAttr" -ne "$hasSuffix" ]; then
        no "(9') over_ceiling honesty: attribute present=$hasAttr but suffix present=$hasSuffix on one of the fixture probes — they must ride together"
    fi
done
ok "(9') over_ceiling honesty: attribute and suffix never rode alone across the fixture probes above"

# ── (8) PARITY vs a verbatim copy of lb3_sim.py's toks()/bm25_rank(), >=10 real queries over src/ ─────────
# root-relative to src/, matching what `"$BIN" src --for=…`'s p= attributes name (R-R: single-root runs
# strip the crawl root, and the driver below crawls src/ as the root — same normalisation lensRowPath uses).
TRACKED="$( git -C "$ROOT" ls-files -- src 2>/dev/null | grep -E '\.(h|cpp)$' | sed 's#^src/##' )"
if [ -z "$TRACKED" ]; then
    no "(8) PARITY: no git-tracked src/*.h|*.cpp — is this a git checkout?"
else
    printf '%s\n' "$TRACKED" > "$TMP/tracked.txt"
    cat > "$TMP/parity.py" <<'PYEOF'
# verbatim from $ORCH/sim/lb3_sim.py (toks/bm25_rank only — the registered formula), plus a driver that
# checks namehits.h's OWN algorithm, not --for's ranking (the already-named set is read from the real
# answer, exactly as src/verbs_for.h builds it: sigs rows + the deep tail's SHOWN rows).
import math, os, re, subprocess, sys
from collections import Counter

STOP = {'cc', 'h', 'py', 'how', 'does', 'reach', 'where', 'is', 'implemented', 'the', 'a', 'to', 'in', 'of', 'and', 'for', 'when', 'rocksdb'}

def toks(s):
    s = re.sub(r'([a-z])([A-Z])', r'\1 \2', s)
    return [t for t in re.split(r'[^A-Za-z0-9]+', s.lower()) if t and t not in STOP and not t.isdigit()]

def bm25_rank(files, q):
    docs = {f: (toks(os.path.splitext(os.path.basename(f))[0]), toks(f)) for f in files}
    N = len(docs); qset = set(q)
    df = [Counter(), Counter()]
    for n, p in docs.values():
        for fi, d in enumerate((n, p)):
            for t in set(d): df[fi][t] += 1
    avg = [sum(len(v[i]) for v in docs.values()) / max(1, N) for i in (0, 1)]
    def s(f):
        tot = 0
        for fi, w in ((0, 3), (1, 2)):
            d = docs[f][fi]; c = Counter(d)
            for t in qset:
                if c[t]:
                    idf = math.log(1 + (N - df[fi][t] + .5) / (df[fi][t] + .5))
                    tot += w * idf * c[t] * 2.2 / (c[t] + 1.2 * (.25 + .75 * len(d) / max(1e-9, avg[fi])))
        return tot
    sc = {f: s(f) for f in files}
    return [f for f in sorted(files, key=lambda f: (-sc[f], f)) if sc[f] > 0]

BIN, ROOT, TRACKED_FILE = sys.argv[1], sys.argv[2], sys.argv[3]
tracked = [l.strip() for l in open(TRACKED_FILE) if l.strip()]

QUERIES = [
    "how does the pagerank power iteration reach convergence",
    "lexical resolve pattern packtask quality",
    "compact legend rewrite for the sigs rows",
    "merge scout conflict site detection",
    "quality delta acks and the caught-by ledger",
    "tree sitter ingest cache invalidation",
    "test gate affected tests selection",
    "substitution meter hook telemetry",
    "edit receipt post check verification",
    "MCP manifest tools list serving",
    "namehits legend byte accounting",
    "graph query expression language filters",
]

PATH_RE = re.compile(r'[\s<]p="([^"]+)"')   # a LEADING space/tag-open — "amp=" also ends in "p=" and must not match

bad = 0
for q in QUERIES:
    out = subprocess.run([BIN, "src", "--for=" + q], capture_output=True, text=True, cwd=ROOT).stdout
    if "<namehits" not in out:
        # Q6 (round 3): a genuinely empty picked list now emits NOTHING at all — no longer a self-closed
        # n="0" — so absence is only a FAIL if the python mirror expected real candidates. named= is read
        # off the WHOLE answer here (no <namehits> to rpartition away), same PATH_RE the present case uses.
        named_empty = set(PATH_RE.findall(out))
        expected_empty = [f for f in bm25_rank(tracked, toks(q)) if f not in named_empty][:3]
        if expected_empty:
            print(f"  FAIL  (8) PARITY '{q}': no <namehits> element at all, but python(lb3_sim formula)={expected_empty}")
            bad += 1
        else:
            print(f"  PASS  (8) PARITY '{q}': (0 qualify) — Q6: nothing emitted, matches the formula")
        continue
    # rpartition, not partition: N3 removed the definition from the top legend, so "<namehits" can only ever
    # appear once now (the real element, the last child right before </ctx>) — rpartition is future-proof
    # against that no longer being true (kept as the same defensive pattern the CLI/MCP parity check uses).
    pre, _, rest = out.rpartition("<namehits")
    named = set(PATH_RE.findall(pre))
    m = re.search(r'n="(\d+)"', "<namehits" + rest[:rest.find(">") + 1])
    nh_block = rest[rest.find(">") + 1 : rest.find("</namehits>")] if "</namehits>" in rest else ""
    actual = re.findall(r'<nh p="([^"]+)"/>', nh_block)
    expected = [f for f in bm25_rank(tracked, toks(q)) if f not in named][:3]
    if actual == expected:
        print(f"  PASS  (8) PARITY '{q}': {actual if actual else '(0 qualify)'}")
    else:
        print(f"  FAIL  (8) PARITY '{q}': ripwire={actual} python(lb3_sim formula)={expected}")
        bad += 1

sys.exit(1 if bad else 0)
PYEOF
    python3 "$TMP/parity.py" "$BIN" "$ROOT" "$TMP/tracked.txt"
    parity_rc=$?
    if [ "$parity_rc" -eq 0 ]; then
        ok "(8) PARITY: ripwire's namehits ranking matches lb3_sim.py's toks()/bm25_rank() exactly on 12 real queries"
    else
        no "(8) PARITY: at least one query's file list diverged from lb3_sim.py's formula — see FAILs above"
    fi
fi

# ── (9) MCP TWIN: forTaskText (src/mcpverbs.h) carries the SAME <namehits> element ─────────────────────
# Wired in for lane r2-LB3x (review base 14a2539c): the CLI --for lens had <namehits> from round 2's own
# landing, but the MCP `for` verb (forTaskText) had ZERO occurrences of namehits/kNameHits until this fix
# — RED at 14a2539c by construction, no rebuild needed to prove it (grep the base commit's mcpverbs.h).
cat > "$TMP/mcptext.py" <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: d = json.loads( line )
    except Exception: continue
    c = d.get( "result", {} ).get( "content" )
    if c: print( c[0].get( "text", "" ) )
PY
mcp_for(){
    local root="$1" task="$2" extra="${3:-}"
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"%s}}}\n' \
           "$root" "$task" "$extra" | "$BIN" --mcp 2>/dev/null | python3 "$TMP/mcptext.py"
}

mcp1="$( mcp_for test/fixture 'geometry area of a shape' )"
case "$mcp1" in
    *'<namehits n="2"><nh p="geometry.h"/><nh p="geometry.cpp"/></namehits><!--namehits: up to 3 files this answer did not already name, ranked ONLY by how many query words their file name (x3) and directory path (x2) contain (BM25); a lookup, NOT graph evidence; n= shown--></ctx>'*)
        ok "(9) MCP for: namehits n=\"2\" (geometry.h/.cpp) + trailing comment, last child, right before </ctx> — same as the CLI full dialect" ;;
    *) no "(9) MCP for: unexpected namehits shape: $( printf '%s' "$mcp1" | grep -o '<namehits.*' | tail -c 260 )" ;;
esac
# N3: the definition must be gone from the MCP header comment too — it rides only in the trailing comment now.
mcphdr1="${mcp1%%<namehits*}"
case "$mcphdr1" in
    *namehits*) no "(9) N3: the MCP header comment still mentions namehits — the definition did not move" ;;
    *) ok "(9) N3: MCP header comment carries no namehits clause at all" ;;
esac

# absence under an explicit budget_tokens — the MCP twin of the CLI's --token-budget scope rule (5)
mcpb="$( mcp_for . 'lexical resolve pattern packtask' ', "budget_tokens":900' )"
if ! printf '%s' "$mcpb" | grep -q namehits; then
    ok "(9) MCP for budget_tokens=900: no namehits anywhere (same unpriced-ceiling rule as the CLI)"
else
    no "(9) MCP for budget_tokens=900: namehits leaked in under an explicit budget"
fi

# ── CLI/MCP byte-parity of the <namehits> element AND its trailing comment, on 3 representative tasks ──────
# N3 (task item 5): the MCP `for` twin must match the CLI exactly, element AND definition — both surfaces
# use the FULL wording (the MCP dialect has no compact/full split), so a true byte match now covers the
# comment too, not just the element. rpartition mirrors (8) PARITY's own reasoning: since N3 removed the
# definition from the top legend, "<namehits" cannot appear there any more either, so the LAST (only)
# "<namehits" in the string is always the real element.
cat > "$TMP/nhparity.py" <<'PY'
import sys
def nh_block( doc ):
    _, marker, rest = doc.rpartition( "<namehits" )
    if not marker:
        return None
    tag_end = rest.find( ">" )
    if tag_end == -1:
        return None
    if rest[ :tag_end ].endswith( "/" ):
        elem_end = tag_end + 1          # self-closed: <namehits n="0"/> — Q6 no longer produces this, kept defensively
    else:
        close = rest.find( "</namehits>" )
        if close == -1:
            return None
        elem_end = close + len( "</namehits>" )
    # N3: the trailing definition comment, if any, immediately follows the element — fold it in too.
    tail = rest[ elem_end: ]
    if tail.startswith( "<!--" ):
        comment_end = tail.find( "-->" )
        if comment_end != -1:
            elem_end += comment_end + len( "-->" )
    return "<namehits" + rest[ :elem_end ]
cli_doc, mcp_doc = open( sys.argv[1] ).read(), open( sys.argv[2] ).read()
cli_nh, mcp_nh   = nh_block( cli_doc ), nh_block( mcp_doc )
if cli_nh is None and mcp_nh is None:
    print( "(0 qualify on both sides — Q6: nothing emitted, correctly absent on both)" ); sys.exit( 0 )
if cli_nh is None or mcp_nh is None:
    print( f"MISSING cli={cli_nh!r} mcp={mcp_nh!r}" ); sys.exit( 1 )
if cli_nh != mcp_nh:
    print( f"DIFFER cli={cli_nh!r} mcp={mcp_nh!r}" ); sys.exit( 1 )
print( cli_nh )
PY
for q in "geometry area of a shape" "geometry consumer app" "call a native function from python"; do
    "$BIN" test/fixture --for="$q" 2>/dev/null > "$TMP/nhp_cli.xml"
    mcp_for test/fixture "$q" > "$TMP/nhp_mcp.xml"
    if nhout="$( python3 "$TMP/nhparity.py" "$TMP/nhp_cli.xml" "$TMP/nhp_mcp.xml" )"; then
        ok "(9) PARITY CLI/MCP <namehits> byte-identical for '$q': $nhout"
    else
        no "(9) PARITY CLI/MCP <namehits> DIFFERS for '$q': $nhout"
    fi
done

[ "$fail" -eq 0 ] && echo "namehitscheck: ALL PASS" || echo "namehitscheck: FAILURES ABOVE"
exit "$fail"
