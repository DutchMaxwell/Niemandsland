"""GATE D1-B5b (NML-1073 M5) — MELEE, IMPACT and MORALE replayed on the tray, on
a BUNDLED game.

`tools/melee_replay_gate.py` runs over the whole 168-game arena corpus, which
lives outside the repo. This test runs the same comparison over ONE game copied
into `fixtures/melee_replay/`: `alien_hives_1000_vs_change_disciples_1000_s31`,
the smallest recorded game with a FULL-equal charge activation. It is trimmed to
the fields the gate reads — every `act`/`auto` line keeps `state` and `pick` and
drops `trace`, `pool`, `statics`, `charge_gate` and the two `charge_illegal`
maps; `dice.jsonl` is verbatim; `arena_fixture.json` carries the one field the
gate wants from the arena result, `dice_seed`. 320 KB in all.

THE `auto` LINES ARE KEPT ON PURPOSE. `dice.jsonl` stamps each roll with the
ACTIVATION ordinal, and a side that hands its tail to the other writes a
`kind:"auto"` line that takes an ordinal too. Drop them and every ordinal after
the first one slides — the game would be compared against the wrong rolls and
this test would be measuring nothing.

WHAT IS PINNED:
  * ZERO `faces` divergences. A face can only part company after the shape has
    already held, so one would mean the `Tray` twin itself is wrong — GATE R's
    ground, already proven 6003/6003.
  * every compared roll scores the same hits/blocks off the recorded faces.
  * the FULL-equal charge activations, which is what carries the draw order:
    Impact, the charger's strikes, the strike-back AND the loser's morale test
    all have to land in the right places for a whole activation to match roll
    for roll. D1-B5b moved this fixture from 1 to 2 and the compared rolls from
    9 to 10, and the morale die is what did it — on the whole 168-game corpus
    the same change moved FULL-equal 7 -> 18 of 237.
  * one activation where the port's trailing morale block matches the table's in
    count, target AND roller.

THE RED, and it is the stricter of the two this port has. The corpus tool's
`--red-misseed` can only speak for acts whose SHAPES already agree; here the
bar is stated on the outcome instead: at `dice_seed + 1` — same counts, same
targets, one seed over — `full_equal` must fall to **0** and at least one act
must part on the FACES. A green there would mean the faces are not being
compared at all.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
GAME = Path(__file__).resolve().parent / "fixtures" / "melee_replay"
QBE_REF = Path(os.path.expanduser("~/selfplay_out/qbe_ref"))


def replay(seed_shift: int = 0) -> dict:
    """The gate's per-act verdicts on the bundled game, as a tally."""
    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    burn = srg.burn_prefix(dice)
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                     "knobs": dict(head.get("knobs", {}), hero_attach=True)})
    out = {"acts": 0, "full_equal": 0, "faces": 0, "rolls": 0, "hits_equal": 0,
           "morale_equal": 0}
    for act in lines:
        k = int(act["act"])
        action = (act.get("pick") or {}).get("action") or {}
        if int(action.get("kind", -1)) != mrg.CHARGE_KIND or not action.get("charge"):
            continue
        out["acts"] += 1
        i0 = srg.first_at_or_after(dice, k)
        tray = nml_core.Tray(seed + seed_shift)
        if burn[i0]:
            tray.roll(burn[i0])
        _, report = core.resolve_with_tray(
            core.state_of(act["state"]), action, nml_core.Rng(0), tray)
        got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
               for r in report["rolls"]]
        want = [(r["roll_kind"], r["count"], r["target"], r["faces"], r["owner"])
                for r in dice[i0:] if int(r["act"]) == k]
        if not got or not want:
            continue
        gm, wm = mrg.trailing_morale(got), mrg.trailing_morale(want)
        if gm and wm and [(g[1], g[2], g[4]) for g in gm] == [(w[1], w[2], w[4]) for w in wm]:
            out["morale_equal"] += 1
        for g, w in zip(got, want):
            if g[:3] != w[:3] or g[4] != w[4]:
                break
            if g[3] != w[3]:
                out["faces"] += 1
                break
            out["rolls"] += 1
            if srg.successes(g[3], g[2]) == srg.successes(w[3], w[2]):
                out["hits_equal"] += 1
        else:
            if len(got) == len(want):
                out["full_equal"] += 1
    return out


