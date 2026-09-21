# Readability construct validity: what the lens claims, and how we would check it

Status: **investigation, not a conclusion.** This document states what `--readability` actually computes
and actually claims (read from the code, not assumed), designs a validation of its *ordering* against human
judgment that we have not yet run, and runs the two validations that need no human labels at all — reporting
their numbers whether or not they are flattering. It ends with what we would like help with from readability
researchers who study exactly this gap.

Two published results shaped where ripwire's readability lens sits, and both are **design influences, not
implementations** — nothing in `src/readability.h` runs a model or a judge:

- LLM judges of code readability lean on surface features rather than the construct itself — part of why
  ripwire's readability lens is a deterministic, closed-form formula (Halstead volume, token entropy, the
  Posnett sigmoid fit) instead of a model call, and why the underlying evidence is disclosed (`vol=`, `ent=`,
  `posnett=`) rather than a single opaque number.
- A study of prompt-side style constraints on LLM code generation found they help but plateau — part of why
  ripwire's readability-adjacent gate (`--quality-delta`'s `verbosity` kind) runs **after** each edit, against
  the actual diff, rather than living inside a generation prompt as one more instruction competing with the
  rest of the prompt for effect.

Both are cited in the readability design note — an internal working document, not part of this
repository — at its §7, as the "Readability
Spectrum" prompt-constraint finding and as "LLM self-judges … fixate on surface features (CoReEval)" —
see the reference list at the end of this document for both arXiv identifiers. That design log already states
the honesty bound this document expands on: *"Everything here is a lens, never a verdict."* This document is
the follow-through on that bound — checking it empirically rather than repeating it.

## 1. What we actually compute, and what we actually claim (from the code)

`--readability` (`src/readability.h`) is a single closed-form pass per function or method:

- **V — Halstead volume**: `V = N · log2(η)`, `N` = operator+operand token count, `η` = distinct tokens.
- **E — token entropy**: Shannon entropy (bits) of the definition's own token-frequency distribution.
- **L — lines**: the physical line span of the definition (`Symbol::loc`), signature included.
- **P — Posnett score**: `P = sigmoid(8.87 − 0.033·V + 0.40·L − 1.5·E)` — the coefficients published in
  Posnett, Hindle & Devanbu, *A Simpler Model of Software Readability*, MSR 2011.

Three facts about how this is used, verified against the source rather than assumed:

**It is emitted, and used elsewhere in the tool, as an ORDERING, never as a grade.** The verb sorts rows
*least readable first* and says so in its own legend (`src/readability.h`, `kReadabilityLegend`):

> "P was fitted on snippets of 20 lines or fewer: read the ORDER, not the number, and never as a grade."

The header comment states the reason in more detail, and names the literature that forced this framing
rather than a house preference: *"Scalabrino ASE'17 and Trockman MSR'18 both find no readability metric
correlates strongly with measured understandability; Fakhoury ICPC'19 finds the classic models miss real
readability-improving commits. So P is never a grade, never a gate, and never a verdict — it orders a
worklist."* The published `README.md` repeats the same claim as an external-facing promise, in a table of
lenses deliberately kept *outside* the tool's evidence-weighted panel join. Its row for `--readability`
reads, across that row's "why beside the join" and "on this repo" cells: *"the fitted score saturates past 20
lines — only the ordering is meaningful, and an ordering cannot vote in a count"* / *"ordering only, never a
grade."*

