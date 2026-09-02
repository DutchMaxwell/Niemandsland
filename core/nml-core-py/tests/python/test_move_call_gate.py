"""GATE S4 — the PLAIN MOVE scoring, on a synthetic fixture.

`tools/move_call_gate.py` runs over the recorded arena corpus, which lives
outside the repo (see that tool's docstring). This file holds the scoring
arithmetic itself to ONE hand-built recorded call and ONE hand-built port
answer, so the END bar (0.05") and the RED (`--red-shift` moves every
recorded endpoint 0.06") are pinned without a corpus on hand.

S12 adds the PER-MODEL fold's own strict-share semantics (a unit-level
average would pass where the strict per-model fold must not) and the
`GAP_BUCKETS`/`SIZE_GROUPS` histogram helpers, pinned the same way.
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


def test_per_model_fold_fails_on_one_stray_model_even_though_the_centroid_would_pass():
    """S12 PER-MODEL's whole point: two of three models land dead-on and the
    third half an inch out. The mean per-model offset (a centroid's-eye view)
    is a sixth of an inch — inside even a loose 0.5" tolerance — but the
    STRICT per-model fold this line reports (every model, not the average)
    must count this act as a miss."""
    got_end = [[40.0, 10.0], [42.0, 10.0], [44.5, 10.0]]
    want_planned = [[40.0, 10.0], [42.0, 10.0], [44.0, 10.0]]
    want_trails = [[[40.0, 10.0], p] for p in want_planned]  # 0", 2", 4" legs — none over budget
    worst, equal, scored, trimmed = gate.score_end(got_end, want_planned, want_trails, 6.0)
    assert trimmed == 0
    assert scored == 3
    assert equal == 2, "two of the three models land inside the bar"
    assert equal != scored, "PER-MODEL's strict fold must fail: one model missed"
    mean_off = sum(abs(g[0] - w[0]) for g, w in zip(got_end, want_planned)) / 3
    assert mean_off < 0.5, "a centroid-style average would have passed a loose tolerance"
    assert worst > gate.BAR_IN


def test_red_shift_parts_the_per_model_fold_too():
    """The RED proof, stated for PER-MODEL: shifting every recorded endpoint
    0.06" must move a unit that started fully within the bar to fully
    outside it, on ALL its models — PER-MODEL reads the same `score_end`
    output as END, so it cannot survive the shift either."""
    got_end = [[40.0, 10.0], [42.0, 10.0]]
    want_planned = [[40.0, 10.0], [42.0, 10.0]]
    want_trails = [[[36.0, 10.0], p] for p in want_planned]
    worst, equal, scored, _ = gate.score_end(got_end, want_planned, want_trails, 6.0,
                                             red_shift=False)
    assert equal == scored == 2, "both models start inside the bar"
    worst, equal, scored, _ = gate.score_end(got_end, want_planned, want_trails, 6.0,
                                             red_shift=True)
    assert equal == 0, "the red shift must part every model, not just one"
    assert equal != scored


def test_gap_bucket_orders_the_worst_model_gap():
    assert gate.gap_bucket(0.0) == "le_bar"
    assert gate.gap_bucket(gate.BAR_IN) == "le_bar"
    assert gate.gap_bucket(0.2) == "le_0_5in"
    assert gate.gap_bucket(0.5) == "le_0_5in"
    assert gate.gap_bucket(1.5) == "le_2in"
    assert gate.gap_bucket(5.0) == "le_6in"
    assert gate.gap_bucket(6.01) == "gt_6in"


def test_size_group_buckets_by_model_count():
    assert gate.size_group(1) == "1"
    assert gate.size_group(2) == "2-5"
    assert gate.size_group(5) == "2-5"
    assert gate.size_group(6) == "6+"


def test_call_reach_in_reads_the_rung_line():
    c = {"rung": "reach_in=9.0000 avoid_difficult=false avoid_dangerous=true allow_contact=false"}
    assert gate.call_reach_in(c) == 9.0


def test_trail_len_in_sums_the_routed_legs():
    assert gate.trail_len_in([[0.0, 0.0], [3.0, 0.0], [3.0, 4.0]]) == 7.0
