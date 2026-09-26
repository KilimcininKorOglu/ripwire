#!/usr/bin/env bash
# impactdepthcheck.sh — depth-labelled --impact (0.6.5): the hop depth the blast-radius walk already records
# (graph.h transitiveCallersDepth), put on the listing.
#
# THE DEFECT. --impact listed its reach set in PageRank order with no depth, so a reader could not tell a direct
# caller from a four-hop dependent, and the page window (40 rows by default, --limit=N) cut across every depth at
# once: a well-ranked 2- or 3-hop dependent could push a DIRECT caller out of the page, and nothing in the answer
# said which depths the page covered. The fix orders rows by hop depth first (PageRank order within a depth, as
# before) BEFORE the window cuts, prints d= on the rows (run-length: the page's first row and each depth change),
# and puts by_depth=k:n,… on the root, so a cut drops the deepest rows first and says where it stopped.
#
# FIXTURE (written below): target() has TWO direct callers. direct_b sits under hub(), which six functions call,
# so hub (2 hops) and direct_b out-rank the other direct caller, direct_z, under PageRank. On the pre-fix binary
# --impact=target --limit=2 printed direct_b and hub and dropped direct_z: arm (1) is RED there.
#
# ARMS
#   (1) HEAD FIRST: --limit=2 prints exactly the d=1 set, which equals --callers=target's rows (a second verb's
#       answer, not this gate's own table).
#   (2) by_depth= on the root is "1:2,2:1,3:6" on the fixture and its counts sum to reaches=.
#   (3) every row's depth (d= expanded run-length) equals the fixture's hand-derived hop count; d= is printed on
#       the first row and exactly where the depth changes; depths never decrease down the listing.
#   (4) a page that starts mid-depth (--offset=3) still prints d= on its first row.
#   (5) --json: "by_depth" is the same counts as an array and every row carries "d" equal to the XML depth.
#   (6) --format=columnar: fields= names depth and the <depth> column equals the XML depths.
#   (7) the MCP impact twin: the same by_depth= and the same rows (name, d=) as the CLI, and the same full clause.
#   (8) reaches="0" (lonely): no by_depth=, no d=, and neither legend carries the depth reading.
#   (9) legends: the full answer carries graphlegend.h's clause, the compact one its two readings.
#  (10) re-derivation on the shared gate fixture (test/fixture, --impact=distance): the d=1 rows equal
#       --callers=distance, and by_depth= sums to reaches=.
#  (11) determinism: two runs are byte-identical.
#
# Usage: bash test/impactdepthcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/impactdepthcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIXD="$TMP/fix"; mkdir -p "$FIXD"
cat >"$FIXD/depth.c" <<'EOF'
void target( void ) {}
void direct_b( void ) { target(); }
void hub( void ) { direct_b(); }
void u1( void ) { hub(); }
void u2( void ) { hub(); }
void u3( void ) { hub(); }
void u4( void ) { hub(); }
void u5( void ) { hub(); }
void u6( void ) { hub(); }
void direct_z( void ) { target(); }
void lonely( void ) {}
EOF

echo "impactdepthcheck: $BIN"
BIN="$BIN" FIXD="$FIXD" GATEFIX="$ROOT/test/fixture" python3 - <<'PY'
import json, os, re, subprocess, sys

BIN, FIXD, GATEFIX = os.environ["BIN"], os.environ["FIXD"], os.environ["GATEFIX"]
fail = [0]
def ok(m): print("  PASS  " + m)
def no(m): print("  FAIL  " + m); fail[0] = 1

def run(root, *args):
    p = subprocess.run([BIN, ".", "--no-cache"] + list(args), cwd=root, capture_output=True, text=True, timeout=300)
    return p.stdout

def root_attrs(doc, tag="impact"):
    m = re.search(r"<%s ([^>]*)>" % tag, doc)
    return dict(re.findall(r'(\w[\w-]*)="([^"]*)"', m.group(1))) if m else None

