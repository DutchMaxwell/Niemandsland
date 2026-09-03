#!/usr/bin/env python3
"""ANALYSIS MODE — a recorded Gen-0 teacher game read back as prose, boards and a
dice trail, so a human can trace every AI decision and spot the mistakes.

The record keeps the menu and the chosen act but no state, no scores, no dice. This
gets them back the way PR #564's proof does — replay from `(seed, dice_seed, armies,
knobs)` with the recorded acts FORCED, on the RECORDED search knobs, so `trace.scored`
(hand prior over the whole menu), `trace.rs` (rollout value per expanded candidate) and
the search's own argmax are the teacher's numbers. `_pick` taps every menu, `Tapped` the
state either side of the apply and the dice report; #564's field-exact menu comparison is
the FIDELITY TRIPWIRE, so a replay that leaves the recording RAISES instead of narrating a
game that was never played. Corpus files are READ-ONLY."""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen0_replay_one as gr  # noqa: E402
import narrator_render as nr  # noqa: E402
from gen0_replay_one import nml_core, selfplay  # noqa: E402

A = {"rows": [], "i": 0, "acts": []}


def _pick(core, state, player, net_player=0, eps=0.0, explore_seed=0, cands=False):
    if not state.pool(player, bool(core.knobs().get("hero_attach", True))):
        return {}
    pick = core.plan_with_rollout(state, player, selfplay.TRAINER_STATICS, eps=0.0,
                                  explore_seed=explore_seed, cands=True)
    if not pick.get("used"):
        return {}
    row, tr = A["rows"][A["i"]], pick["trace"]
    if "cands" in row:                           # #564's tripwire, verbatim —
        bad = gr.menu_diff(tr["cands"], row["cands"]["list"])  # Gen-0 corpus only:
        if bad:                                  # arena rows record no menu.
            raise gr.Diverged("seq %d (round %d, side %d): %s" % (row["seq"], row["round"], row["side"], bad))
    A["acts"].append({"row": row, "menu": tr["cands"], "keys": state.keys(), "exp": pick["expectation"],
                      "hand": [(s["idx"], s["score"]) for s in tr["scored"]], "waits": pick["waits"],
                      "rs": {r["idx"]: r["rs"] for r in tr["rs"]}, "own": tr["scored"][tr["best_idx"]]["idx"],
                      "up": tr["scored"][tr["runner_idx"]]["idx"] if tr["runner_idx"] >= 0 else None})
    A["i"], act = A["i"] + 1, (row["cands"]["list"][row["cands"]["best"]] if "cands" in row
                               else row["action"])
    pick["action"], pick["unit_key"] = act, act["unit"]
    return pick


class Tapped:
    # The core with `resolve_with_tray` tapped: the state either side of the played
    # activation and its dice report — neither read changes a die.
    def __init__(self, core):
        self.core = core

    def __getattr__(self, name):
        return getattr(self.core, name)

    def resolve_with_tray(self, state, action, rng, tray):
        before = state.plain()
        nxt, rep = self.core.resolve_with_tray(state, action, rng, tray)
        A["acts"][-1].update(before=before, after=nxt.plain(), rep=rep)
        return nxt, rep


