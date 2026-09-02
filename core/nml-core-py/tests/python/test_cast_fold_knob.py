"""GATE for the `cast_fold` knob (NML-1157) — test_knob_wiring style.

THE DEFECT. `Caster(X)` is a HERO rule in every faction book the Gen-0 corpus
plays, and a joined hero never activates on its own (`State::can_activate`,
`solo_controller.gd:423`) — so the acting unit `si` is always the HOST, and the
host is not the caster. Both cast paths read the host: `sim::cast_phase` tests
`statics[profile[si]].is_caster` and spends `state.casts[si]`, and the legacy
spell rider in `resolve`'s shoot branch calls `spell_ev_of(us.is_caster,
&us.spells, next.casts[si], ...)`. Both answer "no caster, no tokens".

MEASURED by replaying `~/selfplay_out/gen0_teacher` (20 games, 796 activations,
`tools/game_narrator.py`): 13 caster units — `Vradhez` Caster(2) and
`Echo-3G01` Caster(1), 110 and 100 points — EVERY ONE an attached hero; 52
activations by a chain holding cast tokens; **0 casts and 0 tokens spent**. The
recordings' own `magic` telemetry agrees: `granted` 4-6 per game, `casts` 0.

Turning `seam_cast` on does NOT fix that — the sub-phase runs and returns on its
first read. That is why this is a defect and not a knob.

THE HOLE THIS GUARDS: a knob accepted and stamped but never read. The `Seams`
half is proven in Rust (`sim::cast_fold_tests`); this file proves the header
round-trip, that OFF is the default everywhere, and that a real game with the
cast sub-phase ON plays differently with the fold than without it.

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
#: Robot Legions carry `Echo-3G01`, a Caster(1) HERO that joins `Warriors` —
#: the exact shape the defect is about.
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


def _casts(res) -> int:
    return sum((res.get("magic", {}).get("casts") or {}).values())


def test_the_default_header_carries_cast_fold_off():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {}})
    assert core.knobs()["cast_fold"] is False
    core.set_header({"profiles": {}, "knobs": {"cast_fold": False}})
    assert core.knobs()["cast_fold"] is False


def test_the_header_honours_cast_fold_on():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {"cast_fold": True}})
    assert core.knobs()["cast_fold"] is True


def test_the_trainer_default_is_off():
    """A corpus recorded without the flag must be the corpus it always was —
    the fold moves the LEGACY spell rider's volley EV, not only the sub-phase."""
    assert sp.TRAINER_KNOBS["cast_fold"] is False


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_a_default_game_stamps_no_cast_fold_key():
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    assert "cast_fold" not in res["knobs"]


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_the_teachers_casters_are_joined_heroes_and_never_cast_today():
    """The measurement, reproduced in one game: the list carries a Caster, it is
    granted tokens, and the game books zero casts. This is the RED — it must
    keep passing for as long as the trainer records with the fold off."""
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    magic = res.get("magic") or {}
    assert sum((magic.get("casters") or {}).values()) > 0, "the fixture list must carry a Caster"
    assert sum((magic.get("granted") or {}).values()) > 0, "and it must be granted tokens"
    assert _casts(res) == 0, "0 casts — the defect, still standing"


@pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")
def test_cast_fold_changes_a_game_that_has_a_joined_caster(monkeypatch):
    """The seam is load-bearing. Same seed, same dice, cast sub-phase ON in both
    arms — the only free variable is whether the caster is looked for on the
    chain. `seam_cast` has no `play_game` kwarg of its own (it is a
    `TRAINER_KNOBS` entry), so the sub-phase is turned on the way the trainer
    turns it on. If this ever passes with identical results the knob is not
    reaching `sim::caster_of`."""
    monkeypatch.setitem(sp.TRAINER_KNOBS, "seam_cast", True)
    off = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    on = sp.play_game(
        SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, cast_fold=True, **GAME
    )
    assert on["knobs"]["cast_fold"] is True
    assert _casts(off) == 0, "seam_cast alone still casts nothing — that is the whole finding"
    assert _casts(on) > 0, "with the fold the joined hero finally casts"
