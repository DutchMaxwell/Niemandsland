"""The header epoch governs imported ledger buffs as well as combat reads."""
from copy import deepcopy
from pathlib import Path

import nml_core
import pytest


REPO = Path(__file__).resolve().parents[4]


def shooting_line():
    profiles, units = {}, {}
    for key, player, x in (("shooter", 1, 0.0), ("target", 2, 0.2)):
        profiles[key] = dict(
            unit_id=key, name=key, quality=4, defense=4, tough=99,
            wounds_max=[99], model_count=1, caster_value=0,
            base_radius=0.016, game_system="gf", faction_folder="robot_legions",
            special_rules=[], item_grants=[], attached_hero_rules=[],
            move_bands={"advance": 6.0, "rush": 12.0}, weapons=[])
        units[key] = dict(
            player=player, alive=1, wounds=[99], radii=[0.016],
            positions=[[x, 0.0, 0.0]], in_cover=False, shaken=False,
            fatigued=False, activated=False, casts=0, morale_bonus=0,
            aircraft=False, dormant=False, ambush_arrived_round=-1,
            earliest_arrival_round=-1, wound_frac=0.0, mods={}, mods_base={},
            bands={"advance": 6.0, "rush": 12.0})
    profiles["shooter"]["weapons"] = [dict(
        name="Rifle", range=24, attacks=64, count=1, rules=["AP(1)"])]
    return profiles, dict(round=2, rounds_total=4, scoring="end", units=units)


@pytest.mark.parametrize("epoch", [0, 6, 7, 9])
@pytest.mark.parametrize("bearer,knob,value,save_target", [
    ("shooter", "ap_mod", -1, 4),
    ("target", "def_mod", 1, 4),
    ("target", "defense_mod", -1, 6),
])
def test_state_import_uses_the_header_epoch(epoch, bearer, knob, value, save_target):
    profiles, plain = shooting_line()
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": profiles, "knobs": {"rules_epoch": epoch}})
    buffed = deepcopy(plain)
    buffed["units"][bearer]["ledger"] = {"buffs": [{knob: value}]}

    def shoot(state):
        _, report = core.resolve_with_tray(
            core.state_of(state), {"kind": nml_core.HOLD, "unit": "shooter",
                                   "shoot": "target"},
            nml_core.Rng(0), nml_core.Tray(27))
        return report["rolls"]

    plain_rolls, buffed_rolls = shoot(plain), shoot(buffed)
    assert next(r["target"] for r in plain_rolls if r["kind"] == "defense") == 5
    if epoch < nml_core.EPOCH_7_TABLE_RULES:
        assert buffed_rolls == plain_rolls
    else:
        assert next(r["target"] for r in buffed_rolls if r["kind"] == "defense") == save_target
