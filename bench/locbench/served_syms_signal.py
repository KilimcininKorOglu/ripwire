#!/usr/bin/env python3
# served_syms_signal.py — the pre-registered scoring procedure for `served_syms` as a miss/abstention
# signal (docs/research/confidence-and-abstention.md §5.4, pre-registered 2026-09-23; fix round 1
# 2026-09-23 after adversarial review `reports/rv-served-syms-prereg.md`).
#
# WHAT THIS IS. `served_syms` (calibrate_confidence.py's `grade()`'s `served_syms=len(head)`) already
# ships on every `--for` bundle as the size of the served head. No number computed UNDER THIS
# PROCEDURE existed when §5.4 was written — but two EXPLORATORY numbers were already seen and are
# disclosed, not hidden: a prior review (`reports/rv-margin-resolution.md`) computed served_syms's
# AUROC as a miss detector at 0.669 (file_hit) / 0.723 (func_hit) on this same 92, and 0.769/0.791 on
# a different 40-row sample — in both cases without an operating point and without a recorded
# orientation (the reviewer's scratch script is lost). The registered orientation below (§5.4.3) is
# INFORMED BY those seen numbers, not blind — say so, don't claim otherwise. This module is the
# scoring itself, run over rows `calibrate_confidence.py`'s `scored_instances()` already produces — it
# reads no LocBench data itself, invokes the binary nowhere, and fetches nothing. It is pure
# post-processing of a `rows` list whose per-row shape already carries `served_syms`, `file_hit`,
# `func_hit`, `confidence`, `margin_pct`, `repo`, `instance_id` (see calibrate_confidence.py's
# `grade()`/`measure_instance()`).
#
# COMMENSURABILITY. Reuses `auroc`, `confusion` and `prf` from bench/arb/score_abstention_calibration.py
# — the registered primitives — rather than re-deriving any of them. The registered orientation (§5.4.3
# — larger served_syms is more miss evidence) warns on the HIGH side of a threshold, but `confusion()`
# only counts the LOW-side predicate `value <= threshold`. Rather than a second counting loop, `_confusion_ge`
# gets there by calling `confusion(labels, values, t - 1)` (exact, because served_syms is an integer)
# and relabelling its four cells — see that function's docstring for the swap. No new loop, no new
# comparison logic; `confusion()` is the only place `<=`/`>=` counting happens in this module.
#
# FIX ROUND 1 (2026-09-23, after `reports/rv-served-syms-prereg.md`, VERDICT NOT READY):
#   HIGH-1 — §5.4.3's mechanism argument (adaptiveCut/kept/hitCeiling) does not run under the
#     registered invocation (that chain is `--adaptive`-only; default `--for` never reads `kept`).
#     Orientation is now registered as "raw value, informed by the seen 0.669/0.723", not derived from
#     a mechanism. ORIENTATION and the no-flip rule are unchanged (the reviewer's own ruling).
#   HIGH-2 — the fingerprint's AUROC tolerance rejected the only 4-dp value the figure it pins was ever
#     published as (0.5805). FINGERPRINT now pins the exact nearest lattice point to that published
#     value, with a per-grain tolerance sized to the AUROC lattice's own step (see FINGERPRINT_AUROC_TOL).
#     Added `rows_len_matches_n`, missing before.
#   HIGH-3 — SR-1 (fire-rate) was folded into the band verdict, so a FAIL could be reported on
#     data where the owner's actual band (false-warn/recall only) WAS met. `choose_operating_point`
#     now returns band_met and sr1_met separately; `score_served_syms` has four outcomes.
#   MEDIUM — "was never scored"/"our best disclosed signal" removed from every sentence (served_syms
#     WAS scored, exploratorily); §5.2's AUROC band is now reported (not gating) via `auroc_band_5_2`.
#
# FROZEN BY THE PRE-REGISTRATION — none of the constants below may be tuned after seeing a served_syms
# number COMPUTED UNDER THIS PROCEDURE; a change to any of them is a new pre-registration, not a bug fix:
#   ORIENTATION        — §5.4.3: +1 == larger served_syms is registered as MORE miss evidence, informed
#                         by the exploratory 0.669/0.723 already seen (not a mechanism derivation).
#   GATING_GRAIN        — §5.4.2: func_hit is the sole grain a PASS is checked against; file_hit is
#                          scored and reported but never gates a PASS.
#   FALSE_WARN_MAX,
#   RECALL_MIN          — §5.2's operating-point band, unchanged: 0.20 / 0.50. (§5.2's separate AUROC
#                          band is reported, not gating here — see auroc_band_5_2.)
#   FIRE_RATE_CEILING    — §5.3 rule 2, carried into this round as SR-1: 0.25. Reported and
#                          verdict-bearing for its OWN outcome (pass_fire_rate_rejected), never folded
#                          silently into band_met.
#   FINGERPRINT          — §5.4.1's reproduction figures, checked before anything else runs.
#   BOOTSTRAP_SEED,
#   BOOTSTRAP_RESAMPLES  — §5.4.5: fixed so a re-run reproduces the same interval.
#
# USAGE (library). `from served_syms_signal import score_served_syms`; called by
# calibrate_confidence.py's main() with the `summary` dict it already built and the `rows` list that
# produced it. Direct unit tests live in the sibling `test_served_syms_signal.py` (synthetic, hand-built
# rows only — never touches LocBench data or the network; run `python3
# bench/locbench/test_served_syms_signal.py`).
import pathlib, random, sys