def test_the_bundled_game_replays_its_melee_dice_on_the_tray():
    got = replay()
    assert got["acts"] == 3, "the fixture's charge acts: %s" % got
    assert got["faces"] == 0, "a face parted after the shape held — the Tray twin is wrong: %s" % got
    assert got["rolls"] == 10, "rolls compared before the first shape divergence: %s" % got
    assert got["hits_equal"] == got["rolls"], "hits/blocks off the recorded faces: %s" % got
    assert got["full_equal"] >= 2, "a FULL-equal charge act fell away: %s" % got
    assert got["morale_equal"] >= 1, "no morale block matched count, target and roller: %s" % got


def test_red_a_wrong_seeded_tray_parts_on_the_faces():
    """THE LOAD-BEARING RED. `dice_seed + 1` leaves every die count and every
    target exactly as the recorded state produced them, so the shapes still line
    up, the comparison REACHES the faces, and it has to fail there."""
    red = replay(seed_shift=1)
    assert red["acts"] == 3
    assert red["faces"] > 0, "a wrong-seeded tray still matched every face: %s" % red
    assert red["full_equal"] == 0, "a wrong-seeded tray produced a FULL-equal act: %s" % red


def test_d5_1_the_charge_landing_knob_reaches_the_resolver_from_the_header():
    """NML-1073 M5 D5-1 — the `charge_landing` knob crosses FOUR layers before it
    can refuse anything: the header's `knobs` object -> `acts::Knobs` ->
    `Core::seams` -> `Seams::charge_landing` -> `resolve_with`. A knob that
    quietly fell off any of them would leave every gate green while measuring
    the OLD rule, and Rust cannot see that seam. So this test is about the
    WIRING; the rule itself is red-greened next door in `tests/parity.rs`
    (`d5_1_charge_landing_asks_whether_the_snap_still_fits_the_budget`: 20 of 52
    recorded contacts refused, the rest still fighting).

    All three of the bundled game's charges land INSIDE the 0.05" contact
    epsilon, where `snap_charge` returns 0 for free (solo_controller.gd:8639) —
    so the fixture as recorded cannot show the gate biting, and saying so is
    part of the measurement. Act 16's charger is a 16" Fast unit; stripped to
    12" its move spends the whole band and stops in the window the gate is
    about, more than a hair from contact and less than the engage inch. That
    band is the ONLY thing changed, and the two arms differ only in the knob.

    THE BAND WAS 14" UNTIL D5-4. The engage test now measures `_moving_models`
    on both sides (`nearest_melee_gap_in` :8526), and this act's target carries
    a joined hero standing in front of it — so the gap to close is SHORTER than
    the two hosts' was, and a 14" charge now lands inside the contact epsilon
    where the snap is free. 12" puts the same act back in the window the D5-1
    gate is about; nothing else about the test moved.
    """
    import copy

    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    burn = srg.burn_prefix(dice)
    act = next(a for a in lines if int(a["act"]) == 16)
    action = act["pick"]["action"]
    assert int(action["kind"]) == mrg.CHARGE_KIND and action.get("charge")
    state = copy.deepcopy(act["state"])
    assert state["units"][action["unit"]]["bands"]["rush"] == 16, "the fixture's Fast charger"
    state["units"][action["unit"]]["bands"]["rush"] = 12

    rolls = {}
    for landing in (False, True):
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=landing)})
        assert core.knobs()["charge_landing"] is landing, "the header knob round-trips"
        i0 = srg.first_at_or_after(dice, 16)
        tray = nml_core.Tray(seed)
        if burn[i0]:
            tray.roll(burn[i0])
        _, report = core.resolve_with_tray(
            core.state_of(state), action, nml_core.Rng(0), tray)
        rolls[landing] = len(report["rolls"])

    assert rolls[False] > 0, "with the seam OFF a charge inside the engage inch fights: %s" % rolls
    assert rolls[True] == 0, (
        "the seam did not reach the resolver — the snap had no budget left and the "
        "melee still ran: %s" % rolls)