**It is not one of `--quality-delta`'s ten gating kinds.** The per-edit gate's kinds are `complexity`,
`verbosity`, `nesting`, `params`, `duplication`, `dead-code`, `api-surface`, `error-masking`,
`short-horizon-churn` and `new-clone-of-reused-helper` (`src/quality.h:4565` and the kind dispatch around
it). None of them is Halstead volume, token entropy or the Posnett score. The one readability-*adjacent*
kind is `verbosity`, and reading its implementation shows exactly what it measures and what it does not:
`verbosity` is **CODE line count only** (`src/quality.h`, `locBySym`, `codeLocByNode` — "Q-DIAL-3: blank and
comment-only lines are not debt"). It shares one input (`L`) with the Posnett formula and none of the other
two (`V`, `E`). So the per-edit gate that actually blocks a merge never sees the entropy or Halstead-volume
half of the readability lens at all — it sees a plain, un-weighted line count.

**The only place the Posnett rank feeds a joined judgment is `--ensemble`, and even there it is kept
ordinal, not additive.** `src/ensemble.h` folds `--readability`'s rank into its "structural" evidence family
alongside complexity/LOC/nesting/params, and its own header comment states why the five are one family and
not five independent votes: *"ccx, loc, nest, params and the Posnett score all track SIZE — Posnett's own fit
is literally linear in L. Counting them as five agreeing witnesses is the Maintainability-Index failure
(§3.10): re-weighting one signal and calling it five."* — and separately, on why the Posnett rank and churn
are handled differently from the other four: *"The other two signals (Posnett readability, churn) are
RANKINGS whose own authors publish no defensible absolute cut: --readability's header says in so many words
to read the ORDER, not the number. The only honest predicate on an ordinal signal is an ordinal cut, so each
fires for the WORST DECILE of its own ranking."* `--ensemble` records only a symbol's position in that
worst-decile prefix (`rrank=`), never `posnett=` itself — there is, by the same comment's own words a few
lines later, "no composite number anywhere in this verb, by contract."

**So: does the tool present readability as an absolute grade anywhere?** No surface we found does. The one
place a reader could plausibly *read* it that way — a raw `posnett=` value on an individual row of
`--readability`'s own output — carries the legend's own correction directly above it every time it is
printed ("read the ORDER, not the number, and never as a grade"), and the value visibly saturates to
`0.000` for a large share of real functions (see §3), which is itself a standing, unavoidable reminder that
the number is not meant to be read on its own. We consider the code's claim to already be the *honest* one:
ordering-only, disclosed as ordering-only, at every point of contact. The rest of this document is about
whether that ordering claim itself survives contact with a human judgment — which is a strictly harder bar
than "is the code's rhetoric honest," and one the code freely admits it has not cleared (Scalabrino/Trockman/
Fakhoury are cited as open problems, not as solved ones).

## 2. A validation of the ORDERING, not the score

Reproducibility (the same input always yields the same rank) is not construct validity (the rank means what
we say it means). The formula could be perfectly deterministic and still rank functions in an order no human
reader would recognize. Here is the validation we think would settle that, specified concretely enough to run:

**Unit of comparison: pairs, not scores.** Ask a rater "which of these two is more readable," never "rate
this snippet 1–5" — the literature's own ground-truth datasets are pairwise-derived or scale-based and Vitale
(2025, cited in the readability design note §7) found up to a third of classic scale labels
self-contradictory on reread. A forced pairwise choice is cheaper to collect, cheaper to get consistent, and
is exactly the shape `--readability`'s own claim needs checking against: it emits an order, so validate the
order.

**Where pairs come from (three tiers, cheapest first):**

1. **This repo's own git history** — a commit whose message says refactor/simplify/cleanup gives a free
   (before, after) pair of the same function, no synthetic construction needed. This is what §3's proxy (a)
   already mines, at zero marginal data-collection cost.
2. **`bench/external/arb` and `bench/external/swex`** — this repo already vendors multiple external-repo
   snapshots and commit histories for other evaluation harnesses (agentic-benchmark corpora, not readability
   ones). The same commit-message mining in §3's script generalizes to any of them by pointing `--root` at a
   different checkout — more languages, more authors, no ripwire-specific style bias. We did not run this for
   the current round (time-boxed to this repo, see §3) but the script takes a `--bin`/corpus-root pair for
   exactly this reason.
3. **Synthetic pairs from `--readability`'s own ranking** — take two functions already far apart in the
   lens's own order (one from the worst decile, one from the best) and ask a rater to confirm or reject the
   implied direction. Cheapest to collect, weakest signal (it can only confirm the lens agrees with itself at
   the extremes, which §3 proxy (b) already establishes for free without a human).

**How a human judgment would be collected.** Blinded, randomized left/right presentation (no file path, no
`posnett=`, no commit message); each pair rated independently by at least three raters, majority vote as the
pair's label, inter-rater agreement reported alongside the correlation (a low agreement number is itself a
finding, per Vitale). Raters should not be told which side the lens preferred — Piantadosi et al.'s "readable
state flip" framing (cited in the readability design note §6) is a reasonable model for how to phrase the
question without anchoring the rater on a metric.

