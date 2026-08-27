"""GATE D1-B6a (NML-1073) — the recorded TRAY STREAM replays exactly.

`tools/dice_stream_gate.py` is the CORPUS gate against the full 168-game
`~/selfplay_out/qbd_ref` (run it directly — see that tool's docstring); this
file holds the same walk to one small in-repo fixture so the check always
runs, on a machine that never recorded the corpus.

The fixture is `fixtures/blessed_sisters_1000_vs_blood_brothers_1000_s31/`,
copied verbatim from that corpus's smallest game (9 rolls, 4 KB) — `dice.jsonl`
plus a minimal `arena_fixture_s31.json` carrying only the two fields the walk
reads, `dice_seed` and `seed`, both 31.

RED PROOF: burning one tray draw before the walk shifts the whole stream, so
the FIRST line must mismatch.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import dice_stream_gate as gate  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
GAME = FIXTURES / "blessed_sisters_1000_vs_blood_brothers_1000_s31"


def test_dice_seed_of_reads_and_cross_checks_the_arena_json():
    assert gate.dice_seed_of(GAME) == 31


def test_the_recorded_tray_stream_replays_exactly_on_the_twin():
    result = gate.walk_game(GAME)
    assert result.mismatch is None, result.mismatch
    assert result.rolls == 9
    assert result.kinds["attack"] == 6
    assert result.kinds["defense"] == 3


def test_red_an_extra_draw_shifts_the_stream_and_the_first_line_mismatches():
    result = gate.walk_game(GAME, red_extra_draw=True)
    assert result.mismatch is not None, "the extra draw must desync the tray"
    line_no, seq, roll_kind, detail = result.mismatch
    assert line_no == 1, "the fixture's first roll is count=1 — no d6 collision room"
    assert seq == 1
    assert roll_kind == "attack"
