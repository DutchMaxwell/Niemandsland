"""GATE for `deployment_gate.py`'s `interleave_order` class.

THE HOLE this guards: the class's own derivation. `expected_interleave` builds
the rulebook's cross-side order (GF v3.5.1 p.6) out of the two sides'
`placement_order`s, and the class then demands the recording match it. If that
derivation were wrong the class would either reject correct recordings or, far
worse, accept whole-side ones — the exact deviation the rung exists to catch.
So every expectation below is written out BY HAND, not computed.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import deployment_gate as dg  # noqa: E402

#: side 1: three normals then a scout; side 2: four normals then a scout —
#: each side's own drain order, main queue first (solo_controller.gd:9036-9042).
ORDERS = {"1": ["a1", "a2", "a3", "a_s"], "2": ["b1", "b2", "b3", "b4", "b_s"]}
SCOUTS = {"1": {"a_s"}, "2": {"b_s"}}


def test_the_winner_places_first_and_the_sides_alternate():
    """Winner 1: one each in turn; side 2's fourth normal lands alone once
    side 1's main queue is empty; then the scout phase, winner first."""
    assert dg.expected_interleave(ORDERS, SCOUTS, 1) == [
        (1, "a1"), (2, "b1"), (1, "a2"), (2, "b2"), (1, "a3"), (2, "b3"),
        (2, "b4"), (1, "a_s"), (2, "b_s"),
    ]


def test_the_other_roll_off_outcome_leads_with_the_other_side():
    assert dg.expected_interleave(ORDERS, SCOUTS, 2) == [
        (2, "b1"), (1, "a1"), (2, "b2"), (1, "a2"), (2, "b3"), (1, "a3"),
        (2, "b4"), (2, "b_s"), (1, "a_s"),
    ]


def test_scouts_never_interleave_with_normals():
    """B9: the scout phase starts only after BOTH armies' normals are down —
    no scout may appear before the last normal of either side."""
    seq = dg.expected_interleave(ORDERS, SCOUTS, 1)
    last_normal = max(i for i, (_, k) in enumerate(seq) if k not in SCOUTS["1"] | SCOUTS["2"])
    first_scout = min(i for i, (_, k) in enumerate(seq) if k in SCOUTS["1"] | SCOUTS["2"])
    assert first_scout > last_normal


def test_a_side_with_no_units_is_simply_skipped():
    assert dg.expected_interleave({"1": [], "2": ["b1", "b2"]}, {"1": set(), "2": set()}, 1) == [
        (2, "b1"), (2, "b2"),
    ]


def test_the_whole_side_order_is_what_the_class_must_reject():
    """The RED input, built the way a pre-#575 dump recorded it — and it must
    differ from the rulebook order, or the class could never fail."""
    dump = {"sides": {s: {"placement_order": ORDERS[s]} for s in ("1", "2")}}
    whole = dg.whole_side_sequence(dump, 1)
    assert whole == [
        (1, "a1"), (1, "a2"), (1, "a3"), (1, "a_s"),
        (2, "b1"), (2, "b2"), (2, "b3"), (2, "b4"), (2, "b_s"),
    ]
    assert whole != dg.expected_interleave(ORDERS, SCOUTS, 1)
