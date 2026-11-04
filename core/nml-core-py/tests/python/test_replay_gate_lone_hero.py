"""G4-H6 — a LONE joined hero's save compares as the HOST label in the shoot replay gate.

The table signs a save made for a lone attached hero (host with no living model, hero still standing) with the HOST
unit's label (G4-T2); the core's replay signs it with the hero's own name. The gate compared owner strings exactly,
so an act whose every die, target and face matched still parted on `owner` - 36 of the 1104 round-2 shooting acts
once the aim reaches the hero (F-AIM). The gate now accepts either label for a lone hero's roll.

SHOOT GATE ONLY. The first version of this row also normalised the charge gate; the round-2 charge diagnosis found no
act there that needs it (the signer of a lone hero's melee dice already agrees), and a label map that nothing needs
only hides a real signer bug later - so the charge gate keeps comparing owners exactly.

A RELAXATION, NEVER A NEW FAILURE. The first version replaced the core's label by the host's for EVERY roll the lone
hero signs, which turned one act that matched before (gf_1000_net_026 act 15: the hero rolls under its own name at
the table too) into an `owner` failure. `signer_ok` accepts the roller's own name OR the host's.

THE TESTS.
  * the stub cases build a tiny game in a temp dir and replace the core by a stub that signs the save as the HERO, so
    they measure the gate's owner comparison alone: a lone hero compares as the host; as itself; a LIVE host does not
    make the hero compare as the host's label (the guard: a real signer bug stays visible).
  * the live case replays a RECORDED activation through the real core: `fixtures/g4r2_h6/aof_1000_net_007` act 22,
    the 1104 recording (host `Dark Shooters` destroyed, hero `Champion` shoots), the sidecar left out so the aim is
    the pick itself. Every die matches; the defender's save is signed `AI (Champion)` by the port and
    `AI (Dark Shooters)` by the table. (The act stays one roll short of FULL-equal - the table's morale test of the
    lone hero - a different cause, pinned as such.)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
LIVE = Path(__file__).resolve().parent / "fixtures" / "g4r2_h6"

HOST = "Change Acolyte Chanters"
HERO = "Change Birdman Champion"
SHOOTER = "Peasant Bowmen"

FACES_ATTACK = [3, 3, 6, 6, 6, 1, 4, 6, 1, 3]
FACES_DEFENSE = [1, 6, 1, 1]


def _write_game(root: Path, host_alive: int, table_signer: str = HOST) -> Path:
    """One recorded game dir: a shooter, a host and its attached hero, one shooting act and the two rolls the stub
    core will draw (the table signs the save as `table_signer`)."""
    game = root / "lone_hero"
    game.mkdir()
    units = {
        "S": {"alive": 10, "attached": [], "attached_to": "", "wounds": [0]},
        "H": {"alive": host_alive, "attached": ["E"], "attached_to": "", "wounds": [0]},
        "E": {"alive": 1, "attached": [], "attached_to": "H", "wounds": [0]},
    }
    head = {"profiles": {"S": {"name": SHOOTER}, "H": {"name": HOST}, "E": {"name": HERO}},
            "terrain": None, "knobs": {"engage_fold": True, "cond_ap": True}}
    shoot = {"kind": "act",
             "pick": {"action": {"kind": 1, "unit": "S", "shoot": "H", "dest": [0.0, 0.0, 0.0]}},
             "state": {"units": units}}
    (game / "acts.jsonl").write_text("\n".join(json.dumps(x) for x in (head, shoot)) + "\n")
    dice = [{"act": 1, "roll_kind": "attack", "count": 10, "target": 5,
             "faces": FACES_ATTACK, "owner": "AI (%s)" % SHOOTER},
            {"act": 1, "roll_kind": "defense", "count": 4, "target": 5,
             "faces": FACES_DEFENSE, "owner": "AI (%s)" % table_signer}]
    (game / "dice.jsonl").write_text("\n".join(json.dumps(x) for x in dice) + "\n")
    (game / "arena_stub.json").write_text(json.dumps({"dice_seed": 36102}))
    return root


class _Core:
    """The port's side: the save is signed by the HERO (the core's own name)."""

    def set_header(self, header):
        pass

    def state_of(self, plain):
        return plain

    def resolve_with_tray(self, state, action, rng, tray):
        report = {"unported": [], "rolls": [
            {"kind": "attack", "count": 10, "target": 5, "faces": FACES_ATTACK, "owner": SHOOTER},
            {"kind": "defense", "count": 4, "target": 5, "faces": FACES_DEFENSE, "owner": HERO},
        ]}
        return SimpleNamespace(plain=lambda: state), report


def _run_shoot(tmp_path, monkeypatch, capsys, host_alive, table_signer=HOST):
    fake = SimpleNamespace(load=lambda repo: _Core(),
                           Tray=lambda seed: SimpleNamespace(roll=lambda n: None),
                           Rng=lambda seed: None,
                           set_legacy_no_cond_ap=lambda flag: None)
    monkeypatch.setattr(srg, "nml_core", fake)
    ref = _write_game(tmp_path, host_alive, table_signer)
    code = srg.run(ref, str(tmp_path), "table", 0, 0, False)
    return code, capsys.readouterr().out


def test_the_shoot_gate_compares_a_lone_heros_save_as_the_host_label(tmp_path, monkeypatch, capsys):
    code, out = _run_shoot(tmp_path, monkeypatch, capsys, host_alive=0)
    assert code == 0, out
    assert "OWNER : 1/1" in out, "the lone hero's save still landed in the owner bucket: %s" % out
    assert "[owner]" not in out, out


def test_a_lone_hero_that_rolls_under_its_own_name_still_matches(tmp_path, monkeypatch, capsys):
    """The relaxation: the table signs the hero's own name (gf_1000_net_026 act 15's shape) - equal before, equal now."""
    code, out = _run_shoot(tmp_path, monkeypatch, capsys, host_alive=0, table_signer=HERO)
    assert code == 0, out
    assert "OWNER : 1/1" in out, out


def test_a_live_host_is_not_normalised_away(tmp_path, monkeypatch, capsys):
    """THE GUARD: with the host still alive the hero is NOT lone, so the labels part exactly as before - the
    normalisation may not hide a real signer bug."""
    code, out = _run_shoot(tmp_path, monkeypatch, capsys, host_alive=5)
    assert code == 1, out
    assert "OWNER : 0/1" in out, out
    assert "[owner]" in out, out


def test_a_recorded_lone_hero_act_replays_on_the_real_core_without_an_owner_part(capsys):
    srg.run(LIVE, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    assert "1/1 acts PREFIX-equal" in out, out
    assert "[owner]" not in out, out
    assert not re.search(r"first field to part: .*owner=", out), out
