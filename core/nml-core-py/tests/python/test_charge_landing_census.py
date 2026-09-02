"""GATE for `tools/charge_landing_census.py` (NML-1157) — the RIGID charge arm
against the table's own mover, on recorded states.

THE FINDING it pins. Reviewing the Gen-0 teacher corpus turned up "the mover
fails inside the band": 6 of the 10 in-band charges over ten narrated games
never reached contact. The mover LADDER is not the cause — the corpus is
recorded with `movement="rigid"`, where `mv::step::charge_move` never runs. The
cause is `sim::spacing_fraction` (sim.rs:1877-1940): the CHARGE candidate aims
at the target unit's CENTRE (menu.rs:552), the rigid delta is clamped to the
band, and then ONE scalar fraction is fitted so that no mover model sits inside
any other unit's disc plus a 1" buffer. A single model of a third unit stops the
whole formation.

Reproducing `spacing_fraction` in Python on the replayed before-state returns
the replay's own displacement to the hundredth of an inch for every charge
tested, which is what makes it "the" cause rather than "a" cause.

WHAT THE TOOL ADDS: the same states run through `Core.charge_move`, i.e. what
`movement="table"` would have done. On `gen0_s321686_d323686` +
`gen0_s325542_d326542` the answer is 2 of the 4 in-band short charges converted
to contact and 2 honest misses — the number the "record Gen-1 with
movement=table" rung rests on.

THE RED (`--red-farthest`) asks the ported mover for the FARTHEST living enemy
instead of the recorded target. The conversions must collapse to zero; a census
that still reports them is measuring something other than reach.

SKIP: needs the Gen-0 teacher corpus, the terrain bank and the private AI lists,
all outside the repo — the same escape hatch every corpus-backed test here uses.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

import charge_landing_census as clc  # noqa: E402
import gen0_replay_one as gr  # noqa: E402

CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(gr.LISTS)
#: Two games of `REVIEW_games_11-20.md`: the first carries the two charges the
#: rigid arm loses, the second the 0.72" charge it gets RIGHT (the review read
#: that one as a failure; the replay says 12 dice and a real melee).
GAMES = ("gen0_s321686_d323686.json", "gen0_s325542_d326542.json")


def _missing() -> bool:
    return not (BANK.is_dir() and LISTS.is_dir() and all((CORPUS / g).exists() for g in GAMES))


@pytest.fixture(scope="module")
def rows():
    clc.tap_state()
    out = []
    for g in GAMES:
        out += clc.census(str(CORPUS / g), str(LISTS))
    return out


@pytest.mark.skipif(_missing(), reason="gen0_teacher corpus / terrain bank / ai_lists not present")
def test_the_census_reproduces_the_reviewed_charges(rows):
    """The shape of the two games, so a corpus swap is loud rather than silent."""
    t = clc.tally(rows)
    assert t["charges"] == 13, t
    assert t["in_band"] == 5, t
    assert t["at_a_joined_hero"] == 8, "8 of 13 charges name a 1-model joined hero: %s" % t


@pytest.mark.skipif(_missing(), reason="gen0_teacher corpus / terrain bank / ai_lists not present")
def test_the_rigid_arm_loses_charges_the_table_mover_lands(rows):
    """THE FINDING. 4 of the 5 in-band charges fall short under the rigid arm;
    the ported mover lands 2 of them from the identical state."""
    t = clc.tally(rows)
    assert t["in_band_rigid_short"] == 4, t
    assert t["rigid_lost_table_lands"] == 2, t
    assert t["honest_miss"] == 2, "the other two are the band's honest bar, not the arm's: %s" % t


@pytest.mark.skipif(_missing(), reason="gen0_teacher corpus / terrain bank / ai_lists not present")
def test_the_two_lost_charges_by_name(rows):
    """Named, so a regression says WHICH activation moved."""
    lost = {(r["act"], r["unit"]) for r in rows
            if r["in_band"] and not r["rigid_contact"] and r["table_contact"]}
    assert lost == {(18, "Battle Brothers"), (40, "Battle Brothers")}, lost
    a40 = next(r for r in rows if r["act"] == 40 and r["unit"] == "Battle Brothers")
    # Declared at 5.15" on a 12" band; the rigid arm's spacing clamp left it at
    # 1.35", 0.35" outside MELEE_ENGAGE_IN, having spent 3.87" of 12".
    assert a40["declared_in"] < a40["band_in"] / 2
    assert a40["rigid_gap_in"] > clc.MELEE_ENGAGE_IN
    assert a40["table_gap_in"] < clc.MELEE_ENGAGE_IN
    assert a40["table_arc_in"] < a40["band_in"], "the table's mover did not even need the band"


@pytest.mark.skipif(_missing(), reason="gen0_teacher corpus / terrain bank / ai_lists not present")
def test_the_charge_the_rigid_arm_gets_right(rows):
    """`gen0_s325542` A41 was read as the corpus's worst failure ("declared at
    1.02\", moved 0.75\", still missed"). Replayed, it is the one in-band charge
    the rigid arm lands: folded gap 0.72", landing 0.00", a real melee."""
    a41 = next(r for r in rows if r["act"] == 41 and r["unit"] == "Blood Battle Brothers")
    assert a41["in_band"] and a41["rigid_contact"] and a41["table_contact"]
    assert a41["dice"] > 0, "it drew dice — both directions of a full melee"


@pytest.mark.skipif(_missing(), reason="gen0_teacher corpus / terrain bank / ai_lists not present")
def test_red_the_farthest_target_converts_nothing():
    """The census measures REACH: point the ported mover at the farthest enemy
    and every conversion must go."""
    clc.tap_state()
    red = []
    for g in GAMES:
        red += clc.census(str(CORPUS / g), str(LISTS), red_farthest=True)
    t = clc.tally(red)
    assert t["in_band_rigid_short"] == 4, "the rigid arm is untouched by the red: %s" % t
    assert t["rigid_lost_table_lands"] == 0, "RED: the table converts nothing at range: %s" % t
