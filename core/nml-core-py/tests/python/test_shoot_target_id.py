"""G4-H4: `shots.jsonl`'s `target_id` aims a split volley at a DUPLICATE name.

Two units can carry one display name (aof_1000_net_008/009: two "Imperial
Artillery"), so the sidecar's `target` name is ambiguous and `split_aim` drops
it. The recorder now also writes the target's unit key (`target_id`); the gate
uses it directly when the header has that key, and only falls back to the old
name lookup when the field is absent, empty or unknown.

The fixture is built here, not shipped: one attacker plus two defenders that
share the name, an act whose recorded `shoot` is the FIRST defender and whose
table volley aimed at the SECOND. The dice are the port's own split resolution
(on the second defender), so a correct injection replays them FULL-equal while
the old ambiguous-name drop stays on the pooled path and parts on the defense
target (3 vs 5).
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
ATTACKER, HOST, OTHER = "atk", "host", "other"
NAME = "Imperial Artillery"
SEED = 11


def _profile(uid: str, name: str, defense: int) -> dict:
    return {
        "attached_hero_rules": [], "base_radius": 0.02, "caster_value": 0,
        "defense": defense, "faction_folder": "imperial", "game_system": "gf",
        "item_grants": [], "model_count": 1,
        "move_bands": {"advance": 6.0, "rush": 12.0}, "name": name,
        "quality": 2, "special_rules": [], "tough": 1, "unit_id": uid,
        "weapons": [{"ap": 0, "attacks": 2, "count": 1, "name": "Rifle",
                     "range": 12, "rules": []}],
        "wounds_max": [1],
    }


def _unit(player: int, pos: list[float]) -> dict:
    zero = {"advance": 0.0, "def": 0, "hit": 0, "morale": 0, "range_in": 0.0, "rush": 0.0}
    return {
        "activated": False, "aircraft": False, "alive": 1, "ambush_arrived_round": -1,
        "attached": [], "attached_to": "", "bands": {"advance": 6, "rush": 12}, "casts": 0,
        "charge_no_difficult": True, "charge_probe_r": 0.02, "fatigued": False,
        "in_cover": False, "los": {}, "mods": dict(zero), "mods_base": dict(zero),
        "morale_bonus": 0, "player": player, "positions": [pos],
        "prof": {"attached_hero_rules": [], "caster_value": 0, "item_grants": [],
                 "max_activation_advance_bonus_in": 0.0, "shooting_range_bonus": 0,
                 "special_rules": [], "tough": 1},
        "radii": [0.02], "shaken": False, "wounds": [1],
    }


def _write_game(tmp_path: Path, target_id: str | None) -> Path:
    profiles = {ATTACKER: _profile(ATTACKER, "Attacker", 4),
                HOST: _profile(HOST, NAME, 3),
                OTHER: _profile(OTHER, NAME, 5)}
    units = {ATTACKER: _unit(1, [0.0, 0.0, 0.0]),
             HOST: _unit(0, [0.2, 0.0, 0.0]),
             OTHER: _unit(0, [0.2, 0.0, 0.1])}
    units[ATTACKER]["los"] = {HOST: True, OTHER: True}
    state = {"objectives": [], "round": 1, "rounds_total": 4, "scoring": "end",
             "unit_order": [ATTACKER, HOST, OTHER], "units": units}
    head = {"kind": "header", "profiles": profiles, "terrain": None,
            "knobs": {"engage_fold": False, "cond_ap": True}}

    core = nml_core.load(str(REPO))
    core.set_header({"profiles": profiles, "terrain": None, "knobs": {}})
    action = {"kind": 0, "unit": ATTACKER, "shoot": HOST,
              "split": [{"member": "Attacker", "weapon": "Rifle", "target": OTHER}]}
    _, report = core.resolve_with_tray(core.state_of(state), action,
                                       nml_core.Rng(0), nml_core.Tray(SEED))
    dice = [{"act": 1, "seq": i, "roll_kind": r["kind"], "owner": "AI (%s)" % r["owner"],
             "target": r["target"], "count": r["count"], "faces": r["faces"]}
            for i, r in enumerate(report["rolls"])]
    shot = {"act": 1, "round": 1, "player": 1, "shooter": "Attacker", "member": "Attacker",
            "weapon": "Rifle", "target": NAME}
    if target_id is not None:
        shot["target_id"] = target_id

    game = tmp_path / ("game_" + ("target_id" if target_id else "none"))
    game.mkdir()
    (game / "acts.jsonl").write_text("\n".join(json.dumps(x) for x in [
        head, {"kind": "act", "player": 1, "round": 1,
               "state": state, "pick": {"action": {"kind": 0, "unit": ATTACKER,
                                                    "shoot": HOST}}},
    ]) + "\n")
    (game / "dice.jsonl").write_text("\n".join(json.dumps(x) for x in dice) + "\n")
    (game / "shots.jsonl").write_text(json.dumps(shot) + "\n")
    (game / "arena_fixture.json").write_text(json.dumps({"dice_seed": SEED}))
    return game


def _gate(game: Path) -> str:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = srg.main(["--ref", str(game.parent), "--limit", "1", "--report-only"])
    assert code == 0
    return buf.getvalue()


def test_target_id_makes_the_duplicate_name_act_full_equal(tmp_path):
    out = _gate(_write_game(tmp_path, OTHER))
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "1 of those FULL-equal" in out, out


def test_without_target_id_the_old_ambiguous_name_path_stays_parted(tmp_path):
    out = _gate(_write_game(tmp_path, None))
    assert "EQUAL : 0/1 acts FULL-equal" in out, out
    assert "0/1 acts injected" in out and "1 uncovered" in out, out


def test_target_id_wins_over_the_name_and_unknown_ids_fall_back():
    head = {"profiles": {"a": {"name": "Same"}, "b": {"name": "Same"}}}
    units = {"a": {"alive": 1}, "b": {"alive": 1}}
    rec = [{"member": "m", "weapon": "w", "target": "Same", "target_id": "b"}]
    assert srg.split_aim(head, rec, "x", units)[0] == [
        {"member": "m", "weapon": "w", "target": "b"}]
    for missing in ("", "gone"):
        aim, why, amb = srg.split_aim(head, [dict(rec[0], target_id=missing)], "x", units)
        assert (aim, why, amb) == (None, "uncovered", 1)


def test_a_dead_host_with_a_living_joined_hero_is_not_stale():
    head = {"profiles": {"host": {"name": "Host"}, "hero": {"name": "Hero"}}}
    rec = [{"member": "m", "weapon": "w", "target": "Host", "target_id": "host"}]
    joined = {"host": {"alive": 0, "attached": ["hero"]}, "hero": {"alive": 1}}
    assert srg.split_aim(head, rec, "x", joined)[0] == [
        {"member": "m", "weapon": "w", "target": "host"}]
    gone = {"host": {"alive": 0, "attached": ["hero"]}, "hero": {"alive": 0}}
    assert srg.split_aim(head, rec, "x", gone)[1] == "stale"
