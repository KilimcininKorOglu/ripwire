#!/usr/bin/env python3
# served_syms_signal.py — the pre-registered scoring procedure for `served_syms` as a miss/abstention
# signal (docs/research/confidence-and-abstention.md §5.4, pre-registered 2026-09-23, BEFORE any
# served_syms number existed under this procedure).
#
# WHAT THIS IS. `served_syms` (calibrate_confidence.py's `grade()`'s `served_syms=len(head)`) already
# ships on every `--for` bundle as the size of the served head; it has never been scored against the
# band `docs/research/confidence-and-abstention.md` §5.2 registered for a miss/abstention signal
# (false-warn <= 0.20 at miss-recall >= 0.50). This module IS that scoring, run over rows
# `calibrate_confidence.py`'s `scored_instances()` already produces — it reads no LocBench data
# itself, invokes the binary nowhere, and fetches nothing. It is pure post-processing of a `rows` list
# whose per-row shape already carries `served_syms`, `file_hit`, `func_hit`, `confidence`,
# `margin_pct`, `repo`, `instance_id` (see calibrate_confidence.py's `grade()`/`measure_instance()`).
#
# COMMENSURABILITY. Reuses `auroc`, `confusion` and `prf` from bench/arb/score_abstention_calibration.py
# — the registered primitives — rather than re-deriving any of them. The registered orientation (§5.4.3
# — larger served_syms is more miss evidence) warns on the HIGH side of a threshold, but `confusion()`
# only counts the LOW-side predicate `value <= threshold`. Rather than a second counting loop, `_confusion_ge`
# gets there by calling `confusion(labels, values, t - 1)` (exact, because served_syms is an integer)
# and relabelling its four cells — see that function's docstring for the swap. No new loop, no new
# comparison logic; `confusion()` is the only place `<=`/`>=` counting happens in this module.
#
# FROZEN BY THE PRE-REGISTRATION — none of the constants below may be tuned after seeing a served_syms
# number; a change to any of them is a new pre-registration, not a bug fix:
#   ORIENTATION        — §5.4.3: +1 == larger served_syms is registered as MORE miss evidence.
#   GATING_GRAIN        — §5.4.2: func_hit is the sole grain a PASS is checked against; file_hit is
#                          scored and reported but never gates a PASS.
#   FALSE_WARN_MAX,
#   RECALL_MIN          — §5.2's band, unchanged: 0.20 / 0.50.
#   FIRE_RATE_CEILING    — §5.3 rule 2, carried into this round as SR-1: 0.25.
#   FINGERPRINT          — §5.4.1's four reproduction figures, checked before anything else runs.
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
ORIENTATION = 1   # +1: larger served_syms == more miss evidence. See module docstring; sweep()'s `>=`
                  # direction is hardwired to this value (asserted below) — changing ORIENTATION is a
                  # new pre-registration decision, not a config flip, and must change the comparison
                  # direction in _confusion_ge/sweep() in the SAME commit.
assert ORIENTATION == 1, "ORIENTATION changed without updating _confusion_ge's >= direction to match"

GATING_GRAIN = "func_hit"          # §5.4.2 — the sole grain a PASS is checked against
FALSE_WARN_MAX = 0.20              # §5.2's band
RECALL_MIN = 0.50                  # §5.2's band
FIRE_RATE_CEILING = 0.25           # §5.3 rule 2 / this round's SR-1

# §5.4.1's four reproduction figures. "score" here is the arb_score (confidence=/margin_pct= combined)
# AUROC calibrate_confidence.py's discrimination() already computes — the doc calls it "margin_pct=/
# score AUROC" because on this corpus margin_pct= carries no information confidence= does not already
# carry (§3.3: "margin_pct= adds no ordering information to confidence=").
FINGERPRINT = dict(
    n=92, confidence_low=74, confidence_high=18,
    misses=dict( file_hit=15, func_hit=38 ),
    score_auroc=dict( file_hit=0.580, func_hit=0.622 ),
)
FINGERPRINT_AUROC_TOL = 0.0005     # tolerance around the doc's 3-decimal-place figures