**The statistic.** Percentage pairwise agreement between the lens's implied direction and the majority human
label, plus a rank correlation (Kendall's τ or Spearman's ρ) over any batch of pairs drawn from one shared
ranked list, since τ is exactly a transform of pairwise agreement and gives readers a standard number to
compare against the published literature's own correlations for competing metrics.

**What would count as success, and what would make us withdraw or demote the lens.** We propose three bands,
calibrated against the literature already cited in this repo (Scalabrino ASE'17 and Trockman MSR'18 found
*no* classic metric correlates strongly with measured understandability — so we are not calibrating against
"strong correlation is achievable," we are calibrating against "is this metric earning the narrow claim it
actually makes"):

- **τ (or equivalent pairwise agreement) comfortably above chance and stable across a second, disjoint
  sample** → keep exactly as-is: an ordering signal, disclosed as such, feeding `--ensemble`'s rank-only
  join and nothing stronger.
- **Weak but directionally consistent, or consistent on some function shapes and not others (e.g., holds for
  size-dominated differences, fails when two functions are close in size but differ in naming/structure)** →
  narrow the claim further and say so in the legend — e.g. disclose that the lens is known to track length
  more than it tracks anything len-independent, which §3's proxy (b) already shows structurally (see the
  "what this cannot catch" paragraph there).
- **No better than chance, or a sign flip on a held-out language/corpus** → withdraw the ranking claim from
  any joined surface (`--ensemble`'s `rrank=`) and keep `--readability` only as a standalone, clearly-labeled
  "how does this formula see the codebase" report — the same demotion path `naminglens.h` already used once
  (§4).

We have not run the human-rated arm. It needs raters we do not have in this pass; §5 names it as the thing we
would like the most external help with.

## 3. What we ran WITHOUT human labels

Two proxies need no rater at all. Both are implemented as re-runnable scripts against the real
`./build/ripwire --readability` binary — not a reimplementation of the formula — so what they measure is
the shipped lens, not a paper description of it.

### 3a. Refactor-commit direction (`bench/readability_refactor_pairs.py`)

For every commit in this repo's history whose subject reads as refactor/simplify/cleanup (case-insensitive,
`refactor|simplify|clean(\s|-)?up`) and whose total changed-line count is ≤400 (so a per-function delta stays
attributable to the named refactor rather than to an unrelated bulk edit riding along in the same commit),
the script extracts every touched `.h`/`.cpp` file at the commit and at its parent, scores each version with
the real lens in a single-file scratch directory, and keeps the functions present in both versions with a
**different** token shape (same shape ⇒ this diff did not touch that function's body ⇒ no evidence either
way). Comparison uses the pre-sigmoid `z` score recomputed at full precision from the CLI's own
integer `toks=`/`vocab=` and its `ent=`/`lines=` — not the CLI's own 3-decimal `posnett=` attribute, which
saturates to a repeated `"0.000"` for most real functions (see the tie count below) and would make most pairs
falsely indistinguishable. `z` is monotonic in `posnett` (same sigmoid), so ranking by `z` ranks identically
to ranking by `posnett` without the display truncation.

**Run** (`--max-commits 80 --max-changed-lines 400`, the numbers below):

