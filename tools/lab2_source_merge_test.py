#!/usr/bin/env python3
"""lab2_source.merge_slots on synthetic per-slot results (no data, no nml_core): manifest order, the first states per
cell exactly as one sequential pass keeps them, headers united, net calls added. Run: python3 -m pytest -q tools/lab2_source_merge_test.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lab2_source as ls  # noqa: E402


def _res(slot, cell, n_timing, n_trans, calls):
    return {"positions": [{"slot": slot}], "discarded": [{"slot": slot, "candidate": "0"}], "missing": [],
            "logs": [{"slot": slot, "eligible": True}],
            "timing": [{"cell": cell, "source": slot, "seq": i} for i in range(n_timing)],
            "transitions": [{"cell": cell, "source": slot, "seq": i} for i in range(n_trans)],
            "headers": {slot + ":0": {"knobs": {}}}, "net": {1: {"calls": calls, "leaves": 2 * calls}, "model_sha256": "m"}}


def test_merge_keeps_manifest_order_and_the_first_states_per_cell():
    results = {"c1_k2": _res("c1_k2", "c1", 12, 9, 5), "c1_k1": _res("c1_k1", "c1", 7, 4, 3), "c5_k1": _res("c5_k1", "c5", 12, 8, 1)}
    timing, trans = ls.TimingSet(), ls.TransitionSet()
    m = ls.merge_slots(["c1_k1", "c1_k2", "c5_k1"], results, timing, trans)   # the manifest order, not the dict's
    assert [p["slot"] for p in m["positions"]] == ["c1_k1", "c1_k2", "c5_k1"]
    c1 = [(s["source"], s["seq"]) for s in timing.states if s["cell"] == "c1"]
    assert c1 == [("c1_k1", i) for i in range(7)] + [("c1_k2", i) for i in range(5)]   # 12: all of k1, then k2's first 5
    assert [r["source"] for r in trans.records if r["cell"] == "c1"] == ["c1_k1"] * 4 + ["c1_k2"] * 5   # quota 9 in c1
    assert sum(1 for r in trans.records if r["cell"] == "c5") == 8 and timing.short({"c1", "c5"}) == {}
    assert set(trans.headers) == {"c1_k1:0", "c1_k2:0", "c5_k1:0"}
    assert m["net"][1] == {"calls": 9, "leaves": 18} and m["net"]["model_sha256"] == "m"
