# Retrieval confidence and abstention

**Status: investigation. No behavior change, no `src/` change, nothing published outside this
directory.** Every number below is local evidence for a decision that has not been taken. None of it
is quoted in `README.md` or in any other claim surface, and the pre-registration in §5 is what would
have to be met before any of it turns into code.

---

## 1. The finding, first

On a held-out slice of 92 LocBench instances, `--for`'s shipped `confidence=` attribute is
**directionally right, weakly discriminating, and unusable at its only operating point.**

- It separates **function-grain** correctness: a gold function is in the served head 88.9% of the
  time when `confidence="high"` against 51.4% when `"low"` — a difference of **+0.375
  [+0.132, +0.513]**, which excludes zero.
- It does **not** separate **file-grain** correctness: 94.4% against 81.1%, a difference of
  **+0.134 [-0.081, +0.247]**, which includes zero.
- It does not separate the bundle as a whole at all: a gold file is named *somewhere* in the answer
  93.2% of the time under `"low"` against 94.4% under `"high"` (**+0.012 [-0.194, +0.105]**).
- Discrimination is in the weak band either way: AUROC **0.580** against a missed gold file,
  **0.622** against a missed gold function.
- At its only operating point — warn iff `confidence="low"` — it flags **74 of 92** answers. It
  catches 14 of the 15 file-grain misses and pays for them with **60 false warnings on correct
  answers**: a false-warn rate of **0.779**.

So the attribute is not noise, which is worth saying after two recorded negatives on the same axis.
But nothing here licenses abstaining on it. A rule that withholds 60 correct answers to suppress 14
wrong ones is worse than the answer it replaces, and a warning that fires on four calls in five is
one a caller learns to skip.

There is a second, structural finding that matters more than the rates:

> **There is no threshold to tune.** `margin_pct=` is `0` for every single `"low"` row (74 of 74) and
> non-zero for every `"high"` row. The pair is one bit plus a number that only exists when the bit is
> set, so its ROC curve has three points and its "sweep" has one interior candidate. Any future work
> on this axis has to add a *fact*, not a cut-point — which is the same conclusion the ARB rounds
> reached from the other direction, now reproduced on a corpus where every query is answerable.

---

## 2. What ships today, and where it came from