| | |
|---|---|
| candidate refactor/simplify/cleanup commits | 80 (78 contributed ≥1 usable pair) |
| function pairs (changed shape, matched by name) | 484 |
| lens ranks AFTER more readable (`z` increased) | 146 (30.2% of the 484 directional pairs) |
| lens ranks AFTER less readable (`z` decreased) | 338 (69.8%) |
| exact tie | 0 |
| mean Δz (after − before, + = more readable) | **+1.89** |
| median Δz | **−0.73** |
| pairs with \|Δz\| > 20 (large swings) | 27 / 484 (5.6%) |

**Read this plainly, including that it is not flattering.** On a majority (70%) of the function pairs a human
called a refactor, the lens's own ranking moved the *wrong* direction — it scored the after-version as *less*
readable. The mean is positive only because a small number of large swings (5.6% of pairs, all from commits
that genuinely shrank a function by splitting work into named helpers) pull it there; the median, which a
skewed distribution like this one should be read against, is negative. This lines up with exactly the
literature the lens's own code already cites as a reason for caution — Fakhoury ICPC'19's finding that
classic readability models "miss real-world readability-improvement commits" is not a hypothetical risk here,
it is what this run measured on ripwire's own history.

**Two worked examples, to show what is and is not driving the number.** The eight largest positive swings
are all commits whose stated purpose was extraction — moving a block of logic out into named helper
functions, which mechanically shortens the function the lens is scoring: `buildFieldNarrowTables`
(114→50 lines), `computeSnapshot` (116→61), `buildScopedRecvDecls` (61→15), `hasNetExfilShape` (59→17),
`buildExternalVetoTables` (147→86), `resolve` in `src/elixir_resolve.h` (57→17), `parseAsan` (99→21) and
`runSkipped` (71→45) — a 25%–75% line-count cut in every case. The lens's length-sensitivity is doing
exactly the intuitive thing there. The single
largest *negative* swing is the opposite shape of edit: commit `15af398e`
(`refactor(L1-fix): keep existing contracts; readings spell no element markup`) inlined a one-line forwarding
wrapper (`classify()`, 5 lines) into what had been a same-named sibling implementation, producing one 126-line
function where there had been a 5-line indirection plus a separate body. The commit message is about
preserving an API contract, not about readability, and a human reader might reasonably call the *pre*-commit
two-function shape less readable (an unexplained one-line forwarder) than the *post*-commit single function —
the opposite of what the lens's length term rewards. We are not correcting for this by hand; it is exactly
the kind of case a pairwise human study (§2) would need to arbitrate, and we would be misrepresenting the
proxy if we quietly excluded it.

Re-run: `bench/readability_refactor_pairs.py --max-commits 80 --out pairs.tsv` (defaults to this repo,
`build/ripwire`; deterministic given a fixed git history and a fixed binary).

### 3b. Self-consistency under meaning-preserving rewrites (`bench/readability_self_consistency.py`)

Two mechanical rewrites that should not change how readable a function is: renaming one local identifier to a
fresh name that collides with nothing else in the function, and swapping two adjacent, mutually-independent
simple statements (`lhs = rhs;`, including one-line typed declarations, in this repo's one-statement-per-line
house style). 80 functions were sampled at even percentile positions across `--readability`'s own
least-readable-first ranking of this repo's `src/` (4,373 functions measured), so the sample spans the whole
distribution rather than only the worst decile the verb shows by default. Each sampled function's own whole
file is re-scored unmutated as the baseline (same single-file measurement path the mutant takes, so there is
no cross-file ingest difference to explain away), then rescored after one mutation.

| mutation | attempted | exact tie (`vol=`, `ent=`, `posnett=` all unchanged) | diverged |
|---|---|---|---|
| rename (fresh, non-colliding identifier) | 75 / 80 | 75 | 0 |
| reorder (two adjacent independent statements) | 20 / 80 | 20 | 0 |

