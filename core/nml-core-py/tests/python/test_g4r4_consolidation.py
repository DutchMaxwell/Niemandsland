"""AI-G4 round 4, row G4R4-CONS (rules epoch 73) - the Consolidation Moves of a melee, and the Dangerous terrain
test the move can cost.

After the melee the table moves a unit (the charger back 1" when neither side was destroyed, the survivor up to 3"
when the enemy was) and then tests the ground it reaches. The core's charge path drew none of it, so the table's
act ended on one die the core never rolled and the AI's search never priced the test.

THE BUNDLED ACTS (the 1104 recording, AoF 1000 pt NET arm, trimmed like `g4r2_pre_uncut_melee`: the header, an `auto`
placeholder for every earlier activation, the one act line, every roll up to it verbatim):

  * `fixtures/g4r4_consolidation/aof_1000_net_039` act 24 - the charger wipes its target, consolidates up to 3" onto
    Dangerous ground and tests it (2 dice); the test costs a wound, so the unit ends one model short of the core's
    old picture (table 10 alive, core 11).
  * `fixtures/g4r4_consolidation/aof_1000_net_003` act 27 - neither side is destroyed: the charger moves back 1" and
    tests that ground (1 die).

aof_1000_net_039 act 9 (a wipe + 3" consolidation) is pinned in `test_g4r2_pre_uncut.py`; act 14 also needs the rout
to take the joined hero with its host (a different row), so it is not bundled here.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def test_both_consolidation_acts_are_full_equal_with_the_trailing_dangerous_test(capsys):
    """Before: each act was ONE roll short (the table's trailing test) and the after-state parted (act 24: 11 models
    against the table's 10). After: every roll, the owner and the after-state equal."""
    mrg.run(FIXTURES / "g4r4_consolidation", str(REPO), "table", 0, True, movement=True)
    out = capsys.readouterr().out
    assert "EQUAL : 2/2 acts FULL-equal" in out, out
    assert "parted: 0 shape, 0 faces" in out, out
