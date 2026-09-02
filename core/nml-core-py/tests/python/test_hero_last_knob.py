"""GATE for the `hero_last` knob (NML-1157) — test_knob_wiring style.

THE RULE. GF Advanced Rules v3.5.1 p.14 (Hero): "when a Hero joins a unit, they
count as part of that unit"; Tough(X): "heroes must be assigned wounds last,
even if already wounded". The shipped table obeys both —
`main._solo_combat_unit` (:8452) resolves a combat intent from or at a joined
hero to its HOST, `main._solo_pick_unit_at` (:9166) does the same for a click,
and `main.gd:10823` fills the host's models first and spills into the hero only
afterwards.

THE PORT DID NOT. `sim::strike_phase` and the volley apply to the NAMED index
alone, so a 1-model Tough(3) hero could be killed inside a living 20-model host.
Measured by replaying `~/selfplay_out/gen0_teacher` (20 games, 796 activations):
42 of 63 chosen charges named a joined hero.

WHY IT IS OFF BY DEFAULT. The recorded reference bundles were produced by the
TABLE, and the table's own AI target list is not the only path into a volley —
across `qbg_ref` + `qag_ref` (336 games, 16 043 acts) **352 recorded acts name a
joined hero**: 221 volleys and 131 charges. Those bundles are the dice oracle. A
bundle replayed with the rule ON would part from its own recording, so
`dice_gate` / `melee_replay_gate` / `shoot_replay_gate` must keep seeing the
knob OFF while new self-play may turn it on.

SKIP: the game-level checks need the terrain bank and the private AI-list corpus
outside the repo, the same escape hatch every knob-wiring test here uses.
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
SEED = 27
GAME = {
    "charge_gate": "off", "hero_attach": "table", "dice": "table",
    "charge_landing": "table", "movement": "rigid", "sighting": "model",
    "cond_ap": True, "objectives": "rulebook", "deployment": "arena",
    "dice_seed": SEED, "sidecars": False,
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


def test_the_default_header_carries_hero_last_off():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {}})
    assert core.knobs()["hero_last"] is False
    core.set_header({"profiles": {}, "knobs": {"hero_last": False}})
    assert core.knobs()["hero_last"] is False


def test_the_header_honours_hero_last_on():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {"hero_last": True}})
    assert core.knobs()["hero_last"] is True


def test_the_replay_default_is_off():
    """The dice oracle's own bundles name a joined hero 352 times; the replay
    default has to keep resolving them where the table resolved them."""
    assert sp.TRAINER_KNOBS["hero_last"] is False


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_a_default_game_stamps_no_hero_last_key():
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    assert "hero_last" not in res["knobs"]


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_hero_last_changes_the_game_and_says_so():
    """The seam is load-bearing: same seed, same dice, same everything else —
    a charge or a volley that used to land on a 1-model hero now lands on its
    host, so the game must diverge. If this ever passes with identical results
    the knob is not reaching `sim::combat_unit`."""
    off = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    on = sp.play_game(
        SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, hero_last=True, **GAME
    )
    assert on["knobs"]["hero_last"] is True
    off_acts = [(r["unit"], r["kind"], r["action"].get("charge"), r["action"].get("shoot"))
                for r in off["planner_positions"]]
    on_acts = [(r["unit"], r["kind"], r["action"].get("charge"), r["action"].get("shoot"))
               for r in on["planner_positions"]]
    assert off_acts != on_acts or off["vp"] != on["vp"], (
        "hero_last=True produced the identical game — the knob is not reaching the resolve"
    )