def rows(doc):
    """[(name, d-or-None)] in document order, <s> rows inside <impact> only"""
    body = doc[doc.index("<impact "):] if "<impact " in doc else ""
    return [(re.search(r' n="([^"]*)"', r).group(1), (re.search(r' d="(\d+)"', r) or [None, None])[1])
            for r in re.findall(r"<s [^>]*/>", body)]

def expand(rs):
    out, cur = [], None
    for n, d in rs:
        if d is not None:
            cur = int(d)
        out.append((n, cur))
    return out

def legend(doc):
    return "".join(re.findall(r"<!--.*?-->", doc[:doc.index("<impact ")] if "<impact " in doc else doc, re.S))

TRUE_DEPTH = {"direct_b": 1, "direct_z": 1, "hub": 2, "u1": 3, "u2": 3, "u3": 3, "u4": 3, "u5": 3, "u6": 3}

# (1) head first
cut = run(FIXD, "--impact=target", "--limit=2", "--legend=full")
callers = set(re.findall(r'<s [^>]*n="([^"]*)"', run(FIXD, "--callers=target", "--legend=full")))
got = set(n for n, _ in rows(cut))
if callers == {"direct_b", "direct_z"} and got == callers:
    ok("(1) --limit=2 prints exactly the direct callers %s (== --callers=target): the cut dropped the deeper rows" % sorted(got))
else:
    no("(1) --limit=2 printed %s; --callers=target is %s — a direct caller was cut while a deeper row was kept" % (sorted(got), sorted(callers)))

# (2) by_depth
full = run(FIXD, "--impact=target", "--limit=100", "--legend=full")
ra = root_attrs(full) or {}
bd = ra.get("by_depth")
if bd == "1:2,2:1,3:6" and sum(int(x.split(":")[1]) for x in bd.split(",")) == int(ra.get("reaches", "-1")):
    ok('(2) by_depth="%s" partitions reaches="%s"' % (bd, ra.get("reaches")))
else:
    no('(2) by_depth=%r reaches=%r (want "1:2,2:1,3:6" summing to reaches=)' % (bd, ra.get("reaches")))

# (3) per-row depth, run-length rule, order
rs = rows(full)
ex = expand(rs)
wrong = [(n, d) for n, d in ex if TRUE_DEPTH.get(n) != d]
runlen = all((d is not None) == (i == 0 or ex[i][1] != ex[i - 1][1]) for i, (_, d) in enumerate(rs))
mono = all(d is not None for _, d in ex) and all(ex[i][1] <= ex[i + 1][1] for i in range(len(ex) - 1))
if len(ex) == 9 and not wrong and runlen and mono:
    ok("(3) 9 rows: every depth matches the hand-derived hop count; d= on the first row and on each change only; depths never decrease")
else:
    no("(3) rows=%d wrong-depth=%s run-length-rule=%s non-decreasing=%s: %s" % (len(ex), wrong, runlen, mono, rs))

# (4) a mid-depth page
page = rows(run(FIXD, "--impact=target", "--offset=3", "--limit=3", "--legend=full"))
if page and page[0][1] is not None and int(page[0][1]) == TRUE_DEPTH.get(page[0][0]):
    ok("(4) --offset=3 page: its first row carries d=%s (%s)" % (page[0][1], page[0][0]))
else:
    no("(4) --offset=3 page's first row carries no correct d=: %s" % page)

# (5) json
try:
    j = json.loads(run(FIXD, "--impact=target", "--limit=100", "--json"))
    jd = [(r["n"], r.get("d")) for r in j["impact"]]
    if j.get("by_depth") == [2, 1, 6] and jd == ex:
        ok('(5) --json: "by_depth":[2,1,6] and every row\'s "d" equals the XML depth')
    else:
        no("(5) --json by_depth=%r rows=%r (XML %r)" % (j.get("by_depth"), jd, ex))
except Exception as e:
    no("(5) --json did not parse: %s" % e)

# (6) columnar
col = run(FIXD, "--impact=target", "--limit=100", "--format=columnar")
fm = re.search(r'fields="([^"]*)"', col); dm = re.search(r"<depth>([^<]*)</depth>", col)
cr = root_attrs(col) or {}
if fm and "depth" in fm.group(1).split(",") and dm and [int(x) for x in dm.group(1).split(",")] == [d for _, d in ex] \
        and cr.get("by_depth") == bd:
    ok("(6) --format=columnar: fields= names depth, the <depth> column equals the XML depths, by_depth= on its root")
