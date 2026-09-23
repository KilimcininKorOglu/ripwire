#!/usr/bin/env python3
"""
Unit tests for bench/locbench/served_syms_signal.py — the §5.4 pre-registered scoring procedure for
`served_syms` (docs/research/confidence-and-abstention.md §5.4, dated 2026-09-23).

SYNTHETIC ONLY. Every fixture here is hand-built in this file. Nothing reads LocBench data, invokes
the ripwire binary, or touches the network — the pre-registration this module scores against requires
that no served_syms number be reported "on the 92" before the real asset tree is on disk; these tests
exist to prove the MATH (operating-point sweep, tie rule, fire-rate self-reject, orientation, bootstrap
determinism, fingerprint check) is correct in advance of that, on data invented for the purpose.

Pure Python, no network, no pytest dependency — same convention as bench/locbench/test_compare_gate.py.
Runs as a plain script:

    python3 bench/locbench/served_syms_signal.py    # (module has no __main__; run the test file)
    python3 bench/locbench/test_served_syms_signal.py

or, if pytest happens to be installed:

    python3 -m pytest bench/locbench/test_served_syms_signal.py

Each `test_*` function is a self-contained assert-based case; `main()` runs them all and reports.
"""
import os, sys

HERE = os.path.dirname( os.path.abspath( __file__ ) )
sys.path.insert( 0, HERE )
sys.path.insert( 0, os.path.join( os.path.dirname( HERE ), "arb" ) )

import served_syms_signal as S
from score_abstention_calibration import auroc


# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────
def mkrow( repo, served_syms, file_hit, func_hit, confidence="low", margin_pct=0 ):
    """A hand-built row in exactly the shape calibrate_confidence.py's grade()/measure_instance()
    produce: instance_id/repo/served_syms/file_hit/func_hit/confidence/margin_pct at minimum — the
    fields served_syms_signal.py actually reads."""
    return dict( instance_id="%s#%d" % ( repo, served_syms ), repo=repo, served_syms=served_syms,
                file_hit=file_hit, func_hit=func_hit, confidence=confidence, margin_pct=margin_pct )


def synthetic_summary( n=92, confidence_low=74, confidence_high=18,
                       misses_file=15, misses_func=38, auroc_file=0.580, auroc_func=0.622 ):
    """The slice of calibrate_confidence.py's `summary` dict check_fingerprint() actually reads."""
    return dict(
        n_scored=n,
        meta=dict( assets="/synthetic/assets", binary_version="ripwire 0.0.0 (test)" ),
        overall=dict( confidence_high=confidence_high ),
        discrimination=dict(
            file_hit=dict( misses=misses_file, auroc=auroc_file ),
            func_hit=dict( misses=misses_func, auroc=auroc_func ) ) )


# ── fingerprint (§5.4.1) ────────────────────────────────────────────────────────────────────────────
def test_fingerprint_matches():
    ok, detail = S.check_fingerprint( synthetic_summary() )
    assert ok, detail
    assert all( detail["checks"].values() ), detail["checks"]


def test_fingerprint_rejects_wrong_split():
    ok, detail = S.check_fingerprint( synthetic_summary( confidence_low=70, confidence_high=22 ) )
    assert not ok
    assert detail["checks"]["confidence_low"] is False
    assert detail["checks"]["confidence_high"] is False
    # everything NOT touched by the mutation must still read True — a single failing check must not
    # taint the others, or a report reading `checks` would misname which figure actually broke.
    assert detail["checks"]["n"] is True
    assert detail["checks"]["misses_file_hit"] is True


def test_fingerprint_rejects_auroc_outside_tolerance():
    ok, detail = S.check_fingerprint( synthetic_summary( auroc_func=0.700 ) )
    assert not ok
    assert detail["checks"]["score_auroc_func_hit"] is False
    assert detail["checks"]["score_auroc_file_hit"] is True


def test_fingerprint_tolerates_rounding_noise():
    # the doc's figures are 3dp; a run landing at 0.6223 (rounds to the same 0.622) must still pass.
    ok, _detail = S.check_fingerprint( synthetic_summary( auroc_func=0.6223, auroc_file=0.5798 ) )
    assert ok


def test_score_served_syms_reports_fingerprint_mismatch_and_nothing_else():
    summary = synthetic_summary( n=91 )   # off by one instance
    out = S.score_served_syms( summary, rows=[] )
    assert out["outcome"] == "fingerprint_mismatch"
    assert out["public_sentence"] == S.PUBLIC_SENTENCE_MISMATCH
    assert "grains" not in out
    assert "chosen_threshold" not in out
    assert "pass" not in out


# ── the >= confusion primitive and the threshold sweep (§5.4.4) ───────────────────────────────────────
def test_confusion_ge_hand_computed():
    # misses (label True) carry the LARGE served_syms values (10, 12); hits carry the small ones
    # (3, 4, 5) — the registered orientation (§5.4.3) says that is the pattern a real miss detector
    # would show.
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    assert S._confusion_ge( labels, values, 10 ) == ( 2, 0, 0, 3 )     # both misses caught, no hit warned
    assert S._confusion_ge( labels, values, 13 ) == ( 0, 2, 0, 3 )     # warn nobody -> both misses missed
    assert S._confusion_ge( labels, values, 3 )  == ( 2, 0, 3, 0 )     # warn everybody -> every hit false-warned


