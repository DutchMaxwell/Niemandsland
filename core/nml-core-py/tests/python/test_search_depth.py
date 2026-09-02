"""The SEARCH A/B seam — per-seat search depth on the fast core's selfplay
path (`deep_player` / `deep_top_k` / `deep_horizon` on `play_game`).

One seat of a paired game must be able to search DEEPER than the other
(600 paired games answering "does more search make the AI stronger?"). The
implementation hands the deep seat's activations a SECOND core built off the
same header payload with the deep pair in place of the base pair. Three
proofs, the knob-wiring pattern (`test_explore_knob.py`,
`test_deployment_knob.py`):

  * `deep_player=0` (the default, and passing it explicitly) plays the
    BYTE-IDENTICAL game the pre-knob code played — vintage-pinned raw digest,
    stamp set included (no stamp exists on this path);
  * a deep game whose deep pair EQUALS the resolved base pair digests
    byte-identically to that pin — the proof the second core really sees the
    same header (same profiles, terrain and every other knob);
  * `deep_player=2` with a deeper pair plays a DIFFERENT game (compared
    without the stamps, so stamps alone cannot pass) and stamps both seats'
    resolved depths as `knobs_by_seat` (the NML-1147a pattern: the stamp
    rides only a game whose deep pair parted from the base pair).
"""

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

#: the explore-knob test's fixture game: seed 27, FAST knobs, fresh core.
SEED = 27
FAST = {"top_k": 2, "horizon": 1}
#: raw `sp.result_digest` at HEAD 08e80b90 (deep_player absent), taken by
#: `.forge/digest_probe.py` BEFORE the seam landed — the pre-change game.
SEED_27_FAST_DIGEST = "15455727f2dace38d0ce9e30c0801d704baa6c7d0edd9bae2904d3a9df03bad7"


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def _digest_without_stamps(result: dict) -> str:
    """`sp.result_digest` with both stamp fields stripped (`knobs` grows with
    mode metadata, `knobs_by_seat` rides only a parted deep pair) — so a
    comparison cannot pass on stamps alone."""
    return sp.result_digest(
        {k: v for k, v in result.items() if k not in ("knobs", "knobs_by_seat")}
    )


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_default_is_byte_identical():
    """`deep_player=0` — passed and defaulted — must leave the pre-knob game
    untouched: same seed, RAW result digest equal to the vintage pin."""
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    explicit = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                            deep_player=0, **FAST)
    assert sp.result_digest(base) == SEED_27_FAST_DIGEST
    assert sp.result_digest(explicit) == SEED_27_FAST_DIGEST


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_equal_knobs_digest_byte_identical():
    """A deep game whose deep pair EQUALS the base pair must digest exactly
    what the pre-change code digested: the second core is built and planned
    on, so the pin can only hold if that core really sees the same header."""
    core = nml_core.load(str(REPO))
    r = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                     deep_player=1, deep_top_k=2, deep_horizon=1, **FAST)
    assert sp.result_digest(r) == SEED_27_FAST_DIGEST
    assert "knobs_by_seat" not in r  # the stamp rides only a parted pair


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_deep_player_stamps_knobs_by_seat():
    """MUTATION GUARD: `deep_player=2` with a deeper pair must play a
    DIFFERENT game than the base (stamps stripped) and stamp both seats'
    resolved depths — p1 the base pair, p2 the deep pair."""
    core = nml_core.load(str(REPO))
    base = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core, **FAST)
    deep = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, core,
                        deep_player=2, deep_top_k=4, deep_horizon=2, **FAST)
    assert _digest_without_stamps(base) != _digest_without_stamps(deep)
    assert deep["knobs_by_seat"] == {
        "p1": {"top_k": 2, "horizon": 1},
        "p2": {"top_k": 4, "horizon": 2},
    }
    assert "knobs_by_seat" not in base
