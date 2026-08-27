"""GATE M5 H6 (NML-1073) — knob wiring tests for `charge_gate` / `hero_attach`.

THE HOLE. `test_selfplay.py` tests `resolve_charge_gate` / `resolve_hero_attach`
and the header-level stamps at the UNIT level, over `acts_25.jsonl`
(`test_the_charge_gate_knob_is_load_bearing`, `test_the_hero_attach_knob_joins_
the_list_the_way_the_table_does`), and its corpus gate calls `sp.play_game` —
but always at the DEFAULTS (`charge_gate="off"`, `hero_attach="off"`). No test
anywhere calls `play_game` with `charge_gate="table"` or `hero_attach="table"`.
That means the two places `play_game` actually WIRES the knobs —

    eff_charge_gate = resolve_charge_gate(charge_gate)        # selfplay.py
    if resolve_hero_attach(hero_attach): ...                  # selfplay.py

— could be cut (`charge_gate` hardcoded before the `resolve_charge_gate` call,
or `if False and resolve_hero_attach(hero_attach):`) and every existing gate,
every existing unit test, and `qa_gate.py`'s 160/160 would stay green, because
none of them ever ask a WHOLE GAME to run with either knob on "table".

MUTATION GUARD. The two tests below are the only thing in this repo that fails
if that wiring is cut. Each plays a real corpus pairing seed for seed under
both modes and requires the played-out game — not just its `knobs` label — to
differ: `_digest_without_knobs` strips the `knobs` field before hashing,
specifically so a cut wire (the mode string accepted and stamped, never
actually read) cannot pass by leaving only the label changed.

SKIP: needs the terrain bank and the private AI-list corpus outside the repo,
the same escape hatch `test_selfplay.py`'s corpus gate uses.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))

#: seeds tried in order until one produces a different game — the same range
#: `test_selfplay.py`'s `GATE_SEEDS` starts from.
SEEDS = range(27, 41)

CHARGE_ARMY1 = LISTS / "robot_legions_1000.json"
CHARGE_ARMY2 = LISTS / "blessed_sisters_1000.json"
HERO_ARMY1 = LISTS / "alien_hives_1000.json"
HERO_ARMY2 = LISTS / "battle_brothers_1000.json"


def _lists_missing(*paths) -> bool:
    return not (BANK_DIR.is_dir() and all(p.exists() for p in paths))


def _digest_without_knobs(result: dict) -> str:
    """`sp.result_digest` over the result with its `knobs` field removed first.
    `play_game` stamps `knobs["charge_gate"]` / `["hero_attach"]` with the mode
    STRING verbatim, so the full digest would differ between `"off"` and
    `"table"` even if the knob changed nothing about the game itself. This is
    the digest that has to move for a divergence to mean anything."""
    return sp.result_digest({k: v for k, v in result.items() if k != "knobs"})


def _first_divergent_seed(army1: Path, army2: Path, knob: str, mode_a: str, mode_b: str):
    """Play `SEEDS` with `knob=mode_a` vs `knob=mode_b` until the two games'
    knob-free digests disagree; return `(seed, result_a, result_b)` for the
    first one, or `(None, None, None)` if none of the tried seeds differ."""
    core = nml_core.load(str(REPO))
    for seed in SEEDS:
        a = sp.play_game(seed, army1, army2, REPO, BANK_DIR, core, **{knob: mode_a})
        b = sp.play_game(seed, army1, army2, REPO, BANK_DIR, core, **{knob: mode_b})
        if _digest_without_knobs(a) != _digest_without_knobs(b):
            return seed, a, b
    return None, None, None


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_charge_gate_off_vs_table_plays_a_different_game():
    """H6/1: `play_game(charge_gate=...)`. Builders on 2026-08-27 measured seed
    27 (robot_legions_1000 vs blessed_sisters_1000) diverge under this knob
    (VP 0/1 off vs 5/4 table); search 27..40 in case the fixtures moved and pin
    whichever seed is found first."""
    seed, off, table = _first_divergent_seed(
        CHARGE_ARMY1, CHARGE_ARMY2, "charge_gate", "off", "table"
    )
    assert seed is not None, "no seed in %s diverged between charge_gate off/table" % list(SEEDS)
    assert off["knobs"]["charge_gate"] == "off"
    assert table["knobs"]["charge_gate"] == "table"
    print("charge_gate off vs table first diverges at seed %d" % seed)


@pytest.mark.skipif(
    _lists_missing(HERO_ARMY1, HERO_ARMY2),
    reason="needs the terrain bank + alien_hives/battle_brothers 1000pt lists",
)
def test_hero_attach_off_vs_table_plays_a_different_game():
    """H6/2: `play_game(hero_attach=...)`. Builders on 2026-08-27 measured seed
    27 (alien_hives_1000 vs battle_brothers_1000) diverge under this knob
    (draw off vs 2:1 table); search 27..40 the same way."""
    seed, off, table = _first_divergent_seed(
        HERO_ARMY1, HERO_ARMY2, "hero_attach", "off", "table"
    )
    assert seed is not None, "no seed in %s diverged between hero_attach off/table" % list(SEEDS)
    assert off["knobs"]["hero_attach"] == "off"
    assert table["knobs"]["hero_attach"] == "table"
    print("hero_attach off vs table first diverges at seed %d" % seed)


# ------------------------------------------------------------ H8: charge_gate.py ---


def test_vecs_differ_treats_unequal_length_as_a_mismatch():
    """H8: `tools/charge_gate.py`'s `action_diff` used to compare `dest`
    vectors with plain `zip(gd, wd)`, which silently drops the tail of the
    longer vector — a 2-vector and a 3-vector agreeing on their first two
    components would have read as equal. `vecs_differ` is the factored-out
    helper (`zip(..., strict=True)` once lengths are known equal); this pins
    equal, differing, and unequal-length inputs directly."""
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
    import charge_gate as cg  # noqa: E402

    assert cg.vecs_differ([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]) is False
    assert cg.vecs_differ([1.0, 2.0, 3.0], [1.0, 2.0, 3.5]) is True
    assert cg.vecs_differ([1.0, 2.0], [1.0, 2.0, 3.0]) is True
