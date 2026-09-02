"""DESIGN_gen0_training §8.6 step 4' — the shard runner, red-green on 3 games.

Four claims, each provable to fail:

  * a shard's content matches the corpus it was built from — same position
    count per game, same label index per position, in order, and the packed
    `cands_ptr` segment length per position equals the recorded menu length
    (SHARD_SCHEMA.md: masks are deliberately not stored, so this is their
    packed-format equivalent);
  * a rerun over a directory whose shard is already complete launches zero
    workers (resumability is "the files exist", nothing softer);
  * a shard whose final files are incomplete (a stand-in for a killed run,
    since actually killing a worker mid-write is not a deterministic test)
    is fully rewritten on rerun, not left half-done;
  * the replay-fidelity tripwire (a corrupted `cands.best`, PR #564's own
    proof) discards that game's rows and names the divergence, without
    raising past `replay_game`.

Skipped where the corpus, army lists or a `.forge/site` wheel are absent —
same gate `test_gen0_replay_one.py` uses, so this runs wherever that does.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import gen0_replay_one as gr  # noqa: E402

TOOL = str(Path(__file__).resolve().parents[2] / "tools" / "gen0_replay_shards.py")
CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(gr.LISTS)
GAMES = ["gen0_s10000_d10000.json", "gen0_s10000_d11000.json", "gen0_s10000_d12000.json"]


def _corpus_missing() -> bool:
    return not (BANK.is_dir() and LISTS.is_dir()
                and all((CORPUS / g).exists() for g in GAMES))


needs_corpus = pytest.mark.skipif(_corpus_missing(), reason="Gen-0 corpus not on this box")


def _run(out_dir: Path, *extra: str) -> tuple[int, str]:
    p = subprocess.run([sys.executable, TOOL, str(CORPUS), "--limit", "3", "--shard-size", "3",
                        "--workers", "3", "--out", str(out_dir), *extra],
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


@needs_corpus
def test_shard_matches_corpus_positions_and_label_indices(tmp_path):
    code, out = _run(tmp_path)
    assert code == 0, out
    index = json.loads((tmp_path / "gen0_shard_00000.json").read_text())
    arrays = np.load(tmp_path / "gen0_shard_00000.npz")
    recs = [json.loads((CORPUS / g).read_text()) for g in GAMES]
    want_counts = [len(r["planner_positions"]) for r in recs]
    assert [g["positions"] for g in index["games"]] == want_counts, index
    assert [g["divergence"] for g in index["games"]] == ["", "", ""], index
    assert arrays["label"].shape[0] == sum(want_counts) == index["positions"]
    want_labels = [row["cands"]["best"] for r in recs for row in r["planner_positions"]]
    assert arrays["label"].tolist() == want_labels
    # SHARD_SCHEMA.md: masks are not stored — cands_ptr's segment widths are
    # their packed-format equivalent, and must equal the recorded menu width.
    want_menu_lens = [len(row["cands"]["list"]) for r in recs for row in r["planner_positions"]]
    ptr = arrays["cands_ptr"]
    assert (ptr[1:] - ptr[:-1]).tolist() == want_menu_lens
    # Every position carries all 18 recorded terrain pieces (the bank's own
    # Terrain::sandbox() is empty — terrain comes from the record instead,
    # see terrain_rows()) — never 0, the gap this run replaces.
    tp = arrays["terr_ptr"]
    assert set((tp[1:] - tp[:-1]).tolist()) == {18}


def test_terrain_rows_matches_hand_computation_for_a_known_forest_piece():
    """The RED for `terrain_rows()` itself: a synthetic piece, by-hand math,
    reproducing tokens.rs's `terrain_token` column for column (PR #584)."""
    import math

    import gen0_replay_shards as grs

    piece = [2, 12.0, -6.0, 6.0, 9.0, 90.0]  # FOREST, 6x9in, centre (12,-6)in, 90 deg
    got = grs.terrain_rows([piece], side=1)[0].tolist()
    yaw = math.radians(90.0)
    want = [12.0 / 30.0, -6.0 / 30.0, 3.0 / 12.0, 4.5 / 12.0, math.cos(yaw), math.sin(yaw),
            0.0, 1.0, 0.0, 0.0, 1.0, 1.0]
    assert got == pytest.approx(want, abs=2e-3)  # f16 rounding
    mirrored = grs.terrain_rows([piece], side=2)[0]
    assert mirrored[0] == pytest.approx(-12.0 / 30.0, abs=2e-3)
    assert mirrored[1] == pytest.approx(6.0 / 30.0, abs=2e-3)


@needs_corpus
def test_a_replay_divergence_is_skipped_and_counted_not_written(tmp_path):
    """PR #564's own RED, at this runner's level: a shifted `cands.best` on a
    COPY must diverge, contribute zero rows, and name the divergence — never
    raise out of `replay_game`, since one bad game must not sink a shard."""
    import gen0_replay_shards as grs
    rec = json.loads((CORPUS / GAMES[0]).read_text())
    row = rec["planner_positions"][5]["cands"]
    row["best"] = (row["best"] + 1) % len(row["list"])
    bad = tmp_path / GAMES[0]
    bad.write_text(json.dumps(rec))
    rows, meta = grs.replay_game(str(bad), str(LISTS))
    assert rows == [], meta
    assert meta["divergence"], meta


@needs_corpus
def test_rerun_over_a_finished_dir_launches_zero_workers(tmp_path):
    code1, out1 = _run(tmp_path)
    assert code1 == 0 and "0 already done, 1 to run -> 1 workers" in out1, out1
    code2, out2 = _run(tmp_path)
    assert code2 == 0, out2
    assert "1 already done, 0 to run -> 0 workers" in out2, out2


@needs_corpus
def test_a_truncated_shard_is_rewritten_on_rerun(tmp_path):
    _run(tmp_path)
    npz_p, json_p = tmp_path / "gen0_shard_00000.npz", tmp_path / "gen0_shard_00000.json"
    json_p.unlink()  # stands in for a run killed after the .npz landed but before the index did
    mtime_before = npz_p.stat().st_mtime_ns
    code, out = _run(tmp_path)
    assert code == 0 and "-> 1 workers" in out, out
    assert json_p.exists()
    assert npz_p.stat().st_mtime_ns > mtime_before
