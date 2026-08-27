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

THE ACTIVATION ORDINAL (D1-B5-0). `read_game` stamps each replayable act line
with its position in the INTERLEAVED `act|auto` stream, because a `kind:"auto"`
activation takes an ordinal in `dice.jsonl` too. THIS FIXTURE HAS NO `auto`
LINES, so none of the numbers below move with that fix — which is exactly why
the fix needs its own test, `test_an_auto_activation_takes_an_ordinal_too`
below, and why the corpus step (15 -> 100 of 669 FULL-equal on `qbe_ref`,
`table_silent` 359 -> 91) cannot be seen here.

WHAT IS PINNED, and why each number is the one it is:

  * ZERO `faces` divergences. A face can only part company after the shape
    already held, so a single one would mean the `Tray` twin itself is wrong —
    and that is GATE R's ground, already proven 6003/6003.
  * every compared roll scores the same hits/blocks off the recorded faces.
  * TWO equality numbers, because they say different things. FULL-equal means
    the port and the table drew the same NUMBER of rolls and every one matched;
    PREFIX-equal means the overlap matched but the lists were different lengths
    (usually because a later activation shares the ordinal — see the tool's
    docstring). 3 full / 3 prefix of 9 here; on the whole 168-game corpus
    D1-B5b moved FULL-equal 100 -> 122 of 669 by drawing the volley's morale
    die, with `table_longer` falling 58 -> 28.

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
    # D1-B4b moved this from 8 to 9: with the attached heroes' own shots in the
    # volley and the Takedown -> Deadly -> rest resolve order ported, one more
    # roll survives to be compared before the first shape parts. D1-B5b moved it
    # to 10 and FULL-equal from 2 to 3, and the volley's MORALE test is what did
    # it (main.gd:8248), rolled at the LIVE Banner-modified target.
    assert got["rolls"] == 10, "rolls compared before the first shape divergence: %s" % got
    assert got["hits_equal"] == got["rolls"], "hits/blocks off the recorded faces: %s" % got
    assert got["full_equal"] >= 3, "FULL-equal acts fell below the measured bar: %s" % got
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


def test_an_auto_activation_takes_an_ordinal_too(tmp_path):
    """RED-GREEN for the ordinal reader, on a game built to have the one thing
    the bundled fixture lacks: an `auto` activation.

    Three lines — header, one `kind:"auto"` activation, one `kind:"act"` — and a
    `dice.jsonl` whose rolls sit under ordinal 2. The act line is the FIRST
    replayable one, so numbering act lines among themselves calls it ordinal 1
    and slices the auto activation's roll; the interleaved position calls it 2
    and slices its own. Both slices exist here, so the wrong one cannot pass by
    drawing nothing.
    """
    import json

    game = tmp_path / "game"
    game.mkdir()
    (game / "acts.jsonl").write_text("\n".join(json.dumps(x) for x in [
        {"profiles": {}, "terrain": None, "knobs": {}},
        {"kind": "auto", "act": 1, "round": 1, "player": 1, "unit": "Dry Side"},
        {"kind": "act", "round": 1, "player": 2, "pick": {"action": {"kind": 0}}, "state": {}},
    ]) + "\n")
    (game / "dice.jsonl").write_text("\n".join(json.dumps(x) for x in [
        {"act": 1, "seq": 1, "roll_kind": "attack", "owner": "AI (Dry Side)",
         "target": 4, "count": 2, "faces": [1, 1]},
        {"act": 2, "seq": 2, "roll_kind": "attack", "owner": "AI (Picked)",
         "target": 3, "count": 3, "faces": [6, 6, 6]},
    ]) + "\n")
    (game / "arena_fixture.json").write_text(json.dumps({"dice_seed": 27}))

    _, lines, dice, _ = srg.read_game(game)
    assert len(lines) == 1, "only the planner-picked line is replayable"
    assert int(lines[0]["act"]) == 2, "the auto activation took ordinal 1"

    k = int(lines[0]["act"])
    i0 = srg.first_at_or_after(dice, k)
    mine = [r for r in dice[i0:] if int(r["act"]) == k]
    assert [r["faces"] for r in mine] == [[6, 6, 6]], "the act got its OWN rolls"
    # RED: the old reader numbered act lines among themselves, so this act was
    # ordinal 1 and read the auto activation's dice instead.
    stale = [r for r in dice if int(r["act"]) == 1]
    assert [r["faces"] for r in stale] == [[1, 1]], "the slice the old reader took"
    assert srg.burn_prefix(dice)[i0] == 2, "and it burned two draws too few"
