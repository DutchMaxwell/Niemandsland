"""PLAN A2 — `tools/rule_fire_census.py` on a synthetic corpus.

The tool's real inputs are the two private reference corpora; this file
builds a miniature one in `tmp_path` (one game: header, one shooting act, an
auto line, one charge act, a two-roll dice tape) and pins the claims the
census must stand on:

  * FIRED counts are the per-act `prof` stamp plus the static header rules of
    alive units — a dead unit's rules must not count, and the auto line
    (which carries no state) must not crash the interleaved ordinal the dice
    join uses.
  * the gate-class labelling lands each rule in the family its effect
    actually needs (the dice kind, the charge class, the volley class,
    unverified), and the verdict column says identical / covered /
    unverified — never more than the corpus proves.
  * the ZERO-FIRE list holds the rules that never went live, ranked by book
    occurrences from the A1 coverage JSON.
  * the RED knob moves exactly the mislabelled rule's acts out of its true
    class — a mislabel that moves nothing proves nothing.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import rule_fire_census as census_mod  # noqa: E402

U1 = "unit-one"
U2 = "unit-two"


def write_corpus(root: Path) -> Path:
    """One game dir with the two field shapes the census reads: the header
    (static rules, weapon rules) and per-act `prof` stamps. Ordinals are the
    INTERLEAVED act|auto positions (1-based): the shooting act is 1, the
    auto line 2, the charge act 3 — auto bumps the counter too."""
    game = root / "testers_1000_vs_targets_1000_s1"
    game.mkdir(parents=True)
    header = {
        "kind": "header",
        "profiles": {
            U1: {"name": "Regenerators", "game_system": "gf",
                 "special_rules": ["Regeneration", "Tough(2)"],
                 "attached_hero_rules": [], "item_grants": [],
                 "weapons": [{"name": "Spitter", "rules": ["AP(1)"]}]},
            U2: {"name": "Striders", "game_system": "gf",
                 "special_rules": ["Strider"],
                 "attached_hero_rules": [], "item_grants": [],
                 "weapons": [{"name": "Club", "rules": []}]},
        },
        "knobs": {},
    }

    def prof(rules: list) -> dict:
        return {"special_rules": rules, "attached_hero_rules": [],
                "item_grants": []}

    shoot_act = {
        "kind": "act", "round": 1, "player": 1,
        "pick": {"action": {"kind": 1, "shoot": U2, "unit": U1}},
        "state": {"units": {U1: {"alive": 1, "prof": prof(["Regeneration"])},
                            U2: {"alive": 1, "prof": prof(["Strider"])}}},
    }
    charge_act = {
        "kind": "act", "round": 2, "player": 2,
        "pick": {"action": {"kind": 3, "charge": U1, "unit": U2}},
        "state": {"units": {U1: {"alive": 0, "prof": prof(["Regeneration"])},
                            U2: {"alive": 1, "prof": prof(["Melee Shrouding"])}}},
    }
    auto = {"kind": "auto", "round": 1, "player": 1, "unit": U1, "action": 0}
    with (game / "acts.jsonl").open("w") as f:
        for i, line in enumerate([header, shoot_act, auto, charge_act], 1):
            if line["kind"] in ("act", "auto"):
                line = dict(line, act=i)   # what read_game stamps
            f.write(json.dumps(line, sort_keys=True) + "\n")
    dice = [
        {"act": 1, "roll_kind": "regeneration", "count": 1, "target": 6,
         "faces": [3], "owner": "Regenerators", "player": 1, "seq": 1},
        {"act": 3, "roll_kind": "attack", "count": 2, "target": 4,
         "faces": [2, 5], "owner": "Striders", "player": 2, "seq": 2},
    ]
    with (game / "dice.jsonl").open("w") as f:
        for rec in dice:
            f.write(json.dumps(rec, sort_keys=True) + "\n")
    return root


def write_repo(root: Path) -> Path:
    """A miniature mechanics map + A1 coverage file (the census reads both
    from paths at runtime, never from the private snapshots)."""
    assets = root / "assets" / "solo"
    assets.mkdir(parents=True)
    (assets / "rules_mechanics_gf.json").write_text(json.dumps({
        "common": {
            "Regeneration": {"primitive": "Regeneration"},
            "Blast": {"primitive": "Shot Modifier"},
            "Melee Shrouding": {"primitive": "Melee Shrouding"},
            "Bulwark": {"primitive": "Utility Buff"},
            "Rapid Rush": {"primitive": "Rapid Rush"},
        },
        "factions": {},
    }))
    (assets / "rules_mechanics_aof.json").write_text(json.dumps(
        {"common": {}, "factions": {}}))
    (root / "coverage.json").write_text(json.dumps({
        "rows": {
            "Regeneration": {"occ": 12, "occ_by_system": {"gf": 8, "aof": 4}},
            "Blast": {"occ": 30, "occ_by_system": {"gf": 30}},
            "Bulwark": {"occ": 5, "occ_by_system": {"gf": 5}},
        },
    }))
    return root


def census_for(root: Path, red: str | None = None) -> dict:
    return census_mod.census(root, root, root, root / "coverage.json", red)


def test_fire_counts_join_prof_stamp_and_header(tmp_path: Path) -> None:
    root = write_corpus(write_repo(tmp_path))
    rows = census_for(root)["rows"]
    # act 1: u1 (Regeneration + static Tough/AP) and u2 (Strider) alive.
    assert rows["Regeneration"]["fired_qbg"] == 1
    assert rows["Tough"]["fired_qbg"] == 1          # header static, alive act
    assert rows["AP"]["fired_qbg"] == 1             # weapon rule, alive act
    assert rows["Strider"]["fired_qbg"] == 2        # u2 alive in BOTH acts
    # act 3 (after the auto line): u1 is DEAD — its rules must not count again.
    assert rows["Regeneration"]["fired_qbg"] == 1
    assert rows["Melee Shrouding"]["fired_qbg"] == 1
    # the real per-die fire count off the tape's roll_kind (NML-1104).
    assert rows["Regeneration"]["dice_fires_qbg"] == 1
    # Blast never went live: zero fire, despite its book occurrences.
    assert not rows["Blast"]["in_corpus"]


def test_classes_verdicts_and_zero_fire_ranking(tmp_path: Path) -> None:
    root = write_corpus(write_repo(tmp_path))
    res = census_for(root)
    rows = res["rows"]
    assert rows["Regeneration"]["class"] == "dice_stream"
    assert census_mod.verdict_of(rows["Regeneration"]) == "identical"
    assert rows["Melee Shrouding"]["class"] == "melee_replay"
    assert census_mod.verdict_of(rows["Melee Shrouding"]) == "covered"
    assert rows["AP"]["class"] == "shoot_replay"
    assert census_mod.verdict_of(rows["AP"]) == "covered"
    assert rows["Strider"]["class"] == "unverified"
    assert census_mod.verdict_of(rows["Strider"]) == "unverified"
    # the heuristic must not swallow "ap" inside "rapid" (whole-word match).
    assert rows["Rapid Rush"]["class"] == "unverified"
    s = res["summary"]
    # A1 coverage ranks the zero-fire list: Blast (30 occ) before Bulwark (5).
    assert s["zero_fire_ranked"][:2] == ["Blast", "Bulwark"]
    assert rows["Blast"]["book_occ"] == 30
    # the act-class tally: one shooting act, one melee act, both with a
    # recorded roll under their interleaved ordinal -> gate-comparable.
    qbg = res["qbg"]["classes"]
    assert qbg["shooting"]["acts"] == 1 and qbg["shooting"]["with_rolls"] == 1
    assert qbg["melee"]["acts"] == 1 and qbg["melee"]["with_rolls"] == 1


def test_pairs_count_cooccurrence_per_act_unit(tmp_path: Path) -> None:
    root = write_corpus(write_repo(tmp_path))
    pairs = {(e["pair"][0], e["pair"][1]): e
             for e in census_for(root)["pairs"]}
    # act 1, unit u1: {Regeneration, Tough, AP} -> three pairs, once each.
    assert pairs[("AP", "Regeneration")]["qbg"] == 1
    assert pairs[("AP", "Tough")]["qbg"] == 1
    assert pairs[("Regeneration", "Tough")]["qbg"] == 1
    # act 3, unit u2: static Strider joins the prof stamp -> one pair.
    assert pairs[("Melee Shrouding", "Strider")]["qbg"] == 1
    # pairs never bridge units: u1's rules never pair with u2's Strider.
    assert not any(("Strider" in e["pair"] and e["pair"] != ["Melee Shrouding", "Strider"])
                   for e in census_for(root)["pairs"])


def test_red_class_moves_exactly_the_mislabelled_rule(tmp_path: Path) -> None:
    root = write_corpus(write_repo(tmp_path))
    res = census_for(root, red="Melee Shrouding")
    red = res["red"]
    assert red["true_class"] == "melee_replay"
    # its ONE fired act leaves the melee_replay bucket — exactly, both corpora.
    assert red["moved"]["qbg"] == {"before": 1, "after": 0, "drop": 1}
    assert red["moved"]["qag"] == {"before": 1, "after": 0, "drop": 1}
    assert red["ok"]
    # the mislabel is visible on the row itself.
    assert res["rows"]["Melee Shrouding"]["class"] == "unverified"
    assert res["rows"]["Melee Shrouding"]["class_green"] == "melee_replay"


def test_summary_lines_and_report(tmp_path: Path) -> None:
    root = write_corpus(write_repo(tmp_path))
    res = census_for(root)
    lines = census_mod.summary_lines(res)
    assert any("RULE-FIRE universe" in ln for ln in lines)
    report = census_mod.markdown_report(res)
    assert "ZERO-FIRE list" in report and "Blast" in report
    assert "rule PAIRS" in report
    out = tmp_path / "out.json"
    out.write_text(json.dumps(res, sort_keys=True))
    assert json.loads(out.read_text())["summary"]["rules_fired"] == 5
