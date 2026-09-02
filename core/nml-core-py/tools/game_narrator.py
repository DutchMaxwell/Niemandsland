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
    nml_core.objective_layout = lambda t, s, m, z: gr._layout(t, s + 500000, m, z)
    nml_core.Tray = lambda _s: gr._tray(gr.G["dice"])
    selfplay._pick_for, load = _pick, nml_core.load
    nml_core.load = lambda p: Tapped(load(p))
    try:
        a1, a2 = [str(Path(lists) / Path(rec["armies"][s]).name) for s in ("p1", "p2")]
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
    # Per-model (from, to, inches) for the acting unit, in table inches.
    return [((p[0] / nr.M_IN, p[2] / nr.M_IN), (q[0] / nr.M_IN, q[2] / nr.M_IN),
             ((p[0] - q[0]) ** 2 + (p[2] - q[2]) ** 2) ** 0.5 / nr.M_IN)
            for p, q in zip(act["before"]["units"][key]["positions"], act["after"]["units"][key]["positions"])]


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
                    or "nobody moved")]
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+", help="corpus gen0_s<seed>_d<dice>.json files")
    ap.add_argument("--out", required=True, help="output dir; one subdir per game")
    ap.add_argument("--lists", default=gr.LISTS, help="local mirror of the fleet's ai_lists")
    a = ap.parse_args()
    for g in a.games:
        rec, acts = replay(g, a.lists, gr.REPO, gr.BANK)
        rec["stem"], nm = Path(g).stem, dict(zip(acts[0]["keys"], rec["roster"]))
        lists = {s: json.loads((Path(a.lists) / Path(rec["armies"][s]).name).read_text("utf-8"))
                 for s in ("p1", "p2")}
        d = Path(a.out) / rec["stem"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "narration.md").write_text("\n".join(narrate(rec, acts, nm, lists)) + "\n", "utf-8")
        (d / "dice.md").write_text("\n".join(nr.dice_md(rec, acts, nm)) + "\n", "utf-8")
        nr.boards(rec, acts, nm, moved, d)
        print("[NARRATED] %s -> %s (%d activations, %d rolls)"
              % (rec["stem"], d, len(acts), sum(len(x["rep"]["rolls"]) for x in acts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