def test_d5_2_the_movement_knob_moves_the_charge_per_model_from_the_header():
    """NML-1073 M5 D5-2 — the `movement` knob crosses the same four layers the
    `charge_landing` knob does (header `knobs` -> `acts::Knobs` -> `Core::seams`
    -> `Seams::movement` -> `resolve_with`), and the thing it switches on is a
    whole solver, so a knob that fell off would leave the gate measuring the OLD
    rigid translation while claiming the table's route.

    Two arms, one act, nothing changed but the knob. OFF, every model of the
    charging unit takes the SAME clamped delta, so the pairwise offsets are
    preserved to the digit. ON, the M4 movement port solves the route per model
    and the formation FANS — models end inches apart from where the rigid slide
    would have put them. The landing is also read directly (`Core.charge_move`),
    because the endpoints are what `charge_move_gate.py` holds against the
    table's recorded `moves_calls.jsonl` on the reference corpora.
    """
    import math

    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    act = next(a for a in lines if int(a["act"]) == 16)
    action = act["pick"]["action"]
    assert int(action["kind"]) == mrg.CHARGE_KIND and action.get("charge")

    ends = {}
    for movement in (False, True):
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=False, movement=movement)})
        assert core.knobs()["movement"] is movement, "the header knob round-trips"
        nxt = core.resolve(core.state_of(act["state"]), action)
        ends[movement] = nxt.plain()["units"][action["unit"]]["positions"]
        if not movement:
            # The port declines to plan when the knob is off — nothing is built.
            continue
        land = core.charge_move(core.state_of(act["state"]), action["unit"], action["charge"])
        assert land is not None, "the port plans this charge"
        assert len(land["movers"]) == len(land["end"]) > len(ends[False]), \
            "one endpoint per moving model, the attached hero's included"
        assert land["budget_in"] == 16.0, "the charger's Fast rush band is the granted budget"
        # The distance-truth trim (_execute_move solo_controller.gd:4841) compares
        # in METRES with a 0.0005 m slack, i.e. 0.0197" — a trail inside that is
        # never cut, so the band is the bar plus the table's own tolerance.
        assert 0.0 <= land["arc_in"] <= land["budget_in"] + 0.02, \
            "no model walks past its band: %s" % land["arc_in"]
        assert land["remaining_in"] == max(0.0, land["budget_in"] - land["arc_in"])

    assert len(ends[False]) == len(ends[True])
    apart = [math.dist(a, b) / 0.0254 for a, b in zip(ends[False], ends[True])]
    assert max(apart) > 1.0, (
        "the seam did not reach the resolver — the charge still landed on the rigid "
        "delta: %s" % [round(x, 3) for x in apart])
    # RED-GREEN for the CLAIM, not just for the difference: the rigid arm really
    # is one translation (every pairwise offset preserved), the table arm is not.
    def spread(ps):
        d0 = [p[i] - ps[0][i] for p in ps for i in (0, 2)]
        return d0
    assert spread(ends[False]) != spread(ends[True]), "the table arm steers per model"


@pytest.mark.skipif(not QBE_REF.exists(), reason="no qbe_ref reference corpus on this machine")
def test_d5_2_review_the_landing_gate_only_bites_with_charge_landing_on():
    """REVIEW #440 fix — `sim.rs:1166` used to set the D5-1 budget gate
    (`charge_remaining_in`) from the D5-2 landing UNCONDITIONALLY, so
    `movement="table"` silently forced `charge_landing="table"` on even with
    that knob off. Pinned on `qbe_ref/alien_hives_1000_vs_change_disciples_
    1000_s30` act 24, the review's own proof: off/off draws 2 melee rolls, and
    table/off MUST equal it (before the fix it drew 0); table/table (both
    knobs on) still refuses.

    `dangerous=False` throughout: D1-B8 puts a p.12 dangerous-terrain roll in
    front of the melee on this very act, and this test's subject is the LANDING
    gate, not the die count. With the knob on, every arm below simply gains that
    one roll (3 / 3 / 1) and the three relations are unchanged.
    """
    import nml_core

    game = QBE_REF / "alien_hives_1000_vs_change_disciples_1000_s30"
    head, lines, dice, seed = srg.read_game(game)
    burn = srg.burn_prefix(dice)
    act = next(a for a in lines if int(a["act"]) == 24)
    action = (act.get("pick") or {}).get("action") or {}
    assert int(action.get("kind", -1)) == mrg.CHARGE_KIND and action.get("charge")

    rolls = {}
    for movement, charge_landing in ((False, False), (True, False), (True, True)):
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=charge_landing, movement=movement,
                                       dangerous=False)})
        i0 = srg.first_at_or_after(dice, 24)
        tray = nml_core.Tray(seed)
        if burn[i0]:
            tray.roll(burn[i0])
        _, report = core.resolve_with_tray(
            core.state_of(act["state"]), action, nml_core.Rng(0), tray)
        rolls[(movement, charge_landing)] = len(report["rolls"])

    assert rolls[(False, False)] == 2, "the off/off baseline: %s" % rolls
    assert rolls[(True, False)] == rolls[(False, False)], (
        "movement=table with charge_landing OFF must behave like D5-1-off: %s" % rolls)
    assert rolls[(True, True)] == 0, "movement=table WITH charge_landing still refuses: %s" % rolls


