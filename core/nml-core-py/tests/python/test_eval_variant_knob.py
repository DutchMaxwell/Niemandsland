"""GATE for the `eval_variant` knob (evolved-hand-eval lane, step 2) —
test_knob_wiring / test_deployment_knob style.

THE HOLE this guards: a header knob that is accepted and stamped but never
actually read (or read at only ONE of the two call sites `score.rs` and
`rollout::blend_score` name) would leave every gate green while quietly
routing a future evolved eval nowhere. Today only variant 0 exists, so the
proof this PR can make is narrower than a real A/B: the second core built
off `eval_variant_player`/`eval_variant` (the `deep_player` pattern, PR
#515) must be BYTE-IDENTICAL to the pre-knob game at variant 0 — the seam
changes nothing until a variant is registered — and a header asking for
anything else must be refused loudly, never a silent fallback.

SKIP: the game-level checks need the terrain bank and the private AI-list
corpus outside the repo, the same escape hatch every knob-wiring test here
uses; the header round-trip checks need neither.
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
ARMY1 = LISTS / "alien_hives_1000.json"
ARMY2 = LISTS / "battle_brothers_1000.json"
SEED = 27
#: the search-A/B harness's own knob set (`search_ab_one.py`), held fixed so
#: `eval_variant` is the only free variable.
GAME = {
    "charge_gate": "off", "hero_attach": "table", "dice": "table",
    "charge_landing": "table", "movement": "rigid", "sighting": "model",
    "cond_ap": True, "objectives": "rulebook", "deployment": "arena",
    "dice_seed": SEED,
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def test_the_default_header_carries_eval_variant_0():
    """`Core.knobs()` round-trip — absent from the header, and stamped
    explicitly at 0, both read back 0 (`acts::Knobs::eval_variant`)."""
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {}})
    assert core.knobs()["eval_variant"] == 0
    core.set_header({"profiles": {}, "knobs": {"eval_variant": 0}})
    assert core.knobs()["eval_variant"] == 0


def test_an_unregistered_eval_variant_is_refused_loudly():
    """`acts::read_act_header`'s own RED proof, reached through the Python
    seam: variant 1 has no registered arm, so `set_header` raises instead of
    silently arming variant 0 or panicking deep inside a rollout."""
    core = nml_core.load(str(REPO))
    with pytest.raises(Exception):
        core.set_header({"profiles": {}, "knobs": {"eval_variant": 1}})


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_eval_variant_player_at_0_is_byte_identical():
    """The second-core pattern's own proof, `deep_player`'s ported verbatim:
    naming a seat with `eval_variant=0` (the default) must play the
    byte-identical game and leave `knobs_by_seat` unstamped — the second
    core sees the identical header and the knob does not move anything yet."""
    plain = sp.play_game(SEED, ARMY1, ARMY2, REPO, BANK_DIR, None, sidecars=False, **GAME)
    seamed = sp.play_game(
        SEED, ARMY1, ARMY2, REPO, BANK_DIR, None, sidecars=False,
        eval_variant_player=1, eval_variant=0, **GAME,
    )
    assert sp.result_digest(plain) == sp.result_digest(seamed)
    assert "knobs_by_seat" not in seamed


@pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")
def test_an_unregistered_variant_raises_from_play_game_too():
    with pytest.raises(Exception):
        sp.play_game(
            SEED, ARMY1, ARMY2, REPO, BANK_DIR, None, sidecars=False,
            eval_variant_player=1, eval_variant=1, **GAME,
        )
