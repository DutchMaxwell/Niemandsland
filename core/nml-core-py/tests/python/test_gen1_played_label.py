"""Gen-1 recorder fix — RED/GREEN for `row["cands"]["played"]`.

FINDING (verified by hand against the pre-fix tree, exact commands in the
PR body): `row["action"]` is the act ACTUALLY PLAYED — after a
`pool_value_fn` re-rank (PR #627, `selfplay._pick_for`) swaps a different
candidate in — but `row["cands"]["best"]` is the HAND planner's own argmax,
which the re-rank never moves. The two part company at every re-ranked
position; `row["cands"]["best"]`'s own comment ("at eps=0 the played
candidate") was only ever true at `pool_value_fn=None`. Two consumers read
`best` as if it always named the played act:

  * `gen0_replay_one.forced_pick` forced `best`, so a value-player record
    diverged at the FIRST re-ranked position (the replay played a candidate
    the search never actually chose, and the state stopped matching the
    recording's own next state);
  * `gen0_replay_shards.export` passed `best` into `Core.policy_tokens` as
    the training LABEL, so a Gen-1 corpus would teach the hand's picks, not
    the promoted player's.

The fix: `_pick_for` now stamps `played_idx` on every pick (the hand argmax
by default, the re-ranked candidate's index once a `pool_value_fn` swap
lands), `play_game` carries it as `row["cands"]["played"]`, and both
consumers read `played` (falling back to `best` on a record from before the
key existed, where the two were always equal).

Three claims below, each provable to fail on the pre-fix tree — proven by
hand (not re-derivable here without reverting the source: a record built
through today's `play_game` already carries `played`, so exercising the
OLD `forced_pick`/`export` against it needs the OLD tool code, not a fixture
this file can toggle):

  (i)   a record with a re-ranked position replays EXACTLY through
        `gen0_replay_one.replay()` — RED on the pre-fix `forced_pick`
        (forces `best` unconditionally): diverges at seq 0, the very first
        re-ranked row (measured: `compared=1, matched=0, "menu width 40,
        recorded 50"`);
  (ii)  exporting that same record through `gen0_replay_shards` labels
        every row `cands["played"]`, never `cands["best"]` (they differ at
        17 of 47 rows in the fixture below — issue #635's `melee_reach`
        defaulting to "table" for a fresh `play_game()` shortened this
        fixture from 50 to 47 rows; re-measured, replay still matches
        exactly, `divergence == ""`);
  (iii) an OLD Gen-0 record (predating `played`) still replays 100% and
        exports the byte-identical shard it always did — measured by hand,
        sha256 `1168e0f76dbf8795b91a1694e081e76ee6353e094e9d7605e6afb0e350
        d993e0` for `gen0_shard_00000.npz` over the 3-game sample below,
        BOTH before and after this fix.

(i)/(ii) need only the terrain bank and the local `ai_lists` mirror (the
same `needs_fixtures` gate `test_narrator_shipped_knobs.py` uses); (iii)
additionally needs the 3-game Gen-0 corpus sample the rest of this
directory's replay tests use.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import gen0_replay_one as gr  # noqa: E402
import selfplay  # noqa: E402

SHARDS_TOOL = str(Path(__file__).resolve().parents[2] / "tools" / "gen0_replay_shards.py")
BANK = Path(gr.BANK)
LISTS = Path(gr.LISTS)
P1 = LISTS / "change_disciples_1000.json"
P2 = LISTS / "robot_legions_1000.json"
CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
OLD_GAMES = ["gen0_s10000_d10000.json", "gen0_s10000_d11000.json", "gen0_s10000_d12000.json"]
OLD_SHARD_SHA256 = "1168e0f76dbf8795b91a1694e081e76ee6353e094e9d7605e6afb0e350d993e0"

needs_fixtures = pytest.mark.skipif(
    not (BANK.is_dir() and P1.exists() and P2.exists()),
    reason="terrain bank or the 1000-pt ai_lists mirror absent",
)
needs_corpus = pytest.mark.skipif(
    not (BANK.is_dir() and LISTS.is_dir() and all((CORPUS / g).exists() for g in OLD_GAMES)),
    reason="Gen-0 corpus not on this box",
)


def _invert_hook(core, state, cands, pool_idx, rs, side):
    """The R2 seam from PR #627 (`pool_value_fn`), armed at `w=inf` (net-only
    blend): naming `-rs[j]` for every pooled candidate makes the seat play
    its WORST hand-rollout row instead of the search's own best — a re-rank
    at every activation whose pool holds more than one distinct value."""
    return [-r for r in rs]


def _build_reranked_record(out_dir: Path) -> Path:
    """One fixed-seed game, shipped knobs (`play_game`'s own bare defaults
    bar `dice`/`deployment`), `top_k=2 horizon=1`, side 1 re-ranked by
    `_invert_hook` — measured: 17 of its 47 rows land `best != played`,
    including the very first (seq 0). Re-measured for issue #635: `play_game`'s
    own bare defaults now include `melee_reach="table"`, which shortened this
    fixture from 50 to 47 rows (replay still reproduces it exactly)."""
    out = selfplay.play_game(
        4242, str(P1), str(P2), gr.REPO, str(BANK), None,
        dice_seed=4242, dice="table", deployment="arena",
        top_k=2, horizon=1, record_cands=True, record_aux=False,
        pool_value_fn={1: _invert_hook}, pool_value_w=math.inf,
    )
    rows = out["planner_positions"]
    assert any(r["cands"]["best"] != r["cands"]["played"] for r in rows), \
        "the crafted hook produced no re-rank at all -- test premise broke"
    # `record_aux=False`: `gen0_replay_shards.replay_game()` still refuses
    # `record_aux=True` (out of scope here, see `test_gen0_replay_one.py`'s
    # own dedicated acceptance test for `gen0_replay_one.replay()`), and the
    # played/best label is independent of the AUX targets either way.
    #
    # `gen0_replay_one.replay()`/`gen0_replay_shards.replay_game()` both read
    # `prescreen.knobs` (the corpus batch driver's own wrapper), not the raw
    # `play_game()` result's top-level `knobs` -- `record_cands`/`record_aux`
    # never ride that top-level dict at all, so they are added here.
    out["prescreen"] = {"knobs": dict(out["knobs"], record_cands=True, record_aux=False)}
    path = out_dir / "gen0_s4242_d4242.json"
    path.write_text(json.dumps(out), encoding="utf-8")
    return path


@needs_fixtures
def test_a_reranked_record_replays_exactly_through_gen0_replay_one(tmp_path):
    """GREEN: forcing `played` (falling back to `best` only where absent)
    reproduces the whole game menu for menu, matched == recorded. RED on the
    pre-fix `forced_pick` (forces `best` unconditionally) was measured by
    hand: `compared=1, matched=0, divergence="seq 0 (round 1, side 2): menu
    width 40, recorded 50"` -- it never gets past the very first activation
    once the wrong act at seq 0 changes the state."""
    path = _build_reranked_record(tmp_path)
    res = gr.replay(str(path), str(LISTS), 0)
    assert res["divergence"] == "", res
    # 47, not 50 — issue #635 (`melee_reach` now defaults to "table" for a
    # fresh `play_game()`) shortened this fixture; re-measured, replay still
    # matches exactly, which is the whole point of this assertion.
    assert res["matched"] == res["recorded"] == res["compared"] == 47, res


@needs_fixtures
def test_export_of_a_reranked_record_labels_played_not_best(tmp_path):
    """GREEN: the shard exporter's label matches `cands["played"]` at every
    row -- including the 17 where that is NOT `cands["best"]` -- and the
    shard meta says every row used the `played` label kind."""
    corpus_dir = tmp_path / "corpus"
    corpus_dir.mkdir()
    rec_path = _build_reranked_record(corpus_dir)
    rec = json.loads(rec_path.read_text(encoding="utf-8"))
    rows = rec["planner_positions"]
    out_dir = tmp_path / "shards"
    p = subprocess.run(
        [sys.executable, SHARDS_TOOL, str(corpus_dir), "--lists", str(LISTS),
         "--limit", "1", "--shard-size", "1", "--workers", "1", "--out", str(out_dir)],
        capture_output=True, text=True,
    )
    assert p.returncode == 0, p.stdout + p.stderr
    index = json.loads((out_dir / "gen0_shard_00000.json").read_text())
    assert index["games"][0]["divergence"] == "", index
    # 47, not 50 — see `_build_reranked_record`'s docstring (issue #635).
    assert index["positions"] == len(rows) == index["games"][0]["recorded"] == 47
    # Every row carries `played` (record_cands=True end to end) -- the shard
    # meta's own bookkeeping says so, and it must agree with the array.
    assert index["label_kinds"] == {"played": len(rows), "best": 0}, index
    want_played = [r["cands"]["played"] for r in rows]
    want_best = [r["cands"]["best"] for r in rows]
    assert want_played != want_best, "fixture regression: no row differs any more"
    arrays = np.load(out_dir / "gen0_shard_00000.npz")
    assert arrays["label"].tolist() == want_played
    assert arrays["label"].tolist() != want_best


@needs_corpus
def test_old_gen0_records_still_replay_100pct_and_export_identical_labels(tmp_path):
    """Old Gen-0 rows carry no `cands["played"]` at all -- `export()`'s new
    played-or-best fallback must be a byte-for-byte no-op there. `sha256`
    over the packed shard is the strongest form of that claim: it was
    MEASURED identical both on the pre-fix tree and on this one (see the PR
    body for the exact before/after commands)."""
    recs = [json.loads((CORPUS / g).read_text(encoding="utf-8")) for g in OLD_GAMES]
    assert all("played" not in row["cands"] for r in recs for row in r["planner_positions"])
    out_dir = tmp_path / "shards"
    p = subprocess.run(
        [sys.executable, SHARDS_TOOL, str(CORPUS), "--lists", str(LISTS),
         "--limit", "3", "--shard-size", "3", "--workers", "1", "--out", str(out_dir)],
        capture_output=True, text=True,
    )
    assert p.returncode == 0, p.stdout + p.stderr
    index = json.loads((out_dir / "gen0_shard_00000.json").read_text())
    assert [g["divergence"] for g in index["games"]] == [""] * len(OLD_GAMES), index
    want_counts = [len(r["planner_positions"]) for r in recs]
    assert index["positions"] == sum(want_counts)
    assert index["label_kinds"] == {"played": 0, "best": sum(want_counts)}, index
    want_labels = [row["cands"]["best"] for r in recs for row in r["planner_positions"]]
    arrays = np.load(out_dir / "gen0_shard_00000.npz")
    assert arrays["label"].tolist() == want_labels
    got_hash = hashlib.sha256((out_dir / "gen0_shard_00000.npz").read_bytes()).hexdigest()
    assert got_hash == OLD_SHARD_SHA256, "shard bytes moved for a record with no `played` key: %s" % got_hash