else:
    no("(6) columnar fields=%s depth=%s by_depth=%s" % (fm and fm.group(1), dm and dm.group(1), cr.get("by_depth")))

# (7) the MCP twin
req = "\n".join([json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize"}),
                 json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "impact",
                            "arguments": {"path": FIXD, "symbol": "target", "limit": 100, "legend": "full"}}})]) + "\n"
p = subprocess.run([BIN, "--mcp"], input=req, capture_output=True, text=True, timeout=300)
try:
    mt = json.loads(p.stdout.strip().splitlines()[-1])["result"]["content"][0]["text"]
    ma = root_attrs(mt) or {}
    clause = re.search(r"d=N on <s>: hop depth[^.]*\.", legend(full))
    if ma.get("by_depth") == bd and rows(mt) == rs and clause and clause.group(0) in mt:
        ok("(7) MCP impact: by_depth=, every row's name and d=, and the full clause equal the CLI's")
    else:
        no("(7) MCP impact by_depth=%r rows=%r clause-shared=%s (CLI %r %r)" % (ma.get("by_depth"), rows(mt), bool(clause and clause.group(0) in mt), bd, rs))
except Exception as e:
    no("(7) MCP impact answered nothing parseable: %s / %s" % (e, p.stdout[-300:]))

# (8) reaches=0
for posture in ("full", "compact"):
    z = run(FIXD, "--impact=lonely", "--legend=" + posture)
    za = root_attrs(z) or {}
    if za.get("reaches") == "0" and "by_depth" not in za and not any(d for _, d in rows(z)) \
            and "by_depth=" not in legend(z) and "d=N" not in legend(z):
        ok("(8) --impact=lonely --legend=%s: reaches=0, no by_depth=, no d=, no depth reading" % posture)
    else:
        no("(8) --impact=lonely --legend=%s: %r / legend mentions depth: %s" % (posture, za, "by_depth=" in legend(z)))

# (9) legends define what the answer carries
comp = run(FIXD, "--impact=target", "--legend=compact")
if "d=N on <s>: hop depth" in legend(full) and "by_depth=k:n" in legend(full) \
        and "<s d=N>:" in legend(comp) and "by_depth=k:n:" in legend(comp):
    ok("(9) the full legend carries the d=/by_depth= clause, the compact legend its two readings")
else:
    no("(9) a legend lacks the depth definitions (full: %s, compact: %s)" % ("by_depth=k:n" in legend(full), "<s d=N>:" in legend(comp)))

# (10) re-derivation on the shared gate fixture
gi = run(GATEFIX, "--impact=distance", "--limit=500", "--legend=full")
ga = root_attrs(gi) or {}
gex = expand(rows(gi))
d1 = set(n for n, d in gex if d == 1)
gc = set(re.findall(r'<s [^>]*n="([^"]*)"', run(GATEFIX, "--callers=distance", "--legend=full", "--limit=500")))
gbd = ga.get("by_depth", "")
gsum = sum(int(x.split(":")[1]) for x in gbd.split(",")) if gbd else -1
if d1 and d1 == gc and gsum == int(ga.get("reaches", "-2")) == len(gex):
    ok("(10) test/fixture --impact=distance: d=1 rows == --callers=distance (%d), by_depth=%s sums to reaches=%s" % (len(d1), gbd, ga.get("reaches")))
else:
    no("(10) test/fixture: d=1 %s vs callers %s; by_depth=%s sum %d reaches=%s rows=%d" % (sorted(d1), sorted(gc), gbd, gsum, ga.get("reaches"), len(gex)))

# (11) determinism
if run(FIXD, "--impact=target", "--limit=100") == run(FIXD, "--impact=target", "--limit=100"):
    ok("(11) two runs are byte-identical")
else:
    no("(11) two runs differ")

print("impactdepthcheck: " + ("FAILURES" if fail[0] else "ALL PASS"))
sys.exit(fail[0])
PY
