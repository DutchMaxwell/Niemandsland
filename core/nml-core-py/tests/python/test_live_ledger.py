"""`play_game(live_ledger=True)`: the planner state carries the LIVE mission ledger,
as the table writes it into every capture (battle_sim.gd:1857-1870). The default
False keeps VP [0, 0] in the planner state all game and must stay byte-identical.
RED: with `_write_ledger` a no-op, round 3 plans from [0, 0] against a ledger [2, 3]."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1, ARMY2 = LISTS / "robot_legions_1000.json", LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(
    not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists()),
    reason="needs the terrain bank + 1000pt lists")


def _play(mission: str, live: bool):
    """Seed 27 under a `forced_picks` spy: the vp of the first planner state per round."""
    core = nml_core.load(str(REPO))
    real, seen = sp._pick_for, {}

    def spy(core, state, player, *args, **kwargs):
        plain = state.plain()
        seen.setdefault(int(plain["round"]), plain.get("vp"))
        return real(core, state, player, *args, **kwargs)

    with sp.forced_picks(spy):
        result = sp.play_game(27, ARMY1, ARMY2, REPO, BANK_DIR, core, top_k=2, horizon=1,
                              mission=mission, live_ledger=live)
    return result, seen


@needs_lists
def test_round3_planner_sees_the_live_vp():
    result, seen = _play("domination", True)
    assert result["rounds_log"][1]["vp"] != [0, 0], "fixture must have booked VP by round 2"
    assert seen[3] == result["rounds_log"][1]["vp"]
    assert result["knobs"]["live_ledger"] is True


@needs_lists
def test_default_keeps_the_stale_ledger():
    """N1, the bug the default keeps: round 3 still plans from VP 0:0."""
    result, seen = _play("domination", False)
    assert result["rounds_log"][1]["vp"] != [0, 0]
    assert seen[3] == [0, 0]
    assert "live_ledger" not in result["knobs"]


@needs_lists
def test_duel_is_byte_identical():
    assert sp.result_digest(_play("duel", True)[0]) == sp.result_digest(_play("duel", False)[0])
