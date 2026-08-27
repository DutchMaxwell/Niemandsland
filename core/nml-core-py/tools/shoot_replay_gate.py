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

VERDICTS per act. `want` is EVERY roll the table drew under this activation
ordinal, never a prefix — truncating it would hide the case where the table drew
MORE than the port did:

  `full_equal`   — same number of rolls, every roll identical. THIS is the gate's
                   number, and the tool exits 1 while any act misses it (pass
                   `--report-only` to survey instead of gate).
  `prefix_equal` — the overlap held but the lengths differ. It splits into
                   `table_longer` (the table drew rolls the port did not — often
                   a LATER activation sharing the ordinal, because `move_act_seq`
                   bumps once per planner pick and a dry side hands the tail to
                   the other; benign but unproven) and `port_longer` (the port
                   drew rolls the table never did — never benign).
  `both_silent` / `table_silent` / `port_silent` — one side or both drew nothing.
                   These are classified and CLOSED; they never fall through into
                   the length or shape counters.
  `shape` / `faces` — a roll parted inside the overlap. `faces` after `shape`
                   held would mean the tray twin itself is wrong.

THE TWO REDS, and they are not equals:

  `--red-misseed` is the LOAD-BEARING one. It seeds the tray with `dice_seed + 1`
  and changes nothing else: every die count and every target still comes out of
  the same recorded state, so the shapes line up, the comparison REACHES the
  faces, and every act that rolls must part there. A green here would mean the
  faces are not actually being compared. The bar is stated in dice, not in acts:
  an activation of one or two dice CAN agree on a wrong seed by chance (1/6,
  1/36) and two of the 670 do, so the red holds when no act that staked MORE
  than two dice survived — and the surviving sizes are printed, not hidden.

  `--mode off` reruns the same acts down the expected-value path. It draws no
  dice at all, so it proves the REPORTING CHANNEL — that an absent stream is
  noticed — and nothing whatever about whether the faces are right.

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


def detach(plain: dict) -> dict:
    """`--hero-attach off` on a RECORDED state. The corpus is a table game, so
    every host already carries its `attached` heroes and every hero its
    `attached_to` — which is `hero_attach="table"`, and there is nothing to
    switch on. This strips the two fields instead, so the same acts replay the
    way a `hero_attach="off"` corpus would: the D1-B4b volley then finds no
    member but the host, exactly as `selfplay.play_game(hero_attach="off")`
    leaves it. It is the BEFORE half of the B4b measurement, in one tool."""
    out = dict(plain)
    units = {}
    for k, u in plain["units"].items():
        u = dict(u, attached=[], attached_to="")
        # `attached_hero_rules` (state.rs:71/:173) is the ONE profile field that
        # follows from attachment, and it rides the act's own `prof` block. Left
        # standing, a fallen-hero-less "off" control would still let the hero's
        # rules vote in `AiEv.rule_on_all_models` (ai_ev.gd:79-83) — the control
        # would not be a control.
        if isinstance(u.get("prof"), dict):
            u["prof"] = dict(u["prof"], attached_hero_rules=[])
        units[k] = u
    out["units"] = units
    return out


def detach_header(head: dict) -> dict:
    """The header's half of `--hero-attach off`: an act with no `prof` block
    falls back to the HEADER profile, so the same field has to go there too."""
    profiles = {k: dict(p, attached_hero_rules=[]) for k, p in head["profiles"].items()}
    return dict(head, profiles=profiles)


def defender_state(plain: dict, key: str) -> tuple[int, int]:
    """(alive, total wounds left) of one unit in a plain state."""
    u = plain["units"].get(key)
    if u is None:
        return (-1, -1)
    return (int(u["alive"]), int(sum(u["wounds"])))


