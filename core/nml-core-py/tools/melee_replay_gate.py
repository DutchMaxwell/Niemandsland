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
WHERE it sits: it is the last thing an activation draws. (NML-1104 gave the
RECORDED corpus its own kind per rule — "morale", "fearless", "no_retreat" —
but the port's OWN rolls, `core/nml-core/src/dice.rs`, still stamp the old
blanket "attack"; `shoot_replay_gate.combat_kind()` folds the recorded side's
`roll_kind` back to "attack"/"defense" when this file's `want` tuples are
built, so every "attack" check below — here and in `dice_gate.py` — still
means what it always meant.) `trailing_morale` takes both sides' trailing run
and compares (count, target, roller). A 1-attack strike that scored no hits
looks the same from outside and is counted here too — the bucket is symmetric,
so it cannot flatter the port. Buckets: `equal`,
`table_only` (the table tested and the port did not: it found no loser, or the
wounds it dealt made the other side lose), `port_only`, `other` (both tested, a
different target or roller), `neither`.

CONSOLIDATION (G4R6 R21, epoch 73+). The winner's destination is a free "may": for a charge whose next act shows the
charger alive and the defender wiped, `consol_marker` hands the core the table's recorded final charger centroid as a
neutral marker, so the table's own Dangerous test there has a core twin (`--red-consol-land` hands none).

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
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
from shoot_replay_gate import (  # noqa: E402
    burn_prefix, combat_kind, cut_dangerous, cut_pre_legs, dang_replay, defender_state, extra_die_hosts, first_at_or_after,
    lone_hero_names, parted_field, read_game, read_pre, resolve_vintage_flag, signer_ok, successes, vintage_report_line,
)

#: `BattleSim.CHARGE` — the only act kind that fights a melee.
CHARGE_KIND = 3
#: `AiCombatMath.NO_RETREAT_SELF_WOUND_MAX + 1` — the SUCCESS target of a No
#: Retreat self-wound roll (main.gd:8365), the one morale roll of >1 die.
NO_RETREAT_TARGET = 4
#: `SoloController.INCHES_TO_METERS`.
IN2M = 0.0254


#: The three per-unit header fields rung D5-4b (#447) added — the base SHAPE
#: `base_radius` cannot carry. A corpus recorded before it has none of them.
BASE_SHAPE_KEYS = ("base_shape", "base_w_mm", "base_d_mm")


def round_only_profiles(profiles: dict) -> dict:
    """The header's profile table with the D5-4b base-SHAPE fields removed.

    The RED for D5-2b, and the identity proof in the same move: the twin reads
    the shape ONLY out of these three keys, so stripping them must reproduce
    the pre-D5-2b run line for line — which is also why every corpus older
    than #447 (qbe_ref, qbf_ref, qag_ref) replays byte for byte untouched.
    """
    return {k: {f: v for f, v in p.items() if f not in BASE_SHAPE_KEYS}
            for k, p in profiles.items()}


