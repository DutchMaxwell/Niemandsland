"""GATE D1-B5a (NML-1073 M5) — MELEE and IMPACT replayed on the tray, on a
BUNDLED game.

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
  * the FULL-equal charge activation, which is what carries the draw order:
    Impact, the charger's strikes and the strike-back all have to land in the
    right places for a whole activation to match roll for roll.

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
    out = {"acts": 0, "full_equal": 0, "faces": 0, "rolls": 0, "hits_equal": 0}
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
    assert got["rolls"] == 9, "rolls compared before the first shape divergence: %s" % got
    assert got["hits_equal"] == got["rolls"], "hits/blocks off the recorded faces: %s" % got
    assert got["full_equal"] >= 1, "the FULL-equal charge act fell away: %s" % got


def test_red_a_wrong_seeded_tray_parts_on_the_faces():
    """THE LOAD-BEARING RED. `dice_seed + 1` leaves every die count and every
    target exactly as the recorded state produced them, so the shapes still line
    up, the comparison REACHES the faces, and it has to fail there."""
    red = replay(seed_shift=1)
    assert red["acts"] == 3
    assert red["faces"] > 0, "a wrong-seeded tray still matched every face: %s" % red
    assert red["full_equal"] == 0, "a wrong-seeded tray produced a FULL-equal act: %s" % red
