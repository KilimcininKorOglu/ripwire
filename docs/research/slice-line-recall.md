# `--slice` line recall on an issue-derived Python corpus — ARISE rung 1, measured

**Status: PRE-REGISTRATION ONLY at this commit.** Everything below the `## Results` marker is
written after the protocol was committed, and this paragraph is the proof of ordering: the commit
that adds this file contains no number produced by the harness. Amendments made after a first look at
any result are dated inline and labelled **AMENDMENT**.

**Scope.** This is the retrieval-quality question ARISE (arXiv:2605.03117) raises, asked of
ripwire's `--slice` primitive on a corpus ripwire has not measured it on: issue-derived Python fix
patches, addressed at the **pre-fix** tree. It is a research note, not a product claim. No number
here is published anywhere else until an owner pass.

---

## 1. What is already registered, and what this round adds

`docs/EVALS.md` § *"The `--slice` def-use primitive (2026-08-28)"* registered a line-recall shape.
§ *"`--slice-flow` — ARISE rung 2"* executed it (2026-08-30, ripwire's own history, 38 instances)
and extended it (2026-08-31, three D4-pinned C/C++ trees). **So the registered shape has been run —
twice — and this round does not "finally run it".** What those runs did *not* cover, and what this
round adds:

| already measured | not measured before this round |
| --- | --- |
| cpp family only (4 corpora, all C/C++) | **py family** — the one ARISE itself measured on |
| corpus mined from git history by subject regex | **issue-derived fix patches** (LocBench), the shape ARISE evaluates |
| gold = ADDED lines at the POST-fix tree | **gold = PRE-image lines at the PRE-fix tree** — the actual localization setting |
| set recall: are the gold lines among the rows | **rank**: do the rows put gold lines *first*, vs a random-order control |
| misses pooled | **reachability split**: gold out of reach *by construction* reported apart from gold the slicer dropped |
| bytes | **bytes and wall time** |
| — | **granularity vs presentation**: file-level / symbol-level / line-level answers under one byte budget |

Everything in the right-hand column is new registration and is fixed below before the harness runs.

### 1.1 Gap in the existing registration, closed here before measuring

The 2026-08-28 registration says "take the variables named on the changed lines and ask whether
`--slice=fn:var` surfaces those changed lines among its rows". It is silent on three things that
decide the number:

- **G1 — which tree.** A fix commit has a before and an after. The 2026-08-30/31 runs sliced the
  POST-fix tree and scored ADDED lines. That measures *can the slicer see lines that already exist*.
  The localization task ARISE scores is the other one: the agent holds the **pre-fix** tree and must
  find the lines to change. This round slices the **base commit** and scores **pre-image** lines.
  Both are defensible; they are different questions, and the earlier numbers are not comparable to
  these. Stated, not reconciled.
- **G2 — which lines are gold when a hunk only inserts.** A pure insertion has no pre-image line of
  its own. Rule fixed here: the gold line for an insertion run is the pre-image line **immediately
  preceding** the insertion point (`pre_ln - 1`), or the hunk's first pre-image line when the run
  opens the hunk. One anchor per run, never both neighbours.
- **G3 — what "surfaces" means when the row set is unordered.** `<s>` rows are emitted in source
  order, which is not a relevance ranking. The registration's metric is therefore a *set* metric and
  cannot answer "does the primitive rank". The two ranking rules used here (§4) are defined below,
  before any result, and both are computed from attributes the primitive already emits — no new
  scorer, nothing tuned.

**AMENDMENT 2026-09-20 (a):** G1, G2, G3 are amendments to the 2026-08-28 registration, written and
committed before the harness ran. They do not alter the 2026-08-30 or 2026-08-31 numbers, which
stand under the original reading.

---

## 2. Corpus and slice rule — fixed before looking at any result

**Source, already on disk, nothing downloaded.** `czlll/Loc-Bench_V1` test split, 560 rows, at
`<assets>/datasets/rows_czlll__Loc-Bench_V1_test_560.json`; 165 distinct repositories, of which
**90 have a local checkout**. Every `edit_functions` entry in all 560 rows is a `.py` path, so this
corpus is py-family in its entirety and is reported as such, never averaged with the cpp corpora.

**A row is USABLE iff all of:**

1. its `repo` has a local checkout;
2. `base_commit` resolves as a commit in that checkout;
3. `edit_functions_length == 1` — exactly one edited function. **Rows failing only this are the
   by-construction-unreachable population** (§5) and are counted, never scored as misses;
4. the single `edit_functions` entry is `PATH:FN` with `PATH` ending `.py`, and `PATH` materializes
   at `base_commit`;
5. the selector resolves **uniquely**: `FILE:FN` for a plain name, `FILE::CLASS::METHOD` for a
   dotted `Class.method`. An ambiguous or unresolved selector disqualifies the row and is counted by
   reason;
6. at least one gold line (§G2 above, restricted to the resolved function's line span) exists;
7. at least one gold line names a variable in the function's own `--slice=SEL` inventory (otherwise
   there is no v1 instance to score — counted as `no_touched_var`).

**Cap: none.** Every usable row is measured. The corpus is small enough that a cap would only add a
choice to defend.

**The tree handed to ripwire is a one-file tree**: the target file alone, materialized with
`git show BASE:PATH` into a scratch directory. The checkouts are never written to, never checked
out, never `git worktree add`-ed. This is sound *because the primitive is intra-procedural by
declaration* — no row of `--slice` can depend on a file it does not read — and it removes the
basename-ambiguity that thinned 34/63 candidates in the 2026-08-31 cpp run. It is stated as a
deviation because it also removes a real-world failure mode (whole-repo selector ambiguity), so the
selector-resolution rate reported here is an **upper bound** on what an agent would see on a whole
repo.

**Determinism.** Given the dataset file, the checkouts and the binary, the instance list and every
number are a pure function of the inputs; row order is the dataset's own. The random-order control
uses a fixed seed (`20260920`) and a fixed shuffle count (200).

---

## 3. Arms

All arms run on the same instances, at the base commit's own file.

| arm | command | what it is |
| --- | --- | --- |
| **v1** | `--slice=SEL:VAR` | the registered flat slice |
| **v2** | `--slice=SEL:VAR --slice-flow=both` | rung 2, bounded def-use BFS |
| **inv** | `--slice=SEL` | the sliceable-local inventory (addressing cost) |
| **expand** | `--expand=SEL` | whole-body baseline, recall 1.0 by construction, priced in bytes |
| **file** | the raw file | file-level baseline for §6 |

---

## 4. Metrics — all defined before measuring

**(a) Set recall (the registered shape, at the pre-fix tree).** Per (row, var) instance with
`G_var` = gold lines naming `var`:
`v1_line_recall = |G_var ∩ rows| / |G_var|`; `hit_all` = that ratio is 1.0;
`over_inclusion = |rows| / |G_var|`. Same for v2.

**(b) Rank — the new question.** Candidate pool = **every line in the resolved function's span**.
Two ranking rules, both from attributes already emitted, neither tuned, plus a control:

- **R1 (coverage).** Score a line by the number of *distinct* inventory variables whose v1 slice
  contains it. Ties broken by line number ascending. Rationale: a line participating in several
  tracked locals is the more central statement. Seed-free — it unions over the whole inventory and
  never looks at the gold.
- **R2 (flow depth).** Score a line by `-min(d)` over the `--slice-flow=both` rows of every
  inventory variable (v1 rows count as `d = 0`). Ties broken by R1, then line number. This is the
  primitive's own relevance signal.
- **CTL (random).** A uniform random permutation of the same candidate pool, averaged over 200
  shuffles at seed `20260920`. This is the honest floor: a slice that merely *presents* lines will
  score like CTL.

Metric: `Recall@k = |G ∩ top-k| / |G|`, k ∈ {1, 3, 5, 10, 20}, reported as the instance mean, for
R1, R2 and CTL. Also `MRR` of the first gold line.

**A seeded upper bound is reported separately** (`R2-oracle`): the same R2 ranking computed from the
gold-touched variables only. It is an oracle and is labelled one; it bounds what a perfect seed
choice could buy.

**(c) Reachability.** A cascade, each stage counted, reported as fractions of the 560 rows and of
the gold lines:
`multi-function row` → `no checkout / no commit` → `selector unresolved` → `gold line outside the
resolved span` → `gold line names no sliceable local` → `scoreable`.
A gold line lost at any stage but the last is **out of reach by construction**, not a slicer miss,
and is reported on its own line.

**(d) Cost.** Per instance: output bytes of inv / v1 / v2 / expand / file, and wall-clock
milliseconds of each ripwire invocation (single process, warm cache, median and mean).

---

## 5. Granularity vs presentation — the paper's actual question

ARISE's claim is that the *granularity floor* binds, not the ranking. The test that separates
granularity from presentation: hold the **answer** fixed (the correct function is given) and the
**budget** fixed, and vary only the granularity of what is delivered.

Budgets `B ∈ {512, 1024, 2048, 4096}` bytes of delivered payload. Three deliveries:

- **file-level** — the file's source, from its first line, truncated at `B` bytes;
- **symbol-level** — `--expand=SEL`'s body, truncated at `B` bytes;
- **line-level** — slice rows in **R2** order, each as `line-number: source text`, packed until `B`
  bytes is reached.

Score: the fraction of gold lines whose exact source text appears in the delivered payload.
Reported split by whether the function body **fits** in `B` (where symbol-level is 1.0 by
construction and the comparison is uninformative) and where it does not (where the question bites).
This is a *presentation-controlled* comparison: same correct function, same bytes, different
granularity. It cannot speak to ranking a whole repository — see §8.

---

## 6. What we are NOT claiming

- Nothing here is a Function Recall or Line Recall@1 number comparable to ARISE's. ARISE ranks over
  a whole repository from a natural-language issue; this measures a primitive **given** the correct
  function. The two numbers are not on the same axis and are never put in the same table.
- The one-file tree is an upper bound on selector resolution (§2).
- py-family only. The cpp numbers in `docs/EVALS.md` are a different population.

---

## Results

_(empty at the pre-registration commit — filled by the commit that runs the harness)_