*Agent Retrieval Bench* ([arXiv:2607.24882](https://arxiv.org/abs/2607.24882)) evaluates repository
context retrieval across four retrieval families and reports that no family dominates — and,
separately, that no retriever tells its caller when its own ranking should not be trusted. It names
abstention as the unsolved axis.

We took the disclosure half of that and shipped it. `--for` already computed a relevance-cliff gap
statistic for the `--adaptive` lever, so the root now states what that statistic already knew:

```
<ctx task="…" route="subtoken+body" confidence="high|low" margin_pct="N" …>
```

`deriveForConfidence` (`src/lexical.h`) reads the finished `AdaptiveCut` and nothing else:

- `confidence="high"` iff the cliff scan found a material score drop *inside* the ceiling
  (`!hitCeiling`), **or** every positively-scoring symbol already fits in the served head
  (`positiveHits <= servedTopN`);
- `confidence="low"` otherwise — a flat ranking with more positive matches than the head shows;
- `margin_pct=` is that drop as a whole percent, and `0` when the ceiling was hit.

Three properties are deliberate and remain true: there is **no new scorer**, the `--for --json`
dialect serves the *same* derivation rather than a second opinion, and the two attributes can never
disagree with the `--adaptive` cut because they are computed from the same object. A legend clause
defines both, so a reader who has never seen the attribute can still price it. The lineage row is in
[`LINEAGE.md`](../LINEAGE.md); the registration and the instrument are `bench/arb/run_arb.py`, whose
task-to-verb mapping was written down before a single sample ran.

### What was already measured, and what it did not cover

Two pre-registered rounds in [`EVALS.md`](../EVALS.md) scored this signal against ARB's own
unanswerable-query splits, and both are **recorded negatives**:

| round | signal tested | outcome |
| --- | --- | --- |
| abstention calibration (2026-08-29) | `confidence=` / `margin_pct=` | AUROC ≈ chance (0.48 / 0.51); `"low"` fires at 85–87% *regardless of answerability*; no operating point |
| abstention round 2 (2026-08-30) | the adaptive cut's corpus-support counts | primary AUROC 0.434 / 0.409; no operating point exists behind the gate either |

Round 2 closed a shape, explicitly: a future round "needs a fact that is NOT derived from the lexical
score distribution at all."

Both rounds asked **"does the signal know when there is no answer?"** That is ARB's question, and it
is the right one for a retriever that is allowed to return nothing.

Neither round asked the question a CLI that must answer actually faces: **"does the signal know when
*its own answer* is wrong?"** The label is different (correctness, not answerability), the query mix
is different (every query has a real fix behind it), and — as §1 shows — the answer is different too.
That gap is what this branch measures.

---

## 3. The calibration measurement

### 3.1 Why this is not an ECE

`confidence=` is a two-valued label and `margin_pct=` is a sharpness score. Neither is a probability,
and the tool declares no mapping from either to P(the answer is right). Expected calibration error
and Brier score both need that mapping; computing one by inventing a mapping would be measuring the
mapping, not the tool. What *can* be measured without inventing anything:

1. the hit rate inside each band, with an interval;
2. a reliability table over `margin_pct=` bins — read for **monotonicity**, not against a diagonal
   that does not exist here;
3. **discrimination** (AUROC) of the score the ARB registration already defined.

The script imports that score's AUROC, confusion and sweep straight from
`bench/arb/score_abstention_calibration.py`, and imports the split and the gold/hit definitions from
`bench/locbench/run_locbench.py`, and it invokes the binary through `run_arb.py`'s own `run_bin`, so
a LocBench row and an ARB row are produced by the same call and cannot mean different things by "the
registered rule" or by "how we run the tool". It owns no definition another artifact also owns.

### 3.2 Corpus, invocation and honesty boundaries

- **Corpus.** LocBench V1 test (`czlll/Loc-Bench_V1`), the frozen 560-row slice, sha256
  `5bbcea4b…04c97`, verified by the script before it scores anything.
- **Split.** `heldout` under `run_locbench.py`'s salted repository-disjoint `frozen_partition` — 306
  of the 560 rows. The split is by *repository*, so no repository contributes to both sides.
- **Instances scored: 92.** Those are the held-out rows whose snapshot is already on disk at the
  instance's own `base_commit`, proved by the checkout marker `run_locbench.py` writes. **214
  held-out rows were skipped because their snapshot is not on this disk** — a disclosed floor, not a
  filtered sample. Nothing was fetched.
- **Zero silent skips otherwise:** `for_fail 0`, `index_fail 0`, `parse_fail 0`, `timeout 0`,
  `non_ripwire_language 0`, `no_gold 0`. Every one of the 560 dataset rows lands in exactly one of
  those buckets or in the 92.
- **Invocation:** `ripwire <repo> --for="<first 1200 chars of the issue>"` — default flags. No
  `--top-k`, no `--adaptive`, no budget. That is the bundle an agent is actually handed. (Checked on
  two instances: neither `--top-k` nor `--pack-top-n` moved `confidence=`/`margin_pct=` on this
  corpus, so the label is a property of the score distribution rather than of the head size the
  caller asked for.)
- **Gold and hit.** Gold is LocBench's own `edit_functions` plus the files the fix patch touches. The
  headline metrics grade the **ranked head** — the `<sigs><d>` rows — because that is what
  `confidence=` makes a claim about. The looser `bundle_*` population (head ∪ file-grain tail ∪ hops)
  is reported separately rather than folded in, since crediting the tail to `confidence=` would grade
  the attribute against text it does not describe.
- **Determinism:** two identical 8-instance runs produced byte-identical per-instance rows (wall
  clock excluded). Checked before any table below was read.
- **Parser coverage is not hiding anything:** the gold file was absent from the index in **0 of 92**
  instances, so every miss below is a ranking miss.

### 3.3 The tables

Generated by `bench/locbench/calibrate_confidence.py` (§6 has the command);
binary `ripwire 0.6.1 (dev, built_from=755f9026f)`.

**Base rates over the 92:** a gold file is in the served head 83.7% of the time, a gold function
58.7%, every gold file 60.9%. `confidence="high"` on **18** instances (19.6%), `"low"` on **74**.

#### `confidence=` against four grains of "the gold is in the answer"

| grain | high (n=18) | low (n=74) | difference (high − low) |
| --- | --- | --- | --- |
| a gold **file** in the served head | 0.944 [0.742, 0.990] | 0.811 [0.707, 0.884] | **+0.134** [−0.081, +0.247] — *includes 0* |
| a gold **function** in the served head | 0.889 [0.672, 0.969] | 0.514 [0.402, 0.624] | **+0.375** [+0.132, +0.513] — excludes 0 |
| **every** gold file in the served head | 0.667 [0.437, 0.837] | 0.595 [0.481, 0.699] | **+0.072** [−0.180, +0.277] — *includes 0* |
| a gold file named **anywhere in the bundle** | 0.944 [0.742, 0.990] | 0.932 [0.851, 0.971] | **+0.012** [−0.194, +0.105] — *includes 0* |

Intervals are Wilson; the difference carries a Newcombe interval, because the claim being made is
about a difference and two overlapping single-group intervals are not a test of one.

That the four grains disagree is itself a result, and §7 asks for help with it: **one signal cannot be
"calibrated" without first fixing which grain of correctness it is a claim about.** Ours is currently
a claim about none of them in particular.

#### Reliability over `margin_pct=` bins (grain: a gold file in the served head)

| margin_pct | n | of which `high` | hits | hit rate [95% Wilson] |
| --- | --- | --- | --- | --- |
| 0 | 74 | 0 | 60 | 0.811 [0.707, 0.884] |
| 1–20 | 1 | 1 | 1 | 1.000 [0.207, 1.000] |
| 21–40 | 14 | 14 | 13 | 0.929 [0.685, 0.987] |
| 41–60 | 3 | 3 | 3 | 1.000 [0.439, 1.000] |
| 61–80 | 0 | 0 | 0 | n/a |
| 81–100 | 0 | 0 | 0 | n/a |

Three things to read off it, none of them flattering:

1. **Bin 0 and the `"low"` band are the same 74 rows.** The bit and the number are redundant on this
   corpus; `margin_pct=` adds no ordering information to `confidence=`.
2. **No margin above 60 was ever observed.** The attribute's advertised range is a range the corpus
   never used.
3. **Every `"high"` here was earned by the cliff branch.** The second way to earn `"high"` — every
   positive match already shown — fired zero times in 92 runs, so half of the shipped rule is
   untested by this measurement.

#### Discrimination, and the cost of the only operating point

| grain | n | misses | AUROC (positive class = miss) | DOP miss-recall | DOP false-warn rate |
| --- | --- | --- | --- | --- | --- |
| gold file in the head | 92 | 15 | 0.580 | 0.933 | **0.779** |
| gold function in the head | 92 | 38 | 0.622 | 0.947 | **0.704** |

DOP = the declared operating point, warn iff `confidence="low"`. Against the band table the ARB
rounds registered (AUROC ≥ 0.65 meets, ≥ 0.55 weak; false-abstain ≤ 0.10), both grains land in
**weak** on discrimination and both miss the safety floor by roughly 7×.

#### Where the misses live

| population | n |
| --- | --- |
| scored | 92 |
| gold file never indexed (a parser limit, not a ranking one) | 0 |
| gold file indexed but not in the served head | 15 |
| — of those, warned (`confidence="low"`) | 14 |
| gold file in the served head | 77 |
| — of those, warned — **the false-warn cost** | 60 |

#### EXPLORATORY — two other root facts, reported, deciding nothing

| signal | n | AUROC vs a missed gold file | AUROC vs a missed gold function |
| --- | --- | --- | --- |
| `coverage=` | 88 | 0.654 | 0.486 |
| `dropped_positive=` | 0 | n/a | n/a |
| `margin_pct=` alone | 92 | 0.580 | 0.622 |

`coverage=`'s 0.654 against a missed *file* is the most interesting number in this document and it is
**not a finding**. It is one of three signals looked at after the fact, on a *conditional* attribute
— `coverage=` is emitted only on a thin answer, so its 88 rows are a self-selected subpopulation, not
the same denominator as the rows above — and it reverses to 0.486 on the function grain that
`confidence=` is best at. Promoting it on this evidence is precisely the failure the ARB
registrations were written to prevent. It is named here so that it is on the record as an
after-the-fact observation and can never reappear later as this round's hypothesis.

---

## 4. What abstention could mean for a CLI that must answer

`ripwire` is not a retriever that may return nothing; it is a command that a script and an agent both
call expecting output on stdout. So "abstain" has to be spelled as one of these, and each costs
something real. The honesty contract that judges them is the repository's own: a zero is a
measurement and absent is not zero; every truncation is disclosed; **no surface may quietly round,
guess, or omit** — which forbids a confident-looking answer that lies by omission, and equally
forbids a confident-looking *warning* that does.

| option | what the caller gets | cost | consistent with the contract? |
| --- | --- | --- | --- |
| **(a) answer, with the warning** *(ships today)* | the full bundle plus `confidence=`/`margin_pct=` and a legend clause | 34 bytes of attributes on every root, plus a 222-byte legend clause, all charged against the token budget | **Yes** — it is a labelled fact with a defined derivation. But at a 0.78 false-warn rate it is a fact the caller has no reason to act on, and we have no evidence any caller does. |
| **(b) answer, and name a better verb** | the bundle plus "this looks flat — try `--from-trace` / `--grep` / a narrower query" | the recommendation has to be *earned*: a measured mapping from "flat head" to "which verb wins here", which does not exist | **Only if measured.** Naming a better verb we have not measured is exactly the confident-looking claim the contract forbids — it converts an honest "I am unsure" into an unbacked instruction. Consistent the moment a verb-selection eval backs it; not before. |
| **(c) a short "I cannot rank this confidently" + the evidence** | the counts behind the judgement instead of the ranking | withholds the answer. On this sample that is 74 of 92 calls, **60 of which were right** at file grain | **Yes, and currently unjustified.** Honest, but it trades a mostly-correct answer for a correct and useless one. The contract does not require withholding a good answer; it requires not overselling it. |
| **(d) refuse (non-zero exit, no bundle)** | nothing | (c)'s cost plus composition: every script, pipe and MCP caller that assumed output now has an error path | **In principle yes, in practice no.** A refusal is only honest if it is rare. At a 78% false-warn rate it is not rare, and a tool that refuses four calls in five has redefined itself. |

Two consequences we think the numbers actually support, neither of which is an abstention:

- **(e) scope the claim to the grain it holds at.** The one separation that survives an interval is
  function-grain. The legend sentence today says "treat the set as a starting point, not an answer",
  which is a claim about the *set* — the grain where the signal is weakest. Saying what the attribute
  is a claim about is a disclosure fix, not a behavior change, and it is the cheapest honest move
  available. It still needs replication (§5) before it is written down as true, because n=92 is one
  corpus.
- **(f) keep the axis where the negatives left it.** `--for`'s behavior stays unchanged and the axis
  stays *disclosed, not acted on*. Three measurements now agree on that, from two directions.

---

## 5. Pre-registration — what would license a change

Written before the round it describes has been run, and recorded here rather than in `EVALS.md`
because nothing in it is a published claim yet. Promoting it to `EVALS.md` is a separate decision.

### 5.1 The instrument

Not a recalibration. `EVALS.md` closed recalibration of the lexical score distribution twice, and §3.3
closes it a third time from the correctness side: `margin_pct=` carries no ordering information that
`confidence=` does not already carry. The round therefore proposes **two facts that are not functions
of the score distribution at all**, computed after the head is chosen and emitted only on
`--for --json` (harness-facing, never the XML root — the precedent and the mechanism both exist:
`test/forcalibfactscheck.sh` arm (5) already fails if round 2's `kept`/`scored`/`corpus` appear as XML
root attributes, and this round's facts would be added to that arm in the same commit that emits
them, so "promote only if the calibration earns it" stays a gate rather than an intention):

- **PRIMARY — graph cohesion of the served head.** `head_components` = the number of weakly connected
  components among the served head's symbols under one-hop call edges, and
  `head_top_component_share` = the largest component's share of the head. The hypothesis, stated
  before measurement and with its direction: a head that is one connected neighbourhood is a head
  that found a *subsystem*; a head scattered across many components is a bag of independent name
  matches. Abstain score = `1 − head_top_component_share`.
- **SECONDARY, reported, decides nothing — co-change agreement.** The mean pairwise co-change rate of
  the head's files in git history. Registered as secondary in advance so it cannot become the finding
  afterwards.

Both are already computable from structures the binary holds at emit time; neither is a new scorer.
Call-edge resolution is name-based, so `head_components` inherits the ambiguity the map already
discloses — the round must report `ambiguous=` alongside it rather than treat the graph as complete.

### 5.2 The bands

Scored by the same harness, on the same held-out split, positive class = a missed gold **function**
(the grain where any separation exists at all):

- **AUROC** of the primary: **≥ 0.70 meets** · [0.60, 0.70) weak · < 0.60 does not meet · **≤ 0.35 is
  a directional refutation**, recorded as such and never read as a pass.
- **An operating point must exist:** some threshold with **false-warn ≤ 0.20 at miss-recall ≥ 0.50**.
  The ARB rounds used ≤ 0.10; 0.20 is stated (and stated *here*, in advance) because a *warning* can
  tolerate a higher false rate than a *refusal* can. It is still nearly 4× stricter than the 0.779 we
  measure today, which is the point.
- **Replication:** the bands must be met on the 92 already on disk **and** on a second sample of at
  least 92 more held-out instances materialized from the remaining 214. One corpus of 92 does not
  license a behavior.

### 5.3 The self-reject rules

Any one of these fires and the round is a **negative**; nothing ships, and the negative is recorded
with its numbers the way the two before it were:

1. **No improvement over what we already ship.** The primary's AUROC must beat the shipped
   `confidence=`'s **0.622** by **≥ 0.05**, with a bootstrap interval on the *difference* excluding
   zero. A new fact that merely matches the old one is not a reason to emit a new fact.
2. **Fire-rate ceiling.** Any abstention or warning rule whose trigger fires on **more than 25% of
   queries** is rejected *regardless of its AUROC*. A warning that fires on a quarter of calls is a
   warning the caller stops reading, and the current 80% fire rate is the concrete evidence for that
   ceiling rather than a taste.
3. **No behavior without a downstream win.** Even a passing instrument licenses only the *fact*, on
   `--for --json`. Changing what `--for` does still requires §6's downstream experiment to clear its
   own bar.
4. **Grain honesty.** If the new fact separates on one grain and not another — as the shipped one
   does — the emitted legend must say which grain, or the fact is not emitted. No grain-agnostic
   confidence claim ships again.

---

### 5.4 Pre-registration: `served_syms` (2026-09-23)

Written before this round's number exists. `served_syms` — `grade()`'s count of `<sigs><d>` rows in
the `--for` bundle, i.e. the size of the served head — is not a new fact: it is already emitted,
already disclosed to every caller, and already computed by `calibrate_confidence.py`'s `grade()`
(`served_syms=len(head)`) for every scored row. It has simply never been scored as a miss detector
against §5.2's band. A margin-resolution review (`reports/rv-margin-resolution.md`, HIGH-1,
2026-09-22) reports, **as prior knowledge disclosed here rather than re-derived**, that `served_syms`
scored **0.669 (file_hit) / 0.723 (func_hit)** AUROC on the pre-registered 92 and **0.769 / 0.791** on
a separate, non-pre-registered 40-row sample — in both cases without ever computing an operating
point, and without any record of which direction (larger or smaller `served_syms`) was treated as
"more miss evidence" (the reviewer's scratch script is lost). This section fixes, in advance of that
number being recomputed under a named procedure, everything §5.2's band needs to be checked honestly:
which population, which statistic, which direction, which thresholds, which tie rule, and what each
outcome may be said in public.

**Scope.** This is not a new instrument under §5.1 — `served_syms` is not proposed as a replacement
for `confidence=`/`margin_pct=`, and §5.1's "not a recalibration" argument does not apply to it (it is
not a function of the lexical score distribution; it is a count of rows). This is the overdue scoring
of a signal that already ships, against the band §5.2 already set for a signal that would ship.

#### 5.4.1 Population, identified by fingerprint, not by count

"The 92" is not "however many rows this run happens to produce." Before any `served_syms` number is
computed, the run must reproduce §3.3's own figures on the asset tree it points at:

- `confidence=` split **74 low / 18 high** (n = 92),
- misses **15** (file grain) / **38** (func grain),
- `margin_pct=`/score AUROC **0.580** (file_hit) / **0.622** (func_hit).

All four numbers must match before a single `served_syms` figure is reported. **If any one of them
does not reproduce, the run stops there** and reports exactly that — "the population on this asset
tree is not the pre-registered 92" — with the actual figures it got instead. No `served_syms` AUROC,
threshold, or operating point is reported "on the 92" from a run that failed this check, no matter how
plausible the resulting numbers look. This is the general "check what the population IS, not just that
the number reproduces" lesson, applied here as a mechanical gate rather than a habit to remember.

Every report of a result under this registration — PASS, FAIL, or fingerprint mismatch — **must name
the asset tree it read (`--assets` path) and the binary's `built_from=` sha** (both already printed by
`calibrate_confidence.py`'s `# calibrate_confidence — assets=... binary=...` stderr line and carried
into `meta.binary_version`/`meta.assets` in its JSON output). A result that does not name both is not
a report under this registration.