def run(ref: Path, repo: str, mode: str, limit: int, verbose: int, report_only: bool,
        hero_attach: str = "table") -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no dice.jsonl under %s" % ref)
        return 1

    tally = {k: 0 for k in
             ("acts", "prefix_equal", "full_equal", "table_longer", "port_longer",
              "both_silent", "table_silent", "port_silent", "shape", "faces",
              "declined", "rolls_equal", "rolls", "hits_equal", "hits", "next_checked",
              "next_equal", "equal_over_2", "equal_dice_max", "split_fire",
              "full_equal_owner")}
    unported: dict[str, int] = {}
    reasons: dict[str, int] = {}
    firsts: list[str] = []
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        core = nml_core.load(repo)
        if hero_attach == "off":
            head = detach_header(head)
        # `hero_attach` is also a SEAM (`Seams::hero_attach`, io.rs): with it on,
        # a host's activation marks its heroes activated and drags their models
        # along. Neither touches this tool's verdict — it replays one recorded
        # act at a time and compares the DEFENDER — but a control that only half
        # flips the knob is not a control.
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}),
                                       hero_attach=hero_attach == "table")})
        for k, act in enumerate(lines, 1):
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) not in SHOOTING_KINDS or not action.get("shoot"):
                continue
            tally["acts"] += 1
            i0 = first_at_or_after(dice, k)
            plain = act["state"] if hero_attach == "table" else detach(act["state"])
            state = core.state_of(plain)
            # `--red-misseed` moves the tray one seed over. Every count and
            # every target still comes out of the same state, so the SHAPE holds
            # and the comparison reaches the faces — which is exactly what has
            # to go red, and what `--mode off` (no dice at all) cannot prove.
            tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
            if burn[i0]:
                tray.roll(burn[i0])
            try:
                if mode in ("table", "misseed"):
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
            # SPLIT FIRE, measured rather than assumed: the table signs each save
            # batch with the DEFENDER (main.gd:6448), so a defense roll under
            # this ordinal whose owner is not the recorded `shoot` target means
            # the table aimed a shot somewhere this port cannot follow
            # (`_solo_pick_overlay_target` :2996-3005).
            tgt_owner = "AI (%s)" % head["profiles"][action["shoot"]]["name"] \
                if action["shoot"] in head["profiles"] else None
            if tgt_owner and any(r["roll_kind"] == "defense" and r["owner"] != tgt_owner
                                 for r in dice[i0:] if int(r["act"]) == k):
                tally["split_fire"] += 1

            # `owner` rides along as the FIFTH slot and is deliberately NOT
            # compared: D1-B4b stamps it so a divergence can say WHO rolled
            # (main.gd:7173 — the firing member, so an attached hero signs its
            # own dice), not so the verdict changes shape.
            got = [(r["kind"], r["count"], r["target"], r["faces"], r["owner"])
                   for r in report["rolls"]]
            # EVERY roll the table drew under this activation ordinal, NOT a
            # prefix: truncating to `len(got)` would hide "the table drew more
            # than the port did", which is the whole `table_longer` bucket.
            want = [(r["roll_kind"], r["count"], r["target"], r["faces"], r["owner"])
                    for r in dice[i0:] if int(r["act"]) == k]
            if not got and not want:
                tally["both_silent"] += 1
                continue
            if got and not want:
                tally["table_silent"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [table_silent] %s — the port drew %d roll(s), "
                                  "the table none" % (d.name, k, action["shoot"][-6:], len(got)))
                continue
            if want and not got:
                tally["port_silent"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [port_silent] %s — the table drew %d roll(s), "
                                  "the port none" % (d.name, k, action["shoot"][-6:], len(want)))
                continue

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
                    verdict, why = ("shape",
                                    "roll %d %s: %s(%d dice, %d+, %s) vs table %s(%d dice, %d+, %s)"
                                    % (i + 1, field, g[0], g[1], g[2], "AI (%s)" % g[4],
                                       w[0], w[1], w[2], w[4]))
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
                    firsts.append("%s act %d [%s] %s — %s"
                                  % (d.name, k, verdict, action["shoot"][-6:], why))
            else:
                # The overlap held. PREFIX-equal is that much; FULL-equal also
                # needs the two lists to be the same length. They part when the
                # table ran further activations under this same ordinal
                # (`table_longer`, benign but unproven) or when the port drew
                # rolls the table never did (`port_longer`, never benign).
                tally["prefix_equal"] += 1
                # How many dice this act actually staked on the comparison. A
                # 2-die act agreeing by CHANCE is a 1-in-36 event, so it says
                # nothing; the misseed red below is measured on the acts that
                # staked more than that.
                staked = sum(g[1] for g in got)
                tally["equal_dice_max"] = max(tally["equal_dice_max"], staked)
                if staked > 2:
                    tally["equal_over_2"] += 1
                # D1-B4b — THE SECOND BAR: WHO rolled. The port emits the bare
                # unit name; `dice.jsonl` wraps it the way `_solo_owner_label`
                # does (main.gd:7039-7040), and in a trainer corpus every unit
                # is an AI unit. Compared APART from the four-field verdict so
                # the numbers above stay the ones every earlier run measured —
                # and compared at all because it is what turns "the attached
                # hero fires its OWN shots" from a claim into a verdict: a host
                # rolling the hero's dice matches on count, target and faces and
                # can only part HERE.
                owners_ok = all("AI (%s)" % g[4] == w[4] for g, w in zip(got, want))
                if not owners_ok:
                    reasons["owner"] = reasons.get("owner", 0) + 1
                    if len(firsts) < 3:
                        bad = next((i for i, (g, w) in enumerate(zip(got, want))
                                    if "AI (%s)" % g[4] != w[4]), 0)
                        firsts.append("%s act %d [owner] %s — roll %d: AI (%s) vs table %s"
                                      % (d.name, k, action["shoot"][-6:], bad + 1,
                                         got[bad][4], want[bad][4]))
                if len(got) == len(want):
                    tally["full_equal"] += 1
                    if owners_ok:
                        tally["full_equal_owner"] += 1
                elif len(want) > len(got):
                    tally["table_longer"] += 1
                    reasons["length"] = reasons.get("length", 0) + 1
                else:
                    tally["port_longer"] += 1
                    reasons["length"] = reasons.get("length", 0) + 1
                    if len(firsts) < 3:
                        firsts.append("%s act %d [port_longer] %s — %d rolls vs the table's %d"
                                      % (d.name, k, action["shoot"][-6:], len(got), len(want)))
                if k < len(lines):
                    tally["next_checked"] += 1
                    if defender_state(nxt.plain(), action["shoot"]) == defender_state(
                            lines[k]["state"], action["shoot"]):
                        tally["next_equal"] += 1


    label = {"table": "GATE D1-B4",
             "off": "RED D1-B4 --mode off (dice=expected)",
             "misseed": "RED D1-B4 --red-misseed (tray on dice_seed+1)"}[mode]
    print()
    print("%s over %d games, %d shooting acts, hero_attach=%s (%.1fs)" % (
        label, len(games), tally["acts"], hero_attach, time.perf_counter() - t0))
    print("  EQUAL : %d/%d acts FULL-equal (same roll count, every roll identical)"
          % (tally["full_equal"], tally["acts"]))
    print("  OWNER : %d/%d acts FULL-equal AND every roll signed by the same unit "
          "(the strict bar; %d act(s) match the dice but not the roller)"
          % (tally["full_equal_owner"], tally["acts"],
             tally["full_equal"] - tally["full_equal_owner"]))
    print("        : %d/%d acts PREFIX-equal (the overlap held; %d table_longer, %d port_longer)"
          % (tally["prefix_equal"], tally["acts"], tally["table_longer"], tally["port_longer"]))
    print("  rolls : %d of %d compared rolls equal" % (tally["rolls_equal"], tally["rolls"]))
    print("  hits  : %d/%d rolls score the same hits/blocks off the recorded faces"
          % (tally["hits_equal"], tally["hits"]))
    print("  next  : %d/%d equal defender (alive, wounds) at the next act (prefix-equal acts)"
          % (tally["next_equal"], tally["next_checked"]))
    print("  split : %d both silent, %d table silent, %d port silent, %d shape, %d faces, %d declined"
          % (tally["both_silent"], tally["table_silent"], tally["port_silent"],
             tally["shape"], tally["faces"], tally["declined"]))
    print("  first field to part: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    print("  split-fire: %d/%d acts where the table saved dice under a unit that is NOT "
          "the recorded shoot target" % (tally["split_fire"], tally["acts"]))
    print("  unported branches touched: %s" % (
        ", ".join("%s=%d" % kv for kv in sorted(unported.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)

    if mode == "off":
        # The reporting channel only: with no dice drawn there is nothing to
        # compare, so this proves the tool NOTICES an absent stream — not that
        # the stream is right. `--red-misseed` is the load-bearing one.
        ok = tally["prefix_equal"] == 0 and tally["acts"] > 0
        print("  RED (reporting channel) %s"
              % ("held — no tray, no equal act" if ok else "FAILED — the EV path matched"))
        return 0 if ok else 1
    if mode == "misseed":
        # LOAD-BEARING: the shapes still line up, so the comparison must reach
        # the faces and fail there. A green here would mean the faces are not
        # actually being compared.
        # A wrong seed must redden every act that staked more than a coin-flip's
        # worth of dice. Acts of 1-2 dice CAN agree by chance (1/6, 1/36) and two
        # of them do over 670 acts — counting those as a red failure would be
        # arithmetic denial, so the bar is `equal_over_2 == 0` and the surviving
        # sizes are printed rather than hidden.
        ok = tally["faces"] > 0 and tally["equal_over_2"] == 0
        print("  RED (load-bearing) %s"
              % ("held — %d acts reached the faces and parted; the %d that did not staked "
                 "at most %d dice (chance, 1-in-6^n)"
                 % (tally["faces"], tally["prefix_equal"], tally["equal_dice_max"])
                 if ok else
                 "FAILED — %d act(s) of more than 2 dice survived a wrong-seeded tray"
                 % tally["equal_over_2"]))
        return 0 if ok else 1

    # The GATE is the strict bar: same dice AND the same unit rolling them.
    ok = tally["acts"] > 0 and tally["full_equal_owner"] == tally["acts"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short of full equality, exit 0 by request"
              % (tally["acts"] - tally["full_equal_owner"], tally["acts"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d shooting acts are not FULL-equal (see the buckets above)"
                    % (tally["acts"] - tally["full_equal_owner"], tally["acts"])))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--mode", choices=("table", "off", "misseed"), default="table",
                    help="'table' is the gate; 'off' reruns the acts down the expected-value "
                         "path, which proves the REPORTING CHANNEL only (no dice are drawn, so "
                         "nothing about the faces is tested); 'misseed' is the load-bearing red")
    ap.add_argument("--red-misseed", action="store_true",
                    help="RED PROOF: seed the tray with dice_seed+1. Every count and target is "
                         "unchanged, so the shapes hold and the FACES must part on every act "
                         "that rolls")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short of full equality (this tool is a GATE "
                         "by default and exits 1)")
    ap.add_argument("--hero-attach", choices=("table", "off"), default="table",
                    help="'table' replays the recorded attachment, which is what the corpus "
                         "carries and what D1-B4b reads; 'off' strips `attached`/`attached_to` "
                         "from every replayed state, reproducing a hero_attach='off' corpus — "
                         "the BEFORE half of the B4b measurement")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--verbose", type=int, default=0, help="print every diverging act")
    a = ap.parse_args(argv)
    mode = "misseed" if a.red_misseed else a.mode
    return run(Path(a.ref).expanduser(), a.repo, mode, a.limit, a.verbose, a.report_only,
               a.hero_attach)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
