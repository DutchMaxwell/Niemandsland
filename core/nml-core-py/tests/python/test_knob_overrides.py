"""aifix harness — `knob_overrides` / `knob_override_player` (07.10.2026).

THE HOLE this guards: an A/B arm whose preset never reaches the core. The header parser drops
unknown keys silently, so a typo'd or unexposed knob would play the default and every number
would be a null that looks like a result. The seat core must carry the preset, the base core
must not, and a key the core does not read back must be refused.

The game-level stamp check needs the terrain bank and the private AI lists (the same escape
hatch every knob-wiring test here uses); the header-level checks need neither.
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
HEADER = {"profiles": {}}
PRESET = sp.KNOB_PRESETS["aifix_all"]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))


def test_the_preset_reaches_the_seat_core_and_not_the_base_core():
    base = nml_core.load(str(REPO))
    base.set_header({**HEADER, "knobs": {}})
    seat = sp.core_with_knob_overrides(REPO, HEADER, {}, PRESET)
    for key, want in PRESET.items():
        assert seat.knobs()[key] == want, f"{key} not on in the asking seat"
        assert base.knobs()[key] != want, f"{key} already on in the other seat"


def test_every_named_preset_reaches_the_seat_core():
    """Not only aifix_all: any preset in KNOB_PRESETS must be readable back from the seat core (an unexposed knob
    raises), and must change something the base core does not already carry."""
    base = nml_core.load(str(REPO))
    base.set_header({**HEADER, "knobs": {}})
    for name, preset in sp.KNOB_PRESETS.items():
        seat = sp.core_with_knob_overrides(REPO, HEADER, {}, preset)
        for key, want in preset.items():
            assert seat.knobs()[key] == want, f"{name}: {key}"
            assert base.knobs()[key] != want, f"{name}: {key} already on in the base core"


def test_a_knob_the_core_does_not_read_back_is_refused():
    with pytest.raises(ValueError, match="not read back"):
        sp.core_with_knob_overrides(REPO, HEADER, {}, {"opener_by_finnish": True})


def test_a_seat_may_not_take_both_eval_variant_and_overrides():
    with pytest.raises(ValueError, match="not both"):
        sp.play_game(
            1, Path("a"), Path("b"), REPO, Path("bank"), None, sidecars=False,
            eval_variant_player=1, eval_variant=1, knob_override_player=1,
            knob_overrides={"reply_v2": True},
        )


def test_overrides_need_a_seat():
    with pytest.raises(ValueError, match="knob_override_player"):
        sp.play_game(
            1, Path("a"), Path("b"), REPO, Path("bank"), None, sidecars=False,
            knob_overrides={"reply_v2": True},
        )


@pytest.mark.skipif(
    not (BANK_DIR.is_dir() and (LISTS / "alien_hives_1000.json").exists()),
    reason="needs the terrain bank + 1000pt lists",
)
def test_the_stamp_rides_the_asking_seat_only():
    game = dict(
        charge_gate="off", hero_attach="table", dice="table", charge_landing="table",
        movement="rigid", sighting="model", cond_ap=True, objectives="rulebook",
        deployment="arena", dice_seed=27,
    )
    res = sp.play_game(
        27, LISTS / "alien_hives_1000.json", LISTS / "battle_brothers_1000.json", REPO, BANK_DIR,
        None, sidecars=False, knob_override_player=2, knob_overrides=PRESET, **game,
    )
    assert res["knobs_by_seat"]["p2"] == PRESET and res["knobs_by_seat"]["p1"] == {}
