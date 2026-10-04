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


# A4.2: parallel source candidates. Truth per slot: A = ineligible, eligible, eligible (the third is speculative);
# B = ineligible, ineligible (stays missing); C = eligible. The serial pass plays A/0 A/1 B/0 B/1 C/0.
TRUTH = {"A": [False, True, True], "B": [False, False], "C": [True]}
SERIAL = ["A/0", "A/1", "B/0", "B/1", "C/0"]


def _unit(uid, cell):
    slot, k = uid.split("/")
    ok = TRUTH[slot][int(k)]
    return {"positions": [{"slot": slot, "k": int(k)}] if ok else [], "discarded": [] if ok else [{"slot": slot, "k": int(k)}],
            "missing": [] if ok else [slot], "logs": [{"slot": slot, "k": int(k), "eligible": ok}],
            "timing": [{"cell": cell, "source": uid, "seq": i} for i in range(5)],
            "transitions": [{"cell": cell, "source": uid, "seq": i} for i in range(4)],
            "headers": {uid: {"knobs": {}}}, "net": {1: {"calls": 1, "leaves": 2}, "model_sha256": "m"}, "slot": slot, "k": int(k)}


def _fake_pool(ran):
    def run_clusters(units, workers, init, work, init_args=(), key="", ordered=False):
        assert ordered and work is ls._cand_work
        ran.append(list(units))
        return [{"id": uid, "result": _unit(uid, "c1")} for uid in units]
    return run_clusters


def test_serial_keep_picks_exactly_the_serial_pass_and_names_missing_and_undecided_slots():
    slots = {s: list(range(len(v))) for s, v in TRUTH.items()}
    seen = {(s, k): ok for s, v in TRUTH.items() for k, ok in enumerate(v)}
    assert ls.serial_keep(slots, seen, cap=20) == ([("A", 0), ("A", 1), ("B", 0), ("B", 1), ("C", 0)], ["B"], [])
    assert ls.serial_keep(slots, {("A", 0): False}, cap=20)[2] == ["A", "B", "C"]
    assert ls.serial_keep(slots, seen, cap=1)[1] == ["A", "B"]          # cap 1: A's first candidate is its last


def test_parallel_candidates_write_exactly_the_serial_output_and_drop_speculative_ones(monkeypatch):
    import lab2_pool
    slots = {s: [{"cell": "c1", "slot": s, "candidate": str(k)} for k in range(len(v))] for s, v in TRUTH.items()}
    serial_t, serial_x = ls.TimingSet(), ls.TransitionSet()
    want = ls.merge_slots(SERIAL, {u: _unit(u, "c1") for u in SERIAL}, serial_t, serial_x)
    for width in (1, 2, 3):
        ran = []
        monkeypatch.setattr(lab2_pool, "run_clusters", _fake_pool(ran))
        t, x = ls.TimingSet(), ls.TransitionSet()
        got = ls.source_parallel(slots, 4, width, {"cap": 20}, t, x)
        assert got["missing"] == ["B"] and {k: got[k] for k in ("positions", "discarded", "logs", "net")} == \
            {k: want[k] for k in ("positions", "discarded", "logs", "net")}, width
        assert (t.states, x.records, x.headers) == (serial_t.states, serial_x.records, serial_x.headers), width
        assert ran[0][:3] == ["A/0", "B/0", "C/0"]                       # candidate 0 of every slot first
    assert "A/2" in ran[0] and "A/2" not in x.headers and got["net"][1]["calls"] == 5   # width 3 played A/2, unseen