HERE = pathlib.Path( __file__ ).resolve().parent
sys.path.insert( 0, str( HERE.parent / "arb" ) )
from score_abstention_calibration import auroc, confusion, prf   # the registered primitives

# ── frozen constants (docs/research/confidence-and-abstention.md §5.4) ──────────────────────────────
ORIENTATION = 1   # +1: larger served_syms == more miss evidence — the raw value, informed by the
                  # exploratory 0.669/0.723 AUROC already seen on this population (§5.4.3; fix round 1
                  # dropped the adaptiveCut/hitCeiling mechanism argument, which does not run under
                  # default --for). sweep()'s `>=` direction is hardwired to this value (asserted
                  # below) — changing ORIENTATION is a new pre-registration decision, not a config
                  # flip, and must change the comparison direction in _confusion_ge/sweep() too.
assert ORIENTATION == 1, "ORIENTATION changed without updating _confusion_ge's >= direction to match"

GATING_GRAIN = "func_hit"          # §5.4.2 — the sole grain a PASS is checked against
FALSE_WARN_MAX = 0.20              # §5.2's operating-point band
RECALL_MIN = 0.50                  # §5.2's operating-point band
FIRE_RATE_CEILING = 0.25           # §5.3 rule 2 / this round's SR-1 — reported, own outcome (HIGH-3)

# §5.2's SEPARATE AUROC band (distinct from the operating-point band above), reported per grain,
# never gating a PASS/FAIL here (MEDIUM-3 — the owner's question in this round is the operating point).
AUROC_MEETS_5_2 = 0.70
AUROC_WEAK_5_2 = 0.60
AUROC_REFUTATION_5_2 = 0.35        # <= this: reported as a directional refutation, never re-read as a pass


def auroc_band_5_2( auc ):
    """§5.2's AUROC band ('>= 0.70 meets · [0.60,0.70) weak · <0.60 does not meet · <=0.35 directional
    refutation'), REPORTED only. Deliberately not `score_abstention_calibration.py`'s own `auroc_band()`
    — that function implements the ARB round-one registration's band (0.65/0.55/0.35), a DIFFERENT
    numeric registration that happens to share only the 0.35 directional-refutation cut with §5.2's."""
    if auc is None:
        return None
    if auc >= AUROC_MEETS_5_2:
        return "meets"
    if auc >= AUROC_WEAK_5_2:
        return "weak"
    if auc <= AUROC_REFUTATION_5_2:
        return "does_not_meet_opposite_direction"
    return "does_not_meet"


