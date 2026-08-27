"""D6a (NML-1073 M5) — self-test for `tools/sight_gate.py`: synthetic shots where the expected
`attacks` is hand-computed for both the flat-ratio and bearer-cap paths."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import sight_gate as sg  # noqa: E402

HEAD = {"profiles": {"u1": {"name": "Shooter", "weapons": [
    {"name": "Heavy Rifle", "attacks": 1, "count": 5},   # flat path candidate (count==max_models)
    {"name": "Fusion Rifle", "attacks": 1, "count": 1},  # bearer-cap path candidate
]}}}


def write_game(tmp_path: Path, shots: list[dict]) -> Path:
    d = tmp_path / "g1"
    d.mkdir()
    (d / "acts.jsonl").write_text('{"profiles": %s}\n' % sg.json.dumps(HEAD["profiles"]))
    (d / "dice.jsonl").write_text("")
    (d / "shots.jsonl").write_text("\n".join(sg.json.dumps(s) for s in shots) + "\n")
    return d


def test_effective_attacks_is_godot_round():
    assert sg.effective_attacks(5, 4, 5) == 4      # round(5*4/5) = round(4.0)
    assert sg.effective_attacks(1, 4, 5) == 1       # round(0.8) = 1 (ties away from zero)
    assert sg.effective_attacks(3, 0, 5) == 0


def test_expected_attacks_flat_vs_bearer_cap():
    # flat path: bearers == -1, base = per_model(1) * copies(5), s=4, max=5 -> round(5*4/5)=4.
    assert sg.expected_attacks(1, 5, -1, 4, 5) == 4
    # bearer-cap: per_model(2) * min(bearers=1, s=3) = 2.
    assert sg.expected_attacks(2, 1, 1, 3, 5) == 2
    # bearer-cap where the bearer count, not sighted, binds: min(1, 4) == min(1, 3).
    assert sg.expected_attacks(2, 1, 1, 4, 5) == sg.expected_attacks(2, 1, 1, 3, 5)


def test_resolve_weapon_matches_by_member_and_weapon_name():
    assert sg.resolve_weapon(HEAD, "Shooter", "Heavy Rifle") == (1, 5)
    assert sg.resolve_weapon(HEAD, "Shooter", "Fusion Rifle") == (1, 1)
    assert sg.resolve_weapon(HEAD, "Nobody", "Heavy Rifle") is None


def test_instrument_holds_on_correctly_recorded_shots(tmp_path):
    shots = [
        {"act": 1, "alive": 5, "sighted": 4, "bearers": -1, "max_models": 5,
         "member": "Shooter", "weapon": "Heavy Rifle", "attacks": 4},
        {"act": 2, "alive": 4, "sighted": 3, "bearers": 1, "max_models": 5,
         "member": "Shooter", "weapon": "Fusion Rifle", "attacks": 1},
    ]
    d = write_game(tmp_path, shots)
    result = sg.instrument_check([d], "sighted")
    assert result == {"checked": 2, "ok": 2, "violations": 0, "lookup_misses": 0, "examples": []}


def test_red_formula_alive_breaks_the_flat_path(tmp_path):
    # Same flat-path shot as above (sighted=4 < alive=5): forcing s=alive(5) recomputes
    # round(5*5/5)=5, which must NOT match the recorded attacks=4.
    shots = [{"act": 1, "alive": 5, "sighted": 4, "bearers": -1, "max_models": 5,
              "member": "Shooter", "weapon": "Heavy Rifle", "attacks": 4}]
    d = write_game(tmp_path, shots)
    green = sg.instrument_check([d], "sighted")
    red = sg.instrument_check([d], "alive")
    assert green["violations"] == 0
    assert red["violations"] == 1