**State plainly what this does and does not show.** Halstead volume and Shannon entropy are functions of the
*multiset* of (token, frequency) pairs — not of token identity or statement order (`readability.h`'s own
determinism note: the entropy sum runs over a token-text-**sorted** vector specifically so iteration order
cannot reach the output). So exact invariance under a non-colliding rename or an independent-statement
reorder is what the formula predicts *mathematically*, not a discovery — a 100% tie rate here mostly certifies
that the shipped implementation has no stray non-determinism or order leak, which is a real and worth-having
guarantee, but it is an implementation-correctness result, not a readability-construct-validity result. The
informative failure mode this proxy could have caught — and did not — is any pair that does NOT tie exactly,
which would point at either a bug in this harness's mutation or a genuine order/identity sensitivity in the
lens worth filing as a defect.

**The same invariance is also a disclosed limitation, not only a safety net.** Because the formula is
mathematically blind to identifier length and to statement order, it is *structurally incapable* of
rewarding `numberOfActiveConnections` over `n`, or a well-ordered proof sketch over a scrambled one — both
of which most human readers would call a real readability difference. That is a construct-validity gap this
proxy makes visible without needing a single human label: whatever the lens is measuring, it provably is not
measuring those two things, by the formula's own definition.

**Coverage caveat, reported rather than hidden.** Only 20 of 80 sampled functions (25%) contained an eligible
adjacent, independent, simple-statement pair by our conservative heuristic (excludes calls, subscripts,
member targets, and any pair whose right-hand sides cross-reference the other's left-hand side). This is a
coverage limit of the *harness*, not a claim about the lens — most real functions in this codebase either
have fewer than two adjacent simple statements or have dependencies between them, and a looser heuristic
risks constructing a swap that is not actually independent.

Re-run: `bench/readability_self_consistency.py --samples 80 --seed 20260918 --out consistency.tsv`
(deterministic for a fixed seed, corpus and binary — the sampler's own RNG is seeded, and the rename target
is chosen by frequency-then-lexical order rather than randomly, so re-running with the same seed reproduces
the same mutations).

## 4. Precedent: we have already withdrawn a lens that failed exactly this kind of check

This is not the first deterministic proxy ripwire has shipped, measured, and had to reckon with. §9.0 of
`docs/LINEAGE.md`, and the top of `src/naminglens.h` itself, record `naming-body-mismatch` — a rule that
flagged a name whose tokens shared zero vocabulary with its own body. Measured on this repository's own
`src/` at the commit that shipped it, the rule produced 159 of the lens's 217 naming findings (73% of the
whole signal), and the flagged set was **dominated by the best-named functions in the tree**
(`didYouMean`, `transitiveCallers`, `symbolAdjacency`) — because a good abstraction name states *intent*
while its body states *mechanism*, so near-zero overlap is the signature of a successful abstraction at least
as often as of a lying name. The axis was non-monotonic with quality: no threshold on it has a defensible
direction. It was **withdrawn before it shipped**, and `naminglens.h` carries a do-not-re-add note plus the
measured numbers at the top of the file rather than a silent deletion.

