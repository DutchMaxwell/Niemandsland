"""AI-G4 round 6, row R21 F-CONSOL-LAND (rules epoch 73, GATE ONLY) - the melee gate replays a consolidation where the
table's consolidation LANDED.

A winner who wiped its enemy "may" move up to 3" (Consolidation Moves) - the book names no destination, so the core's
pick (the nearest marker its side does not own) and the table's planner pick are both legal. The table's own Dangerous
terrain test on ITS destination then has no core twin, and the gate filed that die under `morale_table_only` (a
`dangerous`-leg die read as a morale die). The gate now hands the core the table's recorded final charger centroid as a
NEUTRAL marker, for a charge whose next act shows the charger alive and the defender wiped, and tells a recorded
`dangerous`-leg die from a morale die. Neither the core nor the table changes.

THE BUNDLED ACT (the 1105 round-5a recording, GF 1000 pt NET arm, trimmed like `g4r5_dang_tail_melee`: the header, an
`auto` placeholder for every earlier activation, the act line, the NEXT act line and every roll up to the act):

  * `fixtures/g4r6_consol_land/gf_1000_net_005` act 26 - the Destroyer wipes the Change Sentinel Walker, consolidates 2.9"
    east and takes one Dangerous terrain test there (1 die, 6+); the core, aiming at the neutral marker to the
    south-west, crossed no dangerous ground and rolled none.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def melee(capsys, **kw) -> str:
    mrg.run(FIXTURES / "g4r6_consol_land", str(REPO), "table", 0, True, movement=True, **kw)
    return capsys.readouterr().out


def test_the_wiping_charge_is_full_equal_with_the_tables_consolidation_marker(capsys):
    """Before: 0/1 - the table's trailing 1-die 6+ roll was a die the core never rolled, `morale_table_only`.
    After: every roll equal, the die is the same face, and it is no morale die on either side."""
    out = melee(capsys)
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "0 table only" in out, out


def test_a_dangerous_leg_die_is_not_a_morale_die():
    """`trailing_morale` stops at a recorded `dangerous`-leg roll (a sixth tuple field); a `main`-leg die still counts."""
    defence = ("defense", 2, 5, [1, 6], "AI (Walker)")
    assert mrg.trailing_morale([defence, ("attack", 1, 6, [2], "AI (Destroyer)", "dangerous")]) == []
    morale = ("attack", 1, 4, [2], "AI (Destroyer)", "main")
    assert mrg.trailing_morale([defence, morale]) == [morale]
