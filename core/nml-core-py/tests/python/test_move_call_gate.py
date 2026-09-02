"""GATE S4 — the PLAIN MOVE scoring, on a synthetic fixture.

`tools/move_call_gate.py` runs over the recorded arena corpus, which lives
outside the repo (see that tool's docstring). This file holds the scoring
arithmetic itself to ONE hand-built recorded call and ONE hand-built port
answer, so the END bar (0.05") and the RED (`--red-shift` moves every
recorded endpoint 0.06") are pinned without a corpus on hand.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import move_call_gate as gate  # noqa: E402


def test_a_matching_port_endpoint_passes_end_at_the_bar():
    # One model, planned at (40.0, 10.0), routed there in a straight 4" leg —
    # well inside a 6" budget, so nothing is trimmed.
    got_end = [[40.04, 9.98]]  # 0.04" off in x, 0.02" in y — inside 0.05"
    want_planned = [[40.0, 10.0]]
    want_trails = [[[36.0, 10.0], [40.0, 10.0]]]
    worst, equal, scored, trimmed = gate.score_end(got_end, want_planned, want_trails, 6.0)
    assert trimmed == 0
    assert scored == 1
    assert equal == 1
    assert worst <= gate.BAR_IN


def test_a_model_off_by_more_than_the_bar_fails():
    got_end = [[40.2, 10.0]]  # 0.2" off — past the 0.05" bar
    want_planned = [[40.0, 10.0]]
    want_trails = [[[36.0, 10.0], [40.0, 10.0]]]
    worst, equal, scored, trimmed = gate.score_end(got_end, want_planned, want_trails, 6.0)
    assert trimmed == 0
    assert scored == 1
    assert equal == 0
    assert worst > gate.BAR_IN


def test_red_shift_parts_an_otherwise_exact_match():
    """THE RED. A model whose port endpoint lands EXACTLY on the recorded
    `planned` point must fail once every recorded endpoint is shifted 0.06" —
    proving the comparison is measuring the shifted point, not waving it
    through."""
    got_end = [[40.0, 10.0]]
    want_planned = [[40.0, 10.0]]
    want_trails = [[[36.0, 10.0], [40.0, 10.0]]]
    worst, equal, scored, _ = gate.score_end(got_end, want_planned, want_trails, 6.0,
                                             red_shift=False)
    assert equal == 1 and worst == 0.0
    worst, equal, scored, _ = gate.score_end(got_end, want_planned, want_trails, 6.0,
                                             red_shift=True)
    assert scored == 1
    assert equal == 0, "the red shift did not part an exact match"
    assert worst > gate.BAR_IN


def test_a_trail_already_over_budget_is_excused_not_scored():
    """The distance-truth trim (step.rs:477-490): a model recorded with a
    routed trail longer than the granted band was always going to move on to
    a DIFFERENT final resting point than its recorded `planned` — the port's
    `plain_move` returns that trim, so this model is excused as "trimmed"
    rather than counted as an END miss, even though its recorded `planned`
    point and the port's `end` disagree by more than the bar."""
    got_end = [[41.0, 10.0]]  # the port's own (trimmed) landing
    want_planned = [[44.0, 10.0]]  # the recorder's PRE-trim plan, 8" out
    want_trails = [[[36.0, 10.0], [44.0, 10.0]]]  # routed 8" on a 6" budget
    worst, equal, scored, trimmed = gate.score_end(got_end, want_planned, want_trails, 6.0)
    assert trimmed == 1
    assert scored == 0
    assert equal == 0
    assert worst == 0.0, "an excused model must not move the worst-gap tally"


def test_call_reach_in_reads_the_rung_line():
    c = {"rung": "reach_in=9.0000 avoid_difficult=false avoid_dangerous=true allow_contact=false"}
    assert gate.call_reach_in(c) == 9.0


def test_trail_len_in_sums_the_routed_legs():
    assert gate.trail_len_in([[0.0, 0.0], [3.0, 0.0], [3.0, 4.0]]) == 7.0
