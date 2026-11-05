"""AI-G4 round 5, R16 H-EXTRA-DIE-FIVES (the label tail of R15, replay row aof_1000_net_032 act 31).

The table signs the extra attack die a joined hero's Primal form earns with the HOST's label, the core with the rolling
member's. The gate relaxes that label (`extra_die_hosts`) but only behind an unmodified SIX; the Champion's extra die in
aof_032 act 31 is triggered by a 5 alone (the widened window), so it parted as `owner`. The label is relaxed behind a
six OR a five now. Only the label: count, target and faces stay compared in full (the roll compare is not touched here).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

PROFILES = {
    "host": {"name": "Host Unit", "special_rules": [], "weapons": []},
    "hero": {"name": "Champion", "special_rules": ["Primal"], "weapons": []},
}
PLAIN = {"units": {"host": {"attached_to": None}, "hero": {"attached_to": "host"}}}


def roll(count: int, faces: list[int]) -> dict:
    return {"kind": "attack", "count": count, "target": 4, "faces": faces, "owner": "Champion"}


def test_an_extra_die_behind_a_five_alone_carries_the_hosts_label() -> None:
    rolls = [roll(3, [5, 2, 3]), roll(1, [4])]
    assert srg.extra_die_hosts(rolls, PLAIN, PROFILES) == {1: "Host Unit"}


def test_an_extra_die_behind_a_six_still_carries_the_hosts_label() -> None:
    rolls = [roll(3, [6, 2, 3]), roll(1, [4])]
    assert srg.extra_die_hosts(rolls, PLAIN, PROFILES) == {1: "Host Unit"}


def test_a_roll_behind_no_six_and_no_five_is_no_extra_die() -> None:
    rolls = [roll(3, [4, 2, 3]), roll(1, [4])]
    assert srg.extra_die_hosts(rolls, PLAIN, PROFILES) == {}


def test_the_dice_count_must_still_match_the_triggers() -> None:
    rolls = [roll(3, [5, 5, 3]), roll(1, [4])]
    assert srg.extra_die_hosts(rolls, PLAIN, PROFILES) == {}
