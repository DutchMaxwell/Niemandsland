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

NML-1140 step 9 rides the same guards for `objectives="doctrine"`: the knob
must actually hand the choice to `nml_core.doctrine_place` (positions move,
deterministically), the rung must be stamped, and the seam must refuse a
count no mission can draw.
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


def _first_divergent_seed(army1: Path, army2: Path, knob: str, mode_a: str, mode_b: str,
                          **rest):
    """Play `SEEDS` with `knob=mode_a` vs `knob=mode_b` until the two games'
    knob-free digests disagree; return `(seed, result_a, result_b)` for the
    first one, or `(None, None, None)` if none of the tried seeds differ.

    `rest` is the OTHER knobs both arms need in common — `sighting` only has a
    consumer inside the tray volley (sim.rs:1632-1645), so its test has to hold
    `dice="table"` on both sides or the two arms would play the identical
    expected-value game and the guard would pass for the wrong reason."""
    core = nml_core.load(str(REPO))
    for seed in SEEDS:
        a = sp.play_game(seed, army1, army2, REPO, BANK_DIR, core, **{knob: mode_a}, **rest)
        b = sp.play_game(seed, army1, army2, REPO, BANK_DIR, core, **{knob: mode_b}, **rest)
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


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_sighting_unit_vs_model_plays_a_different_game():
    """H6/3: `play_game(sighting=...)` — the D6a-B4 rung, which the trainer
    could not reach at all before this: `TRAINER_KNOBS` carried no `sighting`
    key, so the header always took the crate's serde default (`Sighting::Unit`)
    and a Godot-free corpus could never be written at the sighting fidelity a
    RECORDED corpus is replayed at (`selfplay_gate`/`sidecar_gate` read the
    mode off the header).

    Both arms hold `dice="table"`: the knob's only consumer is inside the tray
    volley (`sim.rs:1632-1645`, `seams.sighting`), so under `dice="expected"`
    the two modes play the same game by construction and this guard would be
    vacuous."""
    seed, unit, model = _first_divergent_seed(
        CHARGE_ARMY1, CHARGE_ARMY2, "sighting", "unit", "model", dice="table"
    )
    assert seed is not None, "no seed in %s diverged between sighting unit/model" % list(SEEDS)
    assert unit["knobs"]["sighting"] == "unit"
    assert model["knobs"]["sighting"] == "model"
    print("sighting unit vs model first diverges at seed %d" % seed)


def test_an_unknown_sighting_mode_raises_instead_of_falling_back():
    """`resolve_sighting` follows `resolve_dice`'s rule: a corpus whose header
    claims a rung it did not play is worse than no corpus."""
    with pytest.raises(ValueError, match="sighting must be one of"):
        sp.resolve_sighting("per_model")


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_objectives_mode_is_stamped_into_the_result_knobs():
    """NML-1147a: `play_game` plays the `objectives` mode (D8a) but never SAID
    so — the result's `knobs` block carried no `objectives` key, so a Gen-0
    corpus that played the rulebook layout records exactly what a
    constants-layout corpus records and no gate can tell them apart. This
    plays one seed under both modes and requires the stamp to read back; the
    KeyError on the `rulebook` arm is the red this test is born with."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="constant")
    b = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="rulebook")
    assert a["knobs"]["objectives"] == "constant"
    assert b["knobs"]["objectives"] == "rulebook"


# ---------------------------------------- NML-1140 step 9: the doctrine knob ---


def _stamp_of(result: dict) -> dict:
    return result["mission"]["objectives_layout"]


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_doctrine_knob_places_by_the_doctrine():
    """Step 9/1: `objectives="doctrine"` vs `"rulebook"`, same seed. The draw is
    shared (same count and first placer — the stream contract), so a knob-free
    divergence means the CHOICE moved; the marker positions moving with it is
    what makes the knob more than its stamp."""
    seed, doctrine, rulebook = _first_divergent_seed(
        CHARGE_ARMY1, CHARGE_ARMY2, "objectives", "doctrine", "rulebook"
    )
    assert seed is not None, "no seed in %s diverged between doctrine/rulebook" % list(SEEDS)
    assert _stamp_of(doctrine)["count_roll"] == _stamp_of(rulebook)["count_roll"]
    assert _stamp_of(doctrine)["first_placer"] == _stamp_of(rulebook)["first_placer"]
    assert _stamp_of(doctrine)["positions"] != _stamp_of(rulebook)["positions"]
    print("doctrine vs rulebook first diverges at seed %d" % seed)


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_doctrine_game_is_deterministic():
    """Step 9/2: the doctrine is a pure function (design 4) — the same seed
    twice plays a byte-identical game, stamp included."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="doctrine")
    b = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="doctrine")
    assert sp.result_digest(a) == sp.result_digest(b)


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_doctrine_stamp_carries_the_mode():
    """Step 9/3: the rung rides under `"doctrine"` beside `"mode": "rulebook"`
    (the step-5 UNSURE, coordinator-approved); the rulebook stamp carries no
    such key and a constants game no layout at all. Every doctrine cell is
    re-checked through `objective_is_legal` — the SAME rule the doctrine
    searched with, other markers only (impassable re-verification is the
    table's gate 1, step 10)."""
    core = nml_core.load(str(REPO))
    search = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                          objectives="doctrine")
    style = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                         objectives="doctrine", doctrine_mode="style")
    rulebook = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                            objectives="rulebook")
    constant = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                            objectives="constant")
    for res, rung in ((search, "search"), (style, "style")):
        stamp = _stamp_of(res)
        assert stamp["mode"] == "rulebook"
        assert stamp["doctrine"] == rung
        assert len(stamp["positions"]) == stamp["count_roll"]
        assert stamp["first_placer"] in (1, 2)
        for i, (x, z) in enumerate(stamp["positions"]):
            others = [[p[0], p[1]] for j, p in enumerate(stamp["positions"]) if j != i]
            assert nml_core.objective_is_legal(None, sp.FRONT_LINE_ZONES, x, z, others)
    assert "doctrine" not in _stamp_of(rulebook)
    assert "objectives_layout" not in constant["mission"]
    print("doctrine positions: search=%s style=%s" % (
        _stamp_of(search)["positions"], _stamp_of(style)["positions"]))


