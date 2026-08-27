"""GATE D1-B4 (NML-1073) — the TABLE's SHOOTING dice, act by act, roll by roll.

WHAT IS BEING GATED. `tools/arena_match.gd` plays on the real table and every
combat die leaves `_solo_tray_roll` (main.gd:7126-7180); D1-B1 taps that into
`dice.jsonl`, one line per roll with the activation ordinal on it. The fast
trainer had no damage dice at all — `sim.rs` filled an expected-value pool. B4
gives it the tray: `dice::resolve_shooting_with_tray` draws the hit dice, the
save batch, Bane's re-roll and the pooled Regeneration roll in the table's own
order, and the wounds then land through the trainer's OWN casualty machinery.

THE THREE CHECKS, on every act whose recorded pick is HOLD/ADVANCE with a shoot
target:

  STREAM — the tray is seeded with the game's `dice_seed` and BURNED forward to
  where this activation started (the sum of `maxi(1, count)` over every earlier
  recorded roll — main.gd:7152-7159's zero-die rule included). The resolver's
  rolls are then compared to the recorded ones tuple by tuple:
  (roll_kind, count, target, faces), EXACT. Faces can only agree if the draw
  ORDER and every die COUNT agree, which is why this one check carries the port.

  HITS — hits/blocks recomputed from the RECORDED faces at the RECORDED target
  (`DiceRules.count_successes`, dice_rules.gd:55-71) against the same numbers
  off the resolver's own roll. Redundant while STREAM is green, and the first
  thing left standing when it is not.

  NEXT STATE — the defender's `alive` and total wounds after the replayed
  activation against the recorded plain state of the NEXT act. Reported as
  measured, not asserted: the table can run further activations between two
  planner picks (a dry side hands the tail to the other), and those land on the
  same defender.

VERDICTS per act: `equal` (every roll matched), `both_silent` (neither side rolled
a die), `table_silent` (the trainer's volley fired, the TABLE's did not),
`port_silent`, `shape` (a count/target parted) and `faces` (the shape held and a
face did not — which would mean the tray twin itself is wrong).

RED PROOF: `--mode off` runs the SAME acts down the expected-value path
(`resolve_stochastic_rng`), which draws nothing from the tray. Every act that
the table rolled dice for must then go red, and none may report `equal`.

    PYTHONPATH=<module> python core/nml-core-py/tools/shoot_replay_gate.py \\
        --ref ~/selfplay_out/qbd_ref --limit 3
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402

#: `AiPlanner` action kinds that shoot (`BattleSim.HOLD` / `.ADVANCE`).
SHOOTING_KINDS = (0, 1)


def successes(faces, target: int) -> int:
    """`DiceRules.count_successes(faces, target, 0)` dice_rules.gd:55-71 — a 6
    always succeeds, a 1 always fails, everything else needs `>= target`."""
    if target <= 0:
        return 0
    return sum(1 for f in faces if f >= 6 or (f > 1 and f >= target))


def read_game(d: Path) -> tuple[dict, list[dict], list[dict], int]:
    """(header, act lines, dice lines, dice_seed) of one recorded arena game."""
    acts = [json.loads(x) for x in (d / "acts.jsonl").read_text().splitlines() if x.strip()]
    head, lines = acts[0], [a for a in acts[1:] if a.get("kind") == "act"]
    dice = [json.loads(x) for x in (d / "dice.jsonl").read_text().splitlines() if x.strip()]
    arena = next(d.glob("arena_*.json"))
    return head, lines, dice, int(json.loads(arena.read_text())["dice_seed"])


def burn_prefix(dice: list[dict]) -> list[int]:
    """Draws standing BEFORE each recorded roll. `maxi(1, count)`, so a zero-die
    roll costs one draw all the same (main.gd:7152-7159) — get this wrong and
    every face from that point on is off by one."""
    out, n = [], 0
    for r in dice:
        out.append(n)
        n += max(1, int(r["count"]))
    out.append(n)
    return out


def first_at_or_after(dice: list[dict], act: int) -> int:
    """Index of the first roll drawn at or after activation `act` — where the
    stream stood when that activation began, whether or not it rolled."""
    for i, r in enumerate(dice):
        if int(r["act"]) >= act:
            return i
    return len(dice)


def defender_state(plain: dict, key: str) -> tuple[int, int]:
    """(alive, total wounds left) of one unit in a plain state."""
    u = plain["units"].get(key)
    if u is None:
        return (-1, -1)
    return (int(u["alive"]), int(sum(u["wounds"])))


def run(ref: Path, repo: str, mode: str, limit: int, verbose: int) -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    tally = {k: 0 for k in
             ("acts", "equal", "both_silent", "table_silent", "port_silent", "shape", "faces",
              "declined", "rolls_equal", "rolls", "hits_equal", "hits", "next_checked", "next_equal")}
    unported: dict[str, int] = {}
    reasons: dict[str, int] = {}
    firsts: list[str] = []
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        core = nml_core.load(repo)
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}))})
        for k, act in enumerate(lines, 1):
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) not in SHOOTING_KINDS or not action.get("shoot"):
                continue
            tally["acts"] += 1
            i0 = first_at_or_after(dice, k)
            state = core.state_of(act["state"])
            tray = nml_core.Tray(seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                if mode == "table":
                    nxt, report = core.resolve_with_tray(state, action, nml_core.Rng(0), tray)
                else:
                    nxt = core.resolve_stochastic_rng(state, action, nml_core.Rng(0))
                    report = {"rolls": [], "unported": []}
            except Exception as exc:  # a declined activation is not a dice verdict
                tally["declined"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            for name in report["unported"]:
                unported[name] = unported.get(name, 0) + 1

            got = [(r["kind"], r["count"], r["target"], r["faces"]) for r in report["rolls"]]
            want = [(r["roll_kind"], r["count"], r["target"], r["faces"])
                    for r in dice[i0:] if int(r["act"]) == k][:len(got) if got else None]
            # `want` is the PREFIX of this activation's own rolls: the table can
            # run further activations under the same ordinal, and those are not
            # this volley's.
            if not got and not want:
                tally["both_silent"] += 1
                continue
            if got and not want:
                tally["table_silent"] += 1
            elif want and not got:
                tally["port_silent"] += 1
            verdict = "equal"
            why = ""
            tally["rolls"] += max(len(got), len(want))
            for i, (g, w) in enumerate(zip(got, want)):
                if g[:3] != w[:3]:
                    # WHICH field parted first is the whole diagnosis: `count`
                    # is the attack-scaling class (the table scales by SIGHTED
                    # models, main.gd:4109, this port by `alive`), `target` the
                    # to-hit / AP class, `kind` a draw-order class.
                    field = ("kind" if g[0] != w[0] else
                             "count" if g[1] != w[1] else "target")
                    reasons[field] = reasons.get(field, 0) + 1
                    verdict, why = "shape", "roll %d %s: %s(%d dice, %d+) vs table %s(%d dice, %d+)" % (
                        i + 1, field, g[0], g[1], g[2], w[0], w[1], w[2])
                    break
                if g[3] != w[3]:
                    verdict, why = "faces", "roll %d %s: %s vs table %s" % (i + 1, g[0], g[3], w[3])
                    break
                tally["rolls_equal"] += 1
                tally["hits"] += 1
                if successes(g[3], g[2]) == successes(w[3], w[2]):
                    tally["hits_equal"] += 1
            if verdict == "equal" and len(got) != len(want):
                verdict = "shape"
                reasons["length"] = reasons.get("length", 0) + 1
                why = "%d rolls vs the table's %d for this activation" % (len(got), len(want))
            if verdict == "equal":
                tally["equal"] += 1
                if k < len(lines):
                    tally["next_checked"] += 1
                    if defender_state(nxt.plain(), action["shoot"]) == defender_state(
                            lines[k]["state"], action["shoot"]):
                        tally["next_equal"] += 1
            elif why and len(firsts) < 3:
                firsts.append("%s act %d [%s] %s — %s" % (d.name, k, verdict, action["shoot"][-6:], why))
            if verdict in ("shape", "faces") and not (got and not want) and not (want and not got):
                tally[verdict] += 1
            if verbose and verdict != "equal":
                print("  %s act %d %s: got %s want %s" % (d.name, k, verdict, got, want))

    label = "GATE D1-B4" if mode == "table" else "RED D1-B4 (dice=expected)"
    print()
    print("%s over %d games, %d shooting acts (%.1fs)" % (
        label, len(games), tally["acts"], time.perf_counter() - t0))
    print("  stream: %d/%d acts roll for roll EQUAL   (%d rolls equal of %d compared)"
          % (tally["equal"], tally["acts"], tally["rolls_equal"], tally["rolls"]))
    print("  hits  : %d/%d rolls score the same hits/blocks off the recorded faces"
          % (tally["hits_equal"], tally["hits"]))
    print("  next  : %d/%d equal defender (alive, wounds) at the next act"
          % (tally["next_equal"], tally["next_checked"]))
    print("  split : %d both silent, %d table silent, %d port silent, %d shape, %d faces, %d declined"
          % (tally["both_silent"], tally["table_silent"], tally["port_silent"],
             tally["shape"], tally["faces"], tally["declined"]))
    print("  first field to part: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    print("  unported branches touched: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(unported.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)
    if mode != "table":
        ok = tally["equal"] == 0 and tally["acts"] > 0
        print("  RED %s" % ("held (the tray is load-bearing)" if ok else "FAILED — the EV path matched"))
        return 0 if ok else 1
    print("  measured, not asserted: this gate REPORTS; the bar is the trend, act by act")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--mode", choices=("table", "off"), default="table",
                    help="'table' is the gate; 'off' is the RED PROOF and must go red")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--verbose", type=int, default=0, help="print every diverging act")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.mode, a.limit, a.verbose)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
