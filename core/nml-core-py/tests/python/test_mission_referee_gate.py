"""Wave C gate C9.5 — `tools/mission_referee_gate.py`'s comparison, on a synthetic
one-game bundle built from acts_25's recorded header and first board.

The board: p1's first unit stands on the one relic, p2's first 0.3 m away. The
table's recorded `post` says p1 seized it and the unit picked it up. The core's
referee must reach exactly that (PASS); a recorded owner flipped to p2 must FAIL
(the comparison can fail); replaying without the carry step must part on
`carried_by` (the RED sees carry); a game stamped with another mission is refused.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import mission_referee_gate as gate  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core" / "tests" / "fixtures"


def _bundle(tmp_path, owners=(1,), mission="relic_hunt"):
    lines = (FIXTURES / "acts_25.jsonl").read_text().splitlines()
    header, pre = json.loads(lines[0]), json.loads(lines[1])["state"]
    first = {}
    for i, (key, unit) in enumerate(pre["units"].items()):
        first.setdefault(unit["player"], key)
        unit.update(alive=1, positions=[[2.0 + i, 0, 2.0 + i]], radii=[0.02], wounds=[1],
                    shaken=False, aircraft=False, ambush_arrived_round=0)
    pre["units"][first[1]]["positions"] = [[0.04, 0, 0]]
    pre["units"][first[2]]["positions"] = [[0.3, 0, 0]]
    pre.update(round=1, objectives=[{"pos": [0, 0, 0], "owner": 0}],
               markers_meta=[{"carry": True, "carried_by": ""}], destroy_seq=[0])
    post = {"owners": list(owners), "vp": [0, 0], "destroy_seq": [0],
            "markers_meta": [{"carry": True, "carried_by": first[1]}]}
    d = tmp_path / "ref" / "g1"
    d.mkdir(parents=True)
    (d / "acts.jsonl").write_text(json.dumps(header) + "\n")
    (d / "rounds.jsonl").write_text(json.dumps({"round": 1, "pre": pre, "post": post}) + "\n")
    (d / "arena_g1.json").write_text(json.dumps({"mission": {"name": mission},
                                                 "rounds_played": 1}))
    return d


def _judge(d, mission="relic_hunt", skip_carry=False):
    return gate.judge_game(nml_core.load(str(REPO)), d, mission, skip_carry)


def test_the_tables_own_ledger_passes(tmp_path):
    g = _judge(_bundle(tmp_path))
    assert [r["parted"] for r in g["rounds"]] == [[]]
    assert g["rounds"][0]["pickups"] == 1
    assert gate.report("relic_hunt", tmp_path, [g], False, 1) == 0


def test_a_flipped_recorded_owner_fails(tmp_path):
    g = _judge(_bundle(tmp_path, owners=(2,)))
    assert g["rounds"][0]["parted"] == ["owners"]
    assert gate.report("relic_hunt", tmp_path, [g], False, 1) == 1


def test_too_few_pickups_is_inconclusive_not_pass(tmp_path):
    g = _judge(_bundle(tmp_path))
    assert gate.report("relic_hunt", tmp_path, [g], False, 5) == 2


def test_the_red_without_the_carry_step_parts_on_the_carrier(tmp_path):
    g = _judge(_bundle(tmp_path), skip_carry=True)
    assert g["rounds"][0]["parted"] == ["carried_by"]
    assert gate.report("relic_hunt", tmp_path, [g], True, 1) == 0


def test_a_game_stamped_with_another_mission_is_refused(tmp_path):
    g = _judge(_bundle(tmp_path, mission="duel"))
    assert "refused" in g
    assert gate.report("relic_hunt", tmp_path, [g], False, 1) == 1
