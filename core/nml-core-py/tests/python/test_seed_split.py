"""The seed split on `play_game`: `layout_seed` (marker layout), `deploy_seed`
(roll-off + deployment) and `play_seed` (the game stream from round 1). None =
`seed`, today's game. Varying ONE of them moves only its own consumer, read by spies:
the layout positions, the deployment positions + opener (`capture`, `_play_round`)
and the game generator's state entering round 1.
RED: with `deploy_seed` ignored (`drng, dep = rng, seed`) the deploy row fails."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

from test_search_depth import (  # noqa: E402
    ARMY1, ARMY2, BANK_DIR, FAST, REPO, SEED, SEED_27_FAST_DIGEST, _lists_missing,
)

needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
SPLIT = {"layout_seed": 11, "deploy_seed": 12, "play_seed": 13}
CAPTURE, PLAY_ROUND = sp.capture, sp._play_round


def _consumers(monkeypatch, **kw):
    """(layout positions, (deployment positions, opener), game rng state at round 1), digest."""
    seen = {}

    def capture(units, positions, *a, **k):
        seen.setdefault("positions", positions)
        return CAPTURE(units, positions, *a, **k)

    def play_round(core, state, opener, rng, *a, **k):
        seen.setdefault("opener", opener)
        seen.setdefault("play", rng.state)
        return PLAY_ROUND(core, state, opener, rng, *a, **k)

    monkeypatch.setattr(sp, "capture", capture)
    monkeypatch.setattr(sp, "_play_round", play_round)
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)), objectives="rulebook",
                     **FAST, **sp.LEGACY_FIDELITY_KNOBS, **kw)
    layout = r["mission"]["objectives_layout"]["positions"]
    return (layout, (seen["positions"], seen["opener"]), seen["play"]), sp.result_digest(r)


@needs_lists
def test_unset_seeds_are_todays_game():
    core = nml_core.load(str(REPO))
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, layout_seed=None, deploy_seed=None,
                     play_seed=None, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    assert sp.result_digest(r) == SEED_27_FAST_DIGEST


@needs_lists
@pytest.mark.parametrize("which", [0, 1, 2])
def test_each_seed_moves_only_its_consumer(monkeypatch, which):
    base, _ = _consumers(monkeypatch, **SPLIT)
    key = list(SPLIT)[which]
    moved, _ = _consumers(monkeypatch, **dict(SPLIT, **{key: 99}))
    assert [b != m for b, m in zip(base, moved)] == [i == which for i in range(3)], key


@needs_lists
def test_the_same_split_twice_is_byte_identical(monkeypatch):
    assert _consumers(monkeypatch, **SPLIT) == _consumers(monkeypatch, **SPLIT)