# §5.4.1's reproduction figures. "score" here is the arb_score (confidence=/margin_pct= combined)
# AUROC calibrate_confidence.py's discrimination() already computes — the doc calls it "margin_pct=/
# score AUROC" because on this corpus margin_pct= carries no information confidence= does not already
# carry (§3.3: "margin_pct= adds no ordering information to confidence=").
#
# score_auroc pins the EXACT nearest achievable lattice point to the published figure, not the
# published figure's own rounding (fix round 1, HIGH-2): AUROC over an m-miss/h-hit population is
# k/(m*h) for half-integer k (Mann-Whitney with tie-averaging, exactly what auroc() computes), so
# "0.580" (§3.3's 3-dp rendering) and "0.5805"/"0.581" (reports/rv-margin-resolution.md, a later
# binary, same 92) can only BOTH be true of one real run if the true value is near 670.5/1155:
#   file_hit: 15 misses x 77 hits = 1155 pairs; 670.5/1155 = 0.580519 (prints 0.580 at 3dp, 0.5805/
#             0.581 at 4dp/3sf, matching both published renderings).
#   func_hit: 38 misses x 54 hits = 2052 pairs; 1276.5/2052 = 0.622076 (prints 0.622 at 3dp, 0.6221
#             at 4dp, matching both published renderings).
FINGERPRINT = dict(
    n=92, confidence_low=74, confidence_high=18,
    misses=dict( file_hit=15, func_hit=38 ),
    score_auroc=dict( file_hit=670.5 / 1155, func_hit=1276.5 / 2052 ),
)
# Per-grain tolerance sized to that grain's OWN lattice step (0.5/(misses*hits)), not a shared guess:
# admits the pinned point plus its two nearest neighbours (+-1 step) and excludes the next step out.
#   file_hit: step = 0.5/1155 = 0.0004329 -> tol 0.0006 admits k in {670, 670.5, 671} (0.0006 > 1 step,
#             < 2 steps = 0.0008658).
#   func_hit: step = 0.5/2052 = 0.0002437 -> tol 0.0003 admits k in {1276, 1276.5, 1277} (0.0003 > 1
#             step, < 2 steps = 0.0004874).
FINGERPRINT_AUROC_TOL = dict( file_hit=0.0006, func_hit=0.0003 )

BOOTSTRAP_SEED = "ripwire-served-syms-prereg-v1"
BOOTSTRAP_RESAMPLES = 10000


# ── §5.4.1 — population fingerprint ─────────────────────────────────────────────────────────────────
def check_fingerprint( summary, rows=None ):
    """(ok, detail). ok is True iff this run's population reproduces every one of §5.4.1's pinned
    figures on `summary` (calibrate_confidence.py's already-built summary dict, read here, never
    recomputed). detail is always returned, even when ok, so a report can quote exactly what matched.

    `rows`, optional: when given, also checks `len(rows) == summary["n_scored"]` (fix round 1, HIGH-2's
    "count checks" / the reviewer's C9 — nothing today calls this with rows=None except a caller that
    only wants to check the summary in isolation, e.g. a unit test; `score_served_syms` always passes
    rows, so the real gate always runs this check)."""
    n = summary["n_scored"]
    high = summary["overall"]["confidence_high"]
    low = n - high
    misses = { g: summary["discrimination"][g]["misses"] for g in ( "file_hit", "func_hit" ) }
    score_auroc = { g: summary["discrimination"][g]["auroc"] for g in ( "file_hit", "func_hit" ) }

    def close( a, b, tol ):
        return a is not None and abs( a - b ) <= tol

    checks = dict(
        n=( n == FINGERPRINT["n"] ),
        confidence_low=( low == FINGERPRINT["confidence_low"] ),
        confidence_high=( high == FINGERPRINT["confidence_high"] ),
        misses_file_hit=( misses["file_hit"] == FINGERPRINT["misses"]["file_hit"] ),
        misses_func_hit=( misses["func_hit"] == FINGERPRINT["misses"]["func_hit"] ),
        score_auroc_file_hit=close( score_auroc["file_hit"], FINGERPRINT["score_auroc"]["file_hit"],
                                    FINGERPRINT_AUROC_TOL["file_hit"] ),
        score_auroc_func_hit=close( score_auroc["func_hit"], FINGERPRINT["score_auroc"]["func_hit"],
                                    FINGERPRINT_AUROC_TOL["func_hit"] ),
    )
    if rows is not None:
        checks["rows_len_matches_n"] = ( len( rows ) == n )
    ok = all( checks.values() )
    return ok, dict( checks=checks,
                     measured=dict( n=n, confidence_low=low, confidence_high=high,
                                   misses=misses, score_auroc=score_auroc,
                                   rows_len=( len( rows ) if rows is not None else None ) ),
                     expected=FINGERPRINT )


