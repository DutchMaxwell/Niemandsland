"""NML-1146 — `tools/pick_census.py`'s CLASSIFICATION LOGIC.

The tool's home is the arena corpus outside the repo and a rollout there is
minutes — far too much for a test suite. What is pinned here is the half that
decides the verdict and carries no planner at all: the margin buckets, the
unit-flip anatomy (recorded margin, one-step swap, twin margin), and the ONE
synthetic red — a wrong vintage must agree STRICTLY less, and equality fails.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import pick_census as pc  # noqa: E402


# ---------------------------------------------------------------- buckets ---


def test_margin_buckets_cut_at_the_documented_edges():
    assert pc.margin_bucket(0.0) == "<1e-3"
    assert pc.margin_bucket(9.9e-4) == "<1e-3"
    assert pc.margin_bucket(1e-3) == "<1e-2"
    assert pc.margin_bucket(9.9e-3) == "<1e-2"
    assert pc.margin_bucket(1e-2) == "<5e-2"
    assert pc.margin_bucket(4.9e-2) == "<5e-2"
    assert pc.margin_bucket(5e-2) == ">=5e-2"


def test_a_missing_runner_up_stays_none_not_a_tie():
    """A margin with nothing to subtract is no data — folding it into "<1e-3"
    would count a tie the tie-break never faced."""
    assert pc.margin_bucket(None) == "none"


# ------------------------------------------------------------ flip anatomy ---


def _pick(after, score, unit=None):
    p = {"expectation": {"after": after}}
    if score is not None:
        p["runner_up"] = {"score": score, "unit_key": unit}
    return p


def test_flip_row_reads_recorded_margin_swap_and_twin_margin():
    rec = _pick(0.50, 0.495, "b")
    twin = dict(_pick(0.50, 0.48, "c"), unit_key="b")
    row = pc.flip_row(rec, twin)
    assert row == {"rec": "<1e-2", "swap": True, "twin": "<5e-2"}


def test_flip_row_says_none_when_either_side_has_no_runner_up():
    assert pc.flip_row(_pick(0.5, None), dict(unit_key="b")) == \
        {"rec": "none", "swap": False, "twin": "none"}


def test_swap_is_false_when_the_twin_lands_elsewhere():
    rec = _pick(0.5, 0.4, "b")
    twin = dict(_pick(0.5, 0.3, "c"), unit_key="c")
    assert pc.flip_row(rec, twin)["swap"] is False


# ------------------------------------------------------------ synthetic red ---


def test_red_needs_strictly_less_agreement():
    assert pc.red_holds(90, 89)
    assert not pc.red_holds(90, 90)
    assert not pc.red_holds(90, 91)
