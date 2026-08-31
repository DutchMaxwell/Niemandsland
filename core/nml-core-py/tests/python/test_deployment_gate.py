"""Synthetic 2-dump gate test: seed+lists join, per-unit classes, red knob (NML-1152 step 9).

Two dumps share ONE game seed but carry BOTH seat orders (step-7 finding) — a
gate joining records by seed alone would collapse them. The synthetic "table"
truth is the twin's own output on those inputs (the comparator machinery under
test: quantum classes, structural fails, floor skip, exit codes), with dump B's
side-1 spot shifted HALF a scan step so the within class fires — and the red
knob's full-step shift lands that unit at 1.5 steps (mismatch), so EXACT
collapses to 0 and the knob fires.
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import deployment_gate as gate  # noqa: E402

CP = {"grid_rotation_degrees": 0.0, "grid_size_inches": 3.0,
      "inches_to_meters": 0.0254, "table_size_feet": [6.0, 4.0]}
SEED = 7
BOARD_KEY = str(500000 + SEED)


def _template(lists, ambush_side2):
    """One dump's inputs only — spots/models/sections are recorded from the twin after."""
    sides = {}
    for slot in ("1", "2"):
        roster = [["u1", False, False, 0]]
        reserved = []
        if ambush_side2 and slot == "2":
            roster.append(["a1", False, True, 0])
            reserved = ["a1"]
        sides[slot] = {
            "roster": roster, "reserved": reserved, "fills": [],
            "seed_value": SEED + int(slot), "placement_order": [], "tray_models": [],
            "units": {"u1": {"name": "U1", "section": 0, "spot": [0.0, 0.0], "models": [[0.0, 0.0]],
                             "n_models": 1, "base_r_m": 0.016, "footprint": [[0.0, 0.0]],
                             "ignores_terrain": False, "vanguard_pushed": False, "facing_rad": 0.0,
                             "scout": False, "ambush": False,
                             "model_shapes": [{"is_oval": False, "w_mm": 32, "d_mm": 32, "tough": 1, "n": 1}]}},
        }
    return {"seed": SEED, "lists": lists, "sides": sides}


def _synthetic():
    """Truth-record both seat orders; B's side-1 spot sits half a scan step off the twin."""
    bank = {"walls": [], "blockers": [], "blocker_boxes": []}
    a = _template(["alpha", "beta"], ambush_side2=True)
    attempts, opener = gate.roll_off(SEED)
    _, _, finished, _ = gate.run_dump(a, [], CP, (bank["walls"], bank["blockers"], bank["blocker_boxes"]), 0)
    for slot in ("1", "2"):
        a["sides"][slot]["placement_order"] = [p["key"] for p in finished[slot]]
        for p in finished[slot]:
            u = a["sides"][slot]["units"][p["key"]]
            u["spot"] = list(p["spot"])
            u["models"] = copy.deepcopy(p["models"])
            u["section"] = p["section"]
    b = copy.deepcopy(a)
    b["lists"] = ["beta", "alpha"]
    # Half a step, OPPOSITE the red knob's direction: WITHIN in green, and the
    # red run lands it at 1.5 steps -> MISMATCH (a same-direction full-step
    # offset would cancel the knob; same-direction half-step stays within).
    b["sides"]["1"]["units"]["u1"]["spot"][0] -= gate.SCAN_STEP / 2
    extracts = {
        "pregame_pipeline.json": [a, b],
        "pregame_roll_off.json": [{"seed": SEED, "attempts": attempts, "opener": opener,
                                   "deploy_order": [opener, 3 - opener],
                                   "side_seed_values": {"1": SEED + 1, "2": SEED + 2}}],
        "pregame_deploy_spots.json": {"boards": {BOARD_KEY: {"cells": []}}, "cell_params": CP},
        "pregame_bank_v2.json": {"boards": {BOARD_KEY: bank}},
    }
    return extracts


def _run(tmp_path, capsys, extra=None):
    for name, data in _synthetic().items():
        with open(os.path.join(tmp_path, name), "w") as f:
            json.dump(data, f)
    code = gate.main(["--fixtures", str(tmp_path)] + (extra or []))
    return code, capsys.readouterr().out


def test_gate_join_classes_floor(tmp_path, capsys):
    code, out = _run(tmp_path, capsys)
    assert code == 0
    assert "corpus 2 dumps / 4 sides / 4 placed units" in out
    assert "spots 3/4 EXACT | 1 within | 0 MISMATCH" in out
    assert "models 4/4 exact; sides all-exact 3/4" in out
    assert "roll-off 2/2 OK; deploy order 2/2 OK; structure 2/2 OK" in out
    assert "floor SKIPPED (partial corpus 4/1060 units)" in out


def test_gate_red_shift(tmp_path, capsys):
    code, out = _run(tmp_path, capsys, ["--red-shift", "1"])
    assert code == 1
    assert "spots 0/4 EXACT | 3 within | 1 MISMATCH" in out
    assert "RED knob 1: exact 0 vs 0 — displacement detected, exit 1 as designed" in out