def header_walls_m(d: Path, head: dict) -> tuple[list, str]:
    """The board's wall segments in the ACT-HEADER contract — WORLD METRES —
    plus one line saying where they came from.

    TWO SOURCES, TWO FRAMES. Rung D5-2a (#436) puts `walls` inside the act
    header's `terrain` object as `TerrainOverlay.get_wall_segments_world()`, i.e.
    world metres centred on the origin. `moves_calls.jsonl`'s header has carried
    the same segments since M4-0a but in the movement planner's BOARD-LOCAL INCH
    frame (`walls_in`, solo_controller.gd:6165-6169). A corpus recorded before
    D5-2a has only the second, so it is converted back here — the inverse of the
    one conversion `Terrain::set_walls_world_m` performs — and the gate then
    prints what the port made of it again (`--walls-check`).
    """
    ter = head.get("terrain") or {}
    if ter.get("walls"):
        return ter["walls"], "act header terrain.walls (D5-2a), %d segments" % len(ter["walls"])
    mc = d / "moves_calls.jsonl"
    if not mc.exists():
        return [], "NONE — no act-header walls and no moves_calls.jsonl"
    with open(mc, encoding="utf-8") as f:
        mh = json.loads(f.readline())
        raw = mh.get("walls") or []
        src = "header"
        # `MoveRecorder._header_line` (move_recorder.gd:126) snapshots the walls of
        # the FIRST plan call of the game, and in a handful of games that call ran
        # before the wall provider was live — the header then reads 0 segments
        # while every later line carries the real list INLINE. Take the first
        # inline list in that case; a header that HAS walls is always preferred.
        if not raw:
            for line in f:
                w = json.loads(line).get("walls")
                if isinstance(w, list) and w:
                    raw, src = w, "first inline call line (header was empty)"
                    break
    board = mh.get("board_in") or [0.0, 0.0]
    half = [board[0] * 0.5, board[1] * 0.5]
    out = [[[(p[0] - half[0]) * IN2M, (p[1] - half[1]) * IN2M] for p in w] for w in raw]
    return out, "moves_calls.jsonl %s, %d segments (inches -> metres)" % (src, len(out))


def consol_marker(plain: dict, action: dict, nxt: dict | None) -> dict:
    """G4R6 R21 F-CONSOL-LAND (epoch 73+): `plain` with a NEUTRAL marker at the table's recorded final centroid of the charger.

    For a charge whose NEXT act shows the charger alive and the defender wiped. The winner's consolidation destination is a
    free choice (both legal); the core aims at the nearest marker its side does not own, so it lands where the table's
    consolidation did and the table's own Dangerous terrain test there has a core twin. Any other act is returned as it is.
    """
    units = (nxt or {}).get("units") or {}
    u, t = units.get(action["unit"]) or {}, units.get(action["charge"]) or {}
    ps = u.get("positions") or []
    if int(u.get("alive", 0)) <= 0 or int(t.get("alive", 0)) > 0 or not ps:
        return plain
    c = [sum(p[i] for p in ps) / len(ps) for i in (0, 2)]
    return dict(plain, objectives=list(plain["objectives"]) + [{"owner": 0, "pos": [c[0], 0.0, c[1]]}])


def legged(got: list[tuple], want: list[tuple]) -> list[tuple]:
    """`got` where a roll that is the SAME die as the table's carries the table's recorded `leg` (the core's rolls have none)."""
    return [g + want[i][5:] if i < len(want) and g == want[i][:5] else g for i, g in enumerate(got)]


def trailing_morale(rolls: list[tuple]) -> list[tuple]:
    """The activation's trailing MORALE block, which is the last thing it draws.

    A morale test is one die, and so is Fearless's re-roll — but No Retreat's
    self-wound roll is `wounds_to_destroy` dice (main.gd:8364) and it is always
    LAST. Walking back over 1-die rolls alone therefore stops at it and drops
    the whole block, which is why it is accepted once, at the end, by its
    target. A die of the recorded `dangerous` leg (a sixth field) is the
    Dangerous terrain test of a move, never a morale die (G4R6 R21).
    """
    i = len(rolls)
    if i and rolls[i - 1][0] == "attack" and rolls[i - 1][1] > 1 \
            and rolls[i - 1][2] == NO_RETREAT_TARGET:
        i -= 1
    while i > 0 and rolls[i - 1][0] == "attack" and rolls[i - 1][1] == 1 and rolls[i - 1][5:] != ("dangerous",):
        i -= 1
    return rolls[i:]


