"""GATE D1-B4 (NML-1073 M5) — SHOOTING replayed on the tray, on a BUNDLED game.

`tools/shoot_replay_gate.py` runs over the whole 168-game arena corpus, which
lives outside the repo. This test runs the same tool over ONE game copied into
`fixtures/shoot_replay/` so the port has a bar that travels with the checkout:
`alien_hives_1000_vs_battle_brothers_1000_s33` (the smallest recorded game that
still carries several shooting activations), trimmed to the fields the gate
reads — the act lines keep `state` and `pick` and drop `trace`,
`charge_illegal`, `charge_illegal_grid`, `pool` and `statics`; `dice.jsonl` is
verbatim; `arena_fixture.json` carries the one field the gate wants from the
arena result, `dice_seed`. 340 KB in total.

WHAT IS PINNED, and why each number is the one it is:

  * ZERO `faces` divergences. A face can only part company after the shape
    already held, so a single one would mean the `Tray` twin itself is wrong —
    and that is GATE R's ground, already proven 6003/6003.
  * every compared roll scores the same hits/blocks off the recorded faces.
  * TWO equality numbers, because they say different things. FULL-equal means
    the port and the table drew the same NUMBER of rolls and every one matched;
    PREFIX-equal means the overlap matched but the lists were different lengths
    (usually because a later activation shares the ordinal — see the tool's
    docstring). 2 full / 3 prefix of 9 here.

THE TWO REDS, and only one of them is load-bearing:

  * `misseed` — the tray on `dice_seed + 1` and nothing else changed. Counts and
    targets still come out of the same state, so the shapes hold, the comparison
    REACHES the faces, and every act that rolls must part there. Without this
    one, "the faces matched" could mean "the faces were never compared".
  * `off` — the expected-value path, which draws no dice at all. It proves the
    reporting channel notices an absent stream, and nothing about the faces.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE_REF = Path(__file__).resolve().parent / "fixtures"
GAME = FIXTURE_REF / "shoot_replay"


def replay(mode: str) -> dict:
    """The gate's own per-act verdicts on the bundled game, as a tally."""
    import nml_core

    head, lines, dice, seed = srg.read_game(GAME)
    burn = srg.burn_prefix(dice)
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                     "knobs": dict(head.get("knobs", {}))})
    out = {"acts": 0, "full_equal": 0, "prefix_equal": 0, "faces": 0, "rolls": 0,
           "hits_equal": 0}
    for k, act in enumerate(lines, 1):
        action = (act.get("pick") or {}).get("action") or {}
        if int(action.get("kind", -1)) not in srg.SHOOTING_KINDS or not action.get("shoot"):
            continue
        out["acts"] += 1
        i0 = srg.first_at_or_after(dice, k)
        tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
        if burn[i0]:
            tray.roll(burn[i0])
        state = core.state_of(act["state"])
        if mode in ("table", "misseed"):
            _, report = core.resolve_with_tray(state, action, nml_core.Rng(0), tray)
        else:
            core.resolve_stochastic_rng(state, action, nml_core.Rng(0))
            report = {"rolls": []}
        got = [(r["kind"], r["count"], r["target"], r["faces"]) for r in report["rolls"]]
        # EVERY roll under this ordinal, not a prefix — see the tool's docstring.
        want = [(r["roll_kind"], r["count"], r["target"], r["faces"])
                for r in dice[i0:] if int(r["act"]) == k]
        if not got or not want:
            continue
        # Same walk the tool does: stop at the FIRST roll whose shape parted —
        # everything after it is drawn from a stream that has already shifted,
        # so comparing it would only count noise.
        parted = False
        for g, w in zip(got, want):
            if g[:3] != w[:3]:
                parted = True
                break
            out["rolls"] += 1
            if g[3] != w[3]:
                out["faces"] += 1
                parted = True
                break
            if srg.successes(g[3], g[2]) == srg.successes(w[3], w[2]):
                out["hits_equal"] += 1
        if not parted:
            out["prefix_equal"] += 1
            if len(got) == len(want):
                out["full_equal"] += 1
    return out


def test_the_bundled_game_replays_its_shooting_dice_on_the_tray():
    got = replay("table")
    assert got["acts"] == 9, "the fixture's shooting acts: %s" % got
    assert got["faces"] == 0, "a face parted after the shape held — the Tray twin is wrong: %s" % got
    assert got["rolls"] == 8, "rolls compared before the first shape divergence: %s" % got
    assert got["hits_equal"] == got["rolls"], "hits/blocks off the recorded faces: %s" % got
    assert got["full_equal"] >= 2, "FULL-equal acts fell below the measured bar: %s" % got
    assert got["prefix_equal"] >= 3, "PREFIX-equal acts fell below the measured bar: %s" % got
    print("D1-B4 fixture: %d/%d FULL-equal, %d PREFIX-equal, %d rolls compared, 0 face divergences"
          % (got["full_equal"], got["acts"], got["prefix_equal"], got["rolls"]))


def test_red_a_misseeded_tray_parts_on_the_faces():
    """THE LOAD-BEARING RED. `dice_seed + 1` leaves every die count and every
    target exactly where they were, so the shapes still line up and the
    comparison REACHES the faces — where it must fail on every act that rolls.
    If this ever came out green, the green above would only mean the faces are
    not being compared at all."""
    red = replay("misseed")
    assert red["acts"] == 9
    assert red["faces"] > 0, "the comparison never reached a face: %s" % red
    # The bar is in DICE, not acts: a one- or two-die activation can agree on a
    # wrong seed by chance (1/6, 1/36) — two of the corpus's 670 do. Nothing on
    # this fixture survives at all, which is a stricter statement, so it is the
    # one asserted here.
    assert red["full_equal"] == 0 and red["prefix_equal"] == 0, "a wrong seed replayed: %s" % red


def test_red_the_expected_value_path_cannot_replay_one_roll():
    """The REPORTING CHANNEL only: without the tray there are no faces at all,
    so this says the tool notices an absent stream — not that the faces are
    right. That is `test_red_a_misseeded_tray_parts_on_the_faces`'s job."""
    red = replay("off")
    assert red["acts"] == 9
    assert red["rolls"] == 0 and red["prefix_equal"] == 0, "the EV path produced dice: %s" % red
