"""GATE for the `menu_targets` knob (NML-1157) — test_knob_wiring /
test_eval_variant_knob style.

THE RULE. GF Advanced Rules v3.5.1 p.14 (Hero): "when a Hero joins a unit, they
count as part of that unit". The shipped table never lets one be named alone
(`solo_controller.gd:1197`, `main.gd:8452`, `main.gd:9166`); `menu::enemy_keys`
did, so `best_shoot`/`best_charge` could aim at a 1-model hero standing inside a
20-model host. `best_charge` also emits exactly ONE target, ranked by
`charge_score` = dealt - taken with no distance term, so the slot goes to the
smallest strike-back on the board and the enemy an inch away is never offered.

MEASURED on `~/selfplay_out/gen0_teacher`, 796 replayed activations: 544 of 787
charge offers name a joined hero, 51 name the nearest enemy, and 134 of the 144
activations with an enemy inside 2" are offered a charge at somebody else.

THE HOLE THIS GUARDS: a knob accepted and stamped but never read would leave
every gate green while the menu stayed unchanged. So the checks are (1) the
header round-trip, (2) OFF is the default everywhere, and (3) a REAL game plays
DIFFERENTLY with the knob on — the same "prove the seam is load-bearing" bar
`test_deployment_knob` sets.

SKIP: the game-level checks need the terrain bank and the private AI-list
corpus outside the repo, the same escape hatch every knob-wiring test here uses.
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
#: the Gen-0 teacher's own knob set, held fixed so `menu_targets` is the only
#: free variable (`gen0_replay_one.KNOBS`).
GAME = {
    "charge_gate": "off", "hero_attach": "table", "dice": "table",
    "charge_landing": "table", "movement": "rigid", "sighting": "model",
    "cond_ap": True, "objectives": "rulebook", "deployment": "arena",
    "dice_seed": SEED, "sidecars": False,
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def test_the_default_header_carries_menu_targets_off():
    """`Core.knobs()` round-trip — absent from the header and stamped False
    both read back False (`acts::Knobs::menu_targets`)."""
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {}})
    assert core.knobs()["menu_targets"] is False
    core.set_header({"profiles": {}, "knobs": {"menu_targets": False}})
    assert core.knobs()["menu_targets"] is False


def test_the_header_honours_menu_targets_on():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {"menu_targets": True}})
    assert core.knobs()["menu_targets"] is True


def test_the_trainer_default_is_off():
    """A corpus recorded without the flag must be the corpus it always was."""
    assert sp.TRAINER_KNOBS["menu_targets"] is False


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_a_default_game_stamps_no_menu_targets_key():
    """Stamped only when ON, the way `deployment` is: a default game writes the
    identical `knobs` object it wrote before this knob existed, so no Godot
    parity gate (`sidecar_gate.py`) sees a new key."""
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    assert "menu_targets" not in res["knobs"]


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_menu_targets_on_changes_the_game_and_says_so():
    """The seam is load-bearing: same seed, same dice, same everything else —
    the menu the search sees is different, so the game must diverge. If this
    ever passes with identical results the knob is not wired to the menu."""
    off = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    on = sp.play_game(
        SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, menu_targets=True, **GAME
    )
    assert on["knobs"]["menu_targets"] is True
    off_acts = [(r["unit"], r["kind"]) for r in off["planner_positions"]]
    on_acts = [(r["unit"], r["kind"]) for r in on["planner_positions"]]
    assert off_acts != on_acts or off["vp"] != on["vp"], (
        "menu_targets=True produced the identical game — the knob is not reaching "
        "menu::candidates_tuned"
    )
