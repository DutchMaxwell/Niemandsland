"""NML-1147 — `tools/pick_stage_census.py`'s STAGE-DIFF LOGIC.

The tool's home is the arena corpus outside the repo and a rollout there is
minutes. What is pinned here is the half that decides the verdict and carries
no planner at all: the first-diverging-stage walk, and the ONE synthetic red
per stage — a tampered trace must bucket into the stage the tamper touched,
never silently into "clean". The order-stage zero-gates (`rank_order`, `pool`,
`argmax`) are the tool's permanent regression tripwire: the tie-break chain is
ported at parity, and any nonzero there is a regression, not a finding.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import pick_stage_census as psc  # noqa: E402


def _trace(scored=None, pool_idx=None, rs=None, best_idx=None):
    t = {}
    if scored is not None:
        t["scored"] = scored
    if pool_idx is not None:
        t["pool_idx"] = pool_idx
    if rs is not None:
        t["rs"] = rs
    if best_idx is not None:
        t["best_idx"] = best_idx
    return t


def _rows(scores):
    """scored/rs rows as idx:score pairs in order."""
    return [{"idx": i, "score": s, "rs": s} for i, s in enumerate(scores)]


def test_identical_traces_are_clean():
    t = _trace(scored=_rows([0.5, 0.4]), pool_idx=[0, 1],
               rs=_rows([0.5, 0.4]), best_idx=0)
    assert psc.stage_diff(t, t) == []


def test_a_shorter_prefilter_is_prefilter_len():
    a = _trace(scored=_rows([0.5, 0.4]))
    b = _trace(scored=_rows([0.5, 0.4, 0.3]))
    assert psc.stage_diff(a, b) == ["prefilter_len"]


def test_a_different_candidate_set_is_prefilter_idxset():
    a = _trace(scored=[{"idx": 0, "score": 0.5}, {"idx": 1, "score": 0.4}])
    b = _trace(scored=[{"idx": 0, "score": 0.5}, {"idx": 2, "score": 0.4}])
    assert psc.stage_diff(a, b) == ["prefilter_idxset"]


def test_a_score_drift_reports_its_magnitude():
    a = _trace(scored=_rows([0.5, 0.4]))
    b = _trace(scored=_rows([0.5, 0.47]))
    d = psc.stage_diff(a, b)
    assert d[0] == "prefilter_score_drift"
    assert abs(d[1] - 0.07) < 1e-12


def test_swapped_tied_rows_are_rank_order_the_tie_breaks_own_signature():
    a = _trace(scored=[{"idx": 0, "score": 0.5}, {"idx": 1, "score": 0.5}])
    b = _trace(scored=[{"idx": 1, "score": 0.5}, {"idx": 0, "score": 0.5}])
    assert psc.stage_diff(a, b) == ["rank_order"]


def test_a_different_pool_order_is_pool():
    a = _trace(scored=_rows([0.5, 0.4]), pool_idx=[0, 1])
    b = _trace(scored=_rows([0.5, 0.4]), pool_idx=[1, 0])
    assert psc.stage_diff(a, b) == ["pool"]


def test_an_rs_drift_reports_magnitude_and_row_count():
    a = _trace(scored=_rows([0.5, 0.4]), rs=_rows([0.5, 0.4]))
    b = _trace(scored=_rows([0.5, 0.4]),
               rs=[{"idx": 0, "rs": 0.5}, {"idx": 1, "rs": 0.46}])
    d = psc.stage_diff(a, b)
    assert d[0] == "rs_drift"
    assert abs(d[1] - 0.06) < 1e-12 and d[2] == 1


def test_a_different_argmax_is_the_last_stage():
    a = _trace(scored=_rows([0.5, 0.4]), rs=_rows([0.5, 0.4]), best_idx=0)
    b = _trace(scored=_rows([0.5, 0.4]), rs=_rows([0.5, 0.4]), best_idx=1)
    assert psc.stage_diff(a, b) == ["argmax"]
