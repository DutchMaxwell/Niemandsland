"""A 63-bit game seed must play. Hashed seed registries draw 1 + sha256 mod (2**63 - 1); the per-activation streams
derived as `seed * STRIDE + seq` (explore, playout cap, the pair and fork sidecars) wrap into the 64-bit range the
core's Rng takes. Every seed below 2**63 / stride derives exactly as before, so recorded digests stay byte-identical
(test_parity is the gate for that). RED: without the wrap play_game raises OverflowError ('explore_seed') on the
first pick."""

from __future__ import annotations

import os
import shutil
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
    not ((BANK_DIR / "board_29.json").exists() and ARMY1.exists() and ARMY2.exists()),
    reason="needs the terrain bank + 1000pt lists")
BIG = 8099187357376372864  # a registry-sized seed: 63 bits


def test_derived_seeds_are_unchanged_below_the_wrap_and_wrap_above_it():
    small = 27 * sp.EXPLORE_SEED_STRIDE + 5
    assert sp._derived(small) == small
    big = BIG * sp.EXPLORE_SEED_STRIDE + 5
    assert big >= 2 ** 63 and sp._derived(big) == big % 2 ** 63 and 0 <= sp._derived(big) < 2 ** 63


@needs_lists
def test_a_63_bit_game_seed_plays_with_its_sidecars(tmp_path):
    shutil.copy(BANK_DIR / "board_29.json", tmp_path / ("board_%d.json" % BIG))
    res = sp.play_game(BIG, ARMY1, ARMY2, REPO, tmp_path, nml_core.load(str(REPO)), top_k=2, horizon=1, dice="table")
    assert res["winner"] in ("p1", "p2", "draw")
