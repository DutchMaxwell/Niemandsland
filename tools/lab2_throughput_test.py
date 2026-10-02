#!/usr/bin/env python3
"""Tests for tools/lab2_throughput.py (pilot report part 2). Run: python3 -m pytest -q tools/lab2_throughput_test.py"""
import importlib.util
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
_SPEC = importlib.util.spec_from_file_location("lab2_throughput", os.path.join(_HERE, "lab2_throughput.py"))
tp = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_throughput"] = tp
_SPEC.loader.exec_module(tp)

CELLS = ["c%d" % i for i in range(1, 13)]


def test_least_loaded_schedule_matches_a_hand_result():
    # 5,3,3,2 on two workers: [5,0] -> [5,3] -> [5,6] -> [7,6]; the tie at 0/0 goes to worker 0
    assert tp.schedule([5, 3, 3, 2], 2) == ([7, 6], 7)
    assert tp.schedule([4, 4], 2) == ([4, 4], 4)


def test_p6_is_laptop_at_exactly_12_hours_and_fleet_just_above():
    assert tp.venue(12.0) == "laptop" and tp.venue(12.01) == "fleet"


def _rows():
    """Two D clusters per cell and arm; the larger cluster takes 10 s for I, 20 s for L (so units 20 s and 40 s)."""
    out = []
    for part, arms in (("A", ("I", "L")), ("B", ("L", "C"))):
        for c in CELLS:
            for k, scale in ((1, 1.0), (2, 0.5)):
                for arm in arms:
                    out.append({"part": part, "cell": c, "source": "%s_k%d" % (c, k), "arm": arm,
                                "wall_s": scale * (10.0 if arm in ("I", "C") else 20.0)})
    return out


def _logs(y=1.0):
    return [{"cell": c, "mover": m, "eligible": i < y * 10, "wall_s": 2.0} for c in CELLS for m in (1, 2) for i in range(10)]


def test_cluster_cost_is_twice_the_larger_d_cluster_over_the_arms():
    assert tp.unit_costs(_rows())[("A", "c3", "L")] == 40.0
    assert tp.cluster_cost(tp.unit_costs(_rows()), "A", "c3", ("I", "L")) == 60.0


def test_zero_source_yield_fails_the_pilot():
    out = tp.report(_rows(), _logs(0.0), 0.0, {"A": ("I", "L"), "B": ("L", "C")})
    assert out["verdict"] == "PILOT_STOP" and any("zero yield" in p for p in out["problems"])


def test_a_cheap_projection_stays_on_the_laptop_and_a_huge_one_with_no_allocation_is_cost_stop():
    arms = {"A": ("I", "L"), "B": ("L", "C")}
    cheap = tp.report(_rows(), _logs(), 100.0, arms)
    assert cheap["venue"] == "laptop" and cheap["laptop_hours"] < 12
    huge = tp.report([dict(r, wall_s=r["wall_s"] * 400) for r in _rows()], _logs(), 100.0, arms)
    assert huge["venue"] == "fleet" and huge["fleet"] is None and huge["verdict"] == "COST_STOP"


def test_fleet_choice_is_fewest_hours_then_fewest_boxes_within_40_started_box_hours():
    # 100 clusters of 1 h: 1 box (4 workers) 25 h, 2 boxes 13 h, 3 boxes 9 h, 4 boxes 7 h (27 / 28 started box-hours)
    best = tp.fleet_choice([3600.0] * 100, 0.0)
    assert best["boxes"] == 4 and best["started_box_hours"] == 28 and best["eur"] == pytest.approx(28 * 0.2478)
    assert tp.fleet_choice([3600.0] * 100, 0.0, cap=20) is None


def test_main_writes_the_report(tmp_path):
    import json
    d = tmp_path / "rows"
    d.mkdir()
    for i, r in enumerate(_rows()):
        json.dump(r, open(str(d / ("%d.json" % i)), "w"))
    json.dump(_logs(), open(str(tmp_path / "logs.json"), "w"))
    out = tmp_path / "out.json"
    rc = tp.main(["--rows", str(d), "--source-logs", str(tmp_path / "logs.json"), "--overhead-s", "100",
                  "--arms", '{"A": ["I", "L"], "B": ["L", "C"]}', "--out", str(out)])
    assert rc == 0 and json.load(open(str(out)))["venue"] == "laptop"
