"""Gen-0 training design step 1 (DESIGN_gen0_training_2026-09-02 SS5.1) — RED
proof for `gen0_stats.py`.

(a) A two-game, four-position synthetic fixture whose every reported number
is checked against a value worked out by hand (see the module docstring's
worksheet in the PR body for the arithmetic). Fully synthetic: no dependency
on the real (read-only) corpus.

(b) The tool must REFUSE (raise / nonzero exit), never warn, on a COPY of a
good record that is then corrupted two ways: `cands.best` out of range, and
`action` disagreeing with `cands.list[best]`. The real corpus is read-only
and is never touched by this test or the tool; both RED cases corrupt an
in-memory copy of the synthetic fixture instead.
"""
import copy
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import gen0_stats  # noqa: E402


def _cand(kind, unit, dest=None, **extra):
    c = {"kind": kind, "unit": unit}
    if dest is not None:
        c["dest"] = dest
    c.update(extra)
    return c


def _pos(unit, kind, cands, best):
    # `action` is its OWN dict, like a real JSON parse -- never the same object as
    # cands.list[best], so corrupting one cannot silently also move the other.
    return {"side": 1, "round": 1, "seq": 0, "value": 0.5, "unit": unit, "kind": kind,
            "action": copy.deepcopy(cands[best]), "intent": "",
            "cands": {"list": cands, "best": best}}


def _game1():
    p1 = _pos("p1_B", 1, [_cand(0, "p1_A"), _cand(2, "p1_A", [0, 0, 0]),
                          _cand(0, "p1_B"), _cand(1, "p1_B", [1, 0, 0])], best=3)
    p2 = _pos("p2_X", 2, [_cand(2, "p2_X", [0, 0, 0]), _cand(0, "p2_X"),
                          _cand(3, "p2_Y", [0, 0, 0], charge="p1_A")], best=0)
    return {"winner": "p1", "rounds_played": 4, "armies": {"p1": "/x/faction_a_1000.json"},
            "planner_positions": [p1, p2]}


def _game2():
    p1 = _pos("p1_Z", 0, [_cand(0, "p1_Z")], best=0)
    p2 = _pos("p2_M", 2, [_cand(1, "p2_N", [0, 0, 0]), _cand(2, "p2_N", [1, 0, 0]),
                          _cand(0, "p2_M"), _cand(2, "p2_M", [2, 0, 0]),
                          _cand(1, "p2_M", [3, 0, 0], wave="idle")], best=3)
    return {"winner": "p2", "rounds_played": 4, "armies": {"p1": "/x/faction_b_2000.json"},
            "planner_positions": [p1, p2]}


def test_two_game_fixture_matches_hand_arithmetic():
    games = [("gen0_s1_d1.json", _game1()), ("gen0_s2_d2.json", _game2())]
    s = gen0_stats.collect(games)
    assert s["games"] == 2
    assert s["positions_per_game"] == {"n": 2, "mean": 2.0, "p10": 2, "p50": 2, "p90": 2,
                                       "min": 2, "max": 2}
    mw = s["menu_width"]
    assert (mw["n"], mw["mean"], mw["p10"], mw["p50"], mw["p90"], mw["min"], mw["max"]) == (
        4, 3.25, 1, 4, 5, 1, 5)
    assert mw["hist"]["0-9"] == 4 and mw["ge32"] == 0.0 and mw["ge64"] == 0.0 and mw["eq1"] == 0.25
    assert s["menu_width_by_points"][1000]["mean"] == 3.5
    assert s["menu_width_by_points"][2000]["mean"] == 3.0
    assert s["chosen_kind_share"] == {"ADVANCE": 0.25, "RUSH": 0.5, "HOLD": 0.25}
    mk = s["menu_kind_share"]
    assert mk["HOLD"] == pytest.approx(5 / 13) and mk["RUSH"] == pytest.approx(4 / 13)
    assert mk["ADVANCE"] == pytest.approx(3 / 13) and mk["CHARGE"] == pytest.approx(1 / 13)
    assert s["best_nonzero_share"] == 0.5
    assert (s["best_idx"]["mean"], s["best_idx"]["p50"]) == (1.5, 3)
    assert (s["distinct_units"]["mean"], s["distinct_units"]["p50"]) == (1.75, 2)
    assert (s["acting_unit_block"]["mean"], s["acting_unit_block"]["max"]) == (2.0, 3)
    assert s["chosen_unit_first_share"] == 0.5
    assert s["within_unit_slot0_share"] == 0.5
    assert s["winner"] == {"p1": 1, "p2": 1}
    assert s["rounds_played"] == {4: 2}
    assert s["baselines"] == {"holdout_games": 1, "holdout_positions": 2, "slot0": 0.5,
                              "first_unit": 0.5, "own_slot0": 0.5, "majority_kind": 0.0}


def _write(tmp_path, name, game):
    f = tmp_path / name
    f.write_text(json.dumps(game))
    return f


def test_refuses_best_out_of_range(tmp_path):
    bad = copy.deepcopy(_game1())          # a COPY of a good record, never the corpus itself
    bad["planner_positions"][0]["cands"]["best"] = 99
    _write(tmp_path, "gen0_s1_d1.json", bad)
    with pytest.raises(SystemExit):
        gen0_stats.main(["--corpus", str(tmp_path), "--out", str(tmp_path / "o.json")])


def test_refuses_action_disagrees_with_menu(tmp_path):
    bad = copy.deepcopy(_game1())
    bad["planner_positions"][0]["action"]["kind"] = 0  # was 1: no longer == cands.list[best]
    _write(tmp_path, "gen0_s1_d1.json", bad)
    with pytest.raises(SystemExit):
        gen0_stats.main(["--corpus", str(tmp_path), "--out", str(tmp_path / "o.json")])
