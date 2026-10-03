"""lab2_p9: the probe slots, the three P9 decisions (hand-computed projections), a tray decline as incompleteness,
and the outcome blindness: a row that raises on any read of `y` decides exactly like a plain one."""
import importlib.util
import os

import pytest

_SPEC = importlib.util.spec_from_file_location("lab2_p9", os.path.join(os.path.dirname(os.path.abspath(__file__)), "lab2_p9.py"))
p9 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(p9)
_LAB = importlib.util.spec_from_file_location("lab2_tree_probe", os.path.join(os.path.dirname(p9.__file__), "lab2_tree_probe.py"))
lab = importlib.util.module_from_spec(_LAB)
_LAB.loader.exec_module(lab)
CELLS = ["c%d" % i for i in range(1, 13)]


class Blind(dict):
    """A probe row that fails the test the moment anything reads its outcome."""

    def __getitem__(self, key):
        assert key not in ("y", "winner"), "P9 read an outcome"
        return super().__getitem__(key)

    def get(self, key, default=None):
        assert key not in ("y", "winner"), "P9 read an outcome"
        return super().get(key, default)


def _probes(wall=1.0, valid=True):
    return [Blind(cell=c, arm=a, wall_s=wall, valid=valid, y=1, winner="p1") for c in CELLS for a in p9.CONTROLS]


L_GAMES = {c: [30.0, 60.0] for c in CELLS}  # the largest L game per cell: 60 s


def test_probe_slots_take_the_first_ending_of_each_cell_in_manifest_order():
    positions = [{"cell": c, "slot": "%s_%d" % (c, k)} for k in (1, 2) for c in reversed(CELLS)]
    slots = p9.probe_slots(positions)
    assert len(slots) == 24 and [s[0]["cell"] for s in slots[:6]] == ["c1", "c1", "c2", "c2", "c3", "c3"]
    assert {s[0]["slot"] for s in slots} == {"%s_1" % c for c in CELLS} and {s[2] for s in slots} == {0}


def test_mode_a_when_both_caps_fit():
    mode, proj = p9.decide(_probes(), L_GAMES, pilot_left_h=2, confirm_left_h=5, workers=4)
    # 12 cells x 2 x 1 s x (2 endings x 16 continuations - 2 probes) / 3600 / 4 workers; A: x 640 per cell
    assert mode == "MODE_A" and proj["mode_a_pilot_h"] == pytest.approx(720 / 14400)
    assert proj["mode_a_confirm_h"] == pytest.approx(15360 / 14400)


def test_mode_b_when_the_a_controls_overflow_the_confirmation_cap():
    mode, proj = p9.decide(_probes(), L_GAMES, pilot_left_h=2, confirm_left_h=0.5, workers=4)
    assert mode == "MODE_B" and proj["mode_b_pilot_h"] == pytest.approx(12 * 2 * 60 * 8 / 14400)


def test_pilot_stop_when_neither_fits():
    assert p9.decide(_probes(), L_GAMES, pilot_left_h=0.5, confirm_left_h=0.5, workers=4)[0] == "PILOT_STOP"


def test_a_tray_decline_is_incompleteness_and_rules_out_mode_a():
    rows = _probes()
    rows[5] = Blind(rows[5], valid=False, reason="unported:deadly")
    mode, proj = p9.decide(rows, L_GAMES, pilot_left_h=100, confirm_left_h=100, workers=4)
    assert (mode, proj["complete"]) == ("MODE_B", False)


def test_a_blocked_stratum_probe_is_counted_but_not_incompleteness():
    rows = _probes()
    for i in (3, 5, 17):  # unported true-tray transitions (HOLD until D151 (b))
        rows[i] = Blind(rows[i], valid=False, blocked=True, reason='blocked_stratum: TreeUnported("takedown")')
    mode, proj = p9.decide(rows, L_GAMES, pilot_left_h=100, confirm_left_h=100, workers=4)
    assert (mode, proj["complete"], proj["blocked_stratum"]) == ("MODE_A", True, 3)
    rows[8] = Blind(rows[8], valid=False, reason="declined: side 1 (L_tray) declined with 2 units to activate: ")
    assert p9.decide(rows, L_GAMES, pilot_left_h=100, confirm_left_h=100, workers=4)[1]["complete"] is False


def test_a_missing_probe_cell_is_incompleteness():
    mode, proj = p9.decide(_probes()[:-2], L_GAMES, pilot_left_h=100, confirm_left_h=100, workers=4)
    assert (mode, proj["complete"]) == ("MODE_B", False)


def test_the_mode_b_control_is_l_through_the_true_tray():
    l_arm, l_tray = (lab.arm_kwargs({"arm": a}, 5) for a in ("L", "L_tray"))
    assert l_tray == dict(l_arm, deep_tree_dice="tray") and "deep_tree_dice" not in l_arm
    with pytest.raises(ValueError):
        lab.arm_kwargs({"arm": "Ltray"}, 5)  # a misspelt arm must not fall through to the C rung


def test_l_tray_rows_carry_their_own_search_keys_and_score_descriptively():
    seeds = {"terrain": "1", "layout": "2", "deploy": "3", "play_general": ["4", "5"], "tray": ["6", "7"],
             "search": {"d%dc%d" % (d, s): {"L": {"1": "10"}, "L_tray": {"1": "8%d%d" % (d, s), "2": "9%d%d" % (d, s)}}
                        for d in (0, 1) for s in (1, 2)}}
    rows = lab.game_rows([{"block": "b1", "cell": "c3", "mission": "duel", "army1": "a", "army2": "b",
                           "seeds": seeds}], ("L_tray",))
    assert len(rows) == 4 and all(r["seeds"]["search"] == {"1": "8%d%d" % (r["d"], r["seat"]), "2": "9%d%d" % (r["d"], r["seat"])}
                                  for r in rows)
    done = list(zip(rows, (1.0, 1.0, 0.5, 0.0)))
    assert lab.control_scores(done) == {"c3": {"b1": {"L_tray_I": 0.125}}}
