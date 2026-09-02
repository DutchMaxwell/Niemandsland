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
    bad = gr.menu_diff(tr["cands"], row["cands"]["list"])
    if bad:                                      # #564's tripwire, verbatim
        raise gr.Diverged("seq %d (round %d, side %d): %s" % (row["seq"], row["round"], row["side"], bad))
    A["acts"].append({"row": row, "menu": tr["cands"], "keys": state.keys(), "exp": pick["expectation"],
                      "hand": [(s["idx"], s["score"]) for s in tr["scored"]], "waits": pick["waits"],
                      "rs": {r["idx"]: r["rs"] for r in tr["rs"]}, "own": tr["scored"][tr["best_idx"]]["idx"],
                      "up": tr["scored"][tr["runner_idx"]]["idx"]})
    A["i"], act = A["i"] + 1, row["cands"]["list"][row["cands"]["best"]]
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
    kn = rec["prescreen"]["knobs"]
    if not kn.get("record_cands") or kn.get("record_aux"):
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
                                     movement=kn["movement"], **gr.KNOBS)
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
        out += ["", "### R%d A%d (seq %d) — p%d activates **%s** (Q%s+ D%s+, %d models; %s)"
                % (rnd, n, r["seq"], r["side"], nm.get(key, key), inf.get(key, "?" * 3)[0],
                   inf.get(key, "?" * 3)[1], u["alive"], inf.get(key, ("", "", "-"))[2]),
                "- menu %d candidates; top-3 by hand prior: %s" % (len(a["menu"]), ", ".join(
                    "%s %.4f" % (nr.cand_text(a["menu"][i], nm), s) for i, s in a["hand"][:3])),
                "- chose #%d **%s**%s — hand %.4f, rs %s; runner-up #%d %s; value %.4f -> %.4f, %d unit(s)"
                " still to act%s" % (best, nr.cand_text(a["menu"][best], nm),
                    " [intent %s]" % r["intent"] if r["intent"] else "", dict(a["hand"])[best],
                    "%.4f" % a["rs"][best] if best in a["rs"] else "NOT expanded", a["up"],
                    nr.cand_text(a["menu"][a["up"]], nm), a["exp"]["before"], a["exp"]["after"], a["waits"],
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
            out.append("- dice: %d hits, %d blocks, %d unsaved — %s" % (nr.hits(rl, "attack"),
                       nr.hits(rl, "defense"), max(0, nr.hits(rl, "attack") - nr.hits(rl, "defense")),
                       "; ".join("%s %dd6>=%d %s (%s)" % (x["kind"], x["count"], x["target"], x["faces"],
                                                          x["owner"]) for x in rl)))
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
    return out


def is_reserve(u):
    # Ambush/Infiltrate/Rapid Ambush, on the unit's own rules or an item's grant.
    ns = [r.get("name", "") for r in u.get("rules", [])]
    ns += [c.get("name", "") for it in u.get("items", []) for c in it.get("content", [])]
    return any(k in n.lower() for n in ns for k in ("ambush", "infiltrate"))


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
               objective_gifts=0, reserve_absent={"p1": 0, "p2": 0},
               owners_by_round=[g["owners"] for g in rec["rounds_log"]])
    acted = {a["row"]["unit"] for a in acts}
    for a in acts:
        r, key, bu, au = a["row"], a["row"]["unit"], a["before"]["units"], a["after"]["units"]
        kind, rolls, chosen = int(r["kind"]), a["rep"]["rolls"], a["menu"][r["cands"]["best"]]
        mv = moved(a, key); far = max([x[2] for x in mv] + [0.0])
        row["hold_nothing"] += kind == 0 and not rolls
        row["acts_with_dice"] += bool(rolls)
        skeys, los, seen = sorted(bu), a["before"].get("los_pairs"), set()
        for c in a["menu"]:
            if c["unit"] == key and c.get("shoot") and c["shoot"] not in seen:
                seen.add(c["shoot"])
                row["shoot_offers_total"] += 1
                row["shoot_offers_unexecutable"] += bool(
                    los is not None and los[skeys.index(key)][skeys.index(c["shoot"])] == "0")
        if (tgt := chosen.get("shoot")) and rolls:
            row["shots_executed"] += 1
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
            row["charges_reached_contact"] += bool(rolls)
        row["dangerous_plain"] += kind in (1, 2) and au.get(key, {}).get("alive", 0) < bu[key]["alive"]
    for i, pb in enumerate(rec["mission"]["objectives_layout"]["placed_by"]):
        owner = row["owners_by_round"][-1][i]
        row["objective_gifts"] += pb in (1, 2) and owner in (1, 2) and owner != pb
    for s in ("p1", "p2"):
        for i, u in enumerate(lists[s]["units"]):
            if is_reserve(u) and "%s_%d_%s" % (s, i, u.get("id", i)) not in acted:
                row["reserve_absent"][s] += u.get("cost", 0)
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