# ── §5.4.4 — threshold procedure ────────────────────────────────────────────────────────────────────
def _confusion_ge( labels, values, t ):
    """tp/fn/fp/tn for the registered rule `warn(row) <=> served_syms(row) >= t`, reusing
    score_abstention_calibration.py's `confusion()` rather than re-looping — no new counting logic.

    `confusion(labels, values, t - 1)` computes the OPPOSITE-direction predicate
    `predicted_abstain = value <= t - 1`, which (served_syms being an integer, per §5.4.2, so `t - 1`
    is exact) is precisely `NOT (value >= t)` — the complement of the rule this round registers. Every
    row confusion() counts as its "abstain" is therefore a row THIS rule does NOT warn on, and vice
    versa, so tp/fn and fp/tn swap places: confusion()'s tp' (label True, predicted-abstain True) is
    exactly this rule's fn (label True, warned False), and so on for the other three cells.

    NOTE (review LOW-1, deferred — not part of fix round 1's scope): this is exact only when every
    value and every candidate t is an integer, which `grade()`'s `served_syms=len(head)` always is
    today; a non-integer input would silently miscount. Not validated here; flagged for a later round."""
    tp2, fn2, fp2, tn2 = confusion( labels, values, t - 1 )
    return fn2, tp2, tn2, fp2


def sweep( labels, values ):
    """The full §5.4.4 threshold table. T = distinct(values) ∪ {max(values)+1} (the "warn on nobody"
    sentinel `V` alone cannot represent). One row per candidate t: recall, false_warn (= prf()'s
    `false_abstain_rate`, relabelled to this round's vocabulary), warn_rate (= (tp+fp)/n, the fraction
    of the 92 this t would warn on — what SR-1 gates), `band` (recall/false_warn alone, the owner's
    actual question, per HIGH-3), `safe` (`band` AND warn_rate under SR-1's ceiling — what
    `choose_operating_point`'s real-PASS branch requires), and the raw confusion counts."""
    if not values:
        return []
    candidates = sorted( set( values ) ) + [ max( values ) + 1 ]
    n = len( labels )
    table = []
    for t in candidates:
        tp, fn, fp, tn = _confusion_ge( labels, values, t )
        stats = prf( tp, fn, fp, tn )
        recall, false_warn = stats["recall"], stats["false_abstain_rate"]
        warn_rate = ( tp + fp ) / n if n else None
        band = ( false_warn is not None and false_warn <= FALSE_WARN_MAX
                and recall is not None and recall >= RECALL_MIN )
        safe = band and warn_rate is not None and warn_rate <= FIRE_RATE_CEILING
        table.append( dict( threshold=t, recall=recall, false_warn=false_warn,
                            precision=stats["precision"], f1=stats["f1"], warn_rate=warn_rate,
                            band=band, safe=safe, tp=tp, fn=fn, fp=fp, tn=tn ) )
    return table


def choose_operating_point( table, n_rows ):
    """The §5.4.4 tie rule, SR-1, and the HIGH-3 split, applied to a threshold table (either `sweep()`'s
    own, or any hand-built table of {threshold, recall, false_warn, warn_rate, ...} rows — this function
    derives band/SR-1 membership itself from those four raw fields rather than trusting `sweep()`'s own
    `band`/`safe` columns, so the two can never silently disagree and a hand-built test fixture that
    omits those columns still works). Returns {"band_met", "sr1_met", "chosen", "best_band_only"}:
      - band_met: True iff SOME t satisfies the owner's actual band (false_warn<=0.20, recall>=0.50),
        regardless of SR-1 — this is what "PASS on the 92" means per §5.4.4's verbatim verdict rule.
      - best_band_only: the highest-recall (ties -> larger t) row among ALL band-satisfying rows,
        ignoring SR-1 — the point a pass_fire_rate_rejected sentence cites.
      - sr1_met: True iff some band-satisfying row ALSO clears the fire-rate ceiling.
      - chosen: the tie-rule winner among band-AND-SR1 rows (None unless sr1_met) — the point a real
        PASS sentence cites, and what SR-3 freezes for §5.2's replication.
    n_rows is accepted for symmetry with the doc's phrasing but is not needed separately: `warn_rate`
    in each row already carries the (tp+fp)/n_rows fraction."""
    del n_rows

    def in_band( r ):
        return ( r["false_warn"] is not None and r["false_warn"] <= FALSE_WARN_MAX
                and r["recall"] is not None and r["recall"] >= RECALL_MIN )

    def clears_sr1( r ):
        return r["warn_rate"] is not None and r["warn_rate"] <= FIRE_RATE_CEILING

    def pick( rows ):
        return max( rows, key=lambda r: ( r["recall"], r["threshold"] ) ) if rows else None

    band_rows = [ r for r in table if in_band( r ) ]
    safe_rows = [ r for r in band_rows if clears_sr1( r ) ]
    return dict( band_met=bool( band_rows ), sr1_met=bool( safe_rows ),
                best_band_only=pick( band_rows ), chosen=pick( safe_rows ) )


