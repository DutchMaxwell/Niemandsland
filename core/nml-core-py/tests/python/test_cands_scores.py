"""Gen-1 recorder fix — the per-candidate scores `record_cands` used to drop.

The Gen-0 recorder wrote `row["cands"] = {"list": [...], "best": idx}` and
threw away the per-candidate scores the planner trace had already computed
(`trace.scored`'s hand prior, `trace.rs`'s rollout values) — a teacher corpus
that cannot see WHAT each unpicked candidate was worth. The fix keeps them as
arrays PARALLEL to `cands.list`: entry i of each array describes
`cands.list[i]` (`scored` covers every built candidate, `rs` is None where
the pool never rolled one), and the game header stamps `core_commit`, the
short sha of the checkout the core was built from.

RED-GREEN CONTRACT: remove the `"scored"`/`"rs"` construction from the
recorder's row build (selfplay.py `_play_round`, the `record_cands` branch)
or the `core_commit` header stamp, and this test FAILS — the numeric score
assertions and the header assertion below are the red arms.
"""

from __future__ import annotations

import math
import os
import re
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
#: the fast trainer's own knobs (`test_trace_cands.py`'s arms) — the only
#: game this smoke test runs, so its rows stay comparable with that suite's.
FAST = {"top_k": 2, "horizon": 1}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_record_cands_keeps_scores_and_stamps_core_commit(monkeypatch):
    """One 1-round smoke game with `record_cands=True`: every candidate's
    score fields survive into the row (parallel arrays), and the header says
    which core build recorded it."""
    monkeypatch.setattr(sp, "ROUNDS", 1)
    core = nml_core.load(str(REPO))
    res = sp.play_game(
        27, ARMY1, ARMY2, REPO, BANK_DIR, core, record_cands=True, **FAST
    )
    rows = res["planner_positions"]
    assert rows, "the smoke game recorded no activations — the gate proves nothing"
    checked = 0
    for row in rows:
        cands = row["cands"]
        n = len(cands["list"])
        assert n > 0, "row seq %d: an empty candidate menu" % row["seq"]
        assert len(cands["scored"]) == n, (
            "row seq %d: cands.scored is not parallel to cands.list" % row["seq"]
        )
        assert len(cands["rs"]) == n, (
            "row seq %d: cands.rs is not parallel to cands.list" % row["seq"]
        )
        for i, s in enumerate(cands["scored"]):
            assert (
                isinstance(s, (int, float)) and not isinstance(s, bool)
                and math.isfinite(s)
            ), "row seq %d: candidate %d carries no numeric hand prior score" % (
                row["seq"], i,
            )
            checked += 1
        for i, r in enumerate(cands["rs"]):
            assert r is None or (
                isinstance(r, (int, float)) and not isinstance(r, bool)
                and math.isfinite(r)
            ), "row seq %d: candidate %d's rollout value is neither numeric nor None" % (
                row["seq"], i,
            )
        # `scored` is the JOIN carrier too: the argmax's build index points
        # into the same indexing the score array sits on.
        assert 0 <= cands["best"] < n
        assert isinstance(cands["scored"][cands["best"]], (int, float))
    assert checked > 0, "no candidate score was ever asserted — the gate proves nothing"
    commit = res.get("core_commit")
    assert isinstance(commit, str) and re.fullmatch(r"[0-9a-f]{7,40}", commit), (
        "the header carries no core build identity (core_commit %r)" % (commit,)
    )
