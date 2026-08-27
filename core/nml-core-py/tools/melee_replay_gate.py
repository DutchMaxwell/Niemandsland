"""GATE D1-B5 (NML-1073) — the TABLE's MELEE and MORALE dice, act by act, roll by roll.

WHAT IS BEING GATED. B4 put the table's SHOOTING on the tray; the melee half of
an activation still filled an expected-value pool, and the morale test that
follows every volley and every melee was left undrawn — so from the first one
onward a `dice="table"` game was on a different stream than the recording. B5
resolves the whole charge on the tray, in `main._solo_resolve_ai_charge`'s own
order (main.gd:8039-8118): Counter's pre-phase, Impact (:8067), the charger's
strikes (:8081), the strike-back (:8100), the melee result and the loser's
morale test (:8110-8118) with Fearless's re-roll and No Retreat's self-wounds.

This tool is `shoot_replay_gate.py`'s twin for the CHARGE acts and shares its
act-positioning code (`read_game`, `burn_prefix`, `first_at_or_after`) — one
truth for where an activation starts in the stream, including the `kind:"auto"`
lines that also carry an activation ordinal.

THE THREE BARS, on every act whose recorded pick is a CHARGE with a target:

  FACES  — the tray is seeded with the game's `dice_seed`, burned forward to
           where this activation began, and every roll compared tuple by tuple:
           (roll_kind, count, target, faces), EXACT. Faces can only agree if the
           draw ORDER and every die count agree, which is what carries the port.
  HITS   — hits/blocks recomputed from the RECORDED faces at the RECORDED target
           (`DiceRules.count_successes`) against the same numbers off the
           resolver's own roll.
  NEXT   — `alive` and total wounds of BOTH combatants after the replayed melee
           against the recorded plain state of the next act. Both, not just the
           defender: a melee is the one activation where the ACTING unit takes
           wounds too.

THE MORALE CHECK, reported apart from the three bars. A morale test is one die,
and it is the last thing an activation draws, so both sides' trailing run of
1-die "attack" rolls is compared (test die, then Fearless's 4+ re-roll — No
Retreat's self-wound roll is the only trailing morale roll of more than one die
and is picked up with them). Buckets: `morale_equal` (same count, target and
owner), `morale_table_only` (the table tested and the port did not — the port
either found no loser or the wounds it dealt made the other side lose),
`morale_port_only`, `morale_target` (both tested, different target or roller).
A 1-attack strike that scored no hits looks the same from outside and is counted
here too; the bucket is symmetric, so it cannot flatter the port.

THE RED. `--red-misseed` seeds the tray with `dice_seed + 1` and changes nothing
else: every die count and every target still comes out of the same recorded
state, so the shapes line up, the comparison REACHES the faces, and every act
that staked more than a coin flip's worth of dice must part there.

    PYTHONPATH=<module> python core/nml-core-py/tools/melee_replay_gate.py \\
        --ref ~/selfplay_out/qbe_ref --limit 3
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
from shoot_replay_gate import (  # noqa: E402
    burn_prefix, defender_state, first_at_or_after, read_game, successes,
)

#: `BattleSim.CHARGE` — the only act kind that fights a melee.
CHARGE_KIND = 3


def trailing_singles(rolls: list[tuple]) -> list[tuple]:
    """The activation's trailing run of 1-die "attack" rolls — where a morale
    test lives (main.gd:8313 stamps it `roll_kind` "attack", :8320)."""
    i = len(rolls)
    while i > 0 and rolls[i - 1][0] == "attack" and rolls[i - 1][1] == 1:
        i -= 1
    return rolls[i:]


def run(ref: Path, repo: str, mode: str, limit: int, report_only: bool) -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    tally = {k: 0 for k in
             ("acts", "full_equal", "prefix_equal", "table_longer", "port_longer",
              "both_silent", "table_silent", "port_silent", "shape", "faces", "declined",
              "rolls", "rolls_equal", "hits", "hits_equal", "next_checked", "next_equal",
              "equal_over_2", "equal_dice_max", "morale_equal", "morale_table_only",
              "morale_port_only", "morale_target", "morale_none")}
    unported: dict[str, int] = {}
    reasons: dict[str, int] = {}
    firsts: list[str] = []
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        core = nml_core.load(repo)
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=True)})
        for pos, act in enumerate(lines):
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) != CHARGE_KIND or not action.get("charge"):
                continue
            tally["acts"] += 1
            i0 = first_at_or_after(dice, k)
            state = core.state_of(act["state"])
            tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                nxt, report = core.resolve_with_tray(state, action, nml_core.Rng(0), tray)
            except Exception as exc:
                tally["declined"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            for name in report["unported"]:
                unported[name] = unported.get(name, 0) + 1
            got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
                   for r in report["rolls"]]
            want = [(r["roll_kind"], r["count"], r["target"], r["faces"], r["owner"])
                    for r in dice[i0:] if int(r["act"]) == k]

            if not got and not want:
                tally["both_silent"] += 1
                continue
            if got and not want:
                tally["table_silent"] += 1
                continue
            if want and not got:
                tally["port_silent"] += 1
                continue

            # --- morale, measured apart from the four-field verdict, and only on
            #     the acts where BOTH sides rolled: an act the table never
            #     fought (`table_silent`) has no morale test to compare with.
            gm, wm = trailing_singles(got), trailing_singles(want)
            if not gm and not wm:
                tally["morale_none"] += 1
            elif gm and not wm:
                tally["morale_port_only"] += 1
            elif wm and not gm:
                tally["morale_table_only"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [morale_table_only] the table drew %s, the port none"
                                  % (d.name, k, [(w[2], w[4]) for w in wm]))
            elif [(g[1], g[2], g[4]) for g in gm] == [(w[1], w[2], w[4]) for w in wm]:
                tally["morale_equal"] += 1
            else:
                tally["morale_target"] += 1

            verdict, why = "equal", ""
            tally["rolls"] += max(len(got), len(want))
            for i, (g, w) in enumerate(zip(got, want)):
                if g[:3] != w[:3] or g[4] != w[4]:
                    field = ("kind" if g[0] != w[0] else "count" if g[1] != w[1]
                             else "target" if g[2] != w[2] else "owner")
                    reasons[field] = reasons.get(field, 0) + 1
                    verdict = "shape"
                    why = ("roll %d %s: %s(%d dice, %d+, %s) vs table %s(%d dice, %d+, %s)"
                           % (i + 1, field, g[0], g[1], g[2], g[4], w[0], w[1], w[2], w[4]))
                    break
                if g[3] != w[3]:
                    verdict, why = "faces", "roll %d %s: %s vs table %s" % (i + 1, g[0], g[3], w[3])
                    reasons["faces"] = reasons.get("faces", 0) + 1
                    break
                tally["rolls_equal"] += 1
                tally["hits"] += 1
                if successes(g[3], g[2]) == successes(w[3], w[2]):
                    tally["hits_equal"] += 1
            if verdict != "equal":
                tally[verdict] += 1
                if why and len(firsts) < 3:
                    firsts.append("%s act %d [%s] %s -> %s — %s"
                                  % (d.name, k, verdict, action["unit"][-6:],
                                     action["charge"][-6:], why))
                continue
            tally["prefix_equal"] += 1
            staked = sum(g[1] for g in got)
            tally["equal_dice_max"] = max(tally["equal_dice_max"], staked)
            if staked > 2:
                tally["equal_over_2"] += 1
            if len(got) == len(want):
                tally["full_equal"] += 1
            elif len(want) > len(got):
                tally["table_longer"] += 1
                reasons["length"] = reasons.get("length", 0) + 1
            else:
                tally["port_longer"] += 1
                reasons["length"] = reasons.get("length", 0) + 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [port_longer] %d rolls vs the table's %d"
                                  % (d.name, k, len(got), len(want)))
            # NEXT STATE — both combatants, because both of them bleed in a melee.
            if pos + 1 < len(lines):
                tally["next_checked"] += 1
                nx = nxt.plain()
                if all(defender_state(nx, key) == defender_state(lines[pos + 1]["state"], key)
                       for key in (action["unit"], action["charge"])):
                    tally["next_equal"] += 1

    label = {"table": "GATE D1-B5", "misseed": "RED D1-B5 --red-misseed (tray on dice_seed+1)"}[mode]
    print()
    print("%s over %d games, %d charge acts (%.1fs)"
          % (label, len(games), tally["acts"], time.perf_counter() - t0))
    print("  EQUAL : %d/%d acts FULL-equal (same roll count, every roll identical, same roller)"
          % (tally["full_equal"], tally["acts"]))
    print("        : %d/%d acts PREFIX-equal (the overlap held; %d table_longer, %d port_longer)"
          % (tally["prefix_equal"], tally["acts"], tally["table_longer"], tally["port_longer"]))
    print("  rolls : %d of %d compared rolls equal" % (tally["rolls_equal"], tally["rolls"]))
    print("  hits  : %d/%d rolls score the same hits/blocks off the recorded faces"
          % (tally["hits_equal"], tally["hits"]))
    print("  next  : %d/%d equal (alive, wounds) for BOTH combatants at the next act"
          % (tally["next_equal"], tally["next_checked"]))
    print("  split : %d both silent, %d table silent, %d port silent, %d shape, %d faces, %d declined"
          % (tally["both_silent"], tally["table_silent"], tally["port_silent"],
             tally["shape"], tally["faces"], tally["declined"]))
    print("  morale: %d equal, %d table only, %d port only, %d different target/roller, %d neither"
          % (tally["morale_equal"], tally["morale_table_only"], tally["morale_port_only"],
             tally["morale_target"], tally["morale_none"]))
    print("  first field to part: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    print("  unported branches touched: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(unported.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)

    if mode == "misseed":
        ok = tally["faces"] > 0 and tally["equal_over_2"] == 0
        print("  RED (load-bearing) %s"
              % ("held — %d acts reached the faces and parted; the %d that did not staked at "
                 "most %d dice (chance, 1-in-6^n)"
                 % (tally["faces"], tally["prefix_equal"], tally["equal_dice_max"]) if ok else
                 "FAILED — %d act(s) of more than 2 dice survived a wrong-seeded tray"
                 % tally["equal_over_2"]))
        return 0 if ok else 1
    ok = tally["acts"] > 0 and tally["full_equal"] == tally["acts"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short of full equality, exit 0 by request"
              % (tally["acts"] - tally["full_equal"], tally["acts"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d charge acts are not FULL-equal (see the buckets above)"
                    % (tally["acts"] - tally["full_equal"], tally["acts"])))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--red-misseed", action="store_true",
                    help="RED PROOF: seed the tray with dice_seed+1. Every count and target is "
                         "unchanged, so the shapes hold and the FACES must part")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short of full equality")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, "misseed" if a.red_misseed else "table",
               a.limit, a.report_only)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