# ── §5.4.5 — uncertainty ────────────────────────────────────────────────────────────────────────────
def _by_repo( rows ):
    out = {}
    for r in rows:
        out.setdefault( r["repo"], [] ).append( r )
    return out


def _quantile_ci( boots, alpha=0.025 ):
    """(lo, hi, n_usable) from a sorted-on-return bootstrap distribution. Empty input -> (None, None, 0)."""
    if not boots:
        return None, None, 0
    boots = sorted( boots )
    lo = boots[ max( 0, int( alpha * len( boots ) ) ) ]
    hi = boots[ min( len( boots ) - 1, int( ( 1 - alpha ) * len( boots ) ) ) ]
    return lo, hi, len( boots )


def bootstrap_auroc_ci( rows, grain, seed=BOOTSTRAP_SEED, n_boot=BOOTSTRAP_RESAMPLES ):
    """Repository-clustered bootstrap 95% CI for served_syms's AUROC against `grain`'s miss label.
    Method: bench/agentloop/analyze.py's `clustered_bootstrap_lower` (resample REPOS with replacement,
    `len(repos)` draws per resample, pool every row belonging to the sampled repos, recompute).
    Independent re-implementation for this row shape and for a single-arm AUROC rather than a paired
    delta — that function is not imported (it is paired-delta-specific and inlined in its own module).
    A resample whose pooled sample is single-class on `grain` yields no AUROC (auroc() returns None)
    and is excluded from the interval; the number actually used is returned as n_usable.
    (lo, hi, n_usable) — the point estimate is computed by the caller, once, on the real 92 rows."""
    by_repo = _by_repo( rows )
    repos = sorted( by_repo )
    if not repos:
        return None, None, 0
    rng = random.Random( seed )
    boots = []
    for _ in range( n_boot ):
        sampled_repos = [ rng.choice( repos ) for _ in repos ]
        pooled = [ row for repo in sampled_repos for row in by_repo[repo] ]
        labels = [ not row[grain] for row in pooled ]
        scores = [ ORIENTATION * row["served_syms"] for row in pooled ]
        a = auroc( labels, scores )
        if a is not None:
            boots.append( a )
    lo, hi, n_usable = _quantile_ci( boots )
    return lo, hi, n_usable


def bootstrap_operating_point_ci( rows, grain, t, seed=BOOTSTRAP_SEED, n_boot=BOOTSTRAP_RESAMPLES ):
    """Same repo-clustered bootstrap, at the FIXED threshold t — never re-swept per resample (§5.4.5:
    this answers "how stable is THIS t's cell counts", not "would a fresh sweep pick a different t").
    Returns {"false_warn": {...}, "recall": {...}}, each {point, ci_lo, ci_hi, n_resamples}. A resample
    with no positive (or no negative) row on `grain` contributes no reading to whichever statistic needs
    that class and is excluded from that statistic's count only."""
    labels_point = [ not r[grain] for r in rows ]
    values_point = [ r["served_syms"] for r in rows ]
    tp, fn, fp, tn = _confusion_ge( labels_point, values_point, t )
    point = prf( tp, fn, fp, tn )

    by_repo = _by_repo( rows )
    repos = sorted( by_repo )
    rng = random.Random( seed )
    fw_boots, rc_boots = [], []
    for _ in range( n_boot ):
        sampled_repos = [ rng.choice( repos ) for _ in repos ]
        pooled = [ row for repo in sampled_repos for row in by_repo[repo] ]
        labels = [ not row[grain] for row in pooled ]
        values = [ row["served_syms"] for row in pooled ]
        tp2, fn2, fp2, tn2 = _confusion_ge( labels, values, t )
        stats = prf( tp2, fn2, fp2, tn2 )
        if stats["false_abstain_rate"] is not None:
            fw_boots.append( stats["false_abstain_rate"] )
        if stats["recall"] is not None:
            rc_boots.append( stats["recall"] )
    fw_lo, fw_hi, fw_n = _quantile_ci( fw_boots )
    rc_lo, rc_hi, rc_n = _quantile_ci( rc_boots )
    return dict( false_warn=dict( point=point["false_abstain_rate"], ci_lo=fw_lo, ci_hi=fw_hi,
                                  n_resamples=fw_n ),
                recall=dict( point=point["recall"], ci_lo=rc_lo, ci_hi=rc_hi, n_resamples=rc_n ) )


