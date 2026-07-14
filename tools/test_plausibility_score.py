#!/usr/bin/env python3
"""Fixture-based tests for tools/plausibility_score.py.

The scorecard is only trustworthy if its arithmetic is pinned. These tests
build tiny synthetic artifact sets (no game engine) and assert the exact
sub-scores, the idle-detection rules, and the headline weighting.

Run:  python3 -m pytest tools/test_plausibility_score.py
"""

import importlib.util
import json
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "plausibility_score", os.path.join(_HERE, "plausibility_score.py")
)
ps = importlib.util.module_from_spec(_SPEC)
sys.modules["plausibility_score"] = ps
_SPEC.loader.exec_module(ps)


# ---------------------------------------------------------------------------
# Fixture builder
# ---------------------------------------------------------------------------
def write_game(tmp_path, decisions=None, result=None, battlelog=None,
               army1=None, army2=None):
    d = tmp_path
    if decisions is not None:
        (d / "decisions.json").write_text(json.dumps(decisions))
    if result is not None:
        (d / "result.json").write_text(json.dumps(result))
    if battlelog is not None:
        (d / "battlelog.txt").write_text(battlelog)
    if army1 is not None:
        (d / "army_p1.json").write_text(json.dumps(army1))
    if army2 is not None:
        (d / "army_p2.json").write_text(json.dumps(army2))
    return str(d)


def army(units):
    return {"name": "T", "units": units}


def unit(name, cost, ranges, size=1):
    return {"name": name, "cost": cost, "size": size,
            "weapons": [{"name": "w", "range": r, "attacks": 1} for r in ranges]}


# ---------------------------------------------------------------------------
# battlelog parsing
# ---------------------------------------------------------------------------
def test_parse_battlelog_basics():
    text = (
        'R1  Alpha fires Gun at Bravo — 2 hits\n'
        'R1  Note: "Aircraft" is not automated in solo — apply it manually\n'
        'R1  Note: "Aircraft" is not automated in solo — apply it manually\n'
        'R2  Charlie charges\n'
        'R2  Bravo loses a model (2/3)\n'
        'R2  Bravo takes 3 wounds (1/3)\n'
        'R3  Delta destroyed\n'
        'R3  Echo casts Zap at Bravo\n'
        'R3  Echo casts Zap at Bravo — needs 4+ (1 token)\n'
    )
    bl = ps.parse_battlelog(text)
    assert bl["fires"]["Alpha"] == 1
    assert "Alpha" in bl["shot_any"]
    assert bl["charges"]["Charlie"] == 1
    assert bl["casts"]["Echo"] == 1           # declaration counted once, not the "needs" line
    assert bl["models_lost"]["Bravo"] == 1
    assert bl["wounds_taken"]["Bravo"] == 3
    assert "Delta" in bl["destroyed"]
    assert "Bravo" in bl["damaged"] and "Delta" in bl["damaged"]
    assert bl["not_automated"] == ["Aircraft"]  # de-duplicated


# ---------------------------------------------------------------------------
# M1 idle detection  — the core regression: intent != impact
# ---------------------------------------------------------------------------
def test_m1_mover_with_only_intent_is_idle(tmp_path):
    """A unit that advances with shoot_after_advance=True but never resolves a
    shot in the battlelog is IDLE (the 295pt-biker bug)."""
    decisions = [
        {"kind": "action", "round": 1, "side": 1, "unit": "Biker", "chosen": "advances",
         "data": {"shoot_after_advance": True}},
        {"kind": "move", "round": 1, "side": 1, "unit": "Biker",
         "data": {"achieved_in": 8.0, "budget_in": 8.0}},
        {"kind": "action", "round": 1, "side": 2, "unit": "Gunner", "chosen": "advances",
         "data": {"shoot_after_advance": True}},
    ]
    battlelog = "R1  Gunner fires Rifle at Biker — 1 hits\n"
    g = ps.load_game(write_game(
        tmp_path, decisions=decisions, battlelog=battlelog,
        army1=army([unit("Biker", 295, [24])]),
        army2=army([unit("Gunner", 100, [24])]),
    ))
    card = ps.score_game(g)
    m1 = card["metrics"]["no_idle"]
    idle = {o["unit"] for o in m1["idle_offenders"]}
    assert idle == {"Biker"}            # Biker only intended to shoot -> idle
    assert m1["engaged_units"] == 1     # Gunner actually fired
    assert m1["score"] == 50.0          # 1 of 2 activated units engaged


