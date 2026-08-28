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

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
GAME = Path(__file__).resolve().parent / "fixtures" / "melee_replay"


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
    14" its move spends the whole band and stops in the window the gate is
    about, more than a hair from contact and less than the engage inch. That
    band is the ONLY thing changed, and the two arms differ only in the knob.
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
    state["units"][action["unit"]]["bands"]["rush"] = 14

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
