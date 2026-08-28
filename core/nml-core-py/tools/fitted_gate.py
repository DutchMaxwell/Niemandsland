#!/usr/bin/env python
"""GATE NML-1142 — the crate's FITTED eval against GODOT's own, per planner row.

`AiMissionEval.score` with `fit_mode` on is a BLEND: half the hand eval, half a
trained encoder net that reads the raw board rows (`_score_encoder`
ai_mission_eval.gd:140-148). `core/nml-core/src/fitted.rs` ports that half; this
gate says the port answers the same number the table does.

WHAT IS HELD, per act: `pick.expectation.before` — the ROOT score
`AiPlanner.plan_with_rollout` writes at :129, which is
`AiMissionEval.score(state, player, BattleSim.reply_threat(state, player))` over
the act's OWN recorded state. Nothing between the state and the eval is in the
way: no menu, no `resolve`, no rollout, no dice. A mismatch here is the eval's
and only the eval's. Tolerance 1e-6.

WHERE GODOT'S NUMBER COMES FROM. No corpus on disk carries a fitted score — the
recorders have only ever run with `fit_mode: false` (checked across
`~/selfplay_out` and `~/.cache`, 0 hits). So the reference is REPLAYED, in two
steps, with no change to any shipping file:

  1. `--doctor` stamps `statics.fit_mode = true` onto every act of a recorded
     corpus. `tools/act_recheck.gd` restores the planner's class statics from
     exactly that field (:216), so the doctored copy replays under the fitted
     eval and nothing else moves.
  2. `tools/act_recheck.gd file=<doctored> write=<replay> n=<N>` under
     `NML_FIT_WEIGHTS=net NML_NET_PATH=<net>` — the LIVE GDScript search, with
     the live encoder, writing its own pick + trace per act.

    P=core/nml-core-py/tools/fitted_gate.py; V=~/venvs/nml1142/bin/python
    NET=~/.cache/nml-rehearsal/rehearsal_net_v3.json
    $V $P --doctor <in>/acts.jsonl --out <g>/acts.jsonl
    NML_FIT_WEIGHTS=net NML_NET_PATH=$NET godot --headless --path <wt> \\
        -s res://tools/act_recheck.gd -- file=<g>/acts.jsonl \\
        write=<g>/replay.jsonl n=999
    $V $P --game <g> --net $NET --repo <wt>

The gate reads the STATE from the doctored `acts.jsonl` and the fitted score
from `replay.jsonl`, paired by position. They are the same acts in the same
order, but not the same serialisation: `act_recheck.gd` writes with Godot's
`full_precision` flag, which prints every integer with a decimal point, and the
plain-state reader types those columns as integers. Reading each half from the
file that carries it honestly beats loosening the reader.

RED PROOF: `--red-scale X` multiplies the crate's NET output by X before the
blend (`Core.load_net(scale=)`). At X != 1 every row must go red — a gate that
stayed green would be reading the hand eval, not the net. The blend is half hand
eval, so a 1% scale moves a row by ~0.5% and 1e-6 catches it many times over.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import nml_core

#: `pick.expectation.before` is a P(win) proxy in [0,1]; 1e-6 is the same bar
#: `tools/act_recheck.gd` holds its own replay to (EPS 1e-9 there is over a
#: number both sides computed in ONE process — across a JSON round-trip of a
#: 17-digit float, 1e-6 is the honest floor).
EPS = 1e-6

#: `OPRApiClient.OPRUnit`'s blank quality/defense — what a replay's stand-in
#: `GameUnit` answers for board columns 10/11 (see `check`).
SOURCE_DATA_QUALITY = 4
SOURCE_DATA_DEFENSE = 4


def acts_of(path: Path) -> tuple[dict, list[dict]]:
    """The header line and every `kind == "act"` line of an act corpus."""
    lines = [json.loads(x) for x in path.read_text().splitlines() if x.strip()]
    return lines[0], [a for a in lines[1:] if a.get("kind") == "act"]


def doctor(src: Path, dst: Path) -> int:
    """Copy `src` to `dst` with `statics.fit_mode = true` on every act. The
    corpus is otherwise BYTE-preserved line by line: the states, the menus and
    the recorded picks are the recording's, and only the class static the
    replayer restores from them changes."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with open(dst, "w", encoding="utf-8") as out:
        for raw in src.read_text().splitlines():
            if not raw.strip():
                continue
            rec = json.loads(raw)
            if rec.get("kind") == "act":
                rec.setdefault("statics", {})["fit_mode"] = True
                n += 1
                out.write(json.dumps(rec) + "\n")
            else:
                out.write(raw + "\n")
    return n


