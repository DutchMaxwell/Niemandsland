"""AI-G4F1 (DIAG-PARITY D-A) — the replay gates compare a SAVE target the way the dice read it.

The core clamps the summed save target into 2..6 once (`dice.rs` `save_target(..).clamp(2, 6)`,
since `EPOCH_68_MODIFIER_SUM`); the table hands the tray the raw sum (`main.gd` `base_defense + ap`).
A 6 always saves and a 1 always fails (`successes()`), so a 10+ and a 6+ block the very same faces:
same outcome, and the gates must call the two rolls equal. What is pinned:

  * a DEFENSE roll at 10+ (table) against 6+ (port), same count and faces -> no parted field;
  * a real save difference (5+ against 6+) still parts on `target`;
  * an ATTACK roll is never clamped: 10+ against 6+ still parts on `target`;
  * the melee gate walks the SAME compare, not a copy of it.

Gate tooling only: no rules epoch, no battle-log line.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

FACES = [6, 3, 1]


def roll(kind: str, target: int) -> tuple:
    """A (kind, count, target, faces, owner) tuple as both gates build them."""
    return (kind, len(FACES), target, FACES, "AI (Hive Swarms)")


def test_a_save_past_six_reads_the_same_as_a_six_plus_save():
    # g000 act 24 (shooting, 6+ vs 10+) and g001 melee act 10 (6+ vs 8+).
    assert srg.parted_field(roll("defense", 6), roll("defense", 10)) is None
    assert srg.parted_field(roll("defense", 6), roll("defense", 8)) is None


def test_a_real_save_difference_still_parts_on_the_target():
    assert srg.parted_field(roll("defense", 5), roll("defense", 6)) == "target"


def test_an_attack_target_is_never_clamped():
    assert srg.parted_field(roll("attack", 6), roll("attack", 10)) == "target"


def test_count_and_kind_still_part_first():
    assert srg.parted_field(roll("defense", 6), roll("attack", 6)) == "kind"
    assert srg.parted_field(roll("defense", 6), ("defense", 2, 10, [6, 3], "x")) == "count"


def test_the_melee_gate_walks_the_shared_compare():
    assert mrg.parted_field is srg.parted_field