#### 5.4.2 The statistic

`served_syms(row) = row["served_syms"]`, read exactly as `calibrate_confidence.py`'s `grade()` already
reads it (`len(head)`, where `head` is the `<sigs><d>` rows parsed by `served_head()`) — no
re-parsing, no re-derivation. The invocation is unchanged from §3.2: one default
`ripwire <repo> --for="<first 1200 chars of the issue>"` per instance, no `--top-k`, no `--adaptive`,
no budget — the bundle an agent is actually handed. `served_syms` is a non-negative integer with no
declared upper bound in the emitted contract (the adaptive cut's ceiling bounds it in practice, but
that bound is an implementation detail of `adaptiveCut`, not part of what `--for` promises).

**Positive classes — both grains, same definitions as §3.2/§3.3:** `file_hit` (a gold file is in the
served head) and `func_hit` (a gold function is in the served head), read exactly as `grade()` already
computes them. Both are scored, exactly as the prior-knowledge numbers in 5.4's header report both.

**What the band is gated on.** §5.2 registered its AUROC/operating-point band with "positive class = a
missed gold **function** — the grain where any separation exists at all." This round follows that
choice rather than inventing a looser one: **`func_hit` is the sole gating grain.** A PASS requires the
operating-point criterion (below) to be met on `func_hit`. `file_hit` is scored, reported in full
(AUROC, CI, and its own threshold sweep), and **never gates a PASS** — it is exploratory in the exact
sense §3.3's `coverage=`/`dropped_positive=` block already uses that word: reported so it is on the
record and cannot reappear later as this round's hypothesis if it happens to look better.
*(This is a place §5's existing registration was ambiguous — it registered the func-grain choice for
its own new facts, not for scoring an already-shipped one — and resolving it this way, rather than
requiring both grains or inventing an OR/AND rule, is flagged in the report as a decision for the
reviewer.)*

