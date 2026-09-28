"""Wave C gate C9.9 — `tools/eval_ab_one.py`'s `--mission` door, the seam the
per-mission A/B (plan amendment C9-gate, open decision G-AB) is launched through.

A catalog mission must reach `play_game` with its own marker layout
(`objectives="mission"`) and its id, so the game plays that mission's referee.
Leaving the flag off must hand `play_game` exactly the kwargs every earlier A/B
run used (`objectives="rulebook"`, no `mission`), so no old number moves.
`play_game` is stubbed: the question is the plumbing, not a game.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import eval_ab_one  # noqa: E402
import selfplay  # noqa: E402


def _kwargs(monkeypatch, tmp_path, *extra):
    seen = {}

    def fake_play_game(seed, army1, army2, repo, bank, core, **kw):
        seen.update(kw)
        return {"winner": "draw"}

    monkeypatch.setattr(selfplay, "play_game", fake_play_game)
    monkeypatch.setattr(sys, "argv", [
        "eval_ab_one.py", str(tmp_path), "--seed", "27", "--dice-seed", "27",
        "--army1", "a.json", "--army2", "b.json", "--cand-player", "1", *extra])
    assert eval_ab_one.main() == 0
    return seen


def test_a_catalog_mission_plays_its_own_layout_and_referee(monkeypatch, tmp_path):
    kw = _kwargs(monkeypatch, tmp_path, "--mission", "relic_hunt")
    assert kw["objectives"] == "mission"
    assert kw["mission"] == "relic_hunt"


def test_no_flag_keeps_every_earlier_runs_kwargs(monkeypatch, tmp_path):
    kw = _kwargs(monkeypatch, tmp_path)
    assert kw["objectives"] == "rulebook"
    assert "mission" not in kw
