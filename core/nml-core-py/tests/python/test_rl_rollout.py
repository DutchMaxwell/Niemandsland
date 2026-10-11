"""RL rollout recorder (RL rollout plan, PR 1 part 1 — `core/nml-core-py/tools/rl_rollout.py`).

One full game with BOTH seats on the current policy: the recorder rides `play_game`'s
`cand_logits_fn` + `policy_mode="order"` seam for the menu and plays the SAMPLED candidate (the
pure override pattern), one in-memory token row per decision plus the RL columns. The proofs:

  * STUB POLICY: a deterministic stub (all mass on menu index 0) plays index 0 at every decision,
    so `logp = log softmax(logits / temp)[a]` is exactly 0 and `played_idx` is 0 — the sampled
    index is what got played, never the hand search's own pick;
  * OUTCOME: `packed(...)`'s per-row `outcome` is `teacher_record.pack(rows, winner)`'s own
    mapping (+1 the winner's rows, -1 the loser's, 0 a draw) on the SAME seed;
  * IDENTITY: the recorder runs only when invoked — a plain game played after a recorded one is
    byte-identical to a plain game played before it, and `selfplay._pick_for` is restored.

  RED before the tool exists: the import fails (`No module named 'rl_rollout'`).
Skipped without the private terrain bank; the armies are the in-repo 1000-pt fixture lists.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
import pytest

import nml_core  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import selfplay as sp  # noqa: E402
import teacher_record as tr  # noqa: E402
import rl_rollout as rl  # noqa: E402

BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
ARMY1 = REPO / "test" / "fixtures" / "card_list_aof_beastmen_1000.json"
ARMY2 = REPO / "test" / "fixtures" / "card_list_gf_custodian_brothers_1000.json"
needs_bank = pytest.mark.skipif(not BANK.is_dir(), reason="private terrain bank not on this box")
FAST = {"top_k": 2, "horizon": 1}


def stub_policy(core, state, menu, side):
    """Deterministic: probability 1 on build index 0, so logp = log 1 = 0."""
    logits = np.full(len(menu), -np.inf)
    logits[0] = 0.0
    return logits


def cfg(**over):
    c = {"repo": str(REPO), "bank": str(BANK), "seed": 27, "row_id": "rl1",
         "army1": str(ARMY1), "army2": str(ARMY2), "temp": 1.0, "policy": stub_policy,
         "policy_sha256": "stub-policy", **FAST}
    c.update(over)
    return c


@needs_bank
def test_stub_policy_plays_the_sample_and_packs_the_outcome():
    res, rows = rl.play(rl._init(cfg()))
    assert rows, "no decision captured"
    assert all(int(r["played_idx"]) == 0 for r in rows)
    assert all(float(r["logp"]) == 0.0 for r in rows)
    z = rl.packed(res, rows)
    win, side = res["winner"], z["side"]
    expected = np.where(win == "draw", 0, np.where(side == (1 if win == "p1" else 2), 1, -1))
    assert np.array_equal(z["outcome"], expected)
    assert np.array_equal(z["outcome"], tr.pack(rows, win)["outcome"])
    for k in ("logp", "temp", "played_idx"):
        assert z[k].shape == (len(rows),)
    assert np.all(z["temp"] == np.float32(1.0))


@needs_bank
def test_recorder_is_inert_until_invoked():
    before = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, nml_core.load(str(REPO)), **FAST)
    real_pick = sp._pick_for
    res, rows = rl.play(rl._init(cfg()))
    assert rows
    assert sp._pick_for is real_pick
    after = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, nml_core.load(str(REPO)), **FAST)
    assert sp.result_digest(before) == sp.result_digest(after)