def test_m1_impact_channels(tmp_path):
    """Melee (charge), cast, and holding an objective each count as impact."""
    decisions = [
        {"kind": "action", "round": 1, "side": 1, "unit": "Charger", "chosen": "charges", "data": {}},
        {"kind": "cast", "round": 1, "side": 1, "unit": "Wizard", "chosen": "Zap", "data": {}},
        {"kind": "seize_check", "round": 1, "side": 1, "unit": "Holder", "chosen": "in seize range",
         "data": {"in_seize_range": True, "obj_gap_after_in": 0.5, "toward_objective": True}},
        {"kind": "action", "round": 1, "side": 2, "unit": "Loafer", "chosen": "rushes", "data": {}},
        {"kind": "seize_check", "round": 1, "side": 2, "unit": "Loafer", "chosen": "short of marker",
         "data": {"in_seize_range": False, "obj_gap_after_in": 20.0, "toward_objective": False}},
    ]
    g = ps.load_game(write_game(
        tmp_path, decisions=decisions, battlelog="",
        army1=army([unit("Charger", 100, [0]), unit("Wizard", 100, [18]), unit("Holder", 100, [12])]),
        army2=army([unit("Loafer", 100, [0])]),
    ))
    m1 = ps.score_game(g)["metrics"]["no_idle"]
    assert m1["engaged_units"] == 3
    assert {o["unit"] for o in m1["idle_offenders"]} == {"Loafer"}


def test_m1_joined_hero_excluded(tmp_path):
    """A roster unit that never activates is joined/reserve, not idle."""
    decisions = [
        {"kind": "action", "round": 1, "side": 1, "unit": "Leader", "chosen": "charges", "data": {}},
    ]
    g = ps.load_game(write_game(
        tmp_path, decisions=decisions, battlelog="R1  Leader charges\n",
        army1=army([unit("Leader", 100, [0]), unit("Ghost", 65, [6])]),
        army2=army([unit("Foe", 100, [0])]),
    ))
    m1 = ps.score_game(g)["metrics"]["no_idle"]
    # Ghost never activated -> not in denominator, listed as joined/reserve.
    assert m1["activated_units"] == 1
    assert any("Ghost" in s for s in m1["no_independent_activation"])
    assert m1["idle_units"] == 0


# ---------------------------------------------------------------------------
# M2 movement commitment — boxed vs open sub-inch
# ---------------------------------------------------------------------------
def test_m2_open_subinch_penalised_boxed_excused():
    decisions = [
        # committed full move
        {"kind": "move", "round": 1, "unit": "A", "why": "direct",
         "data": {"achieved_in": 12.0, "budget_in": 12.0}},
        # sub-inch but terrain-boxed -> excused, not an open dribble
        {"kind": "move", "round": 1, "unit": "B", "why": "around difficult",
         "data": {"achieved_in": 0.2, "budget_in": 12.0}},
        # sub-inch in the open ('direct') -> flagged + penalised
        {"kind": "move", "round": 1, "unit": "C", "why": "direct",
         "data": {"achieved_in": 0.5, "budget_in": 6.0}},
    ]
    m2 = ps.m2_move_commitment(decisions)
    assert m2["subinch_boxed_ct"] == 1
    assert len(m2["subinch_open"]) == 1 and "C" in m2["subinch_open"][0]
    # committed moves = 1 of 3 -> 33.33, minus 12 for the one open dribble.
    assert m2["committed_moves"] == 1
    assert m2["score"] == pytest.approx(100.0 / 3 - 12.0, abs=0.1)


def test_median_helper():
    assert ps._median([]) is None
    assert ps._median([5]) == 5
    assert ps._median([1, 3]) == 2.0
    assert ps._median([1, 2, 3]) == 2


# ---------------------------------------------------------------------------
# M3 objective urgency — only the final round, only reachable units
# ---------------------------------------------------------------------------
def test_m3_final_round_reachable_only():
    decisions = [
        # round 1 near a marker but ignored -> NOT counted (not final round)
        {"kind": "seize_check", "round": 1, "unit": "Early", "chosen": "short of marker",
         "data": {"obj_gap_after_in": 2.0, "toward_objective": False}},
        # final round, reachable, pushed -> answered
        {"kind": "seize_check", "round": 3, "unit": "Good", "chosen": "in seize range",
         "data": {"obj_gap_after_in": 1.0, "in_seize_range": True, "toward_objective": True}},
        # final round, reachable, ignored -> offender
        {"kind": "seize_check", "round": 3, "unit": "Bad", "chosen": "short of marker",
         "data": {"obj_gap_after_in": 4.0, "toward_objective": False}},
        # final round but too far -> not relevant
        {"kind": "seize_check", "round": 3, "unit": "Far", "chosen": "short of marker",
         "data": {"obj_gap_after_in": 25.0, "toward_objective": False}},
    ]
    meta = {"rounds_played": 3, "objectives": {"p1": 1, "p2": 0, "neutral": 2}}
    m3 = ps.m3_objective_urgency(decisions, meta)
    assert m3["final_round"] == 3
    assert m3["reachable_units"] == 2
    assert m3["answered_urgency"] == 1
    assert m3["score"] == 50.0
    assert [o["unit"] for o in m3["ignored_reachable_marker"]] == ["Bad"]
    assert m3["neutral_markers_at_end"] == 2


