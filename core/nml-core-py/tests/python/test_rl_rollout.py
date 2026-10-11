"""RL rollout recorder (RL rollout plan, PR 1 — `core/nml-core-py/tools/rl_rollout.py`).

One full game with BOTH seats on the current policy: the recorder rides `play_game`'s
`cand_logits_fn` + `policy_mode="order"` seam for the menu and plays the SAMPLED candidate (the
pure override pattern), one token row per decision plus the RL columns. The proofs:

  * STUB POLICY: a deterministic stub (all mass on menu index 0) plays index 0 at every decision,
    so `logp = log softmax(logits / temp)[a]` is exactly 0 and `played_idx` is 0 — the sampled
    index is what got played, never the hand search's own pick;
  * OUTCOME: the npz's per-row `outcome` is `teacher_record.pack(rows, winner)`'s own mapping
    (+1 the winner's rows, -1 the loser's, 0 a draw) on the SAME seed;
  * IDENTITY: the recorder runs only when invoked — a plain game played after a recorded one is
    byte-identical to a plain game played before it, and `selfplay._pick_for` is restored.

  RED before the tool exists: the import fails (`No module named 'rl_rollout'`).
Skipped without the private terrain bank; the armies are the in-repo 1000-pt fixture lists.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("onnxruntime")
import nml_core  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(REPO / "tools"))
import lab2_net  # noqa: E402
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


def cfg(out, **over):
    c = {"repo": str(REPO), "bank": str(BANK), "out": str(out), "seed": 27, "row_id": "rl1",
         "army1": str(ARMY1), "army2": str(ARMY2), "temp": 1.0, "policy": stub_policy,
         "policy_sha256": "stub-policy", "value_net": lab2_net.ShippedNet(str(REPO)), **FAST}
    c.update(over)
    return c


@needs_bank
def test_stub_policy_plays_the_sample_and_packs_the_outcome(tmp_path):
    w = rl._init(cfg(tmp_path))
    res, rows = rl.play(w)
    assert rows, "no decision captured"
    assert all(int(r["played_idx"]) == 0 for r in rows)
    assert all(float(r["logp"]) == 0.0 for r in rows)
    rl.write(w, res, rows)
    z, meta = np.load(tmp_path / "rl1.npz"), json.load(open(tmp_path / "rl1.json"))
    assert meta["schema"] == "rl-rollout/1" and meta["rows"] == len(rows) == len(z["outcome"])
    assert meta["policy_sha256"] == "stub-policy" and meta["temp"] == 1.0 and meta["winner"] == res["winner"]
    assert np.array_equal(z["played_idx"], np.array([r["played_idx"] for r in rows]))
    assert np.array_equal(z["logp"], np.array([r["logp"] for r in rows]))
    for k in ("logp", "v", "temp", "played_idx"):
        assert z[k].shape == (len(rows),)
    assert np.all(np.isfinite(z["v"]))
    win, side = meta["winner"], z["side"]
    expected = np.where(win == "draw", 0, np.where(side == (1 if win == "p1" else 2), 1, -1))
    assert np.array_equal(z["outcome"], expected)
    assert np.array_equal(z["outcome"], tr.pack(rows, win)["outcome"])


@needs_bank
def test_recorder_is_inert_until_invoked(tmp_path):
    before = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, nml_core.load(str(REPO)), **FAST)
    real_pick = sp._pick_for
    assert rl._work(rl._init(cfg(tmp_path)))["rows"] > 0
    assert sp._pick_for is real_pick
    after = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, nml_core.load(str(REPO)), **FAST)
    assert sp.result_digest(before) == sp.result_digest(after)
