"""G4R3 F-CONT RED-GREEN: the act header's `terrain.containers` reaches the core's per-model sight.

THE BUG THIS PINS. The table's sight keeps a placed container as its exact 6x3 box and drops the painted cells under
it, but the act header carried only the 3-inch-quantised cells (none at all under some boxes). The gate then replayed
a volley with models the table's line never saw: gf_1000_net_033 acts 18 and 23 (core 7 and 10 sighted where the table
counted 5 and 9) and aof_1000_net_029 act 17 (the box blocked all nine shooters at the activation gate, the core saw
one). From EPOCH_73_V36 the recorder writes `terrain.containers = [{c, he, yaw}]` in world metres and the core builds
a solid 2.5-inch volume from each.

Legs: with the box at epoch 73 the shooter behind it is not sighted; the key-deleted mutant (an old recording) and
epoch 72 sight it as before. The box is the one the table recorded for gf_1000_net_033 (c = (0.2286, -0.1143) m,
half extents 3 x 1.5 inches, yaw 0), and the two models stand 12 inches either side of it on the +z axis line.
"""

from __future__ import annotations

from pathlib import Path

import nml_core

REPO = str(Path(__file__).resolve().parents[4])
EPOCH_72_PLAYTEST_RULES = 72
EPOCH_73_V36 = 73
IN2M = 0.0254
BOX = {"c": [0.2286, -0.1143], "he": [3.0 * IN2M, 1.5 * IN2M], "yaw": 0.0}


def _profiles() -> dict:
    out = {}
    for key in ("shooter", "target"):
        out[key] = dict(
            unit_id=key, name=key, quality=4, defense=4, tough=1, wounds_max=[1], model_count=1, caster_value=0,
            base_radius=0.016, game_system="gf", faction_folder="robot_legions", special_rules=[], item_grants=[],
            attached_hero_rules=[], move_bands={"advance": 6.0, "rush": 12.0}, weapons=[])
    return out


def _state(shooter_z_in: float, target_z_in: float) -> dict:
    units = {}
    for key, player, z in (("shooter", 1, shooter_z_in), ("target", 2, target_z_in)):
        units[key] = dict(
            player=player, alive=1, wounds=[1], radii=[0.016], positions=[[BOX["c"][0], 0.0, BOX["c"][1] + z * IN2M]],
            in_cover=False, shaken=False, fatigued=False, activated=False, casts=0, morale_bonus=0, aircraft=False,
            dormant=False, ambush_arrived_round=-1, earliest_arrival_round=-1, wound_frac=0.0, mods={},
            mods_base={}, bands={"advance": 6.0, "rush": 12.0})
    return dict(round=2, rounds_total=4, scoring="end", units=units)


def _sighted(epoch: int, boxes: list | None) -> int:
    """The per-model sighted count of the shooter 12 inches behind the box, the target 12 inches past it."""
    terrain = {"cells": [], "sandbox": [], "walls": [],
               "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
                               "grid_size_inches": 3.0, "inches_to_meters": IN2M}}
    if boxes is not None:
        terrain["containers"] = boxes
    core = nml_core.load(REPO)
    core.set_header({"profiles": _profiles(), "terrain": terrain, "knobs": {"rules_epoch": epoch}})
    return int(core.sighted(core.state_of(_state(-12.0, 12.0)), "shooter", "target", 30.0)["sighted"])


def test_the_box_blocks_the_shooter_behind_it_at_epoch_73():
    assert _sighted(EPOCH_73_V36, [BOX]) == 0, "the table's line stops at the 2.5-inch box"


def test_the_key_deleted_mutant_sees_through_the_box():
    assert _sighted(EPOCH_73_V36, None) == 1, "an old recording carries no key: the core sees as before"


def test_below_epoch_73_the_key_is_not_read():
    assert _sighted(EPOCH_72_PLAYTEST_RULES, [BOX]) == _sighted(EPOCH_72_PLAYTEST_RULES, None) == 1
