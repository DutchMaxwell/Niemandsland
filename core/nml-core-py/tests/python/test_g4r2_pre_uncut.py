"""AI-G4 round 2, rows F-PRE-UNCUT (shoot) and G4-H8 (melee), rules epoch 73 - a dangerous test in front of the
cast leg is cut WITH the cast leg.

The table's activation is [movement] -> dangerous-terrain test -> spell cast -> volley (or pile-in and melee).
`cut_pre_legs` (F-H1b) cut the cast/spell legs only when they LED the act; with the dangerous test in front it left
the act as recorded, so the table's cast die was compared against the core's volley and the act could not be
FULL-equal by construction (the gate printed "pre: 180 cut; 9 left uncut" on the shoot replay, 2 of 51 on the charge
replay). The cut now takes the leading dangerous test along: its dice and the cast legs' are burned off the tray in
one prefix, the state is patched from the `pre` line, and the core's own dangerous test is switched off for that one
act (header knob `dangerous`, restored afterwards) - it would roll a second set of dice the tray has already spent.
A dangerous test with NO cast leg behind it stays the core's.

THE BUNDLED GAMES (the 1104 recording, AoF/GF 1000 pt NET arm, trimmed like the other fixtures: the header, the one
act line and its `pre` line, `auto` placeholders before it, every roll up to it verbatim, its shots):

  * `fixtures/g4r2_pre_uncut_shoot/gf_1000_net_039` act 19 - dangerous (3 dice, 6+), cast (1 die, 5+), volley.
  * `fixtures/g4r2_pre_uncut_melee/aof_1000_net_039` act 9  - dangerous (12 dice), cast (1 die), melee, morale, and a
    second dangerous test (4 dice) after the pile-in that the core never draws (not this row's cause).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def shoot(capsys, **kw) -> str:
    srg.run(FIXTURES / "g4r2_pre_uncut_shoot", str(REPO), "table", 0, 99, True, sighting="model", movement=True, **kw)
    return capsys.readouterr().out


def test_shoot_act_19_is_full_equal_with_the_dangerous_test_cut(capsys):
    out = shoot(capsys)
    assert re.search(r"EQUAL : 1/1 acts FULL-equal", out), out
    assert "1 acts with the table's cast/spell leg cut; 0 left uncut" in out, out


def test_cut_without_burn_parts_the_shoot_act_at_the_faces(capsys):
    out = shoot(capsys, red_pre="noburn")
    assert "EQUAL : 0/1 acts FULL-equal" in out, out
    assert "faces=1" in out, out


def test_melee_act_9_matches_every_roll_the_core_draws_with_the_dangerous_test_cut(capsys):
    """Before: the table's cast die was compared with the melee and the act parted at roll 2 (count). After: all
    nine rolls the core draws match; the act stays ONE roll short of FULL-equal because the table closes it with a
    second dangerous test (4 dice, after the pile-in) the core does not draw - a different cause, pinned as such."""
    mrg.run(FIXTURES / "g4r2_pre_uncut_melee", str(REPO), "table", 0, True, movement=True)
    out = capsys.readouterr().out
    assert "1/1 acts PREFIX-equal (the overlap held; 1 table_longer, 0 port_longer)" in out, out
    assert "parted: 0 shape, 0 faces" in out, out


def test_a_dangerous_test_in_front_of_the_cast_leg_is_cut_with_it():
    """Dangerous (5 dice) + cast (1 die) lead the act: both leave the compared list and 6 draws are burned."""
    rolls = [{"leg": "dangerous", "count": 5}, {"leg": "cast", "count": 1}, {"leg": "main", "count": 4}]
    kept, draws, plain = srg.cut_pre_legs(rolls, {"units": {}}, {}, True, True)
    assert kept == rolls[2:] and draws == 6
    assert srg.cut_dangerous(rolls, kept), "the core's own dangerous test must be switched off for this act"


def test_a_dangerous_test_without_a_cast_leg_stays_the_cores():
    rolls = [{"leg": "dangerous", "count": 5}, {"leg": "main", "count": 4}]
    kept, draws, plain = srg.cut_pre_legs(rolls, {"units": {}}, {}, True, True)
    assert kept == rolls and draws == 0
    assert not srg.cut_dangerous(rolls, kept)