def test_the_seam_refuses_more_than_five_markers():
    """Step 9/4 (the step-5 UNSURE, coordinator-approved): the public seam
    raises for `count > 5` — 8^count search blow-up — instead of grinding on a
    draw no mission can make (d3+2 tops out at 5). The guard is the seam's
    FIRST statement, so junk armies never even reach the doctrine."""
    with pytest.raises(nml_core.Unsupported, match="count must be <= 5"):
        nml_core.doctrine_place(None, "style", ({}, {}), 6, sp.FRONT_LINE_ZONES)


# ------------------------- NML-1140 step 9b: the mixed per-side placement ---


#: Baseline digests captured at 83aa01e (step 10a, pre-9b) in this module's
#: shipped-default state (no legacy fixtures here) — the byte-identity
#: reference the mixed patch must not move: the mixed branch is additive
#: beside the pure modes.
RULEBOOK_27_DIGEST = "87759e0a3786a0b15528b35fa90dd80119553830c81ccac71bb6867dd5dc14f7"
DOCTRINE_27_DIGEST = "4c1b8685dee47c05bc3ec7b7507028c20e757fc6a4ead2d023d32d6a04a27d1b"
MIXED_A = {"1": "search", "2": "random"}  # the doctrine sits seat 1


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_mixed_placement_diverges_from_both_pure_modes():
    """Step 9b/1: `objectives="mixed"` vs BOTH pure modes, same seed. The draw
    is shared (same count and first placer — the stream contract), so a
    knob-free divergence means the CHOICE moved; and the per-seat spec is real
    placement, not a stamp: swapping the seats swaps the placement set."""
    seed, mixed, rulebook = _first_divergent_seed(
        CHARGE_ARMY1, CHARGE_ARMY2, "objectives", "mixed", "rulebook", doctrine_mode=MIXED_A
    )
    assert seed is not None, "no seed in %s diverged between mixed/rulebook" % list(SEEDS)
    assert _stamp_of(mixed)["count_roll"] == _stamp_of(rulebook)["count_roll"]
    assert _stamp_of(mixed)["first_placer"] == _stamp_of(rulebook)["first_placer"]
    assert _stamp_of(mixed)["positions"] != _stamp_of(rulebook)["positions"]
    seed_d, mixed_d, doctrine = _first_divergent_seed(
        CHARGE_ARMY1, CHARGE_ARMY2, "objectives", "mixed", "doctrine", doctrine_mode="search"
    )
    assert seed_d is not None, "no seed in %s diverged between mixed/doctrine" % list(SEEDS)
    assert _stamp_of(mixed_d)["positions"] != _stamp_of(doctrine)["positions"]
    core = nml_core.load(str(REPO))
    swapped = sp.play_game(seed, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                           objectives="mixed",
                           doctrine_mode={"1": "random", "2": "search"})
    assert _stamp_of(swapped)["positions"] != _stamp_of(mixed)["positions"]
    assert _stamp_of(swapped)["count_roll"] == _stamp_of(mixed)["count_roll"]
    print("mixed vs rulebook/doctrine first diverge at seeds %d/%d; seats swap moves the set"
          % (seed, seed_d))


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_mixed_game_is_deterministic():
    """Step 9b/2: the mixed layout is a pure function of the seed and the
    per-seat spec — the same seed twice plays a byte-identical game."""
    core = nml_core.load(str(REPO))
    a = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="mixed", doctrine_mode=MIXED_A)
    b = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                     objectives="mixed", doctrine_mode=MIXED_A)
    assert sp.result_digest(a) == sp.result_digest(b)


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_mixed_stamp_carries_the_per_seat_modes():
    """Step 9b/3: the per-seat spec rides under `"doctrine"` as
    {"p1": rung, "p2": rung} beside `"mode": "mixed"`; the rulebook stamp
    carries no such key. Every mixed cell is re-checked through
    `objective_is_legal` — the SAME rule both placers answered to."""
    core = nml_core.load(str(REPO))
    mixed = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                         objectives="mixed", doctrine_mode=MIXED_A)
    rulebook = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                            objectives="rulebook")
    stamp = _stamp_of(mixed)
    assert stamp["mode"] == "mixed"
    assert stamp["doctrine"] == {"p1": "search", "p2": "random"}
    assert len(stamp["positions"]) == stamp["count_roll"]
    assert stamp["first_placer"] in (1, 2)
    for i, (x, z) in enumerate(stamp["positions"]):
        others = [[p[0], p[1]] for j, p in enumerate(stamp["positions"]) if j != i]
        assert nml_core.objective_is_legal(None, sp.FRONT_LINE_ZONES, x, z, others)
    assert "doctrine" not in _stamp_of(rulebook)
    print("mixed positions: %s" % stamp["positions"])


