"""tools(replay): the record's own `rules_epoch` stamp (the Part B half of
the Gen-2 replay-gap fix; see `test_gen0_replay_one.py`'s `replay_knobs`
tests for Part A, the replay side).

Root cause: `rules_epoch` (external review 03.09. item 3 / F9) rode ONLY
`core.set_header`'s internal knobs dict (consumed by the crate) — never the
RESULT's own `knobs` dict a recorder can read back to summarise what it
played. A Gen-2 recorder building `prescreen.knobs` from that dict therefore
had nothing to copy, and stamped the epoch as a sibling key instead
(`prescreen.rules_epoch`), which `gen0_replay_one.replay_knobs` now falls
back to.

`record_cands` is the gate (`core_commit`'s own idiom, NML-1147a pattern): a
non-recording call stays the exact object it always was, `result_digest`
included — this file's default-call test proves that side too."""

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
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "blessed_sisters_1000.json"
FAST = {"top_k": 2, "horizon": 1}
SEED = 27


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")


@needs_lists
def test_a_default_call_stamps_no_rules_epoch_key():
    """`record_cands=False` (the default) must reproduce today's game
    byte-for-byte — no new key on `knobs`, so `result_digest` does not move
    for every existing gate and A/B tool that never asked to record."""
    core = nml_core.load(str(REPO))
    res = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    assert "rules_epoch" not in res["knobs"]


@needs_lists
def test_record_cands_stamps_the_epoch_actually_used():
    """The default epoch (`nml_core.CURRENT_RULES_EPOCH`) and an explicit
    legacy pin (`0`) both land in `res["knobs"]["rules_epoch"]` unchanged —
    the value stamped is the one `play_game` actually played the game at,
    not a constant."""
    core = nml_core.load(str(REPO))
    default = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                            record_cands=True, **FAST)
    assert default["knobs"]["rules_epoch"] == nml_core.CURRENT_RULES_EPOCH

    legacy = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                           record_cands=True, rules_epoch=0, **FAST)
    assert legacy["knobs"]["rules_epoch"] == 0
