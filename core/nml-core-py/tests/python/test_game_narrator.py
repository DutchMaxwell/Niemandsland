"""ANALYSIS MODE — the narrator's own red-green.

Two halves, the way `test_gen0_replay_one.py` splits:

  * the DISPLAY layer on its own (`narrator_render`), which imports nothing but
    `json` and so runs anywhere: a candidate must name its actor (the menu spans
    every un-activated unit, so an unnamed candidate reads as a duplicate of the
    one above it), a 6 must always succeed and a 1 always fail, and an
    ITEM-granted rule — Ambush arriving through "Winged Breed" — must reach the
    army table, because that is the rule this corpus is known to drop;

  * the TOOL end to end on a real corpus game, through its CLI so the module's
    monkeypatching of `selfplay._pick_for` never leaks into the rest of the
    suite. GREEN: one `###` block per recorded planner position, and no model
    moving further than its own band. RED: one destination coordinate nudged by
    1e-9 on a COPY of the game must make the run RAISE and name the position —
    the fidelity tripwire of PR #564, which is what stops this tool narrating a
    game that was never played.

The corpus half skips where the corpus, the army lists or the terrain bank are
absent (CI), and reproduces only when `PYTHONPATH` points at a private
`nml_core` module — the tool's contract, inherited from #564.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))

import narrator_render as nr  # noqa: E402

CORPUS = Path(os.path.expanduser("~/selfplay_out/gen0_teacher"))
BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
GAME = "gen0_s302919_d303919.json"
BAND_TOL_IN = 0.5   # charge landing adds CHARGE_CONTACT_MARGIN_IN, mods add the rest

needs_corpus = pytest.mark.skipif(
    not ((CORPUS / GAME).exists() and BANK.exists() and LISTS.exists()),
    reason="Gen-0 corpus, terrain bank or ai_lists mirror absent",
)


def test_cand_text_names_its_actor():
    nm = {"p1_0_a": "Guardians", "p1_1_b": "Warriors"}
    a = nr.cand_text({"kind": 2, "unit": "p1_0_a", "dest": [0.254, 0.0, -0.508]}, nm)
    b = nr.cand_text({"kind": 2, "unit": "p1_1_b", "dest": [0.254, 0.0, -0.508]}, nm)
    assert a == 'Guardians RUSH to (10.0,-20.0)' and b.startswith("Warriors RUSH")
    assert a != b, "two units offered the same destination must not read alike"
    shot = nr.cand_text({"kind": 0, "unit": "p1_0_a", "shoot": "p1_1_b"}, nm)
    assert shot == "Guardians HOLD shoot Warriors"


def test_hits_follows_the_six_and_the_one():
    # `DiceRules.count_successes` dice_rules.gd:55-71 — a 6 always succeeds and a
    # 1 always fails, whatever the target is.
    rolls = [{"kind": "attack", "count": 6, "target": 7, "faces": [6, 6, 5, 4, 3, 1]},
             {"kind": "defense", "count": 3, "target": 2, "faces": [1, 2, 3]}]
    assert nr.hits(rolls, "attack") == 2
    assert nr.hits(rolls, "defense") == 2
    assert nr.hits([{"kind": "attack", "count": 1, "target": 0, "faces": [6]}], "attack") == 0


def test_army_table_carries_an_item_granted_rule():
    lst = {"units": [{"id": "x", "name": "Grunt Veteran", "size": 1, "quality": 5, "defense": 5,
                      "cost": 55, "rules": [{"name": "Tough", "rating": 3, "label": "Tough(3)"}],
                      "items": [{"name": "Winged Breed", "content": [{"name": "Ambush"},
                                                                     {"name": "Flying"}]}],
                      "weapons": [{"label": "Bio-Borer", "range": 12, "attacks": 3}]}]}
    row = nr.army_table(lst)[2]
    assert "Tough(3)" in row and "Ambush[Winged Breed]" in row and "Flying[Winged Breed]" in row
    assert 'Bio-Borer (12", A3)' in row
    assert nr.unit_info({"p1": lst}) == {"p1_0_x": (5, 5, "Tough(3), Ambush[Winged Breed], "
                                                    "Flying[Winged Breed]")}


def test_board_svg_is_self_contained():
    svg = nr.board_svg([[2, 0.0, 0.0, 6.0, 6.0, 0]], [(10.0, -3.0, 1)],
                       [(1, "Guardians", 0.8, [(-10.0, 4.0)])], [(1, (-18.0, 4.0), (-10.0, 4.0))],
                       "Round 1")
    assert svg.startswith("<svg") and svg.endswith("</svg>")
    assert "http" not in svg.replace("http://www.w3.org/2000/svg", "")
    assert nr.SIDE[1] in svg and "marker-end" in svg and "Guardians" in svg


def test_terrain_summary_counts_by_class():
    assert nr.terrain_summary([[2, 0, 0, 3, 3, 0], [2, 1, 1, 3, 3, 0], [1, 2, 2, 3, 3, 0]]) \
        == "1 ruins, 2 forest" or nr.terrain_summary(
            [[2, 0, 0, 3, 3, 0], [2, 1, 1, 3, 3, 0], [1, 2, 2, 3, 3, 0]]) == "2 forest, 1 ruins"


def test_moved_refuses_to_pair_a_reformed_unit():
    # A unit that loses models inside its OWN activation (the end-of-move
    # dangerous-terrain test) comes back re-formed and shorter; pairing those by
    # index invents a 17" move on a 12" band, which is what this refuses.
    import game_narrator as gn
    m = lambda xs: {"units": {"u": {"positions": [[x * 0.0254, 0.0, 0.0] for x in xs]}}}
    act = {"before": m([0.0, 2.0, 4.0, 6.0]), "after": m([8.0, 10.0, 12.0, 14.0])}
    assert [round(d, 3) for _, _, d in gn.moved(act, "u")] == [8.0, 8.0, 8.0, 8.0]
    act["after"] = m([8.0, 10.0])
    got = gn.moved(act, "u")
    assert len(got) == 1 and round(got[0][2], 3) == 6.0, got
    assert gn.moved({"before": m([]), "after": m([1.0])}, "u") == []


def _charge_act(rolls, target_alive=3):
    # One synthetic CHARGE activation: "a" charges "b" in band, no forest, no
    # shoot — the only variable is what the dice report carries. Needs neither
    # the corpus nor a replay.
    pos = lambda *xs: [[x * 0.0254, 0.0, 0.0] for x in xs]  # noqa: E731
    unit = lambda p, alive: {"positions": pos(*p), "radii": [], "alive": alive,
                             "wounds": [0] * alive,
                             "bands": {"advance": 6.0, "rush": 12.0}}  # noqa: E731
    rec = {"stem": "fixture", "terrain": [], "winner": 1, "vp": [0, 0],
           "mission": {"objectives_layout": {"placed_by": []}},
           "rounds_log": [{"owners": [], "vp": [0, 0]}]}
    act = {"row": {"unit": "a", "kind": 3, "round": 1, "side": 1, "seq": 1,
                   "cands": {"best": 0}, "intent": None},
           "menu": [{"unit": "a", "kind": 3, "charge": "b"}],
           "before": {"units": {"a": unit((0.0, 1.0), 3), "b": unit((3.0, 4.0), 3)}},
           "after": {"units": {"a": unit((1.0, 2.0), 3), "b": unit((3.0, 4.0), target_alive)}},
           "rep": {"rolls": rolls, "log": [], "unported": []}}
    return rec, [act], {"p1": {"units": []}, "p2": {"units": []}}


def test_charge_contact_needs_an_opposed_exchange_not_just_any_dice():
    # BRIEF_NARRFIX I-1: the charger's OWN dangerous-terrain test draws attack
    # dice too (sim.rs:2960-2978 records it `attack Nd6>=6`), so
    # `charges_reached_contact += bool(rolls)` credited 6 of 13 charges that
    # never reached melee. Contact is an opposed exchange: a defense-class
    # roll, or a casualty on the charge target.
    import game_narrator as gn
    terrain_test = [{"kind": "attack", "count": 2, "target": 6, "faces": [1, 6], "owner": "a"}]
    rec, acts, lists = _charge_act(terrain_test)
    assert gn.stats_row(rec, acts, lists)["charges_reached_contact"] == 0
    rec, acts, lists = _charge_act(terrain_test + [
        {"kind": "attack", "count": 3, "target": 4, "faces": [2, 4, 5], "owner": "a"},
        {"kind": "defense", "count": 2, "target": 4, "faces": [3, 6], "owner": "b"}])
    assert gn.stats_row(rec, acts, lists)["charges_reached_contact"] == 1
    rec, acts, lists = _charge_act(terrain_test + [
        {"kind": "attack", "count": 3, "target": 4, "faces": [4, 4, 4], "owner": "a"}],
        target_alive=0)
    assert gn.stats_row(rec, acts, lists)["charges_reached_contact"] == 1


def test_unsaved_honours_blast_and_never_drops_below_casualties():
    # BRIEF_NARRFIX I-2: `hits(attack) - hits(defense)` ignores Blast(X)/Deadly(X)
    # — one hit expands into a whole save batch, so the line printed "2 unsaved"
    # while the resolve applied 14 (s306052 R4 A27: "6 hits, 4 blocks, 2
    # unsaved" over defense 15d6>=7, Novice Sisters 20->6). The report carries
    # no per-weapon unsaved, so the line states what the state delta applied
    # and says "n/a (Blast/Deadly)" where the arithmetic cannot be trusted.
    import game_narrator as gn
    bu = {"a": {"alive": 3}, "b": {"alive": 20}}
    blast = [{"kind": "attack", "count": 1, "target": 4, "faces": [4], "owner": "a"},
             {"kind": "defense", "count": 15, "target": 7,
              "faces": [6, 6, 6, 6] + [1] * 11, "owner": "b"}]
    line = gn.dice_line(blast, bu, {"a": {"alive": 3}, "b": {"alive": 6}})
    m = re.search(r"blocks, (.+?) unsaved", line)
    assert m, line
    assert m.group(1) == "n/a (Blast/Deadly)" or int(m.group(1)) >= 14, line
    expanded = [{"kind": "attack", "count": 2, "target": 4, "faces": [4, 5], "owner": "a"},
                {"kind": "defense", "count": 2, "target": 4, "faces": [1, 2], "owner": "b"}]
    assert "n/a (Blast/Deadly)" in gn.dice_line(expanded, {"a": {"alive": 3},
                                                           "b": {"alive": 3}},
                                                {"a": {"alive": 3}, "b": {"alive": 2}})


def _rush_act(rolls, terrain):
    # One synthetic RUSH through a dangerous piece: no shoot, no charge — the
    # only attack-kind roll such an activation can hold is the terrain test.
    pos = lambda *xs: [[x * 0.0254, 0.0, 0.0] for x in xs]  # noqa: E731
    unit = lambda p, alive: {"positions": pos(*p), "radii": [], "alive": alive,
                             "wounds": [0] * alive,
                             "bands": {"advance": 6.0, "rush": 12.0}}  # noqa: E731
    rec = {"stem": "fixture", "seed": 1, "dice_seed": 1, "scoring": "?", "terrain": terrain,
           "winner": 1, "vp": [0, 0], "knobs": {"top_k": 1, "horizon": 1, "movement": "free"},
           "mission": {"family": "f", "name": "n", "rounds": 1, "deployment": "d",
                       "objectives_layout": {"positions": [], "placed_by": []}},
           "rounds_log": [{"owners": [], "vp": [0, 0]}]}
    act = {"row": {"unit": "a", "kind": 2, "round": 1, "side": 1, "seq": 1,
                   "cands": {"best": 0}, "intent": None},
           "menu": [{"unit": "a", "kind": 2, "dest": [0.254, 0.0, 0.0]}],
           "hand": [(0, 0.5)], "rs": {0: 0.25}, "exp": {"before": 0.0, "after": 0.0},
           "waits": 0, "own": 0, "up": 0,
           "before": {"units": {"a": unit((0.0, 1.0, 2.0), 3)}},
           "after": {"units": {"a": unit((10.0, 11.0), 2)}},
           "rep": {"rolls": rolls, "log": [], "unported": []}}
    return rec, [act], {"p1": {"units": []}, "p2": {"units": []}}


def test_terrain_test_is_never_printed_as_attack_dice():
    # BRIEF_NARRFIX I-3: the end-of-move dangerous-terrain test reaches the
    # record stamped kind "attack" (sim.rs:2960-2978), so a RUSH through
    # dangerous terrain narrated "attack 3d6>=6" with no target — reviewers
    # read phantom attack rolls. It must narrate as a terrain test, never as
    # attack dice; a stamp the record cannot match falls back to the inferred
    # label, and a genuine attack stays an attack.
    import game_narrator as gn
    terrain = [[4, 5.0, 0.0, 6.0, 6.0, 0]]  # dangerous piece astride the move
    line = lambda rolls, terr: [x for x in gn.narrate(
        *(lambda t: (t[0], t[1], {"a": "Guards"}, t[2]))(_rush_act(rolls, terr))
    ) if x.startswith("- dice:")][0]  # noqa: E731
    roll = [{"kind": "attack", "count": 3, "target": 6, "faces": [1, 6, 3], "owner": "a"}]
    got = line(roll, terrain)
    assert "dangerous terrain test 3d6: [1, 6, 3] -> 1 models lost" in got, got
    assert "attack" not in got, got
    got = line([dict(roll[0], owner="Unrecorded")], terrain)
    assert "terrain test (inferred) 3d6: [1, 6, 3] -> 1 models lost" in got, got
    assert "attack" not in got, got
    got = line([{"kind": "attack", "count": 3, "target": 4, "faces": [4, 4, 1],
                 "owner": "a"}], [])
    assert "attack 3d6>=4 [4, 4, 1] (a)" in got, got


def _morale_act(rolls, tgt=False, flip=False, up=0):
    # One synthetic HOLD/SHOOT activation whose delta carries a casualty: the
    # trailing count-1 "attack" die is the morale test (dice.rs:1108 stamps it
    # `kind: "attack"`), the only variables are the named target, the shaken
    # flip and the runner-up index. Needs neither the corpus nor a replay.
    pos = lambda *xs: [[x * 0.0254, 0.0, 0.0] for x in xs]  # noqa: E731
    unit = lambda p, alive, sh=False: {"positions": pos(*p), "radii": [], "alive": alive,
                                       "wounds": [0] * alive, "shaken": sh,
                                       "bands": {"advance": 6.0, "rush": 12.0}}  # noqa: E731
    rec = {"stem": "fixture", "seed": 1, "dice_seed": 1, "scoring": "?", "terrain": [],
           "winner": 1, "vp": [0, 0], "knobs": {"top_k": 1, "horizon": 1, "movement": "free"},
           "mission": {"family": "f", "name": "n", "rounds": 1, "deployment": "d",
                       "objectives_layout": {"positions": [], "placed_by": []}},
           "rounds_log": [{"owners": [], "vp": [0, 0]}]}
    act = {"row": {"unit": "a", "kind": 0, "round": 1, "side": 1, "seq": 1,
                   "cands": {"best": 0}, "intent": None},
           "menu": [{"unit": "a", "kind": 0, "shoot": "b"}] if tgt else [{"unit": "a", "kind": 0}],
           "hand": [(0, 0.5)], "rs": {0: 0.25}, "exp": {"before": 0.0, "after": 0.0},
           "waits": 0, "own": 0, "up": up,
           "before": {"units": {"a": unit((0.0, 1.0), 3), "b": unit((3.0, 4.0), 4)}},
           "after": {"units": {"a": unit((0.0, 1.0), 3), "b": unit((3.0, 4.0), 2, flip)}},
           "rep": {"rolls": rolls, "log": [], "unported": []}}
    return rec, [act], {"p1": {"units": []}, "p2": {"units": []}}


def test_count_one_morale_die_is_narrated_as_a_morale_test():
    # Verified by replay tonight: morale tests ARE rolled in self-play, but the
    # die is stamped `kind: "attack", count: 1` (dice.rs:1108), so the narrator
    # printed every test as a phantom attack and reviewers concluded morale
    # never happens. The state delta names the site — the owner's shaken flag
    # flipping False->True, or a count-1 attack die after casualties when no
    # attack target is named — and it must read as a morale test in the line
    # and in --stats. `runner_idx == -1` means NO runner-up: `scored[-1]` was
    # the LAST candidate, printed twice.
    import game_narrator as gn

    def dice(rolls, **kw):
        rec, acts, lists = _morale_act(rolls, **kw)
        return [x for x in gn.narrate(rec, acts, {"a": "Guards", "b": "Foes"}, lists)
                if x.startswith("- dice:")][0]

    volley = [{"kind": "attack", "count": 2, "target": 4, "faces": [4, 3], "owner": "a"},
              {"kind": "defense", "count": 2, "target": 4, "faces": [1, 6], "owner": "b"}]
    got = dice(volley + [{"kind": "attack", "count": 1, "target": 4, "faces": [5],
                          "owner": "b"}])
    assert "morale test 1d6>=4 [5] -> holds" in got, got
    assert "attack 1d6>=4 [5]" not in got, got
    assert "dice: 1 hits," in got, got  # the passing test die was a phantom hit
    got = dice(volley + [{"kind": "attack", "count": 1, "target": 4, "faces": [1],
                          "owner": "b"}], tgt=True, flip=True)
    assert "morale test 1d6>=4 [1] -> Shaken" in got, got
    assert "attack 1d6>=4 [1]" not in got, got
    rec, acts, lists = _morale_act(volley + [{"kind": "attack", "count": 1, "target": 4,
                                              "faces": [5], "owner": "b"}])
    assert gn.stats_row(rec, acts, lists)["morale_tests_rolled"] == 1
    rec, acts, lists = _morale_act(volley, up=None)
    text = "\n".join(gn.narrate(rec, acts, {"a": "Guards", "b": "Foes"}, lists))
    assert "runner-up" not in text, text


def run_tool(game: Path, out: Path):
    return subprocess.run([sys.executable, str(TOOLS / "game_narrator.py"), str(game),
                           "--out", str(out)], capture_output=True, text=True)


@needs_corpus
def test_narration_is_one_block_per_recorded_position(tmp_path):
    got = run_tool(CORPUS / GAME, tmp_path)
    assert got.returncode == 0, got.stderr[-2000:]
    rec = json.loads((CORPUS / GAME).read_text(encoding="utf-8"))
    d = tmp_path / Path(GAME).stem
    text = (d / "narration.md").read_text(encoding="utf-8")
    blocks = re.findall(r"^### R(\d+) A(\d+) \(seq (\d+)\)", text, re.M)
    assert len(blocks) == len(rec["planner_positions"])
    assert [int(b[2]) for b in blocks] == [p["seq"] for p in rec["planner_positions"]]
    assert (d / "dice.md").exists()
    for r in {p["round"] for p in rec["planner_positions"]}:
        assert (d / ("round_%d.svg" % r)).read_text(encoding="utf-8").startswith("<svg")


@needs_corpus
def test_no_model_outruns_its_band(tmp_path):
    assert run_tool(CORPUS / GAME, tmp_path).returncode == 0
    text = (tmp_path / Path(GAME).stem / "narration.md").read_text(encoding="utf-8")
    moves = re.findall(r'^- move \((\w+), band ([\d.]+)", farthest model ([\d.]+)"', text, re.M)
    assert moves, "no move line was narrated at all"
    for kind, band, far in moves:
        assert float(far) <= float(band) + BAND_TOL_IN, "%s ran %s of a %s band" % (kind, far, band)
    assert any(float(f) > 1.0 for _, _, f in moves), "nothing moved — the check cannot fail"


@needs_corpus
def test_narration_refuses_a_menu_that_parted(tmp_path):
    # THE RED. One destination coordinate off by a nanometre on a COPY: the tool
    # must raise at the position where the menus part, not narrate a fiction.
    rec = json.loads((CORPUS / GAME).read_text(encoding="utf-8"))
    for c in rec["planner_positions"][0]["cands"]["list"]:
        if c.get("dest"):
            c["dest"][0] += 1e-9
            break
    else:
        pytest.skip("no destination candidate on the first position")
    bad = tmp_path / GAME
    bad.write_text(json.dumps(rec), encoding="utf-8")
    got = run_tool(bad, tmp_path / "out")
    assert got.returncode != 0
    assert "Diverged" in got.stderr and "seq 0" in got.stderr, got.stderr[-2000:]
    assert not (tmp_path / "out" / Path(GAME).stem / "narration.md").exists()