# ---------------------------------------------------------------------------
# M4 firepower / wasted points
# ---------------------------------------------------------------------------
def test_m4_wasted_points_and_fire_fraction(tmp_path):
    decisions = [
        {"kind": "action", "round": 1, "side": 1, "unit": "Shooter", "chosen": "advances", "data": {}},
        {"kind": "action", "round": 1, "side": 1, "unit": "Idle", "chosen": "rushes", "data": {}},
        {"kind": "action", "round": 1, "side": 2, "unit": "Melee", "chosen": "charges", "data": {}},
    ]
    battlelog = "R1  Shooter fires Gun at Melee — 1 hits\nR1  Melee charges\n"
    g = ps.load_game(write_game(
        tmp_path, decisions=decisions, battlelog=battlelog,
        army1=army([unit("Shooter", 200, [24]), unit("Idle", 300, [24])]),
        army2=army([unit("Melee", 150, [0])]),
    ))
    m1 = ps.score_game(g)["metrics"]["no_idle"]
    m4 = ps.score_game(g)["metrics"]["firepower"]
    # two ranged units (Shooter, Idle); only Shooter fired -> 50%
    assert m4["ranged_units"] == 2
    assert m4["ranged_units_that_fired"] == 1
    assert m4["ranged_fired_pct"] == 50.0
    # Idle produced nothing -> 300 of (200+300+150)=650 wasted
    assert m4["wasted_points"] == 300
    assert m4["total_points_activated"] == 650
    assert m1["idle_units"] == 1


# ---------------------------------------------------------------------------
# M5 focus / M6 decisiveness
# ---------------------------------------------------------------------------
def test_m5_focus_finished_vs_dribbled():
    battlelog = (
        "R1  X loses a model (1/2)\n"   # X damaged, survives
        "R1  Y destroyed\n"             # Y finished
        "R1  Y takes 4 wounds (0/1)\n"
    )
    bl = ps.parse_battlelog(battlelog)
    m5 = ps.m5_focus([], bl)
    assert m5["enemy_units_damaged"] == 2
    assert m5["enemy_units_finished"] == 1
    assert m5["damaged_not_finished"] == ["X"]
    assert m5["score"] == 50.0          # 1 of 2 left alive -> 50


def test_m6_decisiveness_marker_share():
    meta = {"objectives": {"p1": 2, "p2": 1, "neutral": 1}, "winner": "p1",
            "survivors": {"p1": {"units": 3}}}
    decisions = [
        {"kind": "seize", "round": 3, "unit": "objective 1", "data": {"index": 0, "owner": 1}},
        {"kind": "seize", "round": 4, "unit": "objective 2", "data": {"index": 1, "owner": 2}},
    ]
    bl = {"not_automated": ["Aircraft"]}
    m6 = ps.m6_decisiveness(meta, decisions, bl)
    assert m6["markers_controlled_at_end"] == 3
    assert m6["markers_total"] == 4
    assert m6["score"] == 75.0
    assert m6["seize_events"] == 2
    assert m6["distinct_objectives_seized"] == 2
    assert m6["not_automated_rules"] == ["Aircraft"]


# ---------------------------------------------------------------------------
# Headline weighting + renormalisation
# ---------------------------------------------------------------------------
def test_headline_renormalises_over_available_metrics(tmp_path):
    """With only decisions (no result/battlelog/armies), the headline must be a
    correctly renormalised mean over the metrics that could be computed."""
    decisions = [
        {"kind": "move", "round": 1, "unit": "A", "why": "direct",
         "data": {"achieved_in": 6.0, "budget_in": 6.0}},
        {"kind": "seize_check", "round": 1, "unit": "A", "chosen": "in seize range",
         "data": {"obj_gap_after_in": 1.0, "in_seize_range": True, "toward_objective": True}},
    ]
    g = ps.load_game(write_game(tmp_path, decisions=decisions))
    card = ps.score_game(g)
    used = card["weights_used"]
    # move_commitment + objective_urgency computable; no_idle also (from decisions).
    assert "move_commitment" in used and "objective_urgency" in used
    # headline == weighted mean over exactly the used metrics.
    num = sum(used[k] * card["metrics"][k]["score"] for k in used)
    assert card["headline_plausibility"] == pytest.approx(round(num / sum(used.values()), 1), abs=0.05)


def test_missing_everything_is_null_not_crash(tmp_path):
    g = ps.load_game(str(tmp_path))       # empty directory
    card = ps.score_game(g)
    assert card["headline_plausibility"] is None
    # a report can still be rendered without throwing
    assert isinstance(ps.format_report(card), str)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
