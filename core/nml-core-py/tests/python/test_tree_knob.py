"""The per-seat TREE seam on `play_game` (tree plan step 10): `deep_search_mode`,
`deep_tree_*` and `deep_pool_wall_ms` join the deep seat's core header, following
`test_search_depth.py`. The tree operator itself is not wired into the search yet,
so these prove the seam (defaults byte-identical, seat stamp, same seed twice
identical, the Tray signature), not a different game."""

from __future__ import annotations

import os
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


def _play(**kw):
    """A deep seat that keeps the base pair (an unset `deep_top_k` resolves to
    the global default, not to the base, so the pair is named)."""
    core = nml_core.load(str(REPO))
    return sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, deep_top_k=2, deep_horizon=1,
                        **FAST, **sp.LEGACY_FIDELITY_KNOBS, **kw)


@needs_lists
def test_tree_defaults_are_byte_identical_and_unstamped():
    r = _play(deep_player=1, deep_search_mode="oneply", deep_tree_budget=128, deep_pool_wall_ms=0)
    assert sp.result_digest(r) == SEED_27_FAST_DIGEST
    assert "knobs_by_seat" not in r


@needs_lists
def test_tree_seat_parts_and_stamps_by_seat():
    r = _play(deep_player=2, deep_search_mode="tree", deep_tree_budget=64)
    assert r["knobs_by_seat"] == {
        "p1": {"top_k": 2, "horizon": 1},
        "p2": {"top_k": 2, "horizon": 1, "search_mode": "tree", "tree_budget": 64},
    }


@needs_lists
def test_a_deadline_stamps_its_seat_only_when_it_parts():
    assert "knobs_by_seat" not in _play(deep_player=1, deep_deadline_us=0)
    assert _play(deep_player=1, deep_search_mode="tree", deep_deadline_us=900)["knobs_by_seat"]["p1"] == {
        "top_k": 2, "horizon": 1, "search_mode": "tree", "deadline_us": 900}


@needs_lists
def test_the_same_seed_twice_is_byte_identical():
    a = _play(deep_player=2, deep_search_mode="tree")
    b = _play(deep_player=2, deep_search_mode="tree")
    assert sp.result_digest(a) == sp.result_digest(b)


@needs_lists
def test_tray_dice_plays_and_stamps():
    r = _play(deep_player=1, deep_search_mode="tree", deep_tree_dice="tray")
    assert r["knobs_by_seat"]["p1"]["tree_dice"] == "tray"
    assert "knobs_by_seat" in r and r["knobs_by_seat"]["p2"] == {"top_k": 2, "horizon": 1}


def test_a_tree_knob_without_a_deep_seat_is_refused():
    """The refusal comes before any list or terrain is read, so it needs neither (it runs in CI)."""
    missing = Path("/nonexistent/list.json")
    with pytest.raises(ValueError, match="deep_player"):
        sp.play_game(SEED, missing, missing, REPO, missing, None, deep_search_mode="tree", **FAST)