We take that as the template for what "failing this validation" would require of us, not just for naming: if
§2's human-rated pairwise study comes back at or below chance, or flips sign across a second corpus, the
correct response is the same one `naming-body-mismatch` got — record the numbers and the reasoning where the
next reader will actually see them (this document and `--readability`'s own header comment, the way
`naminglens.h`'s header comment carries its own withdrawal), demote or remove the claim from any joined
surface (`--ensemble`'s `rrank=` first), and do **not** quietly re-add a close cousin of it later without
citing why this round's finding no longer applies. §3's numbers are not at that bar yet — proxy (a)'s
70%-wrong-direction result on refactor commits is concerning enough that we think the human-rated study in
§2 is now the right next step, not an optional nice-to-have.

## 5. What we would like help with

We are not readability researchers; we are reporting what a deterministic, disclosed, ordering-only lens
measures against a construct it was never claimed to solve, and we would like informed pushback on the
following, specifically:

1. **Is §2's proposed pairwise + rank-correlation protocol the right design**, or is there a better-controlled
   study shape for validating an *ordering* claim (as opposed to the score-based designs most classic
   readability datasets — Buse & Weimer, Scalabrino, Dorn — were built for)? We deliberately avoided asking
   for a 1–5 scale per snippet, on Vitale's (2025) finding that a meaningful fraction of such labels are
   self-contradictory on reread; is a forced pairwise choice actually more reliable, or does it just move the
   inconsistency somewhere this document has not thought to look?
2. **What is a defensible pass/fail bar for an ordering-only metric**, given that the field's own consensus
   (Scalabrino ASE'17, Trockman MSR'18) is that no classic metric correlates *strongly* with measured
   understandability? §2 proposes three bands calibrated against "does the lens earn the narrow claim it
   makes," not against "strong correlation is achievable" — is that the right frame, or does it let a weak
   metric off too easily?
3. **Proxy (a)'s 70%-wrong-direction number** (§3a) is the most actionable finding in this document, and we
   would like a sanity check on the method before we act on it: is commit-message mining (refactor/simplify/
   cleanup) too noisy a readability label on its own — conflating "the author changed something for reasons
   unrelated to readability" with "the author made it more readable" — and if so, what filter (a stricter
   subject regex, a manual pass over a sample, restricting to commits that touch exactly one function) would
   make the label trustworthy enough to report a headline number from?
4. **Is Halstead volume, entropy and length the right feature set to be checking at all** in 2026, or is this
   entire investigation validating a formula the field has already moved past? The readability design note
   §5 surveys later models (Buse & Weimer 2010, Scalabrino 2018) that add lexical/visual/textual
   features on top of the same structural core — if there is a more recent, still-deterministic (no model
   call) formula with better-established construct validity, we would rather adopt it than keep defending
   Posnett 2011 out of inertia.

## Reference list

- Posnett, D., Hindle, A. & Devanbu, P. *A Simpler Model of Software Readability.* MSR 2011.
  [doi:10.1145/1985441.1985454](https://doi.org/10.1145/1985441.1985454)
- Halstead, M. H. *Elements of Software Science.* Elsevier, 1977.
- Scalabrino, S., Linares-Vásquez, M., Poshyvanyk, D. & Oliveto, R. *Improving Code Readability Models with
  Textual Features.* ICPC 2016 / *A Comprehensive Model for Code Readability.* JSEP 2018.
  [doi:10.1109/ICPC.2016.7503707](https://doi.org/10.1109/ICPC.2016.7503707)
- Trockman, A. et al. — the MSR 2018 result cited throughout this repo's readability code as finding no
  readability metric or combination correlates strongly with measured understandability (see
  `src/readability.h`, the readability design note §0).
- Fakhoury, S. et al. *Improving Source Code Readability: Theory and Practice.* ICPC 2019 — 548
  developer-declared readability-improving commits across 63 projects; classic models "fail to capture
  readability improvements."
- Peitek, N., Apel, S., Parnin, C., Brechmann, A. & Siegmund, J. *Program Comprehension and Code Complexity
  Metrics: An fMRI Study.* ICSE 2021. [doi:10.1109/ICSE43902.2021.00056](https://doi.org/10.1109/ICSE43902.2021.00056) —
  Halstead volume specifically tracks measured cognitive load.
- Vitale, T. et al. (2025) — cited in the readability design note §0 as finding up to a third of classic
  readability ground-truth labels self-contradictory.
- The "Readability Spectrum" prompt-style-constraint study, arXiv:2605.13280 — style constraints in a
  generation prompt help but plateau; cited in the readability design note §7.
- CoReEval, arXiv:2510.16579 — LLM self-judges of code readability fixate on surface features; cited
  alongside the prompt-constraint study in the readability design note §7 as the joint reason
  `--quality-delta`'s gate is deterministic and external to the model, applied to the diff.
- `docs/LINEAGE.md` §9.0 and `src/naminglens.h` (top-of-file comment) — the withdrawn `naming-body-mismatch`
  rule, this repo's only other instance of "measured, then withdrawn," and the template §4 of this document
  follows.
