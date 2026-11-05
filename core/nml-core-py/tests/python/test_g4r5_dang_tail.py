"""AI-G4 round 5, row R1 F-DANG-TAIL (rules epoch 73) - a Dangerous test the gate cuts takes its TAIL with it.

When the replay gate cuts the table's Dangerous test (`cut_pre_legs` + `cut_dangerous`, G4-H8) the core rolls none of
its own, and used to lose two things the table does after it: (a) the end-of-activation morale test for the test's
wounds is armed INSIDE the core's test block, so it was never rolled; (b) the cut test's wounds never reached the
charger's self-inflicted tally in the melee result, so the melee was not lost and nobody tested morale.

The gate now hands the core the unit's act-start (alive, wounds) in the header knob `dangerous_replay`; the core reads
the difference to the patched state. In-game play never sets the knob (the Rust test `the_live_test_is_untouched_by_the_
replay_key` pins the play leg).

THE BUNDLED ACTS (the 1105 round-4 recording, AoF/GF 1000 pt NET arm, trimmed like the other fixtures: the header,
`auto` placeholders before the act, the act line and its `pre` line, every roll up to it verbatim, its shots):

  * `fixtures/g4r5_dang_tail_shoot/aof_1000_net_003` act 24  - the table's only roll after the cast leg is the unit's morale test.
  * `fixtures/g4r5_dang_tail_shoot/aof_1000_net_033` act 25  - table-longer by exactly the trailing morale die (a hero tests for the unit).
  * `fixtures/g4r5_dang_tail_shoot/gf_1000_net_047` act 10   - table-longer by exactly the trailing morale die.
  * `fixtures/g4r5_dang_tail_melee/gf_1000_net_002` act 11   - the charger's 2 self-inflicted wounds lose the melee; the hero tests morale.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def shoot(capsys, **kw) -> str:
    srg.run(FIXTURES / "g4r5_dang_tail_shoot", str(REPO), "table", 0, 99, True, sighting="model", movement=True, **kw)
    return capsys.readouterr().out


def melee(capsys, **kw) -> str:
    mrg.run(FIXTURES / "g4r5_dang_tail_melee", str(REPO), "table", 0, True, movement=True, **kw)
    return capsys.readouterr().out


def test_the_three_shooting_acts_are_full_equal_with_the_cut_tests_tail(capsys):
    out = shoot(capsys)
    assert "EQUAL : 3/3 acts FULL-equal" in out, out


def test_the_charge_act_is_full_equal_with_the_cut_tests_wounds_in_the_melee_result(capsys):
    out = melee(capsys)
    assert "EQUAL : 1/1 acts FULL-equal" in out, out


def test_the_mutant_with_the_knob_off_parts_the_four_acts_again(capsys):
    """`--red-dang-tail` hands the core no `dangerous_replay`: the old numbers - all four acts part."""
    assert "EQUAL : 0/3 acts FULL-equal" in shoot(capsys, red_dang_tail=True)
    assert "EQUAL : 0/1 acts FULL-equal" in melee(capsys, red_dang_tail=True)


def test_dang_replay_reads_the_act_start_chain_in_the_cores_morale_terms():
    """The host plus its joined hero; the hero's models count in `alive` only with `hero_counts_in_size`."""
    units = {"host": {"alive": 5, "wounds": [1] * 5, "attached": ["hero"]}, "hero": {"alive": 1, "wounds": [3]}}
    assert srg.dang_replay(units, "host", {}) == [5, 8]
    assert srg.dang_replay(units, "host", {"hero_counts_in_size": True}) == [6, 8]
    assert srg.dang_replay({"solo": {"alive": 1, "wounds": [4]}}, "solo", {}) == [1, 4]
