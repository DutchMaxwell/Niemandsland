"""Ambush-audit follow-up to gen0_stats.py's step 1 (coordinator request after
PR #563): the twin never arrives a reserved Ambush unit (selfplay.py
~1528-1536), so any Gen-0 game whose army carries an Ambush / Infiltrate /
Rapid Ambush / Ambush Beacon unit was played short-handed. `ambush_audit`
resolves each `armies.<side>` box path (`/root/ai_lists/<list>.json`) to a
local list under a caller-given `list_dir`, so this test never touches the
private `~/nml-mission/farm/ai_lists` or the read-only corpus.

RED: a synthetic list with one Ambush unit must count 1 affected game;
removing the rule from that same list must count 0.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import gen0_stats  # noqa: E402

GAME = {"armies": {"p1": "/root/ai_lists/carrier_1000.json", "p2": "/root/ai_lists/carrier_1000.json"}}


def _write_list(tmp_path, rules):
    unit = {"name": "Beacon Troop", "rules": rules, "items": []}
    (tmp_path / "carrier_1000.json").write_text(json.dumps({"units": [unit]}))


def test_ambush_audit_counts_the_carrier(tmp_path):
    _write_list(tmp_path, [{"name": "Ambush"}])
    s = gen0_stats.ambush_audit([("g1.json", GAME)], tmp_path)
    assert s["affected_games"] == 1
    assert s["carriers_per_affected_game"]["mean"] == 2   # both sides use the same list
    assert s["affected_points_split"] == {1000: 1}
    assert s["lists_with_ambushers"] == {"carrier_1000.json": ["Beacon Troop"]}


def test_ambush_audit_counts_zero_without_the_rule(tmp_path):
    _write_list(tmp_path, [])
    s = gen0_stats.ambush_audit([("g1.json", GAME)], tmp_path)
    assert s["affected_games"] == 0
    assert s["affected_points_split"] == {}
    assert s["lists_with_ambushers"] == {}
