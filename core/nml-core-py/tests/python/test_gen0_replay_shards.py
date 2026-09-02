"""DESIGN_gen0_training §5 step 4 — the shard runner, red-green on 3 games.

Three claims, each provable to fail:

  * a shard's content matches the corpus it was built from — same position
    count per game, same label index per position, in order;
  * a rerun over a directory whose shard is already complete launches zero
    workers (resumability is "the files exist", nothing softer);
  * a shard whose final files are incomplete (a stand-in for a killed run,
    since actually killing a worker mid-write is not a deterministic test)
    is fully rewritten on rerun, not left half-done.

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
    want_counts = [len(json.loads((CORPUS / g).read_text())["planner_positions"]) for g in GAMES]
    assert [g["positions"] for g in index["games"]] == want_counts, index
    assert [g["divergence"] for g in index["games"]] == ["", "", ""], index
    assert arrays["label"].shape[0] == sum(want_counts) == index["positions"]
    want_labels = [row["cands"]["best"] for g in GAMES
                   for row in json.loads((CORPUS / g).read_text())["planner_positions"]]
    assert arrays["label"].tolist() == want_labels


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
