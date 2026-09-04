"""GATE for the `melee_reach` knob (W2 S0, PR #616 / issue #635 core leg).

THE RULE. GF Advanced Rules v3.5.1 p.9 "Who Can Strike": only models within 2"
of an enemy model may fight in melee. The Godot table already enforces this
directly in its own combat resolution; the Rust twin's `Knobs::melee_reach`
(`acts::MeleeReach`) is the header knob that turns the same limit on for the
crate's own EV/tray combat (`combat::effective_attacks` /
`combat::striking_models`, wired via `Seams::melee_reach` since PR #616).

THE HOLE THIS GUARDS (issue #635). `Knobs::melee_reach` defaults to `All` —
every alive model of the unit strikes, not just the ones within reach — and
until this change `play_game()` carried no `melee_reach` parameter at all, so
every fast-trainer game (Gen-1, Gen-1b, Gen-2) was recorded with EVERY model
striking, whatever the actual base-edge distances were. `TRAINER_KNOBS` (the
fast trainer's own corpus, matching `~/selfplay_out/gen0_teacher`'s vintage)
and `LEGACY_FIDELITY_KNOBS` (the gates holding the trainer to a FIXED Godot
recording: `qa_gate.py`, `sidecar_gate.py`, `selfplay_gate.py`) must both keep
reading "all" — none of those corpora were recorded with the p.9 limit — while
a FRESH `play_game()` call (no override) must now default to "table" and stamp
it, so replay honours what was actually played.

SKIP: the game-level checks need the terrain bank and the private AI-list
corpus outside the repo, the same escape hatch every knob-wiring test here
uses.
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
#: the Gen-0 teacher's own knob set, held fixed so `melee_reach` is the only
#: free variable (`gen0_replay_one.KNOBS`).
GAME = {
    "charge_gate": "off", "hero_attach": "table", "dice": "table",
    "charge_landing": "table", "movement": "rigid", "sighting": "model",
    "cond_ap": True, "objectives": "rulebook", "deployment": "arena",
    "dice_seed": SEED, "sidecars": False,
}


def _lists_missing() -> bool:
    return not (BANK_DIR.is_dir() and ARMY1.exists() and ARMY2.exists())


needs_lists = pytest.mark.skipif(_lists_missing(), reason="terrain bank / ai_lists not present")


def test_an_absent_melee_reach_key_reads_back_all():
    """`Core.knobs()` round-trip — no `knobs` block at all (every corpus
    recorded before this field existed, and every corpus recorded so far)
    reads back "all", `acts::MeleeReach`'s own `#[default]`, untouched by
    this change so a Gen-0/Gen-1/Gen-2 replay stays byte-identical."""
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {}})
    assert core.knobs()["melee_reach"] == "all"
    core.set_header({"profiles": {}, "knobs": {"melee_reach": "all"}})
    assert core.knobs()["melee_reach"] == "all"


def test_the_header_honours_melee_reach_table():
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": {}, "knobs": {"melee_reach": "table"}})
    assert core.knobs()["melee_reach"] == "table"


def test_the_trainer_default_is_all():
    """A corpus recorded without the flag (every fast-trainer corpus so far,
    `~/selfplay_out/gen0_teacher` included) must be the corpus it always
    was: no p.9 reach limit."""
    assert sp.TRAINER_KNOBS["melee_reach"] == "all"


def test_legacy_fidelity_knobs_pins_melee_reach_all():
    """A gate holding the fast trainer to a FIXED Godot recording
    (`qa_gate.py`, `sidecar_gate.py`, `selfplay_gate.py`) must keep playing
    "all" — the exact opposite of `play_game()`'s own new default — so it
    never takes an opinion on a knob that moved after the recording it holds
    the trainer to."""
    assert sp.LEGACY_FIDELITY_KNOBS["melee_reach"] == "all"


@needs_lists
def test_a_fresh_play_game_stamps_melee_reach_table():
    """THE REQUIRED FIX (#635): a fresh `play_game()` call, no override, must
    stamp "table" into both the crate's header knobs (so the search's own
    combat resolution honours the p.9 2" reach) and the result's own `knobs`
    summary (so a replay tool reads the record's own value back instead of
    re-deriving today's code default)."""
    res = sp.play_game(SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), None, **GAME)
    assert res["knobs"]["melee_reach"] == "table"


@needs_lists
def test_melee_reach_all_stays_absent_from_the_result_knobs():
    """The `ambush`/`los` idiom, not `sighting`'s: "all" is every corpus
    recorded so far, so a caller pinned to it (`LEGACY_FIDELITY_KNOBS`,
    `TRAINER_KNOBS`, and every existing byte-identical `result_digest` test
    that splats one of them in) must write the EXACT object it wrote before
    this knob existed — no new key anywhere, `test_aux_cap.py`'s
    `DEFAULT_27_DIGEST` included. The crate still played "all" underneath
    (`core.knobs()`); only the AUDIT summary stays silent about it."""
    core = nml_core.load(str(REPO))
    res = sp.play_game(
        SEED, str(ARMY1), str(ARMY2), str(REPO), str(BANK_DIR), core,
        melee_reach="all", **GAME,
    )
    assert "melee_reach" not in res["knobs"]
    assert core.knobs()["melee_reach"] == "all"
