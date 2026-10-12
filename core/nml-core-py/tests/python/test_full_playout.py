"""Track 2 (halfinch) RED test — the `Core.full_playout` binding entry.

`arbitration.rs::full_playout` (ai_planner.gd:1338-1417) is the cheap greedy
continuation judge — play ONE candidate from a state to game end under
`policy_step` on both sides and report the arena verdict. It was reachable in
Python only THROUGH the whole search (`plan_with_rollout`); this test pins the
direct entry `core.full_playout(state, action, player, sig)`.

RED TODAY: `Core` has no `full_playout`, so the first call raises
`AttributeError` — the red arm. GREEN once the binding lands: the same call
returns the arena verdict dict, and the same `sig` is deterministic.

The verdict is a golden candidate for the crate's own `full_playout`; pinning
the exact winner for `SIG` is a follow-up for whoever can build the wheel (this
lane cannot; the fix is handed to the lead as a patch).
"""

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
LISTS = Path(os.path.expanduser(os.environ.get("NML_AI_LISTS_DIR", "")))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
#: the fast trainer's knobs (`test_cands_scores.py`'s arms) — one cheap game.
FAST = {"top_k": 2, "horizon": 1}
SEED = 27
SIG = 12345


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_full_playout_plays_a_fixture_state_to_the_arena_verdict(monkeypatch):
    monkeypatch.setattr(sp, "ROUNDS", 1)
    core = nml_core.load(str(REPO))
    cap: dict = {}
    real = sp._pick_for

    def seen(c, state, player, *a, **kw):
        pick = real(c, state, player, *a, **kw)
        if pick.get("used") and "capture" not in cap:
            cap["capture"] = {"plain": state.plain(), "action": pick["action"], "player": int(player)}
        return pick

    monkeypatch.setattr(sp, "_pick_for", seen)
    sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    assert "capture" in cap, "the smoke game recorded no activation — the gate proves nothing"

    c = cap["capture"]
    state = core.state_of(c["plain"])
    first = core.full_playout(state, c["action"], c["player"], SIG)
    again = core.full_playout(state, c["action"], c["player"], SIG)

    assert first == again, "the same sig must give the same playout (determinism)"
    for key in ("p1", "p2", "vp", "objectives", "survivors", "rounds_played", "winner"):
        assert key in first, "full_playout omitted %r" % key
    assert first["winner"] in ("p1", "p2", "draw")
    assert isinstance(first["vp"], list) and len(first["vp"]) == 2
    assert isinstance(first["objectives"], list) and len(first["objectives"]) == 3
    assert isinstance(first["survivors"], list) and len(first["survivors"]) == 2
    assert isinstance(first["rounds_played"], int) and first["rounds_played"] >= 0
