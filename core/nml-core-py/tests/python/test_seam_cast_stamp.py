"""The record's own `seam_cast` stamp (D-MAGIC A/B precondition).

`selfplay.play_game` stamps its kwargs into the result's top-level `knobs`,
but the cast SUB-PHASE switch lives in `selfplay.TRAINER_KNOBS["seam_cast"]`
and reaches the crate only via the header knobs (`nml-core-py/src/lib.rs`
`cast: self.knobs.seam_cast`) — so a record played with the seam ON was
indistinguishable from one played OFF by reading it (the lead's fleet smoke
16.09.: ON casts 2 / OFF casts 0 on the same seed, both `knobs` without the
key). A bank must be verifiable by its own headers (the record tells the
truth), so the stamp rides the top-level `knobs` — only when ON, the
`mission` idiom, so every existing record stays byte-identical.

`gen0_replay_one.KNOBS` pins `seam_cast=False` (every corpus predates the
stamp) and `replay_knobs` forwards a record's own top-level stamp (the
`melee_reach` idiom): a record played ON must REPLAY ON, or its casts
diverge from its own headers.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import gen0_replay_one as gr  # noqa: E402
import selfplay as sp  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
BANK_DIR = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1 = LISTS / "robot_legions_1000.json"
ARMY2 = LISTS / "battle_brothers_1000.json"
SEED = 2
#: #1011's arm: the cast sub-phase needs `hero_attach`/`dice`/... table settings
#: and the joined-caster fold to actually cast; the stamp itself rides the
#: header knobs either way.
GAME = {
    "charge_gate": "off", "hero_attach": "table", "dice": "table",
    "charge_landing": "table", "movement": "rigid", "sighting": "model",
    "cond_ap": True, "objectives": "rulebook", "deployment": "arena",
    "dice_seed": SEED, "sidecars": False,
    "menu_wide": "off", "menu_los": "planner", "los": "unit",
    "hero_last": False, "ambush": "off",
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


needs_lists = pytest.mark.skipif(_lists_missing(), reason="needs the terrain bank + 1000pt lists")


@needs_lists
def test_a_game_played_with_the_seam_on_stamps_seam_cast(monkeypatch):
    """The stamp must say what the game actually played (monkeypatch of
    `TRAINER_KNOBS`, #1011's arm): ON records `seam_cast: True`."""
    monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_cast", True)
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None,
                       cast_fold=True, **GAME)
    assert res["knobs"]["seam_cast"] is True


@needs_lists
def test_a_game_played_off_stamps_no_seam_cast_key():
    """The `mission` idiom: a default (seam OFF) game writes the identical
    object it wrote before the stamp existed — absence IS "off"."""
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None,
                       cast_fold=True, **GAME)
    assert "seam_cast" not in res["knobs"]


def test_a_stamped_seam_cast_is_forwarded_to_the_replay():
    merged = gr.replay_knobs({"seam_cast": True}, {"knobs": {"seam_cast": True}},
                             {"knobs": {"seam_cast": True}})
    assert merged["seam_cast"] is True


def test_a_record_silent_on_seam_cast_still_replays_off():
    """The pin: every corpus recorded before the stamp is silent on the key
    and must keep replaying the seam OFF (`KNOBS`'s gen0-era value)."""
    merged = gr.replay_knobs({}, {}, {})
    assert merged["seam_cast"] is False


def test_a_top_level_stamp_is_forwarded_to_the_replay():
    """The stamp rides the record's TOP-LEVEL `knobs` only (`prescreen.knobs`
    is a different producer and silent on it), so `replay_knobs` reads it
    from `record["knobs"]` — the `melee_reach` idiom."""
    merged = gr.replay_knobs({}, None, {"knobs": {"seam_cast": True}})
    assert merged["seam_cast"] is True
