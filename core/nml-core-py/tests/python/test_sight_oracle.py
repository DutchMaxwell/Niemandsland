"""D6a-B1 (NML-1073) — self-test for `tools/sight_oracle.py`: feed synthetic
acts where the SIGHTED count `s` is KNOWN and check it comes back out.
Three tiny fake act/dice pairs, built directly from the module's own data
shapes (no corpus files touched)."""

from __future__ import annotations

import json
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


def test_act_ordinal_is_interleaved_with_auto_lines(tmp_path):
    # NML-1094: `dice.jsonl` numbers by position among ALL body lines (kind
    # "act" OR "auto", PR #408), not among "act" lines alone. One "auto" line
    # ahead of the only "act" line must still land the right dice slice: act
    # is body position 2, so the recorded roll is stamped act=2, not act=1.
    head = {"profiles": {SHOOTER: {"name": "Shooter", "model_count": 4,
                                    "weapons": [{"attacks": 4, "count": 1, "range": 12}]}}}
    body = [
        {"kind": "auto"},
        {"kind": "act", "pick": {"action": {"unit": SHOOTER, "shoot": TARGET, "kind": 0}},
         "state": {"units": {SHOOTER: {"alive": 4, "attached": []}}}},
    ]
    game_dir = tmp_path / "game_1"
    game_dir.mkdir()
    lines = "\n".join(json.dumps(x) for x in [head, *body]) + "\n"
    (game_dir / "acts.jsonl").write_text(lines)
    dice = [{"act": 2, "roll_kind": "attack", "owner": "AI (Shooter)", "count": 4}]
    (game_dir / "dice.jsonl").write_text("\n".join(json.dumps(x) for x in dice) + "\n")

    records = so.collect(tmp_path, 0)

    assert len(records) == 1
    assert records[0]["act_no"] == 2
    assert records[0]["own"] == [4]
    assert so.bucket_of(records[0]) == "s_eq_alive"
