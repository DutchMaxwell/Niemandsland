"""GATE D1-B5b (NML-1073) — the TABLE's MELEE, IMPACT and MORALE dice, act by act, roll by roll.

WHAT IS BEING GATED. D1-B4 put the table's SHOOTING on the tray; the melee half
of an activation still filled an expected-value pool and drew nothing at all.
B5a resolves the whole charge on the tray in `main._solo_resolve_ai_charge`'s own
order (main.gd:8039-8110): Counter's pre-phase (flagged, never silently skipped),
Impact pool by pool (:6292/:6304), the charger's strikes (:8081), the strike-back
(:8100) — with Unwieldy swapping the charger behind it (:8073) — and the
melee-winner comparison on the PRE-Regeneration tally (:8110).

This tool is `shoot_replay_gate.py`'s twin for CHARGE acts and shares its
act-positioning code (`read_game`, `burn_prefix`, `first_at_or_after`): one truth
for where an activation starts in the stream, `kind:"auto"` lines included.

THE THREE BARS, on every act whose recorded pick is a CHARGE with a target:

  FACES  — the tray is seeded with the game's `dice_seed`, burned forward to
           where this activation began, and every roll compared tuple by tuple:
           (roll_kind, count, target, faces, owner), EXACT. Faces can only agree
           if the draw ORDER and every die count agree, which is what carries
           the port.
  HITS   — hits/blocks recomputed from the RECORDED faces at the RECORDED target
           (`DiceRules.count_successes`) against the same numbers off the
           resolver's own roll.
  NEXT   — `alive` and total wounds of BOTH combatants after the replayed melee
           against the recorded plain state of the next act. Both, not just the
           defender: a melee is the one activation where the ACTING unit bleeds.

THE SILENT BUCKETS ARE SPLIT ON PURPOSE, and the split is the honest part of
this gate's number. `table_silent` + `both_silent` is "the table drew no dice
under this activation at all" — on `qbe_ref` that is roughly half the recorded
CHARGE picks, and it is a CHARGE-LANDING divergence, not a dice one: the table's
charge move did not connect while this port's `edge_gap_in <= MELEE_ENGAGE_IN`
gate lands and fights. `port_silent` is the opposite and is never benign.

THE MORALE CHECK, reported apart from the three bars because a morale roll is
stamped `roll_kind` "attack" like everything else and can only be told apart by
WHERE it sits: it is the last thing an activation draws. `trailing_morale` takes
both sides' trailing run and compares (count, target, roller). A 1-attack strike
that scored no hits looks the same from outside and is counted here too — the
bucket is symmetric, so it cannot flatter the port. Buckets: `equal`,
`table_only` (the table tested and the port did not: it found no loser, or the
wounds it dealt made the other side lose), `port_only`, `other` (both tested, a
different target or roller), `neither`.

THE RED. `--red-misseed` seeds the tray with `dice_seed + 1` and changes nothing
else: every die count and every target still comes out of the same recorded
state, so the shapes line up, the comparison REACHES the faces, and every act
that staked more than a coin flip's worth of dice must part there. It can only
speak for the acts whose shapes already agree — the bundled fixture test
(`test_melee_replay.py`) carries the complementary, stricter red: on that game
`full_equal` must fall to 0 at `dice_seed + 1`.

    PYTHONPATH=<module> python core/nml-core-py/tools/melee_replay_gate.py \\
        --ref ~/selfplay_out/qbe_ref --limit 3
"""

from __future__ import annotations

import argparse
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
#: `AiCombatMath.NO_RETREAT_SELF_WOUND_MAX + 1` — the SUCCESS target of a No
#: Retreat self-wound roll (main.gd:8365), the one morale roll of >1 die.
NO_RETREAT_TARGET = 4


