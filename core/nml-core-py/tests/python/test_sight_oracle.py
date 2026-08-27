"""D6a-B1 (NML-1073) — self-test for `tools/sight_oracle.py`: feed synthetic
acts where the SIGHTED count `s` is KNOWN and check it comes back out.
Three tiny fake act/dice pairs, built directly from the module's own data
shapes (no corpus files touched)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import sight_oracle as so  # noqa: E402

SHOOTER = "shooter_1"
TARGET = "target_1"
HERO = "hero_1"


def make(alive: int, model_count: int, attacks: int, count: int, own: list[int],
          hero_rolls: list[int] | None = None, attached: list[str] | None = None) -> dict:
    """One synthetic act: a single ranged weapon, `own` recorded attack-roll
    counts under the shooter's own name, optional `hero_rolls` under HERO."""
    head = {"profiles": {
        SHOOTER: {"name": "Shooter", "model_count": model_count,
                  "weapons": [{"attacks": attacks, "count": count, "range": 12}]},
        HERO: {"name": "Hero"},
    }}
    state = {"units": {SHOOTER: {"alive": alive, "attached": attached or []}}}
    action = {"unit": SHOOTER, "shoot": TARGET, "kind": 0}
    dice = [{"roll_kind": "attack", "owner": "AI (Shooter)", "count": c} for c in own]
    dice += [{"roll_kind": "attack", "owner": "AI (Hero)", "count": c} for c in (hero_rolls or [])]
    return so.analyze_act(head, state, action, dice)


def test_sighting_below_alive_is_recovered():
    # attacks=5, count=1, model_count=5: s=3 -> round(5*3/5) = 3, unique in 0..5.
    rec = make(alive=5, model_count=5, attacks=5, count=1, own=[3])
    assert rec["candidates"] == [3]
    assert so.bucket_of(rec) == "sighting"


def test_full_alive_is_recovered_and_hero_roll_excluded():
    # attacks=4, count=1, model_count=4, alive=4: s=4 -> round(4*4/4) = 4.
    # A hero roll rides along under the same act and must NOT pollute "own".
    rec = make(alive=4, model_count=4, attacks=4, count=1, own=[4],
               hero_rolls=[2], attached=[HERO])
    assert 4 in rec["candidates"]
    assert so.bucket_of(rec) == "s_eq_alive"
    assert rec["hero_present"] is True
    assert rec["own"] == [4]


def test_impossible_count_is_unexplained():
    # attacks=3, count=1, model_count=5: reachable counts over s=0..5 are
    # {0, 1, 1, 2, 2, 3} -- 4 is never produced by any s.
    rec = make(alive=5, model_count=5, attacks=3, count=1, own=[4])
    assert rec["candidates"] == []
    assert so.bucket_of(rec) == "unexplained"
