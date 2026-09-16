"""GATE for the cast_events "kind" stamp (CAST_FORK_2026-09-16.md Finding 2).

`selfplay._spells_by_kind_tally` counts `state.cast_event_kinds()` from the
pre-apply mark — the "kind" every cast_events entry carries. The core's cast
sub-phase pushed its rules-must-log lines with "rule"/"log" only, so every
kind read "" and `spells_by_kind` was structurally zero, cast phase on or off.

The stamp (sim.rs cast_phase): the FIRST face's spell names the attempt
(battle_sim.gd `_cast_phase`'s own event), and every pushed cast entry carries
that spell's `effect_kind` — the exact strings the GDScript table's `by_kind`
keys carry ("damage" | "buff" | "debuff"; "utility" is skipped by the counter,
exactly as an unknown kind always was).

This file plays ONE real game with `seam_cast` + `cast_fold` on (the joined
Caster finally casts, test_cast_fold_knob.py's GREEN arm) and asserts the
campaign telemetry is no longer structurally zero.
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
ARMY2 = LISTS / "battle_brothers_1000.json"
#: A seed whose casts flow through the cast SUB-PHASE (events pushed, kinds
#: stamped). The legacy spell rider spends tokens without pushing cast_events,
#: so most seeds book casts the tally rightly ignores — seed 27 books two.
SEED = 2
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


def _kinds_sum(res) -> int:
    return sum(
        sum(by_kind.values())
        for by_kind in (res.get("magic", {}).get("spells_by_kind") or {}).values()
    )


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_a_game_with_the_cast_seam_on_reports_nonzero_spells_by_kind(monkeypatch):
    """The D-MAGIC telemetry counts again. `seam_cast` alone casts nothing
    (the joined-caster defect, test_cast_fold_knob.py), so the fold rides
    along — the same arms that file plays, one of them asserting the tally."""
    monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_cast", True)
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None,
                       cast_fold=True, **GAME)
    magic = res.get("magic") or {}
    assert sum((magic.get("casts") or {}).values()) > 0, (
        "the fixture must cast at all (the fold's GREEN arm)"
    )
    assert _kinds_sum(res) > 0, (
        "spells_by_kind must count with the cast phase on — RED while the "
        "cast_events entries carry no kind stamp"
    )