def test_the_mixed_spec_refuses_junk():
    """Step 9b/4: the per-seat spec validates like every mode word — unknown
    rungs, missing seats and wrong shapes raise; and the step seam keeps
    `doctrine_place`'s count guard."""
    with pytest.raises(ValueError, match="mixed doctrine_mode must be"):
        sp.resolve_mixed_placement({"1": "bogus", "2": "random"})
    with pytest.raises(ValueError, match="mixed doctrine_mode must be"):
        sp.resolve_mixed_placement({"1": "search"})
    with pytest.raises(ValueError, match="mixed doctrine_mode must be"):
        sp.resolve_mixed_placement(42)
    with pytest.raises(nml_core.Unsupported, match="count must be <= 5"):
        nml_core.doctrine_place_step(({}, {}), 6, sp.FRONT_LINE_ZONES, [])


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_default_paths_stay_byte_identical():
    """Step 9b/5: the mixed branch is additive — the rulebook and doctrine
    games this module already gates play byte-identical to the pre-9b build
    (digests captured at 83aa01e). The shared code the branch touches — the
    metre conversion, the mode-word table, the tray-seed default — must not
    move them. The pin hashes with the `knobs` block stripped (the
    `#481`-era `c2a354be` precedent): the stream is the contract, header
    metadata (`fit_blend`, ...) is not — re-verified across the `5ac14bd`
    rebase, stripped digests identical on both sides of it."""
    core = nml_core.load(str(REPO))
    rulebook = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                            objectives="rulebook")
    doctrine = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                            objectives="doctrine")
    assert _digest_without_knobs(rulebook) == RULEBOOK_27_DIGEST
    assert _digest_without_knobs(doctrine) == DOCTRINE_27_DIGEST


@pytest.mark.skipif(
    _lists_missing(CHARGE_ARMY1, CHARGE_ARMY2),
    reason="needs the terrain bank + robot_legions/blessed_sisters 1000pt lists",
)
def test_the_dice_seed_seam_moves_only_the_tray():
    """Step 9b/6: the tray's seed is the DICE seed — the same value as the
    game seed plays byte-identical to the default (`dice_seed=None`), a
    different value moves the game (the second dice rung the mixed A/B grid
    varies), and the stamp says which seed the tray drew."""
    core = nml_core.load(str(REPO))
    base = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core, dice="table")
    same = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                        dice="table", dice_seed=27)
    other = sp.play_game(27, CHARGE_ARMY1, CHARGE_ARMY2, REPO, BANK_DIR, core,
                         dice="table", dice_seed=100027)
    assert sp.result_digest(base) == sp.result_digest(same)
    assert same["dice_seed"] == 27
    assert sp.result_digest(other) != sp.result_digest(base)
    assert other["dice_seed"] == 100027


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