def test_sweep_candidate_set_and_boundary_rows():
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    table = S.sweep( labels, values )
    thresholds = [ r["threshold"] for r in table ]
    assert thresholds == [ 3, 4, 5, 10, 12, 13 ], thresholds   # distinct(values) ∪ {max+1}, sorted

    low = next( r for r in table if r["threshold"] == 3 )      # warn everyone
    assert low["recall"] == 1.0 and low["false_warn"] == 1.0 and low["warn_rate"] == 1.0

    high = next( r for r in table if r["threshold"] == 13 )    # warn no one
    assert high["recall"] == 0.0 and high["false_warn"] == 0.0 and high["warn_rate"] == 0.0

    mid = next( r for r in table if r["threshold"] == 12 )
    assert mid["recall"] == 0.5 and mid["false_warn"] == 0.0
    assert abs( mid["warn_rate"] - 0.2 ) < 1e-9


def test_choose_operating_point_applies_fire_rate_self_reject():
    """t=10 has PERFECT recall/false-warn (1.0 / 0.0) but warns on 2 of 5 rows == 0.4 > the 0.25 fire-
    rate ceiling (SR-1), so it must be rejected even though it would otherwise be the obvious pick.
    Only t=12 (recall 0.5, false_warn 0.0, warn_rate 0.2) survives both the band and SR-1."""
    labels = [ True, True, False, False, False ]
    values = [ 10, 12, 3, 4, 5 ]
    table = S.sweep( labels, values )
    chosen = S.choose_operating_point( table, n_rows=5 )
    assert chosen is not None
    assert chosen["threshold"] == 12
    assert chosen["recall"] == 0.5
    assert chosen["false_warn"] == 0.0


def test_choose_operating_point_tie_rule_prefers_larger_threshold():
    """Two candidate rows tied on recall (both 0.6, both inside the band and under the fire-rate
    ceiling) at different thresholds -- the larger threshold (fewer rows warned, more conservative)
    must win, per §5.4.4's tie rule."""
    table = [
        dict( threshold=5, recall=0.6, false_warn=0.10, warn_rate=0.20, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=8, recall=0.6, false_warn=0.05, warn_rate=0.15, tp=3, fn=2, fp=1, tn=9 ),
        dict( threshold=2, recall=0.9, false_warn=0.50, warn_rate=0.60, tp=4, fn=1, fp=6, tn=4 ),  # out of band
    ]
    chosen = S.choose_operating_point( table, n_rows=15 )
    assert chosen is not None and chosen["threshold"] == 8


def test_choose_operating_point_none_when_nothing_qualifies():
    table = [ dict( threshold=t, recall=0.1, false_warn=0.9, warn_rate=0.5, tp=0, fn=0, fp=0, tn=0 )
             for t in ( 1, 2, 3 ) ]
    assert S.choose_operating_point( table, n_rows=10 ) is None


# ── orientation (§5.4.3) ────────────────────────────────────────────────────────────────────────────
def test_orientation_direction_matters_for_auroc():
    """A clean fixture where misses genuinely carry larger served_syms. Scoring it under the REGISTERED
    orientation (ORIENTATION * served_syms, i.e. served_syms unchanged since ORIENTATION == +1) must
    give a strong AUROC; scoring the SAME rows under the opposite orientation (manually negated here,
    never by touching the module constant) must give a correspondingly weak one -- proving the
    direction is not a free parameter the AUROC calculation quietly absorbs."""
    rows = ( [ mkrow( "r/a", sz, file_hit=False, func_hit=False ) for sz in ( 30, 32, 35, 40, 28 ) ]
            + [ mkrow( "r/b", sz, file_hit=True, func_hit=True ) for sz in ( 3, 5, 4, 6, 2 ) ] )
    labels = [ not r["func_hit"] for r in rows ]
    correct = auroc( labels, [ S.ORIENTATION * r["served_syms"] for r in rows ] )
    flipped = auroc( labels, [ -S.ORIENTATION * r["served_syms"] for r in rows ] )
    assert correct > 0.9, correct
    assert flipped < 0.1, flipped
    assert abs( ( correct + flipped ) - 1.0 ) < 1e-9   # AUROC(-score) == 1 - AUROC(score), exactly


# ── bootstrap (§5.4.5) ──────────────────────────────────────────────────────────────────────────────
def _clean_rows( n_miss_repos=6, n_hit_repos=6, miss_base=1000, hit_base=1 ):
    """Two disjoint served_syms ranges (miss rows always >= miss_base, hit rows always < miss_base) so
    the fixture stays cleanly separated regardless of how many repos of each kind are asked for —
    a hit-heavy fixture (for the fire-rate/warn_rate tests) must not accidentally let a hit row's
    served_syms wander into the miss range."""
    rows = []
    for i in range( n_miss_repos ):
        rows += [ mkrow( "miss-repo-%d" % i, sz, file_hit=False, func_hit=False )
                 for sz in ( miss_base + 2 * i, miss_base + 2 * i + 1 ) ]
    for i in range( n_hit_repos ):
        rows += [ mkrow( "hit-repo-%d" % i, sz, file_hit=True, func_hit=True )
                 for sz in ( hit_base + 2 * i, hit_base + 2 * i + 1 ) ]
    return rows