def run(ref: Path, repo: str, mode: str, limit: int, report_only: bool,
        charge_landing: bool = False, movement: bool = False,
        walls_check: bool = False, rigid_red: bool = False,
        no_dangerous: bool = False, no_hero_fold: bool = False,
        engage_fold: str = "auto", cond_ap: str = "auto",
        red_round_only: bool = False, red_dang_tail: bool = False,
        red_consol_land: bool = False) -> int:
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
    warns: list[str] = []
    walls_seen = {"games": 0, "segments": 0, "worst": 0.0, "source": ""}
    vintage_seen: set[tuple[bool, bool]] = set()
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, seed = read_game(d)
        burn = burn_prefix(dice)
        pres = read_pre(d)
        core = nml_core.load(repo)
        # D5-2: the charge move routes around the board's WALLS, and the act
        # corpus carried none before rung D5-2a. Without them the port would
        # plan through ruins and call it the table's route, so the source is
        # named out loud and an empty list is a WARN, not a silent default.
        walls, source = header_walls_m(d, head)
        walls_seen["source"] = source
        if movement and not walls:
            warns.append("%s: %s — the charge route sees no walls" % (d.name, source))
        # NML-1130: `--red-no-hero-fold` still wins outright (it exists to
        # prove the fold's numbers come back, independent of what this corpus
        # was recorded with); otherwise engage_fold/cond_ap read the corpus's
        # OWN vintage — see `vintage_knobs`.
        eff_engage_fold = False if no_hero_fold else \
            resolve_vintage_flag(engage_fold, head, repo, "engage_fold")
        eff_cond_ap = resolve_vintage_flag(cond_ap, head, repo, "cond_ap")
        consol_on = int((head.get("knobs") or {}).get("rules_epoch", 0)) >= 73 and not red_consol_land
        vintage_seen.add((eff_engage_fold, eff_cond_ap))
        nml_core.set_legacy_no_cond_ap(not eff_cond_ap)
        header = {"profiles": round_only_profiles(head["profiles"])
                  if red_round_only else head["profiles"],
                  "terrain": dict(head.get("terrain") or {}, walls=walls)
                  if head.get("terrain") else None,
                  "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                charge_landing=charge_landing,
                                dangerous=not no_dangerous,
                                engage_fold=eff_engage_fold,
                                movement=movement and not rigid_red)}
        core.set_header(header)
        if walls_check and walls:
            walls_seen["games"] += 1
            got = core.walls_in()
            with open(d / "moves_calls.jsonl", encoding="utf-8") as f:
                mb = (json.loads(f.readline()).get("board_in") or [0.0, 0.0])
            want = [[[(p[0] / IN2M) + mb[0] * 0.5, (p[1] / IN2M) + mb[1] * 0.5] for p in w]
                    for w in walls]
            for g, w in zip(got, want):
                for pg, pw in zip(g, w):
                    walls_seen["worst"] = max(walls_seen["worst"],
                                              abs(pg[0] - pw[0]), abs(pg[1] - pw[1]))
                    walls_seen["segments"] += 1
        for pos, act in enumerate(lines):
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) != CHARGE_KIND or not action.get("charge"):
                continue
            tally["acts"] += 1
            i0 = first_at_or_after(dice, k)
            # AI-G4 H1b: the table's cast/spell legs are cut, their dice burned, the state patched (see shoot_replay_gate).
            rolls_k = [r for r in dice[i0:] if int(r["act"]) == k]
            rolls_cut, pre_burn, plain = cut_pre_legs(rolls_k, act["state"], pres.get(k))
            if consol_on:  # G4R6 R21: the core consolidates where the table's consolidation landed
                plain = consol_marker(plain, action, lines[pos + 1]["state"] if pos + 1 < len(lines) else None)
            tray = nml_core.Tray(seed + 1 if mode == "misseed" else seed)
            if burn[i0] + pre_burn:
                tray.roll(burn[i0] + pre_burn)
            dang_off = cut_dangerous(rolls_k, rolls_cut)
            if dang_off:  # G4-H8: the cut took the table's dangerous test; the core rolls none for this one act
                # F-DANG-TAIL: its wounds still lose the melee (`--red-dang-tail` hands the core nothing: the old numbers)
                tail = None if red_dang_tail else dang_replay(act["state"]["units"], action["unit"], header["knobs"])
                core.set_header(dict(header, knobs=dict(header["knobs"], dangerous=False, dangerous_replay=tail)))
            try:
                nxt, report = core.resolve_with_tray(
                    core.state_of(plain), action, nml_core.Rng(0), tray)
            except Exception as exc:  # a declined activation is not a dice verdict
                tally["declined"] += 1
                if len(firsts) < 3:
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            finally:
                if dang_off:
                    core.set_header(header)
            for name in report["unported"]:
                unported[name] = unported.get(name, 0) + 1
            got = [(r["kind"], r["count"], r["target"], r["faces"], "AI (%s)" % r["owner"])
                   for r in report["rolls"]]
            # EVERY roll the table drew under this ordinal, never a prefix:
            # truncating would hide "the table drew more than the port did".
            # `roll_kind` goes through `combat_kind()` (NML-1104) — the
            # module docstring's THE MORALE CHECK section says why.
            want = [(combat_kind(r["roll_kind"]), r["count"], r["target"], r["faces"], r["owner"], r.get("leg", "main"))
                    for r in rolls_cut]
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
            gm, wm = trailing_morale(legged(got, want)), trailing_morale(want)
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
            # R3-H2/R3-H3: a lone joined hero's save and a rule-generated extra die may carry the host's label.
            lone, hosts = lone_hero_names(plain, head["profiles"]), extra_die_hosts(report["rolls"], plain, head["profiles"])
            for i, (g, w) in enumerate(zip(got, want)):
                field = parted_field(g, w) or (
                    "owner" if not signer_ok(report["rolls"][i]["owner"], w[4], lone, hosts.get(i, "")) else None)
                if field:
                    # WHICH field parted first is the whole diagnosis: `count` is
                    # the attack-scaling class (the table scales melee by the
                    # models within 2", this port by `alive`), `target` the
                    # to-hit class, `kind` a draw-ORDER class.
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
    if charge_landing:
        label += " + D5-1 charge_landing"
    if movement:
        label += " + D5-2 movement=table" + (" [RED: rigid]" if rigid_red else "")
    if no_dangerous:
        label += " [RED: --red-no-dangerous, the p.12 test OFF]"
    if no_hero_fold:
        label += " [RED: --red-no-hero-fold, the engage test on the hosts alone]"
    label += " [RED: --red-dang-tail]" if red_dang_tail else ""
    label += " [RED: --red-consol-land]" if red_consol_land else ""
    if red_round_only:
        label += " [RED: --red-round-only, every base its circumscribing circle]"
    silent_table = tally["both_silent"] + tally["table_silent"]
    print()
    print("%s over %d games, %d charge acts, %s (%.1fs)"
          % (label, len(games), tally["acts"], vintage_report_line(vintage_seen),
             time.perf_counter() - t0))
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
    print("  BOTH-SILENT: %d/%d acts where neither side drew a die (counted as equal)"
          % (tally["both_silent"], tally["acts"]))
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
    if movement:
        print("  walls : %s" % (walls_seen["source"] or "none"))
        for w in warns[:3]:
            print("  WARN  : %s" % w)
        if warns:
            print("  WARN  : %d of %d games carry no wall segments at all"
                  % (len(warns), len(games)))
    if walls_check:
        print("  walls : %d endpoint pairs over %d games, worst |port inch - recorded inch| "
              "= %.6f\" (bar 0.05)"
              % (walls_seen["segments"], walls_seen["games"], walls_seen["worst"]))

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
    # Both sides drawing NOTHING is agreement, not a missing verdict.
    ok = (tally["acts"] > 0
          and tally["full_equal"] + tally["both_silent"] == tally["acts"])
    # AI-G4 F-PRINT: the printed number leaves the both-silent acts out, like the pass formula does.
    short = tally["acts"] - tally["full_equal"] - tally["both_silent"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short of full equality, exit 0 by request"
              % (short, tally["acts"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d charge acts are not FULL-equal (see the buckets above)"
                    % (short, tally["acts"])))
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
    ap.add_argument("--movement", action="store_true",
                    help="NML-1073 M5 D5-2: replay with the header knob movement=table — the "
                         "CHARGE moves per model through the M4 movement port on the table's "
                         "arc budget, and D5-1's engage gate then subtracts the arc the route "
                         "actually walked instead of the straight line's length")
    ap.add_argument("--red-move-rigid", action="store_true",
                    help="RED PROOF for --movement: everything else identical (the walls are "
                         "still read and handed over) but the header knob stays OFF, so the "
                         "charge translates rigidly again and the silent buckets fall back")
    ap.add_argument("--walls-check", action="store_true",
                    help="instrument check for the two wall frames: hold the port's converted "
                         "INCH segments against the ones moves_calls.jsonl recorded")
    ap.add_argument("--charge-landing", action="store_true",
                    help="NML-1073 M5 D5-1: replay with the header knob charge_landing on — "
                         "the charge aims and lands the way the table does and fights only "
                         "when the table's SECOND engage gate (the snap must fit the move "
                         "budget the route left over) also passes. OFF is the D1-B5b bar; the "
                         "D5-1 red is the same corpus WITHOUT the flag, where the 'table drew "
                         "nothing' class climbs back")
    ap.add_argument("--red-no-dangerous", action="store_true",
                    help="RED PROOF for D1-B8: switch the p.12 DANGEROUS-terrain test back OFF "
                         "(header knob dangerous=false), everything else unchanged. Every "
                         "bucket must fall back to the pre-D1-B8 baseline")
    ap.add_argument("--red-no-hero-fold", action="store_true",
                    help="RED PROOF for D5-4: measure the engage test over the two HOSTS again "
                         "(header knob engage_fold=false) while hero_attach stays on, "
                         "everything else unchanged. Every bucket must fall back to the "
                         "pre-D5-4 baseline. Wins over --engage-fold.")
    ap.add_argument("--red-round-only", action="store_true",
                    help="RED PROOF for D5-2b: drop the header's base_shape/base_w_mm/"
                         "base_d_mm so every base is its circumscribing circle again, "
                         "everything else unchanged. Every bucket must fall back to the "
                         "pre-D5-2b baseline — and a corpus recorded before #447 carries "
                         "none of the three, so the flag is a no-op there")
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: the header knob engage_fold (PR #446). 'auto' (default) "
                         "reads the corpus's OWN vintage (vintage_knobs) — absent means the "
                         "corpus predates the knob, so OFF; 'on'/'off' force it. "
                         "--red-no-hero-fold overrides this to OFF regardless")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: conditional AP (PR #448/NML-1103), i.e. LEGACY_NO_COND_AP "
                         "inverted. 'auto' (default) reads the corpus's OWN vintage; 'on'/'off' "
                         "force it")
    ap.add_argument("--red-dang-tail", action="store_true",
                    help="G4R5 R1 RED PROOF for F-DANG-TAIL: no `dangerous_replay` knob for a cut Dangerous test (the cut test's wounds are missing from the melee tally again and the acts part)")
    ap.add_argument("--red-consol-land", action="store_true",
                    help="G4R6 R21 RED PROOF for F-CONSOL-LAND: no neutral marker at the table's final charger centroid (the core consolidates where it chooses: the old numbers)")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo,
               "misseed" if a.red_misseed else a.mode, a.limit, a.report_only,
               a.charge_landing, a.movement or a.red_move_rigid, a.walls_check,
               a.red_move_rigid, a.red_no_dangerous, a.red_no_hero_fold,
               a.engage_fold, a.cond_ap, a.red_round_only, a.red_dang_tail, a.red_consol_land)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
