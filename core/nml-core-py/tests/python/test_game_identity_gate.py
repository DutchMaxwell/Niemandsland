"""The game-identity gate (tools/game_identity_gate.py) must be able to FAIL: it is the RED of every
training-speed change ("same seeds -> same games")."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import game_identity_gate as gate  # noqa: E402


def _game(root: Path, name: str, **fields) -> None:
    d = root / name
    d.mkdir(parents=True)
    rec = {"winner": "p1", "rounds_log": [{"vp": [1, 0]}], "wall_seconds": 1.5, "core_commit": "aaa", **fields}
    (d / "gen0_s27_d827.json").write_text(json.dumps(rec))


def test_identical_games_pass_even_when_wall_clock_and_commit_differ(tmp_path):
    _game(tmp_path / "a", "g0")
    _game(tmp_path / "b", "g0", wall_seconds=9.0, core_commit="bbb")
    assert gate.main(["x", str(tmp_path / "a"), str(tmp_path / "b")]) == 0


def test_a_changed_game_fails_the_gate(tmp_path):
    _game(tmp_path / "a", "g0")
    _game(tmp_path / "b", "g0", winner="p2")
    assert gate.main(["x", str(tmp_path / "a"), str(tmp_path / "b")]) == 1


def test_nothing_comparable_fails_too(tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    assert gate.main(["x", str(tmp_path / "a"), str(tmp_path / "b")]) == 1
