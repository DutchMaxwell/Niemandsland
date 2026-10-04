#!/usr/bin/env python3
"""Tests for tools/lab2_report.py (pilot report part 1). Run: python3 -m pytest -q tools/lab2_report_test.py"""
import importlib.util
import math
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
_SPEC = importlib.util.spec_from_file_location("lab2_report", os.path.join(_HERE, "lab2_report.py"))
rep = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_report"] = rep
_SPEC.loader.exec_module(rep)

CELLS = ["c%d" % i for i in range(1, 13)]
Z = 2.5758293035489004 + 0.8416212335729143      # Phi^-1(.995) + Phi^-1(.80), written out by hand
F = 12 / 6.303801


def row(part, cell, src, arm, rep, y, valid=True, **kw):
    r = {"part": part, "cell": cell, "source": src, "arm": arm, "replicate": rep, "y": y, "valid": valid,
         "rss_hwm_mib": 100.0, "decisions": [{"allocated_us": 10, "elapsed_us": 9, "overshoot_us": 0}]}
    r.update(kw)
    return r


def a_rows(gain=lambda cell, k: 0.5 * (k - 1)):
    """24 clusters (2 per cell) x 8 replicates x I/L/T; T gains `gain` over I, L gains half of it."""
    rows = []
    for c in CELLS:
        for k in (1, 2):
            g = gain(c, k)
            for r in range(8):
                rows += [row("A", c, "%s_k%d" % (c, k), "I", r, 0.0),
                         row("A", c, "%s_k%d" % (c, k), "T", r, 1.0 if r < 8 * g else 0.0),
                         row("A", c, "%s_k%d" % (c, k), "L", r, 1.0 if r < 4 * g else 0.0)]
    return rows


def b_rows(l_of=lambda c, k: 0.5 + 0.25 * (k - 1), c_of=lambda c, k: 0.5):
    """24 blocks x 4 games (2 dice x 2 seats) x I/L/C; the candidate score of a game is the arm's block level."""
    rows = []
    for c in CELLS:
        for k in (1, 2):
            for arm, lv in (("I", 0.5), ("L", l_of(c, k)), ("C", c_of(c, k))):
                rows += [row("B", c, "%s_k%d" % (c, k), arm, "d%dc%d" % (d, s), lv) for d in (0, 1) for s in (1, 2)]
    return rows


def test_a_mde_matches_a_hand_computation():
    out = rep.part1(a_rows() + b_rows(), True)
    v = 12 * (1 / 12) ** 2 * 0.125 / 40            # a_T = 0 and 0.5 per cell: s^2 = 0.125, n_c = 40
    assert out["mde"]["A_T"] == pytest.approx(100 * Z * math.sqrt(F * v), rel=1e-9)
    assert out["mde"]["A_L"] == pytest.approx(100 * Z * math.sqrt(F * v / 4), rel=1e-9)   # L gain is half T's
    assert out["flags"]["mde_A_T"] is False and out["verdict"] == "FAIL"          # 7.6 points > the bar of 3
    quiet = rep.part1(a_rows(lambda c, k: 0.125 * (k - 1)) + b_rows(lambda c, k: 0.5 + 0.01 * (k - 1)), True)
    assert quiet["flags"]["mde_A_T"] and quiet["flags"]["mde_B_LI"] and quiet["verdict"] == "PASS"


def test_b_uses_105_blocks_in_c1_and_c2_and_104_elsewhere():
    out = rep.part1(a_rows() + b_rows(), True)
    s2 = 0.5 * (0.25) ** 2                         # b_LI = 0, 0.25 -> variance 0.03125 in every cell
    v = sum((1 / 12) ** 2 * s2 / (105 if c in ("c1", "c2") else 104) for c in CELLS)
    assert out["mde"]["B_LI"] == pytest.approx(100 * Z * math.sqrt(F * v), rel=1e-9)
    assert rep.n_c("B", "c2") == 105 and rep.n_c("B", "c3") == 104 and rep.n_c("A", "c1") == 40


def test_one_missing_row_is_a_pilot_stop_and_withholds_every_flag():
    rows = a_rows() + b_rows()
    rows.pop(5)
    out = rep.part1(rows, True)
    assert out["verdict"] == "PILOT_STOP" and not any(out["flags"].values()) and out["problems"]


def test_a_failed_validation_withholds_every_flag():
    out = rep.part1(a_rows() + b_rows(), False)
    assert out["verdict"] == "PILOT_STOP" and not any(out["flags"].values())


def test_zero_variance_everywhere_needs_the_red_sensitivity_flag():
    rows = a_rows(lambda c, k: 0.0) + b_rows(lambda c, k: 0.5)
    assert rep.part1(rows, True)["flags"]["zero_variance_shows_sensitivity"] is False
    assert rep.part1(rows, True, red_sensitive=True)["flags"]["zero_variance_shows_sensitivity"] is True


def test_rss_and_deadline_gates():
    big = a_rows() + b_rows()
    big[0]["rss_hwm_mib"] = 600.0
    assert rep.part1(big, True, workers=4)["flags"]["rss"] is False
    late = a_rows() + b_rows()
    late[0]["decisions"] = [{"allocated_us": 10, "elapsed_us": float("nan"), "overshoot_us": 0}]
    assert rep.part1(late, True)["flags"]["deadlines"] is False


def test_freeze_carries_p1_p2_p3_and_the_raw_gains():
    rows = a_rows() + b_rows()
    fz = rep.freeze(rep.part1(rows, True), rows, {"workers": 3}, {"c1": {"B_us": 8000}})
    assert fz["p1"] == {"workers": 3} and fz["p2"] == {"c1": 8000} and fz["p3"]["F"] == F
    assert fz["raw_gains"]["A_T"]["c1"]["c1_k2"] == 0.5


def test_decision_times_split_preselection_and_search_per_arm():
    """Stage-0 amendment A3: preselection + search = total per arm (ms, median / nearest-rank p90); an unstamped
    decision reports its total only, a non-finite one is left out."""
    rows = [{"decisions": [{"arm": "L", "elapsed_us": 3000, "preselect_us": 1000},
                           {"arm": "L", "elapsed_us": 5000, "preselect_us": 2000},
                           {"arm": "I", "elapsed_us": 1500, "preselect_us": None},
                           {"arm": "I", "elapsed_us": float("nan"), "preselect_us": None}]}]
    t = rep.decision_times(rows)
    assert t["L"] == {"decisions": 2, "total_ms": {"median": 4.0, "p90": 5.0},
                      "preselect_ms": {"median": 1.5, "p90": 2.0}, "search_ms": {"median": 2.5, "p90": 3.0}}
    assert t["I"] == {"decisions": 1, "total_ms": {"median": 1.5, "p90": 1.5}, "preselect_ms": None, "search_ms": None}
