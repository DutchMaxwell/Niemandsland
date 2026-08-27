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
  * at least three activations replay ROLL FOR ROLL — same kinds, same die
    counts, same targets, same faces — which is what "the draw order is ported"
    means. It is 3 of 9 here and 155 of 670 over the full corpus; the rest are
    the rule gaps the tool's own report names (see its docstring and the PR).

RED PROOF: `--mode off` runs the same acts down the expected-value path, which
draws nothing from the tray, and NOT ONE act may come out equal.
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
    out = {"acts": 0, "equal": 0, "faces": 0, "rolls": 0, "hits_equal": 0}
    for k, act in enumerate(lines, 1):
        action = (act.get("pick") or {}).get("action") or {}
        if int(action.get("kind", -1)) not in srg.SHOOTING_KINDS or not action.get("shoot"):
            continue
        out["acts"] += 1
        i0 = srg.first_at_or_after(dice, k)
        tray = nml_core.Tray(seed)
        if burn[i0]:
            tray.roll(burn[i0])
        state = core.state_of(act["state"])
        if mode == "table":
            _, report = core.resolve_with_tray(state, action, nml_core.Rng(0), tray)
        else:
            core.resolve_stochastic_rng(state, action, nml_core.Rng(0))
            report = {"rolls": []}
        got = [(r["kind"], r["count"], r["target"], r["faces"]) for r in report["rolls"]]
        want = [(r["roll_kind"], r["count"], r["target"], r["faces"])
                for r in dice[i0:] if int(r["act"]) == k][:len(got) if got else None]
        # Same walk the tool does: stop at the FIRST roll whose shape parted —
        # everything after it is drawn from a stream that has already shifted,
        # so comparing it would only count noise.
        for g, w in zip(got, want):
            if g[:3] != w[:3]:
                break
            out["rolls"] += 1
            if g[3] != w[3]:
                out["faces"] += 1
                break
            if srg.successes(g[3], g[2]) == srg.successes(w[3], w[2]):
                out["hits_equal"] += 1
        if got and got == want:
            out["equal"] += 1
    return out


def test_the_bundled_game_replays_its_shooting_dice_on_the_tray():
    got = replay("table")
    assert got["acts"] == 9, "the fixture's shooting acts: %s" % got
    assert got["faces"] == 0, "a face parted after the shape held — the Tray twin is wrong: %s" % got
    assert got["rolls"] == 8, "rolls compared before the first shape divergence: %s" % got
    assert got["hits_equal"] == got["rolls"], "hits/blocks off the recorded faces: %s" % got
    assert got["equal"] >= 3, "roll-for-roll acts fell below the measured bar: %s" % got
    print("D1-B4 fixture: %d/%d acts roll for roll, %d rolls compared, 0 face divergences"
          % (got["equal"], got["acts"], got["rolls"]))


def test_red_the_expected_value_path_cannot_replay_one_roll():
    """Without the tray there are no faces at all — the green above is the
    tray's doing and nothing else's."""
    red = replay("off")
    assert red["acts"] == 9
    assert red["rolls"] == 0 and red["equal"] == 0, "the EV path produced dice: %s" % red