def replay(path, lists, repo, bank):
    """One recorded game replayed act for act; raises unless it reproduces."""
    rec = json.loads(Path(path).read_text(encoding="utf-8"))
    # ARENA records (the A/B harness) carry the same header at the TOP level —
    # knobs, seed, dice_seed; the layout seed stays the armed() +500000 shim —
    # and no prescreen block, so their rows record the CHOSEN act but no menu
    # (record_cands was never on): the fidelity check downgrades to the forced
    # acts plus the outcome. seed/dice_seed were always top-level reads.
    kn = rec.get("prescreen", {}).get("knobs") or rec["knobs"]
    if rec.get("prescreen") and (not kn.get("record_cands") or kn.get("record_aux")):
        raise SystemExit("REFUSED %s: not a Gen-0 teacher recording" % path)
    A.update(rows=rec["planner_positions"], i=0, acts=[])
    gr.G["dice"] = rec["dice_seed"]
    load = nml_core.load
    nml_core.load = lambda p: Tapped(load(p))
    try:
        a1, a2 = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
        with gr.armed(_pick):
            out = selfplay.play_game(rec["seed"], a1, a2, repo, bank, None, top_k=kn["top_k"],
                                     horizon=kn["horizon"], dice_seed=rec["dice_seed"],
                                     movement=kn["movement"],
                                     # DEFECT_LEDGER #12: the RECORD's own key, absent = OFF.
                                     dangerous_end_morale=bool(kn.get("dangerous_end_morale", False)),
                                     # The corpus predates every knob `gr.KNOBS` pins, so those
                                     # pins stand where the recording is silent; an ARENA record
                                     # stamps EVERY one of them itself — not just the six W5a
                                     # menu/sight/ambush keys this once read back, but also
                                     # charge_gate/hero_attach/charge_landing/sighting/cond_ap/
                                     # objectives, each its own rung with its own legacy value
                                     # (DEFECT_LEDGER: a 6-key allowlist silently kept gen0's
                                     # pins under a shipped-default arena record) — and THAT
                                     # played.
                                     **{**gr.KNOBS, **{k: kn[k] for k in gr.KNOBS if k in kn}})
    finally:
        nml_core.load = load
    # Three ways for the replay to be a different game, all fatal: a short run, a
    # menu that parted (raised above), or an outcome the recording never had.
    if A["i"] != len(A["rows"]) or (out["winner"], out["vp"]) != (rec["winner"], rec["vp"]):
        raise gr.Diverged("%d of %d positions, outcome %s %s, recorded %s %s"
                          % (A["i"], len(A["rows"]), out["winner"], out["vp"], rec["winner"], rec["vp"]))
    return rec, A["acts"]