@pytest.mark.skipif(not QBE_REF.exists(), reason="no qbe_ref reference corpus on this machine")
def test_d1_b8_the_dangerous_terrain_test_is_the_activations_first_roll():
    """NML-1073 M5 D1-B8 — the p.12 DANGEROUS-terrain test, end to end against
    the recording.

    `qbe_ref/alien_hives_1500_vs_change_disciples_1500_s30` act 27 is a charge
    the table never fought: its ONLY recorded roll is the dangerous test, which
    is why it sat in `port_silent` before this rung. The table drew 11 dice at
    6+ signed "AI (Change Mutated Cultists)" — 11, not 8, because the unit's
    models are Tough-weighted (`maxi(1, wounds_max)`, solo_controller.gd:5046)
    — and two of the faces are 1s, so the unit took 2 wounds and stood at 14
    models / 14 wounds in the next act.

    GREEN: the port reproduces the roll TUPLE (kind, count, target, faces,
    owner) and lands the same two wounds. RED: with the header knob
    `dangerous=false` it draws nothing and leaves the unit at 16/16, which is
    not where the table found it.
    """
    import nml_core

    game = QBE_REF / "alien_hives_1500_vs_change_disciples_1500_s30"
    head, lines, dice, seed = srg.read_game(game)
    burn = srg.burn_prefix(dice)
    walls, _ = mrg.header_walls_m(game, head)
    pos = next(i for i, a in enumerate(lines) if int(a["act"]) == 27)
    action = lines[pos]["pick"]["action"]

    def arm(dangerous: bool):
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"],
                         "terrain": dict(head.get("terrain") or {}, walls=walls),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=True, movement=True,
                                       dangerous=dangerous)})
        i0 = srg.first_at_or_after(dice, 27)
        tray = nml_core.Tray(seed)
        if burn[i0]:
            tray.roll(burn[i0])
        nxt, report = core.resolve_with_tray(
            core.state_of(lines[pos]["state"]), action, nml_core.Rng(0), tray)
        return report, srg.defender_state(nxt.plain(), action["unit"])

    want = [(r["roll_kind"], r["count"], r["target"], r["faces"], r["owner"])
            for r in dice[srg.first_at_or_after(dice, 27):] if int(r["act"]) == 27]
    assert len(want) == 1 and want[0][1:3] == (11, 6), "the recording itself: %s" % (want,)
    table_next = srg.defender_state(lines[pos + 1]["state"], action["unit"])

    report, got_next = arm(True)
    got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
           for r in report["rolls"]]
    assert got == want, "the port's roll vs the table's: %s vs %s" % (got, want)
    assert got_next == table_next == (14, 14), "%s vs %s" % (got_next, table_next)
    # No silent skip anywhere on this act: `movement="table"` carries the real
    # per-model trails, so the rigid-end approximation is never reached.
    assert "dangerous_rigid_end_only" not in report["unported"]

    red_report, red_next = arm(False)
    assert red_report["rolls"] == [], "RED --red-no-dangerous still drew: %s" % red_report
    assert red_next == (16, 16) != table_next, "the RED must leave the unit unwounded: %s" % (red_next,)


def test_trailing_morale_keeps_a_no_retreat_block_together():
    """RED-GREEN for `trailing_morale`, on the one morale roll of MORE than one
    die.

    A morale test is one die and so is Fearless's re-roll, but No Retreat's
    self-wound roll is `wounds_to_destroy` dice (main.gd:8364) and it is always
    LAST. Walking back over 1-die rolls alone therefore stops at it and drops
    the whole block — the gate would then report `morale_none` for exactly the
    activations that tested hardest. `~/selfplay_out/qbe_ref` fields no No
    Retreat unit, so this is the only place the rule can be held to.
    """
    rolls = [
        ("attack", 6, 3, [1, 2, 3, 4, 5, 6], "AI (Striker)"),   # a strike
        ("defense", 2, 5, [1, 2], "AI (Target)"),               # its saves
        ("attack", 1, 4, [2], "AI (Target)"),                   # the morale test
        ("attack", 1, 4, [3], "AI (Target)"),                   # Fearless's re-roll
        ("attack", 5, 4, [1, 1, 4, 5, 2], "AI (Target)"),       # No Retreat, 5 dice
    ]
    assert mrg.trailing_morale(rolls) == rolls[2:], "the whole block, self-wounds included"

    # RED: the 1-die-only walk-back, which is what this function used to be.
    i = len(rolls)
    while i > 0 and rolls[i - 1][0] == "attack" and rolls[i - 1][1] == 1:
        i -= 1
    assert rolls[i:] == [], "the old walk-back stopped at the self-wound roll and found nothing"

    # And it must not swallow a plain multi-die strike that happens to end an
    # activation at the same target: only ONE such roll is taken, at the end.
    plain = rolls[:2] + [("attack", 4, 4, [1, 2, 3, 4], "AI (Striker)")]
    assert mrg.trailing_morale(plain) == plain[2:], "one trailing roll, and no further"
    assert mrg.trailing_morale(rolls[:2]) == [], "a save batch ends the block"