def check(game: Path, net: str, repo: str, scale: float, tally: dict, firsts: list) -> None:
    """One replayed game: the crate's fitted root score vs Godot's, per act."""
    head, acts = acts_of(game / "acts.jsonl")
    _rhead, replay = acts_of(game / "replay.jsonl")
    core = nml_core.load(repo)
    # THE TWO REPLAY READINGS, both forced rather than inherited, because the
    # reference was produced by `act_recheck.gd` and not by a live game:
    #
    #  * the rule VOCABULARY is this build's. Godot reads no other one — its
    #    `BattleSim._load_vocab` has no per-corpus switch — so a header that
    #    predates the `rule_vocab_version` knob must not send the port to an
    #    older slotting than the reference used.
    #  * columns 10/11 are the blank `OPRApiClient.OPRUnit` 4/4. Every Godot
    #    replay rebuilds its units as `node_recheck.gd` stand-ins, which carry no
    #    `source_data`, and the table's own `board_rows` then answers 4/4 there.
    #    This is the one thing `set_encoder_source_qd` exists for.
    #
    # Neither is assumed silently: a wrong reading in either moves a board column
    # and the score with it, far past 1e-6.
    core.set_header(
        {"profiles": head["profiles"], "terrain": head.get("terrain"),
         "knobs": dict(head.get("knobs", {}),
                       rule_vocab_version=nml_core.RULE_VOCAB_VERSION)}
    )
    core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
    shape = core.load_net(net, scale)
    tally.setdefault("net", shape)
    tally["games"] += 1
    for i, act in enumerate(acts[: len(replay)]):
        rep = replay[i]
        # The pairing is positional, so PROVE it: a replay that slid by one act
        # would compare two different states and could still look green.
        if (int(rep["round"]), int(rep["player"])) != (int(act["round"]), int(act["player"])):
            raise SystemExit("[GATE] %s act %d: replay is not the same act" % (game.name, i))
        if not bool(rep.get("statics", {}).get("fit_mode")):
            tally["not_fitted"] += 1
            continue
        pick = rep.get("pick") or {}
        if not pick.get("used"):
            tally["unused"] += 1
            continue
        want = float(pick["expectation"]["before"])
        try:
            got = float(core.score(core.state_of(act["state"]), int(act["player"])))
        except Exception as exc:  # a state the port declines is NOT a pass
            tally["declined"] += 1
            if len(firsts) < 5:
                firsts.append("%s act %d — DECLINED: %s" % (game.name, i, exc))
            continue
        tally["rows"] += 1
        d = abs(got - want)
        tally["max_diff"] = max(tally["max_diff"], d)
        if d <= EPS:
            tally["ok"] += 1
        else:
            tally["bad"] += 1
            if len(firsts) < 5:
                firsts.append(
                    "%s act %d — godot %.9f crate %.9f diff %.3e"
                    % (game.name, i, want, got, d)
                )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--doctor", type=Path, help="stamp fit_mode onto a recorded acts.jsonl")
    ap.add_argument("--out", type=Path, help="--doctor destination")
    ap.add_argument("--game", type=Path, nargs="*", default=[],
                    help="game dirs carrying acts.jsonl (doctored) + replay.jsonl")
    ap.add_argument("--net", default="", help="the fork_train.py encoder net JSON")
    ap.add_argument("--repo", default="", help="repo root (assets/ + data/ live here)")
    ap.add_argument("--red-scale", type=float, default=1.0,
                    help="RED PROOF: multiply the crate's net output by this")
    a = ap.parse_args(argv)

    if a.doctor:
        if not a.out:
            return int(bool(sys.stderr.write("[GATE] --doctor needs --out\n"))) or 2
        n = doctor(a.doctor, a.out)
        print("[GATE] doctored %d acts -> %s" % (n, a.out))
        return 0

    if not a.game or not a.net or not a.repo:
        sys.stderr.write("[GATE] --game, --net and --repo are all required\n")
        return 2

    tally = {"games": 0, "rows": 0, "ok": 0, "bad": 0, "declined": 0,
             "unused": 0, "not_fitted": 0, "max_diff": 0.0}
    firsts: list[str] = []
    for p in a.game:
        check(Path(p), a.net, a.repo, a.red_scale, tally, firsts)

    print("[GATE] net %s scale %g" % (tally.get("net"), a.red_scale))
    print("[GATE] games %d | rows %d | ok %d | MISMATCH %d | declined %d"
          % (tally["games"], tally["rows"], tally["ok"], tally["bad"], tally["declined"]))
    print("[GATE] skipped: %d not fit_mode, %d pick unused | max |diff| %.3e"
          % (tally["not_fitted"], tally["unused"], tally["max_diff"]))
    for line in firsts:
        print("  " + line)
    if tally["rows"] == 0:
        print("[GATE] VACUOUS — no fitted row to hold anything against")
        return 1
    if a.red_scale != 1.0:
        # The red arm PASSES when the gate fails: a scaled net that still
        # matched would prove the number never came from the net.
        print("[GATE] RED %s — %d of %d rows moved"
              % ("PROVEN" if tally["bad"] == tally["rows"] else "INCOMPLETE",
                 tally["bad"], tally["rows"]))
        return 0 if tally["bad"] == tally["rows"] else 1
    print("[GATE] %s %d/%d" % ("GREEN" if tally["bad"] == 0 else "RED",
                               tally["ok"], tally["rows"]))
    return 0 if tally["bad"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
