"""ANALYSIS MODE's replay merge — every knob PR #624 stamps has to come back
off the RECORD, not off `gen0_replay_one.KNOBS`'s gen0-era pins, or a game
played with the shipped defaults leaves the recording partway through and
`game_narrator.replay()` raises `IndexError` instead of narrating (DEFECT_
LEDGER: the pre-fix merge read back only the six W5a menu/sight/ambush keys,
leaving charge_gate/hero_attach/charge_landing/sighting/cond_ap/objectives
pinned to gen0's own values under an arena record that plays every one of
them differently).

Reproduces on a FRESH game, no value-net seat needed: `play_game(dice=
"table", deployment="arena")` alone diverges under the pre-fix mapping —
confirmed by hand before this fix landed, so this test needs no copy of a
real `token_ab_value_shipped` record.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import gen0_replay_one as gr  # noqa: E402
import game_narrator as gn  # noqa: E402
import selfplay  # noqa: E402

BANK = Path(gr.BANK)
LISTS = Path(gr.LISTS)
P1 = LISTS / "change_disciples_1000.json"
P2 = LISTS / "robot_legions_1000.json"

needs_fixtures = pytest.mark.skipif(
    not (BANK.is_dir() and P1.exists() and P2.exists()),
    reason="terrain bank or the 1000-pt ai_lists mirror absent",
)


@needs_fixtures
def test_a_fresh_shipped_defaults_game_replays_every_recorded_pick(tmp_path):
    """PR #624's own defaults, spelled out for clarity even though they are
    also `play_game`'s bare defaults now: a game played this way stamps
    every knob `game_narrator.replay()` must read back off the header."""
    out = selfplay.play_game(4242, str(P1), str(P2), gr.REPO, str(BANK), None,
                              dice_seed=4242, dice="table", deployment="arena",
                              menu_wide="table", menu_los="resolve", los="model",
                              charge_gate="table", hero_last=True, cast_fold=True,
                              ambush="table")
    rec_path = tmp_path / "fresh_shipped.json"
    rec_path.write_text(json.dumps(out), encoding="utf-8")
    rec, acts = gn.replay(str(rec_path), str(LISTS), gr.REPO, str(BANK))
    assert len(acts) == len(out["planner_positions"]) > 0
    assert (rec["winner"], rec["vp"]) == (out["winner"], out["vp"])
