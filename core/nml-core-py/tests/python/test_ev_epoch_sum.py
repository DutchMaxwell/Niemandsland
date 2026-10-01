"""D21 / evfloor: the expected-wounds (EV) resolve follows the RECORD's rules epoch.

Def 2+ in cover vs AP(1): the old per-group floor saves on 3+ (1.667 expected wounds from ten Q4
attacks), the table's one-sum rule saves on 2+ (0.833). Epoch 68 prices the table's number, epoch
67 and an unstamped header (0) replay the old one. 0.8333 is also the GDScript oracle value
(`test/ai_combat_math_test.gd` D21 block, `ai_ev_test.gd` `test_to_hit_modifiers_are_one_sum_clamped_once`).
"""
from pathlib import Path

import nml_core
import pytest

REPO = Path(__file__).resolve().parents[4]


def line():
    profiles, units = {}, {}
    for key, player, x in (("shooter", 1, 0.0), ("target", 2, 0.3)):
        profiles[key] = dict(
            unit_id=key, name=key, quality=4, defense=2 if key == "target" else 4, tough=99,
            wounds_max=[99], model_count=1, caster_value=0,
            base_radius=0.016, game_system="gf", faction_folder="robot_legions",
            special_rules=[], item_grants=[], attached_hero_rules=[],
            move_bands={"advance": 6.0, "rush": 12.0}, weapons=[])
        units[key] = dict(
            player=player, alive=1, wounds=[99], radii=[0.016],
            positions=[[x, 0.0, 0.0]], in_cover=(key == "target"), shaken=False,
            fatigued=False, activated=False, casts=0, morale_bonus=0,
            aircraft=False, dormant=False, ambush_arrived_round=-1,
            earliest_arrival_round=-1, wound_frac=0.0, mods={}, mods_base={},
            bands={"advance": 6.0, "rush": 12.0})
    profiles["shooter"]["weapons"] = [dict(
        name="Rifle", range=24, attacks=10, count=1, rules=["AP(1)"])]
    return profiles, dict(round=2, rounds_total=4, scoring="end", units=units)


def expected_wounds(epoch):
    """Expected wounds the EV resolve took off the 99-wound target: whole wounds lost plus the carry."""
    profiles, plain = line()
    core = nml_core.load(str(REPO))
    knobs = {} if epoch is None else {"rules_epoch": epoch}
    core.set_header({"profiles": profiles, "knobs": knobs})
    after = core.resolve(core.state_of(plain), {"kind": nml_core.HOLD, "unit": "shooter", "shoot": "target"})
    u = after.plain()["units"]["target"]
    return (99 - u["wounds"][0]) + u["wound_frac"]


@pytest.mark.parametrize("epoch,ev", [(None, 10 * 0.5 * 2 / 6), (0, 10 * 0.5 * 2 / 6), (67, 10 * 0.5 * 2 / 6),
                                      (68, 10 * 0.5 * 1 / 6)])
def test_the_ev_resolve_follows_the_records_epoch(epoch, ev):
    assert expected_wounds(epoch) == pytest.approx(ev, abs=1e-6)