BOOTSTRAP_SEED = "ripwire-served-syms-prereg-v1"
BOOTSTRAP_RESAMPLES = 10000


# ── §5.4.1 — population fingerprint ─────────────────────────────────────────────────────────────────
def check_fingerprint( summary ):
    """(ok, detail). ok is True iff this run's population reproduces every one of §5.4.1's four pinned
    figures on `summary` (calibrate_confidence.py's already-built summary dict, read here, never
    recomputed). detail is always returned, even when ok, so a report can quote exactly what matched."""
    n = summary["n_scored"]
    high = summary["overall"]["confidence_high"]
    low = n - high
    misses = { g: summary["discrimination"][g]["misses"] for g in ( "file_hit", "func_hit" ) }
    score_auroc = { g: summary["discrimination"][g]["auroc"] for g in ( "file_hit", "func_hit" ) }

    def close( a, b ):
        return a is not None and abs( a - b ) <= FINGERPRINT_AUROC_TOL

    checks = dict(
        n=( n == FINGERPRINT["n"] ),
        confidence_low=( low == FINGERPRINT["confidence_low"] ),
        confidence_high=( high == FINGERPRINT["confidence_high"] ),
        misses_file_hit=( misses["file_hit"] == FINGERPRINT["misses"]["file_hit"] ),
        misses_func_hit=( misses["func_hit"] == FINGERPRINT["misses"]["func_hit"] ),
        score_auroc_file_hit=close( score_auroc["file_hit"], FINGERPRINT["score_auroc"]["file_hit"] ),
        score_auroc_func_hit=close( score_auroc["func_hit"], FINGERPRINT["score_auroc"]["func_hit"] ),
    )
    ok = all( checks.values() )
    return ok, dict( checks=checks,
                     measured=dict( n=n, confidence_low=low, confidence_high=high,
                                   misses=misses, score_auroc=score_auroc ),
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
    exactly this rule's fn (label True, warned False), and so on for the other three cells."""
    tp2, fn2, fp2, tn2 = confusion( labels, values, t - 1 )
    return fn2, tp2, tn2, fp2


def sweep( labels, values ):
    """The full §5.4.4 threshold table. T = distinct(values) ∪ {max(values)+1} (the "warn on nobody"
    sentinel `V` alone cannot represent). One row per candidate t: recall, false_warn (= prf()'s
    `false_abstain_rate`, relabelled to this round's vocabulary), warn_rate (= (tp+fp)/n, the fraction
    of the 92 this t would warn on — what SR-1 gates), and the raw confusion counts."""
    if not values:
        return []
    candidates = sorted( set( values ) ) + [ max( values ) + 1 ]
    n = len( labels )
    table = []
    for t in candidates:
        tp, fn, fp, tn = _confusion_ge( labels, values, t )
        stats = prf( tp, fn, fp, tn )
        table.append( dict( threshold=t, recall=stats["recall"], false_warn=stats["false_abstain_rate"],
                            precision=stats["precision"], f1=stats["f1"],
                            warn_rate=( ( tp + fp ) / n if n else None ),
                            tp=tp, fn=fn, fp=fp, tn=tn ) )
    return table


def choose_operating_point( table, n_rows ):
    """The §5.4.4 tie rule and SR-1, applied to `sweep()`'s table. Returns the chosen row, or None when
    no candidate clears the band and the fire-rate ceiling together — which is itself the answer, not a
    missing measurement. n_rows is accepted for symmetry with the doc's phrasing but is not needed
    separately: `warn_rate` in each row already carries the (tp+fp)/n_rows fraction."""
    del n_rows
    safe = [ r for r in table
            if r["false_warn"] is not None and r["false_warn"] <= FALSE_WARN_MAX
            and r["recall"] is not None and r["recall"] >= RECALL_MIN
            and r["warn_rate"] is not None and r["warn_rate"] <= FIRE_RATE_CEILING ]
    if not safe:
        return None
    # highest recall; ties -> larger threshold (fewer rows warned at that recall == more conservative,
    # under the >= -warns-on-large direction this rule uses).
    return max( safe, key=lambda r: ( r["recall"], r["threshold"] ) )


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
PUBLIC_SENTENCE_MISMATCH = (
    "served_syms has not been scored against the pre-registered band: the asset tree available today "
    "does not reproduce the pre-registered 92-instance population, so no number is reported as "
    "measured on it." )


def _public_sentence_fail( grain, g ):
    def s( v ):
        return "n/a" if v is None else "%.3f" % v
    return ( "served_syms, our best disclosed signal, was never scored; scored now on the "
            "pre-registered 92, it does not reach the band (false-warn <= 0.20 at miss-recall >= "
            "0.50): AUROC %s [%s, %s] (%s), and no threshold clears both floors together." %
            ( s( g["auroc"] ), s( g["auroc_ci_lo"] ), s( g["auroc_ci_hi"] ), grain ) )


def _public_sentence_pass( grain, chosen ):
    return ( "served_syms, our best disclosed signal, was never scored; scored now on the "
            "pre-registered 92 at threshold t=%d served symbols, it reaches false-warn=%.3f and "
            "miss-recall=%.3f on %s -- inside the pre-registered band. This is an in-sample result on "
            "one 92-row sample (per docs/research/confidence-and-abstention.md §5.2) and licenses "
            "'worth replicating,' not 'shippable': replication on >=92 fresh held-out instances, at "
            "this same frozen threshold and orientation, has not been run." %
            ( chosen["threshold"], chosen["false_warn"], chosen["recall"], grain ) )


def score_served_syms( summary, rows ):
    """The full §5.4 procedure. `summary` is calibrate_confidence.py's already-built summary dict (read
    only for the §5.4.1 fingerprint check); `rows` is its `instances` list. Returns a dict meant to be
    merged into that summary under the key "served_syms_5_4" — never mutates either argument."""
    fp_ok, fp_detail = check_fingerprint( summary )
    out = dict( fingerprint_ok=fp_ok, fingerprint=fp_detail, orientation=ORIENTATION,
               gating_grain=GATING_GRAIN,
               band=dict( false_warn_max=FALSE_WARN_MAX, recall_min=RECALL_MIN,
                         fire_rate_ceiling=FIRE_RATE_CEILING ),
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
                              sweep=table )
    out["grains"] = grains

    chosen = choose_operating_point( grains[GATING_GRAIN]["sweep"], n )
    out["chosen_threshold"] = chosen
    out["pass"] = chosen is not None

    if chosen is not None:
        out["operating_point_ci"] = bootstrap_operating_point_ci( rows, GATING_GRAIN, chosen["threshold"] )
        other_grain = "file_hit" if GATING_GRAIN == "func_hit" else "func_hit"
        other_pass = any( r["false_warn"] is not None and r["false_warn"] <= FALSE_WARN_MAX
                          and r["recall"] is not None and r["recall"] >= RECALL_MIN
                          and r["warn_rate"] is not None and r["warn_rate"] <= FIRE_RATE_CEILING
                          for r in grains[other_grain]["sweep"] )
        out["grain_honesty"] = dict( gating_grain=GATING_GRAIN, gating_grain_pass=True,
                                     other_grain=other_grain, other_grain_pass=other_pass )
        out["outcome"] = "pass"
        out["public_sentence"] = _public_sentence_pass( GATING_GRAIN, chosen )
    else:
        out["outcome"] = "fail"
        out["public_sentence"] = _public_sentence_fail( GATING_GRAIN, grains[GATING_GRAIN] )
    return out