def test_the_engage_fold_knob_is_load_bearing_on_the_bundled_game() -> None:
    """NML-1073 M5 D5-4 — the attached-hero fold of the ENGAGE test, and its RED.

    `main._run_ai_melee` (:7970) asks `nearest_melee_gap_in`, which measures
    `_moving_models` (:5375) on BOTH sides — host models PLUS attached heroes'.
    D5-1 measured the two HOSTS, so a charge that only reached the target's
    joined hero fell short in the port while the table fought it.

    Act 16 of the bundled game is one: with the fold on the port resolves the
    whole melee (5 rolls), with the header's RED knob `engage_fold=false` it
    draws NOTHING and the activation joins `port_silent`. Two arms, one act,
    nothing changed but that knob — so a wire that fell off between the header
    and `Seams::no_engage_fold` cannot pass here.
    """
    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    act = next(a for a in lines if int(a["act"]) == 16)
    action = act["pick"]["action"]

    rolls = {}
    for fold in (True, False):
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=True, engage_fold=fold,
                                       movement=True)})
        assert core.knobs()["engage_fold"] is fold, "the header knob round-trips"
        _, report = core.resolve_with_tray(
            core.state_of(act["state"]), action, nml_core.Rng(0), nml_core.Tray(seed))
        rolls[fold] = len(report["rolls"])
    assert rolls[True] == 5, "the fold reaches the target's joined hero and the melee runs"
    assert rolls[False] == 0, "RED: on the hosts alone the charge falls short and draws nothing"


def test_the_base_shape_is_load_bearing_on_the_bundled_game() -> None:
    """NML-1073 M5 D5-2b — the ENGAGE test measures the base SHAPE, and its RED.

    `nearest_melee_gap_in` (:8536) asks `SeparationChecker.edge_distance`,
    which walks an oval's exact SUPPORT EXTENT (separation_checker.gd:290);
    the act header carries only `base_radius`, the CIRCUMSCRIBING circle. On a
    92 x 120 mm base the two differ by 1.17" across the short axis.

    Act 16 of the bundled game shows it: with the target's profile stamped as
    that oval — the three D5-4b keys (#447) and nothing else — the charge no
    longer reaches its base and the melee is silent, where the recorded ROUND
    reading fights it out in 5 rolls. `round_only_profiles`, the gate's
    `--red-round-only`, puts the 5 back, and so does turning the two charge
    seams off, because with them off the resolver is imitating
    `BattleSim.edge_gap_in` (battle_sim.gd:869), which has only a radius.
    """
    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    act = next(a for a in lines if int(a["act"]) == 16)
    action = act["pick"]["action"]
    oval = json.loads(json.dumps(head["profiles"]))
    oval[action["charge"]].update({"base_shape": "oval", "base_w_mm": 92, "base_d_mm": 120})
    assert mrg.round_only_profiles(oval) == head["profiles"], \
        "the RED strips exactly the three D5-4b keys and touches nothing else"

    def rolls(profiles: dict, seams_on: bool) -> int:
        core = nml_core.load(str(REPO))
        core.set_header({"profiles": profiles, "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       engage_fold=True, charge_landing=seams_on,
                                       movement=seams_on)})
        _, report = core.resolve_with_tray(
            core.state_of(act["state"]), action, nml_core.Rng(0), nml_core.Tray(seed))
        return len(report["rolls"])

    assert rolls(head["profiles"], True) == 5, "the recorded round base reaches and fights"
    assert rolls(oval, True) == 0, "the oval's support extent is 1.17\" shy — no contact"
    assert rolls(mrg.round_only_profiles(oval), True) == 5, "RED: --red-round-only puts it back"
    assert rolls(oval, False) == rolls(head["profiles"], False), \
        "with both charge seams off the shape is not read at all"
