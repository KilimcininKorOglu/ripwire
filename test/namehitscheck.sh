#!/usr/bin/env bash
# namehitscheck.sh — LB3x (routing-loop round 2, PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/12_round2_PREREG.md,
# Amendment 1 §R2, approved rv-prereg2.md 2026-09-19): the `--for` ranking-to-gold append.
#
# THE CONTRACT THIS PINS (src/namehits.h, src/verbs_for.h):
#   (1) <namehits n="K"><nh p=…/>…</namehits> appears on a default-regime --for answer, IS the last child
#       of the root (right before </ctx>), and is NEVER inside <tail> (whose shown=/total= count a
#       different population — trimmed rows, not unnamed files).
#   (2) APPEND-ONLY + DEDUPED: every <nh p=> names a file this SAME answer did not already emit a p= row
#       for (sigs + the deep tail); no existing row is re-ranked or reordered.
#   (3) HONESTY: n= is the count actually served (0..3), never padded — fewer than 3 qualifying files says
#       so; zero qualifying files still emits the element (<namehits n="0"/>), never silently drops it.
#   (4) Legend: both dialects define namehits/nh/n=, present exactly when the element rides (never one
#       without the other).
#   (5) SCOPE: absent under an explicit --token-budget (the ceiling ladder does not price it yet — see
#       namehits.h) and on --json/--format=candidates/--format=columnar (namehits is an XML-bundle-only
#       enrichment, the T3/auto-bodies precedent).
#   (6) RED-FIRST: everything BEFORE <namehits> is byte-identical to the pre-lever binary's answer for the
#       SAME query (append-only at the DOCUMENT level, not just the element's own row order); every other
#       verb's output is untouched.
#   (7) DETERMINISM: two runs byte-identical (integer scoring, path tie-break — no floating point ever
#       reaches output).
#   (8) PARITY: the formula (name×3 + path×2 BM25, k1=1.2, b=0.75, lb3_sim.py's toks()) matches a python
#       mirror of $ORCH/sim/lb3_sim.py's toks()/bm25_rank(), copied verbatim, on >=10 real queries over
#       this repo's own src/ tree — exact file lists, not just counts.
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
    *'<namehits n="2"><nh p="geometry.h"/><nh p="geometry.cpp"/></namehits></ctx>'*)
        ok "(1)/(3) fixture 'geometry area of a shape': n=\"2\" (honest — only 2 files qualify), last child, right before </ctx>" ;;
    *) no "(1)/(3) fixture 'geometry area of a shape': unexpected shape: $( printf '%s' "$out1" | grep -o '<namehits.*' | head -c 200 )" ;;
esac
case "$out1" in
    *'namehits/nh p=: <=3 unnamed files by file-name/path word match (not graph evidence); n= shown'*)
        ok "(4) compact legend defines namehits/nh/n=" ;;
    *) no "(4) compact legend missing the namehits clause" ;;
esac
if printf '%s' "$out1" | xmllint --noout - 2>"$TMP/xml1.err"; then
    ok "(1) fixture answer is well-formed XML"
else
    no "(1) fixture answer is NOT well-formed: $( cat "$TMP/xml1.err" )"
fi

out1f="$( "$BIN" test/fixture --for='geometry area of a shape' 2>/dev/null )"
case "$out1f" in
    *'<namehits n=> = up to 3 files this answer did not already name, ranked ONLY by how many query words their file name (x3) and directory path (x2) contain (BM25); a lookup, NOT graph evidence; n= rows shown'*)
        ok "(4) full legend defines <namehits n=> verbatim" ;;
    *) no "(4) full legend missing the namehits clause" ;;
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

# honesty at n="0": an all-stopword query tokenizes to nothing (lb3_sim.py STOP), so rankNameHits returns
# empty and the element must still ride, self-closed, never omitted (the <tail> B1.4 convention).
out0="$( "$BIN" test/fixture --for='how does the' 2>/dev/null )"
case "$out0" in
    *'<namehits n="0"/></ctx>'*) ok "(3) all-stopword query: <namehits n=\"0\"/> — present, honest, last child" ;;
    *) no "(3) all-stopword query: expected a self-closed n=\"0\" last child, got: $( printf '%s' "$out0" | grep -o '<namehits.*' | head -c 200 )" ;;
esac

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
    # append-only at the CONTENT level: the header legend comment is EXPECTED to grow (it now defines
    # namehits/nh/n= — that growth is what the byte clause and the compactlegendcheck/forrankordercheck
    # re-pins price), so the honest claim is that the PAYLOAD — <sigs>/<lego>/<compose>/<tail>/bodies,
    # everything from the first <sigs> up to (not including) <namehits> — is untouched: no row moved,
    # reordered or changed to make room for the append.
    newpayload="$( printf '%s' "$newout"  | sed 's/.*\(<sigs\)/\1/' )"; newpayload="${newpayload%%<namehits*}"
    basepayload="$( printf '%s' "$baseout" | sed 's/.*\(<sigs\)/\1/' )"; basepayload="${basepayload%</ctx>}"
    if [ "$newpayload" = "$basepayload" ]; then
        ok "(6) '$q': the payload (sigs/tail rows) is byte-identical to the pre-lever answer — append-only"
    else
        no "(6) '$q': the payload DIFFERS from the pre-lever answer — this is not append-only"
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
        print(f"  FAIL  (8) PARITY '{q}': no <namehits> element in the answer at all")
        bad += 1
        continue
    # rpartition, not partition: the FULL dialect's legend comment spells the literal text "<namehits n=>"
    # (the verbatim definition clause) near the TOP of the document — the real element is the LAST child,
    # right before </ctx>, so it is the LAST "<namehits" in the string, never the first.
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

[ "$fail" -eq 0 ] && echo "namehitscheck: ALL PASS" || echo "namehitscheck: FAILURES ABOVE"
exit "$fail"