#### 5.4.3 Orientation — fixed now, mechanistically, not chosen on the 92

Registered **now**, from the code the mechanism already runs, **not** from any `served_syms` number on
the 92 (none has been computed under this procedure yet): **larger `served_syms` is registered as more
miss evidence.**

The mechanism (`src/lexical.h`'s `adaptiveCut`, `deriveForConfidence`): when the cliff scan finds no
material within-cap drop (`bestCapDrop < 0.20`), `cut.hitCeiling = true` and `cut.kept = hardCeil` —
the head is filled to the (near-)maximum the query's positive hits and the ceiling allow, i.e. `kept`
(and therefore `served_syms`) sits at or near its largest achievable value for that query. That branch
is exactly the one that yields `confidence="low"` on every row in the 92 (§3.3: "every `"high"` here
was earned by the cliff branch"). When a material cliff **is** found within the cap, `cut.kept` is
clamped down to the cliff rank (or the floor, whichever is larger) — a smaller, more selective head —
and that is the branch `confidence="high"` comes from. §1/§3.3 already establish, as published fact
and not as a number this round re-derives, that `confidence="low"` rows have the **lower** hit rate at
both grains (file: 81.1% vs 94.4%; func: 51.4% vs 88.9%). Chaining those two already-published facts —
"low confidence ⟺ hitCeiling ⟺ larger served_syms" and "low confidence ⟺ lower hit rate" — gives a
mechanistic prediction for `served_syms` alone, without looking at a single `served_syms` row: **a
larger served head predicts a more likely miss.**

This is stated as a commitment, not a hedge: the scoring code (§5.4.6) applies this orientation as a
fixed constant. If the resulting AUROC comes out **below** 0.5, that is reported as a clean result
under the registered orientation — an AUROC anti-correlated with the registered direction — and is
**not** silently flipped to report `1 − AUROC` as if the round had registered the other way. Flipping
after seeing the number is exactly the in-sample fishing this document exists to prevent.

*(Decision for the reviewer: the task brief offered "state a mechanistic prediction now" or "register
that orientation is chosen on the 92, labelled post-hoc." This registration takes the first path,
because the mechanism above is derivable from source and from already-published §1/§3.3 numbers alone
— it does not require reading a single new row of data. A reviewer who judges the chain weaker than
this document treats it should say so and require the second path instead; that is a live
disagreement, not a settled one.)*

#### 5.4.4 Threshold procedure

`served_syms` is an integer, so its ROC curve is a step function with one candidate cut per distinct
observed value — the same "every distinct score value is a candidate" convention
`sweep_thresholds` (`bench/arb/score_abstention_calibration.py`) already uses, extended by one sentinel
so "warn on nothing" is always a representable point:

- **Candidates.** Let `V` be the sorted set of distinct `served_syms` values among the 92 scored rows.
  The candidate threshold set is `T = V ∪ { max(V) + 1 }`. For each `t ∈ T`, the rule is
  **`warn(row) ⟺ served_syms(row) ≥ t`** (the registered orientation, §5.4.3) — `t = max(V) + 1` warns
  on no row (the "flag nobody" point, which `V` alone cannot represent) and `t = min(V)` warns on
  every row.
- **Tie rule.** Among every `t ∈ T` whose `(false_warn, recall)` satisfies the band (below), the
  **reported operating point is the one with the highest `recall`**; if more than one `t` ties on
  `recall`, the **larger `t` wins** (it warns on a subset of what the smaller one does, i.e. it is the
  more conservative, fewer-false-warnings choice at that recall — the same "ties broken toward the
  more conservative side" convention `sweep_thresholds`'s own F1 tie rule states, translated to this
  rule's `≥`-warns-on-large direction).
- **Verdict rule, exactly.** Let `false_warn(t)` = the false-warn rate and `recall(t)` = the miss-recall
  at threshold `t`, both computed on `func_hit` misses (§5.4.2). **PASS on the 92 iff `∃ t ∈ T` with
  `false_warn(t) ≤ 0.20 ∧ recall(t) ≥ 0.50` on `func_hit`.** Every `t ∈ T` and its
  `(false_warn, recall)` pair — on both `func_hit` and `file_hit` — is reported in full (the entire
  sweep table), not only the chosen point: a table that shows only the winning threshold invites
  exactly the in-sample cherry-pick this section exists to bound.
- **Self-reject, carried from §5.3 and applied here:**
  - **SR-1 (fire-rate ceiling, from §5.3 rule 2).** Any `t` reported as "the" operating point whose
    `warn` rate on the 92 exceeds **25%** of rows is disqualified from being *the* chosen point even
    if it satisfies the band — reported in the sweep table, but not selected. (`recall ≥ 0.50` with 15
    file / 38 func misses out of 92 rows makes a low fire-rate and the recall floor jointly satisfiable
    only if `served_syms` separates considerably better than chance; this is not assumed, only stated
    as the arithmetic constraint the sweep must clear.)
  - **SR-2 (grain honesty, from §5.3 rule 4).** A PASS on `func_hit` alone, with `file_hit` not meeting
    the band at the same or any threshold, is reported as exactly that — "meets on func_hit, not on
    file_hit" — never folded into a single grain-agnostic sentence.
  - **SR-3 (in-sample disclosure).** Any `t` found this way is chosen **in-sample** (it is selected by
    looking at the 92's own sweep table). A PASS under this procedure licenses "worth replicating,"
    never "shippable," until §5.2's replication runs the **same frozen `(orientation, t)`** —
    unchanged, not re-swept — on a second sample of ≥ 92 fresh held-out instances. The orientation is
    already frozen (§5.4.3); the threshold `t` freezes the moment this round's sweep picks it, and
    is what the replication run receives as a fixed input, not what it re-derives.

#### 5.4.5 Uncertainty

- **AUROC.** Reported with a bootstrap 95% CI: resample the **distinct repositories** contributing to
  the 92 with replacement, `len(repos)` draws per resample (the repository-clustered convention
  `bench/agentloop/analyze.py`'s `clustered_bootstrap_lower` already uses, because the 92 are not 92
  independent draws — the 92 are drawn from 88 held-out repositories, so a handful of repos
  contribute two rows each), pool every row belonging to the resampled repos, recompute AUROC on the
  pooled sample, and repeat. **Fixed seed `"ripwire-served-syms-prereg-v1"`, fixed 10,000 resamples**
  (matching `analyze.py`'s own default `n_boot`). A resample whose pooled sample is single-class (all
  hit or all miss on the gating grain) contributes no AUROC and is excluded from the CI's resample
  count, which is reported alongside the CI (e.g. "9,812 of 10,000 resamples usable").
- **Operating point.** At the *chosen* threshold `t` only (never re-swept per resample — the resample
  answers "how stable is this specific `t`'s cell counts," not "would a fresh sweep pick a different
  `t`"), the same repo-clustered bootstrap over `false_warn(t)` and `recall(t)`, same seed, same 10,000
  resamples.
- These intervals describe sampling variability on **this** 92-row draw; they are not a substitute for
  §5.2's replication on an independent sample, and the pre-registration text reporting them must say
  so in the same sentence that gives the interval.

#### 5.4.6 What is reported, and what each outcome licenses

| outcome | what is reported | the sentence it licenses in a public reply |
| --- | --- | --- |
| **Fingerprint mismatch** | which of the four §5.4.1 figures failed to reproduce, and what was measured instead; asset tree path and binary sha | *"served_syms has not been scored against the pre-registered band: the asset tree available today does not reproduce the pre-registered 92-instance population, so no number is reported as measured on it."* Nothing about `served_syms`'s discrimination or an operating point may be asserted. |
| **FAIL** (fingerprint reproduces; no `t` meets the band on `func_hit`, or the only qualifying `t`s fail SR-1) | `func_hit`/`file_hit` AUROC with CI; the full threshold sweep; the disqualifying reason (band not met, or fire-rate ceiling) | *"served_syms, our best disclosed signal, was never scored; scored now on the pre-registered 92, it does not reach the band (false-warn ≤ 0.20 at miss-recall ≥ 0.50): AUROC \<X\> [CI] (func_hit), and no threshold clears both floors together."* A negative is a complete result and is reported with the same numbers a PASS would carry. |
| **PASS** (fingerprint reproduces; some `t` meets the band on `func_hit`, survives SR-1) | the chosen `t`, its `(false_warn, recall)` with CI, `func_hit`/`file_hit` AUROC with CI, the full sweep table, and SR-2's grain-honesty statement | *"served_syms, our best disclosed signal, was never scored; scored now on the pre-registered 92 at threshold t=\<N\> served symbols, it reaches false-warn=\<X\> and miss-recall=\<Y\> on func_hit — inside the pre-registered band. This is an in-sample result on one 92-row sample (per §5.2) and licenses 'worth replicating,' not 'shippable': replication on ≥92 fresh held-out instances, at this same frozen threshold and orientation, has not been run."* No sentence produced under a PASS may drop the replication clause. |

**Counts that cannot be totals are floors, and a zero means "none found."** Any skip bucket this round's
run reports (`no_snapshot`, `wrong_split`, `index_fail`, `for_fail`, `parse_fail`, `timeout`,
`non_ripwire_language`, `no_gold` — the same eight §3.2 already names) is a floor on how many instances
were *available* to be skipped for that reason, never a claim that no more exist; a `0` in any of those
buckets means the run found none under that reason on this disk, not that the failure mode cannot occur.

---

## 6. Does abstention help the caller? — the downstream experiment we cannot run here

The question ARB actually raises is not whether the signal is accurate; it is whether **an agent does
better when told the ranking is weak.** Retrieval metrics cannot answer it. This is the design, so
that the next person to have a budget can run it.

**Instrument.** `bench/agentloop/` already exists for exactly this shape: fixed model, arms that vary
only the harness, SWE-bench-Lite instances locked in `tasks.lock` (every one from a repository that is
held out under the same `frozen_partition`), resolution scored by the official SWE-bench harness, and
infrastructure failures stopped rather than scored as unresolved.

**Arms.** Two, sharing a byte-identical prompt and differing only in what the tool emits:

| arm | tool behavior |
| --- | --- |
| `ripwire_cli` (control) | today's bundle, today's `confidence=` attribute |
| `ripwire_cli_warn` (treatment) | identical, plus an explicit low-confidence banner naming the evidence and the suggested next step |

**Primary outcome.** `resolved` rate from the official harness. **Secondaries, reported and deciding
nothing:** total tokens, turn count, tool calls, and whether the agent edited a gold file at all.

**The design constraint that decides whether it is worth running at all.** The treatment can only
differ from the control on rows where the signal *fires*. At today's 80% fire rate the treatment is
approximately "always warn", so the experiment would not measure abstention — it would measure
whether a near-constant banner changes agent behavior, which is a different and much less interesting
question. **The experiment is therefore gated on §5.3's fire-rate ceiling: do not run it until the
trigger fires on ≤ 25% of queries.** Running it first would burn the budget on a null result that
tells us nothing about the hypothesis.

**Power, honestly.** Two-proportion, α = 0.05, 80% power, control resolve rate 0.30:

| effect we would want to detect | n per arm |
| --- | --- |
| +10 points (0.30 → 0.40) | ≈ 354 |
| +5 points (0.30 → 0.35) | ≈ 1,375 |

Both are far beyond the locked set, and each cell costs real money. Three ways out, in the order we
would try them:

1. **Restrict to the fired subset and pair within instance.** The treatment is a no-op on
   non-fired rows, so including them only dilutes. Scoring only fired rows, paired by instance,
   removes between-instance variance — the dominant term here.
2. **Use a higher-resolution proxy outcome.** "Did the agent open/edit a gold file" has far more
   variance per instance than a binary resolve and is orders of magnitude cheaper. Its relationship
   to task success is exactly the thing we do not know, which is one of the two places §7 asks for
   help.
3. **Report the null honestly and stop.** A well-powered null on this axis is a publishable result
   for anyone else building the same feature, and this repository already publishes its negatives.

**What would make us NOT ship abstention** — stated in advance, so the result cannot be re-read
afterwards:

- the treatment's resolved rate is not higher and the interval on the difference includes zero; **or**
- the treatment resolves as well but costs more than **+10%** tokens or turns (a warning that only
  makes the agent work harder is a regression); **or**
- the treatment makes the agent *abandon* the tool — a fall in ripwire tool-calls per task with no
  corresponding rise in resolution — which would mean we taught it to distrust a signal that is right
  four times in five; **or**
- the effect exists but only on the proxy outcome and not on `resolved`, with no measured link
  between the two.

---

## 7. What we would like help with

Two places where an outside view would change what we build, rather than confirm it. Both are open
questions, not requests for review.

### 7.1 Calibration methodology for a set-valued answer

`--for` returns a *set* of symbols, and "correct" has at least four grains — a gold file in the head,
the gold function in the head, *every* gold file in the head, and the gold named anywhere in the
bundle. §3.3 measures all four and **they disagree**: the same attribute separates one of them
decisively and another not at all. We do not know a principled answer to:

- **Which grain should a single confidence attribute be a claim about?** Picking the grain it happens
  to win on is obviously wrong. Emitting one number per grain is honest but expensive in a bundle
  whose bytes are budgeted, and we have no evidence a caller would read four.
- **Is there a defensible way to calibrate a two-valued label at all**, or does honest calibration
  force the tool to emit a probability — and if so, calibrated against which grain's label, and
  fitted on what, given that a fitted mapping is itself a model that can be wrong on a new repository?
- **What is the right reference distribution?** Our 92 instances are Python-heavy, issue-shaped
  queries. A confidence attribute is served on every query an agent ever writes, most of which look
  nothing like a GitHub issue. We have no method for stating how far a calibration transfers.

### 7.2 The abstention criterion

- **What false-warn rate is acceptable for a *warning*, as opposed to a refusal?** We pre-registered
  0.20 in §5.2 and we can defend the direction but not the value. We are not aware of measured
  evidence about the rate at which an agent starts ignoring a signal, and that rate is the whole
  criterion.
- **Is there prior evidence that an agent's behavior changes at all in response to a
  retrieval-confidence signal?** Everything we found measures the retriever. If a low-confidence
  banner is simply ignored by current agents, the entire axis is a documentation exercise and the
  honest thing is to say so and stop.
- **A cheaper outcome than `resolved`.** §6's power table is the real blocker. A proxy with a *known*
  relationship to task success would make this axis measurable by people without a large budget,
  which is most of the people who would want to measure it.

If you have measured any of this — including a negative — we would rather hear it than re-derive it.
Issues and PRs against this document are welcome; so is a correction to the statistics above.

---

## 8. Re-running the numbers

Every table in §3.3 is produced by one offline script. It fetches nothing: point it at a LocBench
asset tree a previous `run_locbench.py --work-dir` already left on disk, and it will verify the frozen
dataset hash, score only the instances whose snapshot is provably at the right `base_commit`, and
count every instance it could not score under a named reason.

```bash
cmake -S . -B build && cmake --build build -j

RIPWIRE=$PWD/build/ripwire python3 bench/locbench/calibrate_confidence.py \
    --assets   <a run_locbench.py --work-dir>          \
    --cache-dir <a scratch dir OUTSIDE that tree>      \
    --split heldout                                    \
    --json-out calib.json --md-out calib.md
```

`--md-out` writes exactly the tables above. `--cache-dir` is required and must sit outside `--assets`:
the asset tree is evidence, and a run that rewrites it cannot be re-run against the same bytes.

The ARB side of the same question re-runs through its own instrument, unchanged by this branch:

```bash
python3 bench/arb/run_arb.py --task=abstention          # or --split=selective_retrieval_balanced
python3 bench/arb/score_abstention_calibration.py       # the registered bands, scored
```

---

## 9. Everything this branch did not do

- No `src/` change. `--for` behaves exactly as it did before.
- No new gate, no change to any existing one.
- No number here is quoted in `README.md`, `EVALS.md` or any other claim surface, and none of it is a
  published result. §5 is what would change that.
- The `coverage=` observation in §3.3 is not a finding and must not be cited as one.
- 214 held-out instances were not scored because their snapshots are not on the disk this ran on. The
  92 that were scored are a floor, and a replication on the remainder is part of §5.2.