def test_bootstrap_auroc_ci_is_deterministic_and_sane():
    rows = _clean_rows()
    lo1, hi1, n1 = S.bootstrap_auroc_ci( rows, "func_hit", n_boot=500 )
    lo2, hi2, n2 = S.bootstrap_auroc_ci( rows, "func_hit", n_boot=500 )
    assert ( lo1, hi1, n1 ) == ( lo2, hi2, n2 ), "same seed, same rows must reproduce byte-identically"
    assert n1 > 0
    assert 0.0 <= lo1 <= hi1 <= 1.0
    point = auroc( [ not r["func_hit"] for r in rows ], [ r["served_syms"] for r in rows ] )
    assert lo1 <= point + 1e-9    # the point estimate should not sit strictly outside its own CI on a
                                  # clean, well-separated fixture (a loose sanity check, not a proof)


def test_bootstrap_operating_point_ci_matches_point_estimate_math():
    rows = _clean_rows()
    ci = S.bootstrap_operating_point_ci( rows, "func_hit", t=20, n_boot=300 )
    labels = [ not r["func_hit"] for r in rows ]
    values = [ r["served_syms"] for r in rows ]
    tp, fn, fp, tn = S._confusion_ge( labels, values, 20 )
    from score_abstention_calibration import prf
    expected = prf( tp, fn, fp, tn )
    assert ci["false_warn"]["point"] == expected["false_abstain_rate"]
    assert ci["recall"]["point"] == expected["recall"]
    assert ci["false_warn"]["n_resamples"] > 0 and ci["recall"]["n_resamples"] > 0


# ── end-to-end score_served_syms() (§5.4.6) ────────────────────────────────────────────────────────
def test_score_served_syms_end_to_end_pass():
    # 12 miss rows (served_syms >= 1000) + 80 hit rows (served_syms < 100) = 92, matching the
    # fingerprint's default n=92 exactly; the disjoint ranges keep warn_rate low (SR-1) once a
    # threshold near 1000 is chosen.
    rows = _clean_rows( n_miss_repos=6, n_hit_repos=40 )
    assert len( rows ) == 92
    summary = synthetic_summary()
    out = S.score_served_syms( summary, rows )
    assert out["outcome"] == "pass", out
    assert out["pass"] is True
    assert out["chosen_threshold"] is not None
    assert "worth replicating" in out["public_sentence"]
    assert "not 'shippable'" in out["public_sentence"]
    assert out["grain_honesty"]["gating_grain"] == "func_hit"
    # every candidate threshold's point must be present for both grains (nothing hidden but the winner)
    assert len( out["grains"]["func_hit"]["sweep"] ) >= 2
    assert len( out["grains"]["file_hit"]["sweep"] ) >= 2


def test_score_served_syms_end_to_end_fail_on_no_signal():
    """served_syms uncorrelated with the miss label: no threshold should clear the band."""
    rows = ( [ mkrow( "r/%d" % i, 10, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
              for i in range( 46 ) ]
            + [ mkrow( "s/%d" % i, 10, file_hit=( i % 2 == 0 ), func_hit=( i % 2 == 0 ) )
               for i in range( 46 ) ] )
    # constant served_syms carries no ranking information at all -- a single-value column.
    summary = synthetic_summary( n=len( rows ) )
    out = S.score_served_syms( summary, rows )
    assert out["outcome"] == "fail", out
    assert out["pass"] is False
    assert out["chosen_threshold"] is None
    assert "does not reach the band" in out["public_sentence"]


TESTS = [
    test_fingerprint_matches,
    test_fingerprint_rejects_wrong_split,
    test_fingerprint_rejects_auroc_outside_tolerance,
    test_fingerprint_tolerates_rounding_noise,
    test_score_served_syms_reports_fingerprint_mismatch_and_nothing_else,
    test_confusion_ge_hand_computed,
    test_sweep_candidate_set_and_boundary_rows,
    test_choose_operating_point_applies_fire_rate_self_reject,
    test_choose_operating_point_tie_rule_prefers_larger_threshold,
    test_choose_operating_point_none_when_nothing_qualifies,
    test_orientation_direction_matters_for_auroc,
    test_bootstrap_auroc_ci_is_deterministic_and_sane,
    test_bootstrap_operating_point_ci_matches_point_estimate_math,
    test_score_served_syms_end_to_end_pass,
    test_score_served_syms_end_to_end_fail_on_no_signal,
]


def main():
    failures = []
    for t in TESTS:
        try:
            t()
            print( "PASS  %s" % t.__name__ )
        except AssertionError as e:
            failures.append( t.__name__ )
            print( "FAIL  %s: %s" % ( t.__name__, e ) )
    print( "\n%d/%d passed" % ( len( TESTS ) - len( failures ), len( TESTS ) ) )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit( main() )
