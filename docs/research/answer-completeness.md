# Answer completeness under a ceiling — the scoreboard and the line-granular stair-steps, pre-registered

**Status: DESIGN, 2026-09-23. No number in this note was produced by running anything.** It fixes, before
any measurement, what will be measured, on which population, by which instrument, and what each outcome
licenses. A later section under a `## Results` heading reports against it; nothing above that heading moves
after the commit that adds the first result. Read `docs/METHODOLOGY.md` §9 first — this note does not
define a new objective. The objective is §9 principle 1's **terminality**, the finding instrument is
**recall at k** (principle 6), and what this note adds is the countable form of a §9 *violation* — the
**chop rate** — plus the populations both can be scored on without an external corpus.

---

## 1. The quantities, exactly

### 1.1 Terminality — the objective, unchanged

A call is **terminal** when no native retrieval follows it: `bench/substitution_report.py` §5 counts, per
verb, the ripwire calls that are not followed by a `grep read glob find git-diff git-log git-show-stat` call
within the next five tool calls of the same session (`TERMINALITY_WINDOW = 5`, `SWEEP_CLASSES`). The
registered baseline is the FIND band in `docs/EVALS.md` "Terminality round A" (`--for` 24.5% of 139, the map
40.3% of 395, `--callers` 33.8% of 65, `--expand` 32.1% of 56, `--slice` 46.7% of 30). Its limits are stated
with it and inherited here: single operator, non-randomized, Claude Code only, MCP rows unobserved before the
2026-09-05 matcher, and the edit verbs' policy-read exclusion. Terminality is the number a default is judged
by. It is also **slow and live** — it needs sessions — which is why the rest of this note exists: an offline
proxy that a train can compute in CI, defined so that it can only move in the same direction as terminality.

### 1.2 Complete — the offline proxy, judged mechanically per question type

An answer is **complete** when the thing the question asked for is inside the served document. "Inside" and
"the thing" are fixed per question type, and every judge below already exists in the tree:

| question type | verb(s) | gold | complete when | judge that exists |
| --- | --- | --- | --- | --- |
| localisation | `--for=TASK`, MCP `for` | the file(s) / function(s) a fix touched | every gold function is a `<sigs><d>` row of the served head (**strict**); at least one is (**any**); a gold path appears anywhere in `<sigs>`, `<tail>` or `<hops>` (**lenient**) | `served_head()` in `bench/locbench/calibrate_confidence.py` (on `lane/served-syms-result`, not on main); `run_locbench.py`'s strict / any / lenient grades; `labels_ranking.tsv`'s `path#Symbol` targets in `bench/recalleval/run_recalleval.py` |
| set questions | `--callers=X`, `--impact=X`, `--uses=X`, `--affected=F` | the set the graph holds | the emitted rows plus the disclosed remainder equal the set: `shown == total`, or `capped="1"` with a `next=` whose answer, unioned once, reaches `total` | the verbs' own `shown= total= capped= counts_floor= next=`; the re-derivation gates §9 principle 6 names (`--uses` against `--callers`, `--format=candidates` against a bundle) |
| a body or its lines | `--expand=SEL`, `--slice=SEL[:VAR]`, auto-bodies in `--for` | the lines a fix changed inside the served function | every gold line's text is in the delivered payload (line recall 1.0); the score is the fraction otherwise | `bench/slice/run_slicerecall.py` (own history, cpp family); the R5 protocol of `docs/research/slice-line-recall.md` (on `lane/research-arise-slice`, not on main) |
| orientation | the default map, `--handoff`, `--communities` | none that is mechanical | **not judged complete offline.** Judged by terminality only, and by the *structural* half of the chop rate (§1.3), which needs no gold | the meter; the silent-cut gate of §3.2 |

The strict/any/lenient split is kept apart everywhere, as `run_locbench.py` keeps single-file / multi-file /
all-patch strict apart: a headline "complete" that pools them is not a number this note reports.

### 1.3 Chop rate — §9 violations, counted

A **chop** is a §9 violation in one served document. There are exactly two kinds, and they are reported apart:

- **head-chop** (principle 2 violated): a row the answer needed was *available* to the verb — it is in the
  uncapped run or the `--format=candidates` export of the same query, at a rank the served document reached —
  and is absent from the served document because a ceiling, quota, cap, page or budget removed it. The
  mechanical form: `gold ∈ uncapped(q)` and `gold ∉ served(q)`. It needs gold, so it is measured only on the
  populations of §3 that carry gold.
- **silent-chop** (principle 3 violated): the served document holds fewer rows than the uncapped run of the
  same query, and carries no attribute that says so — no `shown=`/`total=`/`capped=`/`has_more=`/
  `over_ceiling=`/`counts_floor=` on the element that shrank and no `next=` that fetches the remainder. It
  needs no gold: it is a property of two documents, so it can run on every verb over any tree, which is what
  makes it a CI gate (§3.2).

A **disclosed cut** — fewer rows than the uncapped run, *with* the attributes and a `next=` that is
deterministic (same binary, same tree, same answer) — is **not a chop**. It is principle 3's "two known calls".
A cut that is counted but carries no `next=` (and no paging attributes a documented call can continue from) is
a **dead-end cut**: not a chop, because the reader knows what is missing, but principle 3 is only half met. It
is counted apart from both chops and from disclosed cuts, and §3.2 reds on it as its own class.

**What `total=` counts on a byte-trimmed element (ruling, 2026-09-24, adopted for every verb).** `total=` = the
rows handed to the byte gate: after the verb's documented candidate window (the `--for` lens head,
`kForLensDefaultTopN` or `--pack-top-n`; the non-lens `--pack-top-n` window) and after visited rows with
nothing to print, *before* any byte budget. `shown=` = rows printed; `capped="1"` ⇔ the byte budget dropped
rows (or, on the `--for` lens only, shrank them — `shown == total` with `capped="1"`). This is
`src/pageview.h` THE TRUNCATION VOCABULARY rule 5 ("rows handed to the ladder") extended to every byte gate,
so no byte cut can hide inside `total=`. On `60b65f02` the `--pack-budget-bytes` collection gate breaks it —
its cut rows are absent from `total=`, so `shown == total` can print over a cut (§5.1). A candidate *window*
is not a byte cut and is not counted in `total=`; disclosing the ranking universe beyond the window needs its
own attribute (for example `ranked=`), decided once for every ranking verb.

**Chop rate** = documents with at least one chop of either kind / documents scored, reported as the pair
(head-chop rate, silent-chop rate) with n, never pooled. The silent-chop rate's registered target is **zero**
on the flag universe: every silent chop is a defect, and the inventory in §5 is the list of where one can
still happen today.

### 1.4 Cost, and why hits-per-byte cannot be gamed by cutting

The cost of an answer is its **bytes before the row that answers** — the legend-once round's
bytes-to-correct-answer (TTCA), not the document's length: what follows the answering row is cheap to the
agent, what precedes it is paid in full. For a set question the answering row is the last gold row; for an
orientation answer, which has no gold, the whole document is charged.

The efficiency figure is **complete answers per kilobyte**, and its numerator is defined so that a cut can
never raise it:

1. a document credited as complete must be complete under §1.2 **and** free of chops under §1.3 — a
   document that is complete only because the gold happened to survive a silent cut still scores 0, because
   the cut is a defect whether or not it hit gold this time;
2. a **disclosed cut is credited as complete only after following `next=` once**, and is charged the bytes of
   *both* calls up to the answering row — so a stub is worth shipping exactly when
   `bytes(stub) + bytes(next call) < bytes(section)`, the rule the 0.6.2 section stub already applies with
   its legend clause (`kForSectionStubLegend`, `src/serialize.h`) charged whole;
3. an answer with `over_ceiling="1"` is credited as complete at its real bytes — exceeding the ceiling is
   the honest move principle 2 prescribes, and the metric does not punish it; the ceiling's job is done by
   the separate byte floor of §3.3, not by the numerator.

Under these rules the only ways to raise complete-per-kilobyte are to put the answering row earlier, to
remove bytes that precede it, or to answer more questions — which is the whole intended search space.

### 1.5 What no instrument here can see, stated

- **Terminality is single-operator and lexical.** The meter cannot see MCP calls before 2026-09-05, calls
  from clients without a hook, retrieval inside subagents, or whether a `Read` was curiosity rather than
  need (`docs/SUBSTITUTION_METER.md`, "Known undercount"). Complete-per-kilobyte can only be *validated*
  against it, never replace it.
- **"Complete" is gold-relative.** A question whose gold is wrong, or whose true answer is "nothing"
  (an adversarial label), is scored by whatever the label says; `labels_ranking.tsv` carries per-label
  reasons for this purpose and the ARB rounds' unanswerable splits are the only instrument for the second
  case.
- **Orientation has no gold.** The default map's completeness is not measured by anything offline; a
  reorder of the map is judged by the meter alone, which is slow. This note does not pretend otherwise.
- **Head-chop needs the uncapped run**, which on a large tree can itself hit an INDEXING-class cap
  (`docs/LIMITS.md`). A head that was never found is a recall miss, not a chop, and the two are reported
  apart, as `run_locbench.py` reports parse coverage apart from accuracy.

---

## 2. Populations — pinned before any number, and identified by fingerprint

The lesson this round carries (`docs/METHODOLOGY.md` §7 and the 2026-09-22 reviews): **a measurement's
population decides its answer, so check what the population IS, not only that the number reproduces.** Every
population below is named by a ref or a lock file, and every report under this note prints the population's
fingerprint before its first figure. A run whose fingerprint does not match reports exactly that and no
number.

### 2.1 Tier 0 — runs in CI and locally, no external corpus

| id | population | pinned by | fingerprint printed | scores |
| --- | --- | --- | --- | --- |
| **P0-labels** | `bench/recalleval/labels_ranking.tsv` (72 rows, `path#Symbol` targets) and `labels_recall.tsv` (85 rows) over the frozen snapshot `snapshot.mdpack` / `snapshot.srcpack` | `snapshot.lock` (`source_commit`, `files=113`), `srcsnapshot.lock`; hand edits red `test/recallevalcheck.sh` #0 | lock shas, label counts, `skipped=0` | `--for` / `--query` complete (strict/any/lenient), head-chop, bytes-before-answer; `--recall` likewise |
| **P0-history** | fix-shaped commits of this repository, newest 40 qualifying, cpp family, mined from a **pinned ref** (`run_slicerecall.py --ref`) | the ref sha named in the run; never bare `git log` from a moving checkout | ref sha, instance count, the qualifying rule's version | `--slice` / `--expand` line recall at fixed budgets; the body-does-not-fit split |
| **P0-cochange** | the co-change proxy of `bench/ANSWERQUALITY.md` §1 (`ripwire <repo> --eval`, last 80 qualifying commits) | **must be run from a detached checkout at a stated sha**; `test/ripwirepubliccheck.sh` arm 9 refuses an unpinned history walk in a tracked script | the sha, `commits=80`, seed rule | recall@5/10/20 (finding, principle 6); unchanged from today |
| **P0-universe** | every verb the flag universe derives from `src/cli.h` (`test/flaguniverse.py`, the derivation `compactlegendcheck` arm U uses), each run at defaults and at a tight budget on the committed fixture trees under `test/` | the binary and the fixture tree; no history | verb count, fixture sha | **silent-chop only** (§1.3): no gold needed |

Tier 0 is what a train reports. It cannot speak to Python or to issue-derived patches; it can catch every
regression in ordering, disclosure and pricing on the verbs' own contract.

### 2.2 Tier 1 — when the external assets are on disk

| id | population | pinned by | fingerprint |
| --- | --- | --- | --- |
| **P1-92** | the 92 scoreable held-out LocBench instances of `docs/research/confidence-and-abstention.md` §3.3 | `bench/locbench/dataset.lock` (salted split), the asset tree's `.ripwire_at_<sha>` markers | §5.4.1 of that note, verbatim: 74 low / 18 high, misses 15 (file) / 38 (func), `margin_pct=` AUROC at the lattice points 670.5/1155 and 1276.5/2052 within the stated tolerances |
| **P1-heldout** | the repository-disjoint held-out split, N = 243 | `dataset.lock`, `full560.json`'s hash | N, zero-exclusion count, 564/564 scoped gold coverage |
| **P1-py-slice** | the 173 LocBench Python instances of `slice-line-recall.md` R1 | that note's corpus rule and the pre-fix `base_commit` | 173 instances, 2,453 (SEL, VAR) pairs, the 6,809-line ceiling |

Tier 1 adds function grain on real issues and the Python family. Its comparison rule is
`bench/locbench/compare_runs.py`'s paired, repository-clustered bootstrap; a change is read only from the
paired delta and its lower bound, never from two absolute numbers.

---

## 3. The scoreboard (bet B) — what a train reports, and the regression rule

### 3.1 The table every train prints

One row per verb per population, in this order and with nothing pooled:

```
population fingerprint: <id> <sha/lock> n=<N>
verb        n   complete(strict/any/lenient)   head-chop   silent-chop   disclosed-cut   bytes-before-answer p50/p95   terminal% (meter, secondary)
```

`terminal%` is filled from the frozen meter snapshot the round names, or left blank with `n/a: no session
rows`; it is never computed from the live log during a train. `disclosed-cut` is reported beside the chops
so that a fall in silent-chop that is really a rise in disclosed-cut is visible as what it is.

### 3.2 The silent-cut gate (new, structural, corpus-free)

