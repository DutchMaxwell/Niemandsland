#!/usr/bin/env python3
"""Fixture tests for tools/arena_rescore.py.

The re-scorer exists because the historical sign test discards tied seed blocks
and emits no interval. These tests pin the arithmetic on synthetic arms with a
KNOWN effect (0 and +5 points), and demonstrate the failure mode directly: on a
fixed +5 arm the new CI contains the truth and excludes 50, while the old sign
test does not reject.

Run:  python3 -m pytest tools/arena_rescore_test.py
"""

import importlib.util
import json
import os
import random
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "arena_rescore", os.path.join(_HERE, "arena_rescore.py")
)
ar = importlib.util.module_from_spec(_SPEC)
sys.modules["arena_rescore"] = ar
_SPEC.loader.exec_module(ar)

NET = "token_value_v2"
OPP = "token_value_v1"


def _write_game(path, seed, dice, net_is_p1, score):
    """One arena record; score is from the NET's point of view."""
    if net_is_p1:
        grades = {"p1": NET, "p2": OPP}
        winner = "p1" if score == 1.0 else "p2" if score == 0.0 else "draw"
    else:
        grades = {"p1": OPP, "p2": NET}
        winner = "p2" if score == 1.0 else "p1" if score == 0.0 else "draw"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"seed": seed, "dice_seed": dice, "grades": grades,
                   "winner": winner}, fh)


def synth_run(tmp_path, pw, pd, K, seed, games_per_block=4):
    """K seed blocks x games_per_block, alternating net seat; deterministic RNG."""
    os.makedirs(tmp_path, exist_ok=True)
    rng = random.Random(seed)
    for i in range(K):
        for j in range(games_per_block):
            r = rng.random()
            score = 1.0 if r < pw else 0.5 if r < pw + pd else 0.0
            net_is_p1 = (j % 2 == 0)
            fn = (f"arena_{NET}_vs_{OPP}_s{1000 + i}_d{2000 + j}.json" if net_is_p1
                  else f"arena_{OPP}_vs_{NET}_s{1000 + i}_d{2000 + j}.json")
            _write_game(os.path.join(tmp_path, fn), 1000 + i, 2000 + j, net_is_p1, score)
    return str(tmp_path)


# ---------------------------------------------------------------------------
# RED: known +0 and known +5 arms
# ---------------------------------------------------------------------------
def test_known_zero_effect_ci_contains_50(tmp_path):
    d = synth_run(tmp_path, pw=0.3425, pd=0.315, K=60, seed=7)  # true score 50.0
    st = ar.block_stats(ar.load_run(d, net=NET)["blocks"])
    assert st["n"] == 240 and st["K"] == 60
    assert st["ci_lo"] < 0.5 < st["ci_hi"]          # truth inside the interval
    assert not st["ci_excludes_50"]
    assert st["sign_p"] > 0.05                       # old test agrees: null


def test_known_plus5_ci_contains_55_old_sign_test_misses(tmp_path):
    d = synth_run(tmp_path, pw=0.3925, pd=0.315, K=60, seed=7)  # true score 55.0
    st = ar.block_stats(ar.load_run(d, net=NET)["blocks"])
    assert st["ci_lo"] > 0.5                         # new statistic rejects the null
    assert st["ci_lo"] <= 0.55 <= st["ci_hi"]        # ... and brackets the truth
    assert st["sign_p"] > 0.05                       # the old sign test misses it


def test_old_sign_test_discards_ties_that_carry_signal(tmp_path):
    """A block that is 2W/2L reads exactly 0.5 and is dropped by the sign test."""
    d = tmp_path
    for i in range(40):
        for j, score in enumerate([1.0, 0.0, 1.0, 0.0]):
            _write_game(os.path.join(d, f"arena_{NET}_vs_{OPP}_s{50 + i}_d{60 + j}.json"),
                        50 + i, 60 + j, j % 2 == 0, score)
    st = ar.block_stats(ar.load_run(str(d), net=NET)["blocks"])
    assert st["sign_ties"] == 40                     # every tied block discarded
    assert st["sign_p"] == 1.0
    assert st["score"] == pytest.approx(0.5)         # the mean keeps the evidence


# ---------------------------------------------------------------------------
# Block construction
# ---------------------------------------------------------------------------
def test_seats_paired_within_block(tmp_path):
    d = synth_run(tmp_path, pw=0.35, pd=0.30, K=10, seed=3)
    run = ar.load_run(d, net=NET)
    assert len(run["blocks"]) == 10
    assert all(len(v) == 4 for v in run["blocks"].values())


def test_disjoint_seed_pool_has_no_collisions(tmp_path):
    a = synth_run(tmp_path / "a", pw=0.35, pd=0.30, K=20, seed=1)
    b = synth_run(tmp_path / "b", pw=0.35, pd=0.30, K=20, seed=2)
    # force disjoint seeds by shifting b's seeds via a fresh directory
    for f in os.listdir(b):
        os.remove(os.path.join(b, f))
    for i in range(20):
        for j in range(4):
            score = 1.0 if (i + j) % 2 == 0 else 0.5
            _write_game(os.path.join(b, f"arena_{NET}_vs_{OPP}_s{5000 + i}_d{6000 + j}.json"),
                        5000 + i, 6000 + j, j % 2 == 0, score)
    run = ar.load_run([a, b], net=NET)
    assert run["collisions"] == []
    assert len(run["blocks"]) == 40


def test_seed_collision_across_dirs_is_flagged(tmp_path):
    a = synth_run(tmp_path / "a", pw=0.35, pd=0.30, K=10, seed=1)
    b = synth_run(tmp_path / "b", pw=0.35, pd=0.30, K=10, seed=1)
    run = ar.load_run([a, b], net=NET)
    assert len(run["collisions"]) == 10


def test_shuffled_control_reads_null(tmp_path):
    d = synth_run(tmp_path, pw=0.3925, pd=0.315, K=150, seed=11)
    run = ar.load_run(d, net=NET)
    st = ar.block_stats(ar.shuffle_blocks(run, seed=99))
    assert st["ci_lo"] < 0.5 < st["ci_hi"]
    assert not st["ci_excludes_50"]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))