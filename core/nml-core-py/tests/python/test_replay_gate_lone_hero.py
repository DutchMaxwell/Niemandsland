"""G4-H6 — a LONE joined hero's dice compare as the HOST label in both replay gates.

`aof_1000_net_001` act 32 is the real case: the table signs the save made for a
lone attached hero with the HOST unit's name (G4-T2), while the core's replay
signs it with the hero's own name. The gates compared owner strings exactly, so
that act parted on `owner` even though every die, target and face matched.

The fixtures below are the shape of that act: a host with no living models, a
full-strength hero still attached to it, and one shooting/melee roll signed by
each side. They are BUILT IN A TEMP DIR at test time — no fixture data in the
repo — and the core is replaced by a stub so the test measures the GATES' owner
comparison, not the Rust twin (CI owns that). The guard case is the control the
normalisation needs: a host that is still alive must NOT make the hero compare
as its label, or a real signer bug would be hidden.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

HOST = "Change Acolyte Chanters"
HERO = "Change Birdman Champion"
SHOOTER = "Peasant Bowmen"

FACES_ATTACK = [3, 3, 6, 6, 6, 1, 4, 6, 1, 3]
FACES_DEFENSE = [1, 6, 1, 1]


def _write_game(root: Path, host_alive: int, hero_alive: int = 1) -> Path:
    """One recorded game dir of the act-32 shape: a shooter, a host and its
    attached hero, plus the two rolls the stub core will draw."""
    game = root / "lone_hero"
    game.mkdir()
    units = {
        "S": {"alive": 10, "attached": [], "attached_to": "", "wounds": [0]},
        "H": {"alive": host_alive, "attached": ["E"], "attached_to": "", "wounds": [0]},
        "E": {"alive": hero_alive, "attached": [], "attached_to": "H", "wounds": [0]},
    }
    head = {"profiles": {"S": {"name": SHOOTER}, "H": {"name": HOST}, "E": {"name": HERO}},
            "terrain": None, "knobs": {"engage_fold": True, "cond_ap": True}}
    shoot = {"kind": "act",
             "pick": {"action": {"kind": 1, "unit": "S", "shoot": "H",
                                 "dest": [0.0, 0.0, 0.0]}},
             "state": {"units": units}}
    charge = {"kind": "act",
              "pick": {"action": {"kind": 3, "unit": "S", "shoot": "H",
                                  "charge": "H", "dest": [0.0, 0.0, 0.0]}},
              "state": {"units": units}}
    (game / "acts.jsonl").write_text(
        "\n".join(json.dumps(x) for x in (head, shoot, charge)) + "\n")
    # The table's side of the rolls: attack signed by the shooter, save signed
    # by the HOST (G4-T2), exactly as `aof_1000_net_001` act 32 recorded them.
    # The charge act carries the same two rolls — the signer is what this
    # fixture is about, not the melee shape.
    dice = [{"act": 1, "roll_kind": "attack", "count": 10, "target": 5,
             "faces": FACES_ATTACK, "owner": "AI (%s)" % SHOOTER},
            {"act": 1, "roll_kind": "defense", "count": 4, "target": 5,
             "faces": FACES_DEFENSE, "owner": "AI (%s)" % HOST},
            {"act": 2, "roll_kind": "attack", "count": 10, "target": 5,
             "faces": FACES_ATTACK, "owner": "AI (%s)" % SHOOTER},
            {"act": 2, "roll_kind": "defense", "count": 4, "target": 5,
             "faces": FACES_DEFENSE, "owner": "AI (%s)" % HOST}]
    (game / "dice.jsonl").write_text("\n".join(json.dumps(x) for x in dice) + "\n")
    (game / "arena_stub.json").write_text(json.dumps({"dice_seed": 36102}))
    return root


class _Core:
    """The port's side: the save is signed by the HERO (the core's own name)."""

    def set_header(self, header):
        pass

    def state_of(self, plain):
        return plain

    def walls_in(self):
        return []

    def resolve_with_tray(self, state, action, rng, tray):
        report = {"unported": [], "rolls": [
            {"kind": "attack", "count": 10, "target": 5,
             "faces": FACES_ATTACK, "owner": SHOOTER},
            {"kind": "defense", "count": 4, "target": 5,
             "faces": FACES_DEFENSE, "owner": HERO},
        ]}
        return SimpleNamespace(plain=lambda: state), report


def _stub(monkeypatch):
    fake = SimpleNamespace(load=lambda repo: _Core(),
                           Tray=lambda seed: SimpleNamespace(roll=lambda n: None),
                           Rng=lambda seed: None,
                           set_legacy_no_cond_ap=lambda flag: None)
    monkeypatch.setattr(srg, "nml_core", fake)
    monkeypatch.setattr(mrg, "nml_core", fake)


def _run_shoot(tmp_path, monkeypatch, capsys, host_alive):
    _stub(monkeypatch)
    ref = _write_game(tmp_path, host_alive)
    code = srg.run(ref, str(tmp_path), "table", 0, 0, False)
    return code, capsys.readouterr().out


def _run_melee(tmp_path, monkeypatch, capsys, host_alive):
    _stub(monkeypatch)
    ref = _write_game(tmp_path, host_alive)
    code = mrg.run(ref, str(tmp_path), "table", 0, False)
    return code, capsys.readouterr().out


def test_the_shoot_gate_compares_a_lone_heros_save_as_the_host_label(tmp_path,
                                                                   monkeypatch, capsys):
    code, out = _run_shoot(tmp_path, monkeypatch, capsys, host_alive=0)
    assert code == 0, out
    assert "OWNER : 1/1" in out, "the lone hero's save still landed in the owner bucket: %s" % out
    assert "[owner]" not in out, out


def test_the_melee_gate_compares_a_lone_heros_dice_as_the_host_label(tmp_path,
                                                                    monkeypatch, capsys):
    code, out = _run_melee(tmp_path, monkeypatch, capsys, host_alive=0)
    assert code == 0, out
    assert "EQUAL : 1/1" in out, "the lone hero's roll still parted on the signer: %s" % out


def test_a_live_host_is_not_normalised_away_in_the_shoot_gate(tmp_path, monkeypatch, capsys):
    """THE GUARD: with the host still alive the hero is NOT lone, so the labels
    must part exactly as before — the normalisation may not hide a real signer
    bug."""
    code, out = _run_shoot(tmp_path, monkeypatch, capsys, host_alive=5)
    assert code == 1, out
    assert "OWNER : 0/1" in out, out
    assert "[owner]" in out, out


def test_a_live_host_is_not_normalised_away_in_the_melee_gate(tmp_path, monkeypatch, capsys):
    code, out = _run_melee(tmp_path, monkeypatch, capsys, host_alive=5)
    assert code == 1, out
    assert "EQUAL : 0/1" in out, out