# ── §5.4.6 — the assembled result ───────────────────────────────────────────────────────────────────
# Disclosed once, reused in every outcome's sentence so the wording never drifts between them (MEDIUM-1/
# HIGH-1e): served_syms WAS scored once, exploratorily, before this registration -- the sentence must
# say so, never "was never scored", and must say the orientation below was informed by that.
_SEEN_CLAUSE = (
    "served_syms had never been scored against our pre-registered band -- an exploratory AUROC (0.669 "
    "file_hit / 0.723 func_hit) had been computed once in a prior review, on this same 92, without an "
    "operating point or a recorded orientation. Scored now under a named procedure, with the "
    "orientation fixed in advance as the raw value -- informed by that exploratory AUROC having "
    "already been seen, not blind (§5.4.3)" )

PUBLIC_SENTENCE_MISMATCH = (
    _SEEN_CLAUSE + ": the asset tree available today does not reproduce the pre-registered "
    "92-instance population, so no number under this procedure is reported as measured on it." )


def _fmt3( v ):
    return "n/a" if v is None else "%.3f" % v


def _public_sentence_fail( grain, g ):
    return ( _SEEN_CLAUSE + ", it does not reach the band (false-warn <= 0.20 at miss-recall >= 0.50) "
            "on %s: AUROC %s [%s, %s] (§5.2 rung: %s), and no threshold clears both floors "
            "together." %
            ( grain, _fmt3( g["auroc"] ), _fmt3( g["auroc_ci_lo"] ), _fmt3( g["auroc_ci_hi"] ),
             g["auroc_band_5_2"] or "n/a" ) )


def _public_sentence_pass( grain, chosen, op_ci, grain_honesty ):
    fw, rc = op_ci["false_warn"], op_ci["recall"]
    other_verdict = "also meets" if grain_honesty["other_grain_pass"] else "does not meet"
    return ( _SEEN_CLAUSE + ", at threshold t=%d served rows it reaches false-warn=%.3f [%s, %s] and "
            "miss-recall=%.3f [%s, %s] on %s (%d/%d and %d/%d bootstrap resamples usable) -- inside "
            "the pre-registered band and within the 25%% fire-rate ceiling (warns on %.1f%% of the "
            "92). %s %s the same band. This is an in-sample result on one 92-row sample (per "
            "docs/research/confidence-and-abstention.md §5.2) and licenses 'worth replicating,' "
            "not 'shippable': replication on >=92 fresh held-out instances, at this same frozen "
            "threshold and orientation, has not been run." %
            ( chosen["threshold"], chosen["false_warn"], _fmt3( fw["ci_lo"] ), _fmt3( fw["ci_hi"] ),
             chosen["recall"], _fmt3( rc["ci_lo"] ), _fmt3( rc["ci_hi"] ), grain,
             fw["n_resamples"], BOOTSTRAP_RESAMPLES, rc["n_resamples"], BOOTSTRAP_RESAMPLES,
             chosen["warn_rate"] * 100.0, grain_honesty["other_grain"], other_verdict ) )