def trailing_morale(rolls: list[tuple]) -> list[tuple]:
    """The activation's trailing MORALE block, which is the last thing it draws.

    A morale test is one die, and so is Fearless's re-roll — but No Retreat's
    self-wound roll is `wounds_to_destroy` dice (main.gd:8364) and it is always
    LAST. Walking back over 1-die rolls alone therefore stops at it and drops
    the whole block, which is why it is accepted once, at the end, by its
    target.
    """
    i = len(rolls)
    if i and rolls[i - 1][0] == "attack" and rolls[i - 1][1] > 1 \
            and rolls[i - 1][2] == NO_RETREAT_TARGET:
        i -= 1
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
              "morale_port_only", "morale_other", "morale_none")}
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
            tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                nxt, report = core.resolve_with_tray(
                    core.state_of(act["state"]), action, nml_core.Rng(0), tray)
            except Exception as exc:  # a declined activation is not a dice verdict
                tally["declined"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            for name in report["unported"]:
                unported[name] = unported.get(name, 0) + 1
            got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
                   for r in report["rolls"]]
            # EVERY roll the table drew under this ordinal, never a prefix:
            # truncating would hide "the table drew more than the port did".
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
                if len(firsts) < 3:
                    firsts.append("%s act %d [port_silent] the table drew %d roll(s), the port none"
                                  % (d.name, k, len(want)))
                continue

            # MORALE, measured apart from the four-field verdict and only on the
            # acts where BOTH sides rolled: an act the table never fought has no
            # morale test to compare against.
            gm, wm = trailing_morale(got), trailing_morale(want)
            if not gm and not wm:
                tally["morale_none"] += 1
            elif gm and not wm:
                tally["morale_port_only"] += 1
            elif wm and not gm:
                tally["morale_table_only"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [morale_table_only] the table drew %s, the port none"
                                  % (d.name, k, [(w[1], w[2], w[4]) for w in wm]))
            elif [(g[1], g[2], g[4]) for g in gm] == [(w[1], w[2], w[4]) for w in wm]:
                tally["morale_equal"] += 1
            else:
                tally["morale_other"] += 1

            verdict, why = "equal", ""
            tally["rolls"] += max(len(got), len(want))
            for i, (g, w) in enumerate(zip(got, want)):
                if g[:3] != w[:3] or g[4] != w[4]:
                    # WHICH field parted first is the whole diagnosis: `count` is
                    # the attack-scaling class (the table scales melee by the
                    # models within 2", this port by `alive`), `target` the
                    # to-hit class, `kind` a draw-ORDER class.
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
            # How many dice this act staked on the comparison. A 2-die act
            # agreeing by CHANCE is a 1-in-36 event, so it says nothing; the
            # misseed red below is measured on the acts that staked more.
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
            # NEXT STATE — both combatants, because both of them bleed here.
            if pos + 1 < len(lines):
                tally["next_checked"] += 1
                nx = nxt.plain()
                if all(defender_state(nx, key) == defender_state(lines[pos + 1]["state"], key)
                       for key in (action["unit"], action["charge"])):
                    tally["next_equal"] += 1

    label = {"table": "GATE D1-B5b",
             "misseed": "RED D1-B5b --red-misseed (tray on dice_seed+1)"}[mode]
    silent_table = tally["both_silent"] + tally["table_silent"]
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
    # THE SPLIT, spelled out rather than summed: the first line is a
    # CHARGE-LANDING class (the table's charge never connected), the second is a
    # dice class and is never benign.
    print("  silent: %d/%d acts where the TABLE drew nothing (%d both silent + %d table silent) "
          "— the table's charge did not connect; not a dice divergence"
          % (silent_table, tally["acts"], tally["both_silent"], tally["table_silent"]))
    print("        : %d/%d acts where the PORT drew nothing while the table rolled — never benign"
          % (tally["port_silent"], tally["acts"]))
    print("  morale: %d equal (count, target and roller), %d table only, %d port only, "
          "%d other, %d neither"
          % (tally["morale_equal"], tally["morale_table_only"], tally["morale_port_only"],
             tally["morale_other"], tally["morale_none"]))
    print("  parted: %d shape, %d faces, %d declined" % (tally["shape"], tally["faces"],
                                                         tally["declined"]))
    print("  first field to part: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    print("  unported branches touched: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(unported.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)

    if mode == "misseed":
        # LOAD-BEARING as far as it reaches: the shapes still line up, so the
        # comparison must arrive at the faces and fail there. Acts of 1-2 dice
        # CAN agree on a wrong seed by chance (1/6, 1/36), so the bar is stated
        # in dice and the surviving sizes are printed rather than hidden.
        ok = tally["faces"] > 0 and tally["equal_over_2"] == 0
        print("  RED %s"
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
    ap.add_argument("--mode", choices=("table", "misseed"), default="table",
                    help="'table' is the gate and exits 1 short of full equality; 'misseed' is "
                         "the red")
    ap.add_argument("--red-misseed", action="store_true",
                    help="RED PROOF: seed the tray with dice_seed+1. Every count and target is "
                         "unchanged, so the shapes hold and the FACES must part")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short of full equality (this tool is a GATE "
                         "by default and exits 1)")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo,
               "misseed" if a.red_misseed else a.mode, a.limit, a.report_only)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
