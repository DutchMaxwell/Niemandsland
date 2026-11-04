"""RED-GREEN: a BOTH-SILENT act counts as equal in both replay gates.

The gates used to tally `both_silent` and then leave it out of the pass
formula, so a game where the port and the table agree by both drawing nothing
still failed. The fixtures here are synthetic and tiny (a header, one or two
acts, the recorded dice); the core is a stub that returns a fixed roll list per
act, so the case pins the FORMULA, not the dice resolver.

1. only-silent -> gate PASSES after the fix (RED: it FAILED before).
2. silent + one parted act -> gate still FAILS (guards a too-loose formula).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = str(Path(__file__).resolve().parents[4])


class _Next:
    def plain(self):
        return {"units": {}}


class _Core:
    def __init__(self, rolls):
        self._rolls = rolls

    def set_header(self, header):
        pass

    def state_of(self, plain):
        return plain

    def resolve_with_tray(self, state, action, rng, tray):
        return _Next(), {"rolls": list(self._rolls.get(action.get("probe"), [])),
                         "unported": []}


class _Stub:
    def __init__(self, rolls):
        self._rolls = rolls

    def load(self, repo):
        return _Core(self._rolls)

    def set_legacy_no_cond_ap(self, flag):
        pass

    def Tray(self, seed):
        return self

    def Rng(self, seed):
        return self

    def roll(self, n):
        pass


def _game(ref: Path, name: str, acts: list[dict], dice: list[dict]) -> None:
    d = ref / name
    d.mkdir(parents=True)
    head = {"kind": "header", "profiles": {"a": {"name": "A"}, "b": {"name": "B"}},
            "terrain": None, "knobs": {}}
    (d / "acts.jsonl").write_text(
        "\n".join(json.dumps(x) for x in [head] + acts) + "\n")
    (d / "dice.jsonl").write_text("".join(json.dumps(x) + "\n" for x in dice))
    (d / "arena_stub.json").write_text(json.dumps({"dice_seed": 1}))


def _shoot(probe: str) -> dict:
    return {"kind": "act", "round": 1, "player": 1, "state": {"units": {}},
            "pick": {"action": {"kind": 0, "shoot": "b", "probe": probe}}}


def _melee(probe: str) -> dict:
    return {"kind": "act", "round": 1, "player": 1, "state": {},
            "pick": {"action": {"kind": 3, "unit": "a", "charge": "b", "probe": probe}}}


def _parted_dice() -> list[dict]:
    return [{"act": 2, "roll_kind": "attack", "count": 1, "target": 4, "faces": [1],
             "owner": "AI (B)"}]


def _parted_roll() -> list[dict]:
    return [{"kind": "attack", "count": 1, "target": 4, "faces": [6], "owner": "A"}]


def test_shoot_gate_credits_a_both_silent_act(tmp_path, monkeypatch):
    _game(tmp_path, "silent", [_shoot("silent")], [])
    monkeypatch.setattr(srg, "nml_core", _Stub({}))
    assert srg.run(tmp_path, REPO, "table", 0, 0, False,
                   "table", "unit", "auto", "auto", True) == 0


def test_shoot_gate_still_fails_a_parted_act(tmp_path, monkeypatch):
    _game(tmp_path, "mixed", [_shoot("silent"), _shoot("parted")], _parted_dice())
    monkeypatch.setattr(srg, "nml_core", _Stub({"parted": _parted_roll()}))
    assert srg.run(tmp_path, REPO, "table", 0, 0, False,
                   "table", "unit", "auto", "auto", True) == 1


def test_melee_gate_credits_a_both_silent_act(tmp_path, monkeypatch):
    _game(tmp_path, "silent", [_melee("silent")], [])
    monkeypatch.setattr(mrg, "nml_core", _Stub({}))
    assert mrg.run(tmp_path, REPO, "table", 0, False) == 0


def test_melee_gate_still_fails_a_parted_act(tmp_path, monkeypatch):
    _game(tmp_path, "mixed", [_melee("silent"), _melee("parted")], _parted_dice())
    monkeypatch.setattr(mrg, "nml_core", _Stub({"parted": _parted_roll()}))
    assert mrg.run(tmp_path, REPO, "table", 0, False) == 1