def _public_sentence_fire_rate_rejected( grain, best_band_only ):
    return ( _SEEN_CLAUSE + ", it reaches the band at t=%d served rows (false-warn=%.3f, "
            "miss-recall=%.3f on %s) -- but that threshold warns on %.1f%% of the 92, above the 25%% "
            "fire-rate ceiling §5.3 registered (carried into this round as SR-1). It meets the "
            "band and fails the fire-rate self-reject: not a candidate for shipping, and this sample "
            "has no in-band threshold that also clears SR-1." %
            ( best_band_only["threshold"], best_band_only["false_warn"], best_band_only["recall"],
             grain, best_band_only["warn_rate"] * 100.0 ) )


def score_served_syms( summary, rows ):
    """The full §5.4 procedure. `summary` is calibrate_confidence.py's already-built summary dict (read
    only for the §5.4.1 fingerprint check, together with `rows` for the count check); `rows` is its
    `instances` list. Returns a dict meant to be merged into that summary under the key
    "served_syms_5_4" — never mutates either argument.

    Four outcomes (fix round 1, HIGH-3): "fingerprint_mismatch" | "pass" (band met AND SR-1 met) |
    "pass_fire_rate_rejected" (band met at some t, but every such t warns on > 25% of rows) | "fail"
    (no t meets the band at all). `out["pass"]` is True iff outcome == "pass" specifically."""
    fp_ok, fp_detail = check_fingerprint( summary, rows )
    out = dict( fingerprint_ok=fp_ok, fingerprint=fp_detail, orientation=ORIENTATION,
               gating_grain=GATING_GRAIN,
               band=dict( false_warn_max=FALSE_WARN_MAX, recall_min=RECALL_MIN,
                         fire_rate_ceiling=FIRE_RATE_CEILING ),
               auroc_band_5_2=dict( meets=AUROC_MEETS_5_2, weak=AUROC_WEAK_5_2,
                                    refutation=AUROC_REFUTATION_5_2 ),
               asset_tree=summary.get( "meta", {} ).get( "assets" ),
               binary_version=summary.get( "meta", {} ).get( "binary_version" ) )
    if not fp_ok:
        out["outcome"] = "fingerprint_mismatch"
        out["public_sentence"] = PUBLIC_SENTENCE_MISMATCH
        return out

    n = len( rows )
    grains = {}
    for grain in ( "file_hit", "func_hit" ):
        labels = [ not r[grain] for r in rows ]
        scores = [ ORIENTATION * r["served_syms"] for r in rows ]
        auc = auroc( labels, scores )
        ci_lo, ci_hi, n_res = bootstrap_auroc_ci( rows, grain )
        table = sweep( labels, [ r["served_syms"] for r in rows ] )
        grains[grain] = dict( n=n, misses=sum( labels ), auroc=auc,
                              auroc_ci_lo=ci_lo, auroc_ci_hi=ci_hi, auroc_ci_resamples=n_res,
                              auroc_band_5_2=auroc_band_5_2( auc ), sweep=table )
    out["grains"] = grains

    op = choose_operating_point( grains[GATING_GRAIN]["sweep"], n )
    out["band_met"] = op["band_met"]
    out["sr1_met"] = op["sr1_met"]
    out["chosen_threshold"] = op["chosen"]
    out["best_band_only_threshold"] = op["best_band_only"]

    if op["band_met"] and op["sr1_met"]:
        chosen = op["chosen"]
        op_ci = bootstrap_operating_point_ci( rows, GATING_GRAIN, chosen["threshold"] )
        out["operating_point_ci"] = op_ci
        other_grain = "file_hit" if GATING_GRAIN == "func_hit" else "func_hit"
        other_pass = any( r["safe"] for r in grains[other_grain]["sweep"] )
        out["grain_honesty"] = dict( gating_grain=GATING_GRAIN, gating_grain_pass=True,
                                     other_grain=other_grain, other_grain_pass=other_pass )
        out["outcome"] = "pass"
        out["pass"] = True
        out["public_sentence"] = _public_sentence_pass( GATING_GRAIN, chosen, op_ci, out["grain_honesty"] )
    elif op["band_met"]:
        out["outcome"] = "pass_fire_rate_rejected"
        out["pass"] = False
        out["public_sentence"] = _public_sentence_fire_rate_rejected( GATING_GRAIN, op["best_band_only"] )
    else:
        out["outcome"] = "fail"
        out["pass"] = False
        out["public_sentence"] = _public_sentence_fail( GATING_GRAIN, grains[GATING_GRAIN] )
    return out