A gate in the house pattern (`test/*check.sh`, five registrations) that for every verb in the flag universe
runs the fixture tree at defaults and at the tightest budget the verb honours (`--token-budget`, `--limit`,
`--top-k`, `--pack-budget-bytes`, the verb's own cap), parses both documents, and asserts: **for every
element whose row count fell, the served element carries `shown=`+`total=`+`capped=` (or the verb's registered
equivalent, `has_more=`/`next_offset=`/`counts_floor=`/`over_ceiling=`) and a `next=` that, run once,
returns the missing rows.** It fails on the first element that shrank silently, naming verb, element and cap,
and reports a counted cut with no `next=` separately as a dead-end cut (§1.3), so the two classes never pool.
It also asserts the `total=` ruling of §1.3: on a byte-trimmed element, `total=` equals the rows the same call
prints with only the byte budget lifted. Red-first: it must be RED on today's binary for every row of §5 marked SILENT and GREEN after step 2. It
replaces nothing: `capdisclosurecheck.sh` already asserts this for three named caps, and `docs/LIMITS.md`
records per cap whether its file discloses; this generalises the document-level assertion to every verb and
every budget the flag universe can reach.

### 3.3 The regression rule — floor-style, pre-registered, per population

Floors are set once from the step-0 baseline (§4) and recorded under `## Results`; the precedent is
`test/recallevalcheck.sh`'s "never pin exact scores; a fix should move the number and must not trip the gate
by improving".

- **silent-chop: hard zero.** Any silent chop on P0-universe reds the train. There is no tolerance, because
  there is no honest reason for one.
- **head-chop: monotone.** A train may not raise the head-chop count on P0-labels or P0-history above the
  baseline count; on P1 populations the paired delta's clustered-bootstrap lower bound must be ≥ 0.
- **complete: floor at baseline minus one label.** On P0-labels (n = 72 / 85) one label is 1.2–1.4 pp; the
  floor is `baseline − 1 row` per grade, so a genuine one-row loss is visible and a rounding jitter is not.
  On P1-heldout, `compare_runs.py`'s existing predicate (mean strict delta and clustered lower bound).
- **bytes-before-answer: p50 ≤ +5%, p95 ≤ +10%** against baseline on the same population — the caps
  `compare_runs.py` already applies to latency and tokens — *unless* complete rose on the same population,
  in which case the trade is reported and the owner decides (the GATE_DECISION two-tier proposal, not
  adopted here).
- **terminality: never a train gate.** It is the objective, and it is reported from a frozen snapshot per
  round; a train that moves the offline numbers the right way and the meter the wrong way is a finding about
  the proxy, recorded under `## Results`, not a pass.

**Negative consequence, pre-committed.** A change that fails any floor ships its gate and its fixture, reverts
its behaviour, and records the negative under `## Results` — the round A rule, carried over.

---

## 4. Line-granular answers (bet A) — stair-stepped, each step gated on the one before

The hypothesis, from `slice-line-recall.md` R5: under a budget smaller than the function, delivering
ranked *lines* puts more of the answer in front of the agent than delivering the whole body truncated (32.1%
against 17.6% of gold lines at 512 bytes, n = 150 bodies that did not fit; +10.0 pp from filtering alone, a
further +4.4 pp from ordering; the gap closes by 4 KB and the ordering gain was *negative* at 2 KB). The
limit, from the same note: 70.8% of that corpus's gold lines are in fixes that touch more than one function,
which no within-function granularity can reach, and directed cross-function reach recovers 6.14% of that
ceiling — killed at the 20% line. So the lever is real, small-budget, within-function, and worth nothing if
it costs a head row. Hence the order below: nothing line-granular ships before the chop rate is measured and
the cut is disclosed.

### Step 0 — measure the current default's chop rate

- **What:** run §3.1 on every Tier 0 population with today's binary; run the §3.2 gate and record every red
  row against §5. On P0-history additionally record, per instance, whether the served body fits 512 / 1,024
  / 2,048 / 4,096 bytes and the gold-line recall of `--expand` truncated at each.
- **Success band:** none — this is the baseline. Success is that every number carries its fingerprint and
  the §5 inventory agrees with the gate's red rows (a SILENT row the gate does not catch is a gate defect;
  a gate red not in §5 is an inventory defect — both are recorded).
- **Stop if:** the fingerprints do not reproduce, or `skipped > 0` on P0-labels. Then the population is
  fixed first and nothing else is measured.

### Step 1 — priority order per verb, so any cut drops the tail

- **What "priority" is, per verb** (each is a §9.1 finding or an existing disclosed order; nothing new is
  invented here):

  | verb | priority order | disclosed as |
  | --- | --- | --- |
  | `--for` `<sigs>` | the named partner row (`<hdr>`), then lens rank `r=` ascending; the lens `<sigs>` has emitted in `r=` order since P7 (2026-09-05, the `<f>` wrapper removed), and its ladder drops from the rank tail; the one pre-rank cut left is the `--pack-budget-bytes` collection gate (§5.1) | `r=` on the row; `order=` on the root is not emitted today |
  | `--for --limit=N` page | `score=` descending (file share of positive lens score, then best symbol, then path); the registered path-subtoken blend of `lane/r1-page-blend` is **not on main** | none today — that lane proposed `order="blend"` |
  | `--for` `<tail>` | trimmed rows first, in rank order, then the rest | `shown= total= capped=` |
  | `--slice=SEL:VAR` | def-use coverage, then line | `order="defuse"` |
  | `--affected`, `--situ`, `--test-gate` tests-to-run | `changed=1`, then `partner=1`, then `hops=` ascending | the row attributes |
  | `--rank-by=churn-decay` `<recent>` | newest first | the verb's legend |
  | `--callers`, `--uses`, callees | `--grep`'s order (source before test), then path | not disclosed as an order today |
  | `--expand`, `--around`, `--exemplar` callee lists | **node-id order today** — a cap here is a head cut; priority = query rank if a query exists, else caller-count descending | none today |
  | the default map | PageRank `k=` descending; `--order=important-last` reverses for large outputs, the ceiling still applies after the flip | `order=` header field |
  | `--recall` | passage rank | the verb's legend |

- **Success band (per verb changed, on the populations that score it):** head-chop count strictly lower or
  equal, complete not below its floor, bytes-before-answer p50 not up more than 5%, and on any paired
  comparison the lower bound of the delta ≥ 0. The `--slice` def-use result is the calibration for what to
  expect: Δ +0.026, CI [0.004, 0.049], more losing pairs than winning ones — adopt at a lower bound above
  zero, publish the loss count.
- **Stop if:** the lower bound includes zero for a verb — that verb keeps its order and the negative is
  recorded; or if the reorder changes which rows are *served* (it may only change where they land) — then it
  is a ranking change and belongs to a different registration.

### Step 2 — disclosed cuts everywhere

- **What:** every SILENT row of §5 gains the attribute set of §3.2 and a `next=`; every "disclosed, prose
  only" row gains a compact reading in `src/compactlegend.h`. Attributes, not prose (principle 4).
