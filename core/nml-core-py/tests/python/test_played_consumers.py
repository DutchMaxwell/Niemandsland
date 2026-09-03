"""PR #643 follow-up — the cands.best reads that MEAN the played act.
`best` is the HAND argmax; `played` (PR #643) names row["action"], they part
company under a re-rank (PR #627). Pinned on synthetic rows where played !=
best; the old Gen-0 shape must behave exactly as before. Pure sites run
anywhere; stats_row needs the compiled core, skips without a .forge/site build."""
from __future__ import annotations

import copy
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))

import gen0_stats  # noqa: E402
import narrator_render as nr  # noqa: E402

REC = {"seed": 1, "dice_seed": 2, "dice_tally": {}}
NM = {"played_tgt": "played_tgt", "best_tgt": "best_tgt"}
MENU = [{"kind": 0, "unit": "p1_0", "shoot": "best_tgt"},
        {"kind": 0, "unit": "p1_0", "shoot": "played_tgt"}]
STATS_MENU = [{"kind": 0, "unit": "p1_0"}, {"kind": 0, "unit": "p1_0", "shoot": "p2_0"}]
ROLLS = [{"kind": "attack", "count": 1, "target": 4, "faces": [5], "owner": "p1_0"}]


def _dice_act(cands):
    return {"row": {"round": 1, "seq": 0, "side": 1, "unit": "p1_0", "kind": 0, "cands": cands},
            "menu": cands["list"], "rep": {"rolls": ROLLS, "log": [], "unported": []}}


def _pos(best, played=None, action_idx=0):
    menu = [{"kind": 2, "unit": "p1_0", "dest": [0, 0, 0]}, {"kind": 0, "unit": "p1_0"}]
    cands = {"list": menu, "best": best}
    if played is not None:
        cands["played"] = played
    return {"side": 1, "round": 1, "seq": 0, "value": 0.5, "unit": "p1_0", "kind": 2,
            "action": copy.deepcopy(menu[action_idx]), "intent": "", "cands": cands}


def _game(pos):
    return {"winner": "p1", "rounds_played": 1, "armies": {"p1": "/x/faction_1000.json"}, "planner_positions": [pos]}


def test_dice_trail_names_the_played_target():
    out = "\n".join(nr.dice_md(REC, [_dice_act({"list": MENU, "best": 0, "played": 1})], NM))
    assert "played_tgt" in out and "best_tgt" not in out


def test_dice_trail_without_played_still_names_best():
    out = "\n".join(nr.dice_md(REC, [_dice_act({"list": MENU, "best": 0})], NM))
    assert "best_tgt" in out and "played_tgt" not in out


def test_gen0_stats_and_validation_read_the_played_pick():
    pos = _pos(0, played=1, action_idx=1)
    s = gen0_stats.collect([("gen0_s1_d1.json", _game(pos))])
    assert s["best_idx"]["mean"] == 1 and s["best_nonzero_share"] == 1.0
    assert s["baselines"]["slot0"] == 0.0
    gen0_stats.validate("t", [pos])


def test_gen0_shape_without_played_is_byte_identical_to_before():
    pos = _pos(0)
    s = gen0_stats.collect([("gen0_s1_d1.json", _game(pos))])
    assert s["best_idx"]["mean"] == 0.0 and s["best_nonzero_share"] == 0.0
    assert s["baselines"]["slot0"] == 1.0
    gen0_stats.validate("t", [pos])


def test_a_bad_index_is_refused_whatever_its_key():
    for pos in (_pos(99), _pos(0, played=99)):
        with pytest.raises(ValueError):
            gen0_stats.validate("t", [pos])


def test_narrator_stats_key_off_the_played_act():
    pytest.importorskip("nml_core", reason="no .forge/site build on this box")
    import game_narrator as gn
    units = {"p1_0": {"alive": 2, "wounds": [1, 1], "positions": [[0.0, 0.0, 0.0]]},
             "p2_0": {"alive": 2, "wounds": [1, 1], "positions": [[1.0, 0.0, 0.0]]}}
    act = {"row": {"round": 1, "seq": 0, "side": 1, "unit": "p1_0", "kind": 0, "intent": "",
                   "cands": {"list": STATS_MENU, "best": 0, "played": 1}},
           "menu": STATS_MENU, "before": {"units": copy.deepcopy(units)},
           "after": {"units": copy.deepcopy(units)}, "rep": {"rolls": ROLLS, "log": [], "unported": []},
           "keys": ["p1_0", "p2_0"]}
    rec = {"stem": "t", "winner": "p1", "vp": [1, 0], "roster": ["A", "B"],
           "rounds_log": [{"owners": [0, 0], "vp": [0, 0]}], "mission": {}}
    lists = {"p1": {"listPoints": 1000, "name": "P", "units": []}, "p2": {"listPoints": 1000, "name": "Q", "units": []}}
    assert gn.stats_row(rec, [act], lists)["shots_executed"] == 1
    old = copy.deepcopy(act)
    del old["row"]["cands"]["played"]
    assert gn.stats_row(rec, [old], lists)["shots_executed"] == 0