def moved(act, key):
    # Per-model (from, to, inches) for the acting unit, in table inches. A unit
    # that LOSES models inside its own activation — the end-of-move dangerous
    # -terrain test, or a charge's strike-back — comes back with a shorter and
    # RE-FORMED array: pairing those by index invents moves of 17" on a 12"
    # band, so the pairing is refused and the unit CENTROID reported instead.
    a, b = (act[s]["units"][key]["positions"] for s in ("before", "after"))
    xz = lambda p: (p[0] / nr.M_IN, p[2] / nr.M_IN)
    leg = lambda p, q: (xz(p), xz(q), ((p[0] - q[0]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5 / nr.M_IN)
    mid = lambda v: [sum(p[i] for p in v) / len(v) for i in range(3)]
    if not a or not b:
        return []
    return [leg(p, q) for p, q in zip(a, b)] if len(a) == len(b) else [leg(mid(a), mid(b))]


def morale_rolls(rl, bu, au, tgt=None, nm=None):
    # D1-B5b, verified on the corpus by replay: morale tests ARE rolled, but the
    # die is STAMPED `kind: "attack", count: 1` like every tray roll (dice.rs
    # :1108), so it prints as a phantom attack. The state delta names the site:
    # the owner's `shaken` flag flipping False->True is a failed test (sim.rs
    # :1826), and with no attack target named a count-1 attack die AFTER
    # casualties is the loser's/target's test — a real attack always names one.
    # Returns {index: "Shaken"/"holds"}; the die leaves the hits arithmetic.
    names = {v: k for k, v in (nm or {}).items()}
    dead = any(k in au and au[k]["alive"] < bu[k]["alive"] for k in bu)
    out = {}
    for i, x in enumerate(rl):
        if x.get("kind") != "attack" or x.get("count") != 1:
            continue
        k = x.get("owner")
        k = k if k in au else names.get(k)
        flip = k is not None and k in bu and au[k].get("shaken") and not bu[k].get("shaken")
        if not flip and not (tgt is None and dead and i):
            continue
        out[i] = "Shaken" if flip or nr.hits([x], "attack") == 0 else "holds"
    return out


def dice_line(rl, bu, au, key=None, nm=None, crossed=False, inferred=False, tgt=None):
    # BRIEF_NARRFIX I-2: `hits(attack) - hits(defense)` ignores Blast(X)/Deadly(X)
    # — one hit expands into a whole save batch, so the subtraction printed FEWER
    # unsaved than the resolve actually applied (53 activations in 18 of the 20
    # corpus games). The report carries no per-weapon unsaved, so the number is
    # what the state delta applied — models lost — and where the arithmetic would
    # exceed it the volley expanded: say so, never a wrong number.
    # BRIEF_NARRFIX I-3: the end-of-move dangerous-terrain test is STAMPED an
    # "attack" roll (sim.rs:2960-2978: target 6, the moving unit, a 1 wounds) and
    # printed as a phantom attack with no target; a first-roll stamp match IS the
    # test, attack-kind leftovers in a no-target activation over a dangerous
    # crossing are inferred, K is the 1s (`dangerous_wounds`, sim.rs:214).
    terr = set()
    morale = morale_rolls(rl, bu, au, tgt, nm)

    def label(i, x):
        own = key is not None and x["owner"] in (key, (nm or {}).get(key, key))
        if crossed and i == 0 and own and x["kind"] == "attack" and x["target"] == 6:
            terr.add(i)
            return "dangerous terrain test %dd6: %s -> %d models lost" % (
                x["count"], x["faces"], sum(f == 1 for f in x["faces"]))
        if i in morale:
            terr.add(i)
            return "morale test %dd6>=%d %s -> %s" % (x["count"], x["target"], x["faces"],
                                                      morale[i])
        if x["kind"] == "attack" and inferred:
            terr.add(i)
            return "terrain test (inferred) %dd6: %s -> %d models lost" % (
                x["count"], x["faces"], sum(f == 1 for f in x["faces"]))
        return "%s %dd6>=%d %s (%s)" % (x["kind"], x["count"], x["target"],
                                        x["faces"], x["owner"])

    segs = [label(i, x) for i, x in enumerate(rl)]
    atk = [x for i, x in enumerate(rl) if i not in terr]
    dead = sum(u["alive"] - au[k]["alive"] for k, u in bu.items() if k in au)
    naive = max(0, nr.hits(atk, "attack") - nr.hits(rl, "defense"))
    unsaved = dead if dead >= naive else "n/a (Blast/Deadly)"
    return "- dice: %d hits, %d blocks, %s unsaved — %s" % (nr.hits(atk, "attack"),
                                                            nr.hits(rl, "defense"), unsaved,
                                                            "; ".join(segs))


def narrate(rec, acts, nm, lists):
    ms, ob, kb, inf = rec["mission"], rec["mission"]["objectives_layout"], rec["knobs"], nr.unit_info(lists)
    out = ["# %s — analysis mode" % rec["stem"], "",
           "seed **%d** | dice seed **%d** | %s/%s, %d rounds, %s | scoring %s | search top_k %d horizon"
           " %d, movement %s | objectives at %s placed by %s | final owners %s, VP %s, **winner %s**"
           % (rec["seed"], rec["dice_seed"], ms["family"], ms["name"], ms["rounds"], ms["deployment"],
              rec["scoring"], kb["top_k"], kb["horizon"], kb["movement"], ob["positions"], ob["placed_by"],
              rec["rounds_log"][-1]["owners"], rec["vp"], rec["winner"]), "",
           "terrain (72x48in, centre origin, geometry in the round SVGs): %d pieces — %s. `hand` is the"
           " 1-ply prior that RANKS the menu, `rs` the rollout value of an EXPANDED candidate: the"
           " teacher's own numbers, recovered by replay because the recorder kept neither."
           % (len(rec["terrain"]), nr.terrain_summary(rec["terrain"]))]
    for s in ("p1", "p2"):
        out += ["", "## Army %s — %s (%s pts, %s models)" % (s, lists[s].get("name", "?"),
                lists[s].get("listPoints"), lists[s].get("modelCount"))] + nr.army_table(lists[s])
    rnd = 0
    for n, a in enumerate(acts, 1):
        r, key, bu = a["row"], a["row"]["unit"], a["before"]["units"]
        if r["round"] != rnd:
            rnd = r["round"]
            out += ["", "## Round %d" % rnd]
        u, best, mv = bu[key], r["cands"]["best"], moved(a, key)
        lost = len(mv) != len(u["positions"])
        band = u["bands"]["rush" if int(r["kind"]) > 1 else "advance"] * min(1, int(r["kind"]))
        up = "" if a["up"] is None else "; runner-up #%d %s" % (
            a["up"], nr.cand_text(a["menu"][a["up"]], nm))
        out += ["", "### R%d A%d (seq %d) — p%d activates **%s** (Q%s+ D%s+, %d models; %s)"
                % (rnd, n, r["seq"], r["side"], nm.get(key, key), inf.get(key, "?" * 3)[0],
                   inf.get(key, "?" * 3)[1], u["alive"], inf.get(key, ("", "", "-"))[2]),
                "- menu %d candidates; top-3 by hand prior: %s" % (len(a["menu"]), ", ".join(
                    "%s %.4f" % (nr.cand_text(a["menu"][i], nm), s) for i, s in a["hand"][:3])),
                "- chose #%d **%s**%s — hand %.4f, rs %s%s; value %.4f -> %.4f, %d unit(s)"
                " still to act%s" % (best, nr.cand_text(a["menu"][best], nm),
                    " [intent %s]" % r["intent"] if r["intent"] else "", dict(a["hand"])[best],
                    "%.4f" % a["rs"][best] if best in a["rs"] else "NOT expanded", up,
                    a["exp"]["before"], a["exp"]["after"], a["waits"],
                    "" if a["own"] == best else " — **replay argmax #%d != recorded pick**" % a["own"]),
                '- move (%s, band %.1f", farthest model %.2f"): %s' % (nr.KIND[int(r["kind"])], band,
                    max([x[2] for x in mv] or [0.0]), "; ".join('m%d (%.1f,%.1f)->(%.1f,%.1f) %.2f"'
                    % (i, p[0], p[1], t[0], t[1], s) for i, (p, t, s) in enumerate(mv, 1) if s > 0.01)
                    or "nobody moved") + (" — UNIT CENTROID: %d of %d models were removed inside this"
                    " activation (dangerous terrain or a strike-back), so per-model pairing is refused"
                    % (len(u["positions"]) - len(a["after"]["units"][key]["positions"]),
                       len(u["positions"])) if lost else "")]
        rl = a["rep"]["rolls"]
        if rl:
            crossed = any(nr.crosses_forest(p, q, rec["terrain"], ttype=4) for p, q, d in mv if d > 0.01)
            chosen = a["menu"][best]
            out.append(dice_line(rl, bu, a["after"]["units"], key, nm, crossed,
                                 crossed and not (chosen.get("shoot") or chosen.get("charge")),
                                 chosen.get("shoot") or chosen.get("charge")))
        for tag, ex in (("casualties", ["%s %d->%d models, wounds %d->%d" % (nm.get(k, k), bu[k]["alive"],
                        v["alive"], sum(bu[k]["wounds"]), sum(v["wounds"])) for k, v in
                        a["after"]["units"].items() if (v["alive"], sum(v["wounds"]))
                        != (bu[k]["alive"], sum(bu[k]["wounds"]))]),
                        ("rules log", a["rep"]["log"]), ("UNPORTED", a["rep"]["unported"])):
            if ex:
                out.append("- %s: %s" % (tag, "; ".join(ex)))
        if n == len(acts) or acts[n]["row"]["round"] != rnd:
            g = rec["rounds_log"][rnd - 1]
            out.append("- **round %d ends: objectives %s, VP p1 %d – p2 %d**"
                       % (rnd, g["owners"], g["vp"][0], g["vp"][1]))
    st = stats_row(rec, acts, lists)
    out += ["", "## Stats", "- advance_shoot_acts %d, morale_tests_rolled %d, "
            "limited_weapon_shots %d" % (st["advance_shoot_acts"], st["morale_tests_rolled"],
                                         st["limited_weapon_shots"])]
    return out


def is_reserve(u):
    # Ambush/Infiltrate/Rapid Ambush, on the unit's own rules or an item's
    # grant. FALLBACK ONLY: states whose plain form carries the per-unit
    # reserve fields (io.rs plain_of) are read by stats_row directly.
    ns = [r.get("name", "") for r in u.get("rules", [])]
    ns += [c.get("name", "") for it in u.get("items", []) for c in it.get("content", [])]
    return any(k in n.lower() for n in ns for k in ("ambush", "infiltrate"))


def _has_limited(key, lists):
    # Ledger row 30 (PR #615): "Limited" (usable once per game) lives only on
    # the army list — the record's dice report and state.plain() (io.rs
    # `plain_of`) never carry `limited_used`, so the acting unit's own sheet is
    # the sole surviving trace. Key shape is `list_to_profile`'s own
    # "p<side>_<index>_<id>" (unit_info's docstring).
    side, _, rest = key.partition("_")
    idx = rest.partition("_")[0]
    us = lists.get(side, {}).get("units", [])
    if not idx.isdigit() or int(idx) >= len(us):
        return False
    return any(x.get("name") == "Limited" for w in us[int(idx)].get("weapons", [])
               for x in w.get("specialRules", []))


def stats_row(rec, acts, lists):
    # One JSON-able dict of ANALYSIS_first_pass.md's cross-cutting counts for ONE
    # game, no prose or SVG. Q1/Q2 (INVESTIGATION_teacher_defects.md): an
    # unexecutable shoot offer is a candidate with a shoot target whose
    # `los_pairs` entry is 0; a charge beyond band is a declared CHARGE whose
    # gap (`geom::edge_gap_in`) exceeds the actor's own rush band.
    row = dict(game=rec["stem"], points=lists["p1"].get("listPoints"), p1=lists["p1"].get("name"),
               p2=lists["p2"].get("name"), winner=rec["winner"], vp=rec["vp"], activations=len(acts),
               charges_declared=0, charges_beyond_band=0, charges_reached_contact=0, hold_nothing=0,
               acts_with_dice=0, shoot_offers_total=0, shoot_offers_unexecutable=0, shots_executed=0,
               hero_snipes=0, offboard_destinations=0, full_band_forest=0, dangerous_plain=0,
                objective_gifts=0, morale_tests_rolled=0, advance_shoot_acts=0,
                limited_weapon_shots=0, reserve_absent={"p1": 0, "p2": 0},
                reserve_arrived_round2={"p1": 0, "p2": 0},
               owners_by_round=[g["owners"] for g in rec["rounds_log"]])
    nm = dict(zip(acts[0].get("keys", []), rec.get("roster", []))) if acts else {}
    acted = {a["row"]["unit"] for a in acts}
    for a in acts:
        r, key, bu, au = a["row"], a["row"]["unit"], a["before"]["units"], a["after"]["units"]
        kind, rolls = int(r["kind"]), a["rep"]["rolls"]
        chosen = a["menu"][r["cands"]["best"]] if "cands" in r else r["action"]
        mv = moved(a, key); far = max([x[2] for x in mv] + [0.0])
        row["hold_nothing"] += kind == 0 and not rolls
        row["acts_with_dice"] += bool(rolls)
        row["morale_tests_rolled"] += len(morale_rolls(
            rolls, bu, au, chosen.get("shoot") or chosen.get("charge"), nm))
        skeys, los, seen = sorted(bu), a["before"].get("los_pairs"), set()
        for c in a["menu"]:
            if c["unit"] == key and c.get("shoot") and c["shoot"] not in seen:
                seen.add(c["shoot"])
                row["shoot_offers_total"] += 1
                row["shoot_offers_unexecutable"] += bool(
                    los is not None and los[skeys.index(key)][skeys.index(c["shoot"])] == "0")
        if (tgt := chosen.get("shoot")) and rolls:
            row["shots_executed"] += 1
            # Ledger row 23 (PR #620 menu_wide): the ADVANCE+shoot candidate the
            # engine used to decline outright (sim.rs MovedShootLos) now fires.
            row["advance_shoot_acts"] += kind == 1
            row["limited_weapon_shots"] += _has_limited(key, lists)
            if bu.get(tgt, {}).get("alive", 0) > 0 and au.get(tgt, {}).get("alive", 0) == 0:
                h = bu[tgt].get("attached_to")
                row["hero_snipes"] += bool(h and bu[h]["alive"] == au[h]["alive"])
        if d := chosen.get("dest"):
            row["offboard_destinations"] += abs(d[0] / nr.M_IN) > 36 or abs(d[2] / nr.M_IN) > 24
        if kind in (1, 2, 3) and mv and far >= bu[key]["bands"]["rush" if kind > 1 else "advance"] - 0.05:
            row["full_band_forest"] += any(nr.crosses_forest(p, q, rec["terrain"]) for p, q, _ in mv)
        if kind == 3:
            row["charges_declared"] += 1
            row["charges_beyond_band"] += nr.edge_gap_in(
                bu[key]["positions"], bu[key]["radii"], bu[chosen["charge"]]["positions"],
                bu[chosen["charge"]]["radii"]) > bu[key]["bands"]["rush"]
            # I-1 (BRIEF_NARRFIX): the charge's own dangerous-terrain test also
            # draws attack dice (sim.rs:2960-2978 records it `attack Nd6>=6`), so
            # `bool(rolls)` credited 6 of 13 charges that never reached melee.
            # Contact is an opposed exchange — a defense-class roll — or a
            # casualty on the charge target.
            row["charges_reached_contact"] += (any(x["kind"] == "defense" for x in rolls)
                or bu[chosen["charge"]]["alive"] > au.get(chosen["charge"], {}).get("alive", 0))
        row["dangerous_plain"] += kind in (1, 2) and au.get(key, {}).get("alive", 0) < bu[key]["alive"]
    # `objectives_layout` (D8a) is present only under "rulebook" — an arena
    # record played with the shipped `objectives="constant"` default names no
    # placer at all, so nobody can have been "gifted" an objective by it.
    for i, pb in enumerate(rec["mission"].get("objectives_layout", {}).get("placed_by", [])):
        owner = row["owners_by_round"][-1][i]
        row["objective_gifts"] += pb in (1, 2) and owner in (1, 2) and owner != pb
    # "Was in reserve" is `dormant` at round 1 and "never arrived" is
    # `ambush_arrived_round == -1` at game end (io.rs plain_of, selfplay.py:957);
    # the name heuristic — the fallback for states without the fields — also
    # counted joined heroes whose ITEM granted Ambush, never reserved at all.
    first, last = acts[0]["before"]["units"], acts[-1]["after"]["units"]
    if not any("ambush_arrived_round" in u for u in first.values()):
        row["reserve_metric"] = "heuristic"
        for s in ("p1", "p2"):
            for i, u in enumerate(lists[s]["units"]):
                if is_reserve(u) and "%s_%d_%s" % (s, i, u.get("id", i)) not in acted:
                    row["reserve_absent"][s] += u.get("cost", 0)
    else:
        row["reserve_metric"] = "fields"
        for s in ("p1", "p2"):
            for i, u in enumerate(lists[s]["units"]):
                k = "%s_%d_%s" % (s, i, u.get("id", i))
                if not first.get(k, {}).get("dormant"):
                    continue
                arr = last.get(k, {}).get("ambush_arrived_round", -1)
                if arr == -1:
                    row["reserve_absent"][s] += u.get("cost", 0)
                elif arr == 2:
                    row["reserve_arrived_round2"][s] += u.get("cost", 0)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="*", help="corpus gen0_s<seed>_d<dice>.json files")
    ap.add_argument("--corpus", help="scan this dir for gen0_s*_d*.json instead of GAMES")
    ap.add_argument("--sample-every", type=int, default=1, help="stride over the sorted files")
    ap.add_argument("--out", help="output dir; one subdir per game (narration mode)")
    ap.add_argument("--stats", help="write one JSON line per game here; skips narration/SVG")
    ap.add_argument("--lists", default=gr.LISTS, help="local mirror of the fleet's ai_lists")
    a = ap.parse_args()
    games = ([str(p) for p in sorted(Path(a.corpus).glob("gen0_s*_d*.json"))] if a.corpus
             else a.games)[::a.sample_every]
    out = open(a.stats, "w", encoding="utf-8") if a.stats else None
    for g in games:
        try:
            rec, acts = replay(g, a.lists, gr.REPO, gr.BANK)
        except gr.Diverged as exc:
            if not out: raise
            print("[SKIP] %s: %s" % (g, exc), file=sys.stderr); continue
        rec["stem"] = Path(g).stem
        lists = {s: json.loads((Path(a.lists) / Path(rec["armies"][s]).name).read_text("utf-8"))
                 for s in ("p1", "p2")}
        if out:
            out.write(json.dumps(stats_row(rec, acts, lists)) + "\n"); continue
        nm = dict(zip(acts[0]["keys"], rec["roster"]))
        d = Path(a.out) / rec["stem"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "narration.md").write_text("\n".join(narrate(rec, acts, nm, lists)) + "\n", "utf-8")
        (d / "dice.md").write_text("\n".join(nr.dice_md(rec, acts, nm)) + "\n", "utf-8")
        nr.boards(rec, acts, nm, moved, d)
        print("[NARRATED] %s -> %s (%d activations, %d rolls)"
              % (rec["stem"], d, len(acts), sum(len(x["rep"]["rolls"]) for x in acts)))
    if out: out.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
