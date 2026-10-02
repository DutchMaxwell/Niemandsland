"""`play_game(search_seeds={seat: seed})`: one `nml_core.Rng` per seat feeds that
seat's TREE searches their `sig` — two `randi_range(0, 2**31 - 1)` draws per
decision, sig = (hi << 31 | lo) + 1 — and each of its rows carries
`search: {seed, counter}`. A one-ply seat never receives a sig and its rows carry
no `search`. RED: with the tree check in `_search_sig` removed, seat 2 gets sigs."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import selfplay as sp  # noqa: E402

from test_search_depth import ARMY1, ARMY2, BANK_DIR, FAST, REPO, SEED, _lists_missing  # noqa: E402

needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")


def _play():
    """Seat 1 = a small tree, seat 2 = one-ply; every `_pick_for` call as (player, sig, landed)."""
    real, calls = sp._pick_for, []

    def spy(core, state, player, *a, **k):
        pick = real(core, state, player, *a, **k)
        calls.append((player, k.get("sig"), bool(pick)))
        return pick

    with sp.forced_picks(spy):
        r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, nml_core.load(str(REPO)), deep_player=1,
                         deep_search_mode="tree", deep_tree_budget=16, deep_top_k=2, deep_horizon=1,
                         search_seeds={1: 5, 2: 6}, **FAST, **sp.LEGACY_FIDELITY_KNOBS)
    return r, calls


def _stream(seed: int, n: int) -> list[int]:
    rng = nml_core.Rng(seed)
    return [((rng.randi_range(0, 2147483647) << 31) | rng.randi_range(0, 2147483647)) + 1 for _ in range(n)]


@needs_lists
def test_the_tree_seat_draws_its_own_stream_and_logs_it():
    r, calls = _play()
    landed = [sig for player, sig, ok in calls if player == 1 and ok]
    assert landed and landed == _stream(5, len(landed))
    rows = [row for row in r["planner_positions"] if row["side"] == 1]
    assert [row["search"] for row in rows] == [{"seed": 5, "counter": k} for k in range(len(rows))]


@needs_lists
def test_a_one_ply_seat_never_receives_a_sig():
    r, calls = _play()
    assert all(sig is None for player, sig, _ in calls if player == 2)
    assert not any("search" in row for row in r["planner_positions"] if row["side"] == 2)


@needs_lists
def test_the_same_seeds_twice_are_byte_identical():
    assert sp.result_digest(_play()[0]) == sp.result_digest(_play()[0])