- **Success band:** §3.2 gate GREEN on the whole flag universe (silent-chop = 0); the disclosure costs
  ≤ 64 bytes per document that cut (tens of bytes, the compact budget's order of magnitude) and no new
  compact-legend prose beyond one clause per new attribute; all `--for` byte pins in `compactlegendcheck`
  re-anchored with the delta stated; rows byte-identical where nothing was cut.
- **Stop if:** a verb's disclosure would cost more than the content it discloses — then the cut itself is
  wrong for that verb (raise the cap or remove it) rather than the disclosure being skipped.

### Step 3 — line-granular bodies under tight budgets

- **What:** when a requested or auto-served body does not fit the budget it is given, deliver ranked
  `line-number: text` rows of that function in def-use order (the R5 "line-ranked" arm, the mechanism
  `--slice` already has) instead of the body's first bytes, as a **disclosed cut**: `lines shown= total=`
  and `next=--expand=SEL` on the element, `scope="fn"` stating that only the served function was searched.
  Whole body when it fits; never for a function with no sliceable locals (fall back to the truncated body,
  disclosed the same way).
- **Gated on the chop rate:** head-chop and silent-chop on every Tier 0 population may not rise by one
  document. A line delivery that drops the line the fix needed is a head-chop exactly like a row cut.
- **Success band (pre-registered, P0-history cpp family; P1-py-slice when available):** gold-line recall of
  the line delivery ≥ the truncated body's **+ 5 pp at 512 B and at 1,024 B**, not below it at 2,048 B and
  4,096 B, on the body-does-not-fit split; bytes equal by construction. Five points, not R5's +14.5, because
  R5 was handed the correct function and measured Python; this is the tool's own choice of function and
  C++. **all-patch (multi-function) complete is reported and expected NOT to move** — the 70.8% limit is
  disclosed on the element rather than hidden in a pooled recall, and a rise there would be an artefact to
  investigate, not a win.
- **Stop if:** the +5 pp band is missed at either small budget (ship nothing); or filtering wins and
  ordering loses at any budget, as it did at 2 KB in R5 (ship the filter in `order="defuse"`, the only
  order with a measured win, and record it); or any chop count rises (revert, record). The 2026-09-23
  `lane/arise-result` FAIL (`13292db7`: def-primacy over the whole span, R3@1 0.034 vs control 0.042) is the
  standing reason this step ranks lines only by the already-adopted def-use coverage and registers no new
  within-function order.

### Step 4 — stop when complete

- **What:** an answer may be *shortened* — auto-bodies, the `<tail>` and `<hops>` withheld with their counted
  stubs — when a disclosed signal says the head already holds the answer. Never withheld
  entirely, never refused (`confidence-and-abstention.md` §4: options (a), (e), (f) are the only ones the
  contract supports).
- **Gate to enter the step:** a signal meets that note's §5.2 band — **false-warn ≤ 0.20 at miss-recall
  ≥ 0.50** at function grain — on P1-92 *and* on a second sample of at least 92 more held-out instances.
  **No candidate holds that today.** `confidence=`/`margin_pct=` stands at 0.779 false-warn; `served_syms`
  was scored under §5.4 on 2026-09-23 and **failed** (func-grain AUROC 0.278 [0.177, 0.385] under the
  registered orientation, no threshold clearing both floors — that note's §10, `lane/served-syms-result`
  `50c554e6`); `margin_bp` has exactly one re-score left under §5.5. A fresh candidate needs a fresh
  registration on ≥ 92 new instances. No signal, no step; this step is therefore **blocked**, not scheduled.
- **Success band:** on both samples, bytes-before-answer median down ≥ 20% on the calls the signal
  shortens, with **zero** new misses at file grain and at most one at function grain across the 184; every
  shortened element carries its stub and `next=`; the CLI's default behaviour otherwise byte-identical.
- **Stop if:** any new file-grain miss; or the signal's band is met on one sample and not the other (one
  corpus does not license a behaviour — that note's own rule).

---

## 5. Inventory — where a budget or cap can drop answer content today

Every site in the served output where a ceiling, quota, top-k, fanout, page or byte budget removes rows, with
the order the rows are in when the cut lands (a cut on a rank-ordered list drops the tail; a cut on a
source-, path- or id-ordered list drops arbitrary content and can therefore drop the head), and how the
document discloses it. **SILENT** rows are step 2's worklist and §3.2's red arms. Line numbers are on
`origin/main` at `60b65f02`. INDEXING-class caps (`docs/LIMITS.md`, `class` column) bound what can be found
rather than what is shown; they are listed apart because a head that was never found is a recall miss, not a
chop.

Legend: **order** is the order the rows are in when the cut lands (rank = by score; file-major = files by best
rank, rows in source order inside; path-id = tier, then path, then line; source; id = node id). **disclosure** is
what the served document carries; *quintet* = `shown= capped= total= has_more= next_offset=` (+ `offset=`/`limit=`)
from `pageDisclosure` (`src/pageview.h:292`). **compact** = whether the compact legend (the CLI default) gives the
attribute a reading (`src/compactlegend.h` reads `shown/total/capped/has_more/next_offset` and any `*_capped=`
generically). **SILENT** = content dropped and nothing in the document says so.

### 5.1 `--for` (CLI and MCP `for`)

| what is capped | cut at | order | disclosure | compact | note |
| --- | --- | --- | --- | --- | --- |
| `<sigs>` quota `kForLensDefaultTopN`=40 (or `--pack-top-n`) | `src/verbs_for.h:2297`, `:2406`; `src/serialize.h:4169` | rank | PARTIAL — `<tail total= shown= capped=>` counts positive files *not* in the head; positive symbols at rank 41+ whose file is already in the head are counted nowhere | yes | `confidence="low"` hints at saturation without a count |
| relevance floor (zero-score rows) | `src/verbs_for.h:2383`; `src/serialize.h:3892` | rank | header `[relevance floor: kept K of N …]` | yes | |
| `--adaptive` cliff cut, floor 5 | `src/verbs_for.h:2353` | rank | `[adaptive: kept K of N …]`; homonym decline stated | yes | |
| collection byte gate (`--pack-budget-bytes`, 64 KB) | `src/serialize.h:4257`, `:4293` | **file-major, before the rank re-sort at `:4388`** | `dropped_positive=N` (a count; the rows are absent from `<sigs total=>`) | yes | **head-cut site**: a rank-2 row in a later file can be lost while a rank-30 row in the first file ships |
| trim ladder (`kForPayloadBudgetBytes`=7500 or `--token-budget`); step F drops rows | `src/serialize.h:4435` (ladder), `:4478` (marker) | rank, tail first | `<sigs shown= total= capped="1">`, `budget_bytes=`, `dropped_positive=` | yes | `shown==total` with `capped="1"` = rows shrunk, not dropped |
| rank tiers: doc excerpt cut to 96 B at r13–24, doc removed for r>24, signature cut to 160 B for r>24 | `src/serialize.h:4313`, `:4358–4364` | rank | `…` glyph on cut text; **doc removal for r>24 SILENT** | n.a. | always on; no legend clause |
| `kMaxSig`=240 B per signature | `src/serialize.h:3330–3348` | n.a. | `…` glyph | n.a. | |
| file tail `kForFileTailShownCap`=24 | `src/serialize.h:1010` (render `:1026`) | rank | `<tail total= shown= capped=>` | yes | trimmed further under `--token-budget` (`verbs_for.h:3266`) |
| auto-body candidates `kPackTaskBodyCandidates`=6 | `src/verbs_for.h:1829` | rank | `bundle="auto" bodies=N`; `<bodies total=>` counts the 6 only | yes | positives past 6 uncounted |
| auto-body bytes `kForAutoBodyBudgetBytes`=6000 / `kForAnchorBodyBudgetBytes`=22800 | `src/serialize.h:5481`, `:5493` | **file-major** | `<bodies shown= total= capped=>`; `<!-- body omitted (over budget): NAME -->` on the does-not-fit path only (`:5565`); bodies skipped by the budget break are counted, not named | yes | whole body or nothing; **head-cut site** (a higher-ranked body in a later file can be dropped) |
| `<calls>` per body, 16 | `src/serialize.h:5161` | rank when a query exists, else id | `<calls total= shown= capped="1">` | yes | |
| compact route `<hops>` (`kForCompactSurfaceBudgetBytes`=1000; 16 callees per row) | `src/serialize.h:5800` | rank | `<hops shown= total= capped= noedge=>` | yes | |
| `--detail=N` bodies; `--max-tokens` body ceiling | `src/verbs_for.h:3190`, `:3199` | file-major | `<bodies …>`, `max_tokens=`, `over_ceiling=` | yes | |
| lego/compose section → stub | `src/serialize.h:6425`, `:6461` | n.a. | `<lego total= shown="0" capped="1" next=…>` | yes | the disclosed-cut model |
| `--sections=lego` interfaces, 12 | `src/serialize.h:6841`; `src/verbs_for.h:3069` | rank | **SILENT** — rendered `<lego>` carries no `total=` (the pre-cap count exists, only the stub prints it) | n.a. | |
| lego methods per interface, 6 (64 targeted) | `src/serialize.h:6904`, `:6929` | source | `<!-- +more methods -->`, no count | data comment kept | |
| lego implementors per interface, 16 | `src/serialize.h:6940`, `:6951` | list order (?) | `<!-- +more -->`, no count | data comment kept | |
| `--with-graph` `kWithGraphNodeCap`=8 | `src/serialize.h:6534` | rank | **SILENT** | n.a. | |
| `--limit` file page `kForPageRowsDefault`=40 | `src/forpage.h:287`, `:300`, `:303` | rank | quintet + `next=` | yes | `docs/LIMITS.md` lists `forpage.h` as disclosing nothing: a blind spot of the generator (`docs/limits_build.py` counts only `<noun>_capped` spellings, not `pageDisclosure`'s bare `capped=`), not a hand-editable stale row |
| `--token-budget` header ladder (legend clauses, task echo) | `src/verbs_for.h:3315ff` | n.a. | `legendDroppedNote`, `[task_echo: dropped (ceiling)]`, `over_ceiling=` | yes | drops explanation, not rows |
| `--json`: same ladder on JSON bytes; collection gate | `src/serialize.h:8424`; `:8209`, `:8249` | rank / file-major | `"capped":bool`, `dropped_positive`, `budget_bytes`; **no shown/total for sigs** | n.a. | `serialize.h:7259` says JSON skips the ladder — stale |
| `--json`: compose/lego/routes/docs not served | `src/verbs_for.h:1473–1476` | n.a. | `lego_total`, `compose_total`, `routes_total`, `lens=` | n.a. | |
| MCP `for`: same cap/floor/ladder; collection gate off | `src/mcpverbs.h:1873`, `:2104` | rank | as CLI + `budget_bytes=` | yes | no bodies section exists on MCP; not stated in the answer (?) |

### 5.2 The map and its packers

| verb | what is capped | cut at | order | disclosure | compact | note |
| --- | --- | --- | --- | --- | --- | --- |
| map | `--top-k`=200 | `src/serialize.h:2410` | rank selection; emit rank / auto-flip / path | header `<!-- files= symbols= … shown= -->` | yes | no `capped=`; the withheld stub gives `would_show=` |
| map `--max-tokens` | binary search for K | `src/main.cpp:2009` | rank | `max_tokens= fit_bytes=`, `over_ceiling="1"`, `fit_unmeasured=` | yes | |
| map `--token-budget` | whole map withheld | `src/main.cpp:1126` | n.a. | `<r withheld_est_tokens= budget= withheld="1"/>` | yes | |
| map auto-flip | `kFillOrderThreshold` | `src/serialize.h:2460` (JSON `:7765`) | order only | `order=important-last(auto:fill)` | yes | K fixed before the flip; nothing trims after it — **cannot cut the head** |
| map `<c>` callees, per-file symbols | no cap found | `src/serialize.h:3093` | id (CSR) | n.a. | n.a. | |
| map in a directory | scoped `<recent>` `kRecentRows`=40 | `src/main.cpp:1283` | recency | `capped= has_more= next_offset= of=` | yes | |
| `--pack-signatures` (non-lens) | 50 rows + byte gate | `src/serialize.h:4518`, `:4526`, `:4560` | **file-major, source inside** | **SILENT** — plain `<sigs>` | n.a. | **head-cut site** |
| `--pack-top-n` | files + byte budget | `src/serialize.h:3230`, `:3278` | file rank | `<!-- truncated -->` inside the last file's CDATA only; **files past it SILENT** | n.a. | |
| `--outline` | byte budget | `src/serialize.h:6165`, `:6183` | **file-major** | **SILENT** — bare `<outline>` | n.a. | **head-cut site** |

### 5.3 Navigation verbs

| verb | what is capped | cut at | order | disclosure | compact | note |
| --- | --- | --- | --- | --- | --- | --- |
| `--callers` / `--callees` | `kCallHierarchyRowCap`=40 | `src/verbs_navigate.h:174`; order `src/callhierarchy.h:150` | **path-id** (tier, path, line) | quintet | yes | drops whatever sorts last, not the weakest |
| MCP `find_symbol` | `calledBy` windowed at 40 | `src/mcpverbs.h:718`, `:757` | path-id | **SILENT** — count/paging describe `calls` only | n.a. | |
| `--uses` | `kUseSiteRowCap`=100 | `src/verbs_navigate.h:686` (MCP `mcpverbs.h:2903`) | path-id | quintet | yes | |
| `--impact` reach rows | 40 | `src/verbs_navigate.h:2357` (sort `:2331`) | rank (PageRank) | quintet | yes | walk itself uncapped |
| `--impact` importers | `kImportReachRowCap`=40 | `src/graph.h:6190` | **path-id** | `importers= shown_importers= importers_capped=` | yes | `--limit` cannot raise it; no `next=`; absent from the columnar form |
| `--expand` bodies | `--pack-budget-bytes` 64 KB | `src/serialize.h:5481`, `:5493`, `:5565` | file-major, request order | `<bodies shown= total= capped=>` + omitted markers | yes | |
| `--expand` oversized first body | cut at budget | `src/serialize.h:5543–5557`, marker `:5626` | n.a. | `<!-- truncated -->` inside CDATA; **body counts in `shown=`, so `capped="0"`** | n.a. | JSON gives a boolean (`:8536`) |
| `--expand` callee signatures | 16 per body | `src/serialize.h:5161` | **id** (no query) | `<calls total= shown= capped="1">` | yes | disclosed, but the cut is arbitrary |
| `--expand` `sibs=` | `kMaxExpandSibs`=100 | `src/serialize.h:5317` | source | `sibs_total= sibs_capped="1"` | yes | full legend (`:2113`) says "capped at 8" — stale |
| `--expand` `inc=` | `kMaxExpandIncludes`=24 | `src/serialize.h:5342` | source | `inc_total= inc_capped="1"` | yes | |
| `--slice` | no row cap; flow depth 8 (max 32) | `src/slice.h:2981`, `:3478` | def-use / source | `depth= flow_truncated="1"` | yes | |
| `--grep` / `--regex` rows | 100 (or `--pack-top-n`/`--limit`) | `src/verbs_grep.h:602`, `:664` | path-id | quintet | yes | |
| `--grep` collection | `kGrepCollectionBudget`=4,000,000 | `src/search.h:1386` | **ascending fileId, before the tier sort** | `hits_capped="1" counts_floor="1" capped="1"` | yes | **head-cut site**: source-tier hits in later files lost, doc hits kept |
| `--grep` line text | 512 B | `src/search.h:971` | n.a. | `line_bytes=` | ? | not in the compact grep legend |
| `--grep` tier classification | 128 files / 8 MB | `src/search.h:2029` | fileId | `tier_budget= tier_parsed= tier_unclassified=` | partial | |
| `--grep` unindexed candidates | 500 per class | `src/verbs_grep.h:199` | ? | `unindexed_candidates_capped="1"` | yes | |
| `--around` | fanout 32, depth 1 | `src/graph.h:4480`; disclosed `src/serialize.h:1884` | edge weight | `fanout_cut= depth_truncated="1"` | **no** (purpose line only) | |
| `--connect` | `kMaxNodes`=96 / `kMaxEdges`=256 | `src/graph.h:6974`, `:6994` | path length (longest dropped first) | `truncated="paths"`, no count | no (?) | |
| `--connect --max-tokens` | sigs dropped, then legs | `src/mcpverbs.h:3494–3495` | length desc | `truncated="paths" max_tokens= over_ceiling=` | partial | sig removal legend-only |
| `--connect` terminals | `kMaxTerminals`=16 | `src/verbs_navigate.h:2120` (refused); `src/graph.h:6687` (clamp) | id | refused on the CLI; core clamp silent (?) | n.a. | |

### 5.4 Composed verbs

| verb | what is capped | cut at | order | disclosure | compact | note |
| --- | --- | --- | --- | --- | --- | --- |
| `--pack-task` ranking window | `kPackTaskRankTopN`=12 | `src/packtask.h:1405` | rank | **SILENT past 12** — `of_top=` is the window, nothing counts positives beyond it | n.a. | |
| `--pack-task` sig ladder | `sigLadderBudgetBytes` | `src/packtask.h:1057` | rank / file-major collection | `<sigs shown= total= capped=>`, `dropped_positive=`, "ranking: capped" | yes | |
| `--pack-task` far / callers / notes / tests | section quotas | `src/packtask.h:329`; tests `:422` | rank; callers by shared desc | `<X shown= total= capped=>`; an empty section only as "omitted (budget)" / "kept K of N" in `<!-- slice … -->` | yes | |
| `--pack-task` bodies | 6 candidates + budget | `src/packtask.h:1413`, `:1229` | file-major | `<bodies …>`, omitted markers; JSON `bodies_omitted` | yes | |
| `--communities` | modules 30, members 5, bridges 12 | `src/verbs_report.h:2449`, `:2498`, `:2464` | rank mass; member rank; edges desc | `shown_modules= modules_capped=`, `<community shown= capped=>`, `shown_bridges= bridges_capped=` | yes | |
| `--handoff` heuristics | co-change 8, notes 8, docs 4 | `src/handoff.h:302`, `:342`, `:375` | rank / score | `<heuristic n= candidates= capped=>` | yes | |
| `--handoff` budget | drops heuristic rows from the tail | `src/handoff.h:449–455` | priority (docs first) | `withheld="1" withheld_rows= over_ceiling=` | yes | |
| `--handoff` symbols per file | 50 code / 12 docs | `src/handoff.h:148` | source | `syms_total= syms_capped="1"` | yes | |
| MCP body fetch | `kOtherDefCap`=4 | `src/mcpverbs.h:4569` | id | `name_defs=N`, no flag | n.a. | |
| `--deps` | 40 includes per file; 12 files per cycle | `src/serialize.h:7236`, `:7203` | source; SCC order | `<!-- +more -->` with `includes=` total; cycle cut ? | ? | |

### 5.5 Summary: what step 2 fixes, and what step 1 fixes

**Seven SILENT sites** (step 2, and §3.2's red arms on today's binary): the rendered `<lego>` interface cap;
MCP `find_symbol`'s `calledBy` window; `--outline`; the non-lens `--pack-signatures` path; `--pack-top-n` files
past the truncated one; `--with-graph`; `--pack-task` ranks past 12. Plus three **mis-disclosures**: `--expand`'s
oversized-body truncation counted as served (`capped="0"`); `--for`'s r>24 doc removal with no legend clause;
`--for --json`'s `<sigs>` with no `shown=`/`total=`.

**Five cuts that fire before ranking** (step 1's head-cut sites, in priority order): the `--for` `<sigs>`
collection gate and its JSON copy (`serialize.h:4257`/`:4293`, `:8209`/`:8249` — the only one on the default
path of the flagship verb); `--for`/`--expand` bodies regrouped by file before the budget (`:5481`/`:5493`);
the `--grep` collection budget in fileId order (`search.h:1386`); `--outline` (`:6165`); the non-lens
`--pack-signatures` path (`:4526`). Each can drop a higher-ranked row while a lower-ranked one ships, and
only `dropped_positive=` (a count) ever says so.

**Disclosed but arbitrary** — path-, source- or id-ordered lists with a cap, where the cut drops whatever sorts
last rather than the least relevant: `--callers`/`--callees` (path-id), `--uses` (path-id), `--grep` rows
(path-id), `--impact` importers (path-id, no `next=`), `--expand` `<calls>` (id), `sibs=`/`inc=` (source),
MCP `calledBy` (path-id). Step 1 decides an order for each; step 2 already has their attributes.

**Verbs whose cut can only drop the tail today** (rank-ordered at the cut and disclosed): `--for` `<sigs>`
ladder and tail, `--for --limit` page, `--adaptive`, the relevance floor, `--impact` reach rows, `--recall`,
`--slice` (`order="defuse"`), `--communities`, `--handoff` heuristics and budget, `--pack-task` sections, the
map under `--top-k`/`--max-tokens` (the auto-flip reorders after K is fixed and nothing trims after it).

**Docs out of step with code, found on the way:** `docs/LIMITS.md` marks `src/forpage.h` as disclosing nothing
(it carries the quintet — a generator blind spot: `docs/limits_build.py` reads only `<noun>_capped`, so the fix
is in the generator, never a hand edit of the generated file); the `--expand` full legend says `sibs=` is "capped at 8" where the code caps at 100;
`serialize.h:7259`'s note that JSON skips the ladder is stale (`:8424` runs it).

### 5.6 INDEXING-class caps (bound what can be found; a miss here is a recall miss, not a chop)

Disclosed: `kChurnMergeBombMaxFiles` 100 (`merge_bombs_skipped=`); `kCoBoostMaxFilesPerCommit` 30 and
`kCoBoostMaxPartnerFiles` 8 (`coboost_*_capped`); the doc-mention caps 8/2/6 (`doc_mentions_capped`); the
mention caps 16/4/8 (`mention_*_capped` + `_total`); `kMaxUniqueQueryTerms` 1024 (`terms_capped`);
`kMatchMaxHits` 5000 (`hits_capped`); `kMaxAggsModeled` 8000 (`aggs_capped`); `kMaxBindings` 32 (floor flag);
`kMaxFamily` 64 (`<capped what="family">`); `kMaxHunkSide` 24 (counted); `kMaxMacroDepth` 4 / `kMaxNestDepth` 8
(a note); `kMaxProbeCommits` 40000 ("unknown"); `kMaxRefs` 512 (refused); the rename caps 8/4000;
`kSkillScanFindingCap` 200 (`shown/total`).
Not disclosed: `kChaConeCap` 4096 (?), `kCoBoostMaxSymbolsPerFile` 3, `kMentionMaxSymbolsPerFile` 3 (?),
`kForPageUnionSymbolCap` 8, `kFieldWalkCap` 16, `kMaxAliasDepth` 8, `kMaxChainDepth` 8, `kMaxCandidates`
200000, `kMaxIdentsPerLine` 256, the import/qualifier depth caps 256/256/512/32, `kMaxNamesTracked` 2e6,
`kMaxSample` 80 / `kMaxScored` 4000 (eval only), `kType3MaxBucket` 1024 / `kType3MaxTokensForLcs` 4096 (clone
groups are a floor). `docs/LIMITS.md` is the authoritative table; this list is its 2026-09-23 reading.

**Not resolved by this survey** (marked `?` above): `kChaConeCap`'s disclosure; `--deps`' cycle-cut disclosure;
the order of `--connect`'s terminal clamp and lego implementors; the MCP twins of `--communities`, `--handoff`
and `--expand`; whether the siblift and `kExpandMaxSeeds`/`kExpandMaxPer` caps say when they bit rather than
only that a lift happened.


### 5.7 Which cuts to fix first — a provisional ranking, and how it was challenged

**Provisional until the meter has rows.** The only routing data today is our own agents' dogfood fallbacks on
this repository: 145 logged fallback lines across one day's lane reports, mentioning `--for` 44 times,
`--callers` 31, `--expand` 28, `--grep` 26, `--uses` 12, `--quality-delta` 11, `--affected` 7, `--impact` 6,
`--regex` 5. That is a proxy for what *we* ask this tool on *this* tree, not for the user base; the ranking
re-runs when the substitution meter's verb table exists for a second operator. The weight is
**frequency × severity × likelihood the cut fires**, where severity ranks a head-cut or a false `capped="0"`
above a silent tail cut, and that above a disclosed arbitrary cut. Likelihood is read off the cap: a 6,000-byte
pool for six bodies fires on most calls that serve bodies; a 4,000,000-hit collection budget fires on
practically none. Checking likelihood is what moved the proposal below around.

| # | fix | why here | stair-step | pin / re-anchor cost |
| --- | --- | --- | --- | --- |
| 1 | **`--for` bodies and the `<sigs>` tiers.** (a) auto-bodies regroup by file before the 6,000 B pool applies (`serialize.h:5481`/`:5493`) — a head-cut on the default path that fires on most body-bearing calls; rank first, then cut, then `<bodies>` names what it skipped. (b) the doc excerpt removed at r>24 with no clause (`:4358–4364`) — always on, silent; one compact clause. (c) the `<sigs>` collection gate walking files before the rank re-sort (`:4257`/`:4293`, JSON `:8209`/`:8249`) — a head-cut, but at 64 KB it rarely fires on a 40-row quota; fix by moving the re-sort ahead of the gate, cheap once (a) is done. | highest frequency, head-cut on the default path | (a) step 1; (b) step 2; (c) step 1 | **high**: `--for` has ~109 output-pinning gates (goldens, byte ceilings) that run once per train; body order changes bytes, so `compactlegendcheck`'s `--for` pins and the body goldens re-anchor with the delta stated |
| 2 | **`--expand`'s false completeness.** An oversized first body is truncated with the marker inside CDATA and still counted in `shown=`, so the root says `capped="0"` (`:5543–5557`, `:5626`); callee `<calls>` are cut at 16 in node-id order (`:5161`); the full legend says `sibs=` caps at 8 where the code caps at 100 (`:2113` vs `:5317`). | a false "complete" is the worst honesty defect the contract has; `--expand` is the third most-asked verb; the fix is small | disclosure step 2 (cheap, first); callee order step 1 (needs a priority: caller-count descending when no query) | **moderate**: `--expand` goldens, the compact pin for `ripwire.expand/v1`, the sibs legend text; JSON already carries a boolean |
| 3 | **`--callers`/`--callees` 40-row cap in path-id order** (`callhierarchy.h:150`, `verbs_navigate.h:174`) **and MCP `find_symbol`'s silent `calledBy` window** (`mcpverbs.h:718`/`:757`). | second most-asked verb; the cut drops whatever sorts last; the MCP twin drops it silently | `calledBy` disclosure step 2 (cheap); ordering step 1 — priority proposed as tier (source before test), then the caller's own map rank `k=`, then path, reusing the rank the map already computes | **moderate**: `--callers` goldens, `pagingsweepcheck`, MCP parity/contract gates |
| 4 | **`--uses` 100-row cap in path-id order** (`verbs_navigate.h:686`, MCP `:2903`). | same defect class as #3, lower frequency, and a 100 cap fires less often | step 1, sharing #3's rank-before-cap helper | **low–moderate**: `--uses` goldens + MCP twin |
| 5 | **`--impact` importers: path-id, `importers_capped=` with no `next=`, `--limit` cannot raise it, absent from the columnar form** (`graph.h:6190`). | fires on any widely-imported file; disclosed but not fetchable — a principle 3 violation, since the remainder has no deterministic call | step 2 (`next=` or honour `--limit`); order step 1 | **low**: `--impact` goldens and one compact clause |

**What the proposal had that this ranking demotes, and why.** The `--grep`/`--regex` collection budget
(`search.h:1386`) is a genuine before-ranking cut, but at 4,000,000 collected hits it is dormant on every
tree this tool has been run on; it stays on the step-1 list, not in the top five. The `--regex` whole-file
omission on a byte spelled by number is a different defect (a matcher bug, not a cap) and belongs to its own
lane. Below the five, in this order: `--pack-task`'s silent rank window past 12 (`packtask.h:1405`; composed
verb, low frequency, but the flagship one-call verb should not be silent), `--outline` and the non-lens
`--pack-signatures` path (silent and file-major, but almost unasked), `--with-graph` and the rendered `<lego>`
interface cap (silent, opt-in surfaces), `--pack-top-n` files past the truncated one (deprecated verb).

**What the stair-steps already cover.** Every row above is either a step-1 order decision or a step-2
disclosure; none needs step 3 or 4, and none changes what is *served* — only where it lands and what the
document says about it. The §3.2 gate is what keeps the seven silent sites and the `capped="0"` case from
returning after they are fixed.

### 5.8 Where each row stands against the cut-fix lanes (status as of 2026-09-24)

Every table above describes `60b65f02`, and nothing in this note claims a fix. On 2026-09-24 four lanes that
address rows of §5 were in review. Each row below names the lane that *proposes* the change, so it stays true
in whatever order they merge. A row is closed only when the step-0 re-run under `## Results` confirms it on a
merged `main`.

| §5 row | proposing lane | what the lane proposes |
| --- | --- | --- |
| `--for` collection byte gate (XML and JSON); `--for --json` `<sigs>` with no `shown=`/`total=`; the stale `serialize.h:7259` note | `lane/cutfix-for-sigs` | a rank-first gate with `total=` per §1.3; JSON `sigs_shown`/`sigs_total`; the note rewritten |
| `--for` rank tiers: the doc removed past r=24 | `lane/cutfix-for-sigs` | `docs_dropped=N` and a present-only legend clause |
| `kMaxSig` 240 B | `lane/cutfix-for-sigs` | no change, by decision: the per-row `…` is the disclosure, and the row's `--expand` recovers the text |
| trim ladder, `shown == total` with `capped="1"` | `lane/cutfix-for-sigs` | a present-only clause that gives that case a reading |
| auto-bodies, and `--expand`/`--detail`/`--pack-task` bodies (`packBodies`, file-major) | `lane/cutfix-bodies` | a rank-first budget walk, survivors regrouped by file, every omitted body named |
| `--expand` oversized first body (`capped="0"`) | `lane/cutfix-bodies` | `capped="1"`, and `truncated="1" lines= next=` on the body; nothing inside the CDATA |
| `--expand` `<calls>` in node-id order | `lane/cutfix-bodies` | fewest same-named definitions first, then id |
| `--expand` `sibs=` legend ("capped at 8") | `lane/cutfix-bodies` | the legend says 100 |
| `--outline`; non-lens `--pack-signatures` | `lane/cutfix-bodies` | a rank-first walk; `shown= total= capped="1"` on a cut, `total=` per §1.3 |
| `--callers`/`--callees`; `--uses` (CLI, MCP, member-field arm) | `lane/cutfix-navlists` | tier, then resolved in-degree, then path: one order for the cap, the rows and paging |
| MCP `find_symbol` `calledBy` window | `lane/cutfix-navlists` | `calledBy_total`, `shown_calledBy`, `calledBy_capped`, `calledBy_next` when cut |
| `--impact` importers | `lane/cutfix-navlists` | ranked by each importer's own importer count; `--limit` sizes the tier. **Still no `next=`**: a dead-end cut under §1.3 that a documented `--limit` can continue. The columnar form keeps the count only |
| `--grep` collection budget in fileId order | `lane/cutfix-grep` | the files are ranked by tier before the budget is spent |
| `--grep` rows | `lane/cutfix-grep` | no change: the window is already a slice of the tier-sorted list, so the cut drops the doc/test tier first ("path-id" here means tier, then path) |
| `--grep` line text `line_bytes=`; the tier classification budget | `lane/cutfix-grep` | compact readings for `line_bytes=`, `tier=`, `tier_budget=`; `tier_files=` gives the classification its total |
| `--grep` `<unindexed>` list | `lane/cutfix-grep` | tried and reverted, so path order stays: a tier sort put `CMakeLists.txt` below lock files |

**Rows no lane addresses** (SILENT first):

- SILENT: the rendered `<lego>` interface cap of 12 (`--sections=lego`); `--with-graph`'s 8 nodes;
  `--pack-top-n` files past the truncated one; the `--pack-task` ranking window past 12.
- Counted nowhere: `--for` `<sigs>` positives at rank 41+ whose file is already in the head; auto-body
  positives past the 6 candidates; lego methods (6) and implementors (16) (`<!-- +more -->` with no count);
  MCP body fetch `kOtherDefCap` 4 (`name_defs=` with no flag).
- Disclosed, but with no compact reading or no count: `--around` `fanout_cut=`; `--connect`
  `truncated="paths"` (no count) and its `--max-tokens` signature removal (legend only).
- Unresolved (`?` in §5): `--connect`'s terminal clamp in the core; `--deps`' cycle cut; whether MCP `for`
  says it has no bodies section; the map's `--top-k` window (`shown=` in the header comment, no `capped=`).
- The generator blind spot: `docs/limits_build.py` misses `pageDisclosure`'s bare `capped=` (the `forpage.h` row).
- Window disclosure: whether a candidate window (`--for` 40, `--pack-task` 12, auto-bodies 6) should say what
  lies past it (a `ranked=`-style attribute, §1.3) is one decision for every ranking verb, not a per-site fix.

**This inventory is a floor, not a census.** The 2026-09-24 review re-read the emit code and found
output-class cuts this survey did not list, among them `--zoom`'s bridges and its `--mermaid` module caps,
`--tree`'s three symbols per file, `--situ`'s co-change probe window and its decl/def partner cap,
`--plan-lanes --brief` claims per lane, the `--run-trace` tail view with no `capped=`, MCP `owners` and
`mentions` windows with the cap half switched off, and LSP `workspace/symbol`. They join these tables when
step 0 runs; until then, a verb missing from §5 has not been shown to be free of silent cuts.

---

## 6. Decisions this note needs from the owner

1. **Chop rate as a gate.** Adopt §3.3's hard zero on silent-chop for the train, or keep it a reported number
   for one release first.
2. **The emit order of the file-grouped lists.** The `--for` lens `<sigs>` already emits in `r=` order (P7,
   2026-09-05). What still groups by file is `<bodies>` (`packBodies`) and the non-lens `--pack-signatures`
   `<sigs>`. Step 1 keeps that grouping and only guarantees the cut runs on rank; emitting them in pure rank
   order would be a contract change for their parsers, and needs a separate decision.
3. **Callee lists in node-id order** (`--expand`, `--around`, `--exemplar`). Step 1 proposes query rank when a
   query exists and caller-count descending otherwise; the alternative is to leave them and only disclose the
   cap (step 2). Either is honest; only one moves the head.
4. **Step 3 as a default or a flag.** The note registers it as the default behaviour of a body that does not
   fit; the conservative alternative is an opt-in (`--lines`-style) for one release with the same bands.
5. **The disclosure byte budget.** 64 bytes per cut document is proposed; the owner may set it lower and
   accept fewer attributes, or higher and accept a compact clause.
6. **Which proxy becomes the train's number.** §3.3 keeps terminality as the objective and the offline table
   as the gate; if the meter's single-operator log is retired, the offline table is all there is and should
   say so on its face.

## 7. What this note does not claim

No number here is a result. The R5 and def-use figures are quoted from their own notes as the reason the
steps are ordered as they are, not as evidence that the steps will pay. Nothing in this note is quoted on
`README.md`, and nothing in it changes a default.

## Results

*(empty — this section is filled by the lane that executes step 0, with the population fingerprints first.)*
