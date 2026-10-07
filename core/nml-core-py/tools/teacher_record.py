#!/usr/bin/env python3
"""Teacher-data recorder (loop prep, 07.10.2026): the stage-0 full-game path (`lab2_tree_probe.play_row` -- the tree arm
on the row's seat vs the incumbent, the shipped value net at both seats' leaves) with one TOKEN ROW per decision:
`Core.policy_tokens` in netlab/SHARD_SCHEMA.md's packed layout + the tree's root visit distribution `pi` (cands-aligned),
its backed-up root value `v_root`, the played child's mean `v_pick`, the played `label`, the game end from the actor's view
`outcome` (1/0/-1); opponent rows carry `tree_fired` 0 and `pi` 0. One atomic `<row_id>.npz` + `.json` per game (json last =
complete; existing = skipped); budget-bound by default (`--tree-budget`, no clock: the seeds replay the same moves on any
machine), `--deadline-us` = the stage-0 wall allowance. Recording moves no pick (proof: test_teacher_record.py).
`--net-cand X.onnx` (the row's seat) / `--net-inc Y.onnx` (the other seat) make `--arm I` an A/B of two value nets at the
shipped grade, mirrored by seat (proof: test_teacher_ab.py); default = the shipped net on both seats.
  teacher_record.py --blocks B.json --arm L|T|L_tray|C|I --out D --bank BANK --repo WT [--knobs grade.json]
                    [--tree-budget 128] [--deadline-us 0] [--deep-pair 10,3] [--seats 1,2] [--dice 0,1] [--workers N]
                    [--net-cand X.onnx --net-inc Y.onnx]
"""
import argparse, contextlib, json, os, sys  # noqa: E401
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, "..", "python"), os.path.join(HERE, "..", "..", "..", "tools")]
import lab2_net  # noqa: E402
import lab2_pool  # noqa: E402
import lab2_tree_probe as lab  # noqa: E402
import selfplay as sp  # noqa: E402

RAGGED = ("units", "objs", "terr", "cands")
FLAT = ("label", "actor", "target", "hand_score", "pi", "tree_fired", "v_root", "v_pick", "completed", "side", "round", "seq")
_W = {}  # the worker's config (spawn: set by `_init`, read by the arm_kwargs seam)


class Capture:
    # Wraps the live `_pick_for` (selfplay.forced_picks): one token row per landed pick with a menu; picks untouched.
    def __init__(self):
        self.rows, self.first = [], {}

    @contextlib.contextmanager
    def armed(self):
        real = sp._pick_for

        def seen(core, state, player, *args, **kwargs):
            pick = real(core, state, player, *args, **kwargs)
            if pick and "cands" in (pick.get("trace") or {}):
                self.rows.append(self.row(core, state, player, pick))
            return pick
        with sp.forced_picks(seen):
            yield self

    def row(self, core, state, player, pick):
        tr, rnd = pick["trace"], int(state.round)
        label = int(pick.get("played_idx", tr["scored"][tr["best_idx"]]["idx"]))
        # opener_seat = the round's first mover (gen0_replay_shards' `_OPENER` rule, read live)
        t = core.policy_tokens(state, player, tr["cands"], label, hero_attach=True, opener_seat=self.first.setdefault(rnd, player) == player)
        nu, no, nt, nc = (int(sum(t[k + "_mask"])) for k in RAGGED)
        score = {e["idx"]: e["score"] for e in tr["scored"]}
        pi, tree, v_root, v_pick = np.zeros(nc, np.float16), tr.get("tree"), float("nan"), float("nan")
        n = float(sum(r[1] for r in tree["root"])) if tree else 0.0
        if n > 0:
            for idx, visits, mean in tree["root"]:
                pi[idx] = visits / n
            v_root = sum(r[1] * r[2] for r in tree["root"]) / n
            v_pick = next((r[2] for r in tree["root"] if r[0] == label), float("nan"))
        f16 = lambda a: np.asarray(a, np.float16)  # noqa: E731
        return {"units": f16(t["units"][:nu]), "objs": f16(t["objs"][:no]), "terr": f16(t["terr"][:nt]),
                "cands": f16(t["cands"][:nc]), "glob": f16(t["glob"]), "label": np.int16(label), "pi": pi,
                "actor": np.asarray(t["actor"][:nc], np.int16), "target": np.asarray(t["target"][:nc], np.int16),
                "hand_score": f16([score.get(i, float("nan")) for i in range(nc)]), "tree_fired": np.int8(tree is not None),
                "v_root": np.float16(v_root), "v_pick": np.float16(v_pick), "completed": np.int32(tree["completed"] if tree else 0),
                "side": np.int8(player), "round": np.int8(rnd), "seq": np.int16(len(self.rows))}


def pack(rows, winner):
    # netlab/SHARD_SCHEMA.md packing (ptr-based, live rows only) + the teacher columns; `game_id` is the shard packer's.
    out = {"game_id": np.zeros(len(rows), np.int32), "glob": np.stack([r["glob"] for r in rows])}
    out.update({k: np.concatenate([np.atleast_1d(r[k]) for r in rows]) for k in FLAT})
    for k in RAGGED:
        out[k + "_ptr"] = np.concatenate([[0], np.cumsum([len(r[k]) for r in rows])]).astype(np.int64)
        out[k] = np.concatenate([r[k] for r in rows])
    mine = out["side"] == {"p1": 1, "p2": 2}.get(winner, 0)
    out["outcome"] = np.where(winner == "draw", 0, np.where(mine, 1, -1)).astype(np.int8)
    return out


class SeatNets:
    # `lab2_net.ShippedNet`'s surface for `play_row` with ONE net per seat (D-L2: an A/B of two value nets at the shipped grade).
    def __init__(self, nets):
        self.nets, self.model_sha256 = nets, ":".join(nets[s].model_sha256 for s in (1, 2))

    @property
    def counts(self):
        return {s: dict(self.nets[s].counts.get(s, {"calls": 0, "leaves": 0})) for s in (1, 2)}

    def hook(self, side):
        return self.nets[side].hook(side)


def arm_kwargs(row, cfg):
    # The probe's arm kwargs (`lab2_tree_probe.arm_kwargs`, kept as `_PROBE_ARM_KWARGS`) + the recorder's seams: a leaf
    # budget beside/instead of the wall allowance, T = the L tree to the mission end, the deep pair. At the stage-0
    # settings (allowance > 0, budget 0, pair 10/3) they are IDENTICAL -- the runner's moves are the recorder's.
    kw = lab._PROBE_ARM_KWARGS(dict(row, arm="L" if row["arm"] == "T" else row["arm"]), cfg["allowance"])
    kw.update({"deep_tree_leaf": "terminal"} if row["arm"] == "T" else {})
    kw.update({"deep_tree_budget": cfg["budget"]} if cfg["budget"] and row["arm"] != "C" else {})
    if not cfg["allowance"]:
        kw.pop("deep_deadline_after_preselect")  # a clock rule without a clock would only stamp
    return kw if row["arm"] == "C" else dict(kw, deep_top_k=cfg["pair"][0], deep_horizon=cfg["pair"][1])


lab._PROBE_ARM_KWARGS, lab.arm_kwargs = lab.arm_kwargs, lambda row, us: arm_kwargs(row, dict(_W, allowance=us))


def _init(cfg):
    import nml_core as nm
    _W.update(cfg)
    nets = {s: lab2_net.ShippedNet(cfg["repo"], **({"onnx": p, "sha256": lab2_net._sha256(p)} if p else {}))
            for s, p in ((1, cfg.get("net_cand", "")), (2, cfg.get("net_inc", "")))}
    return dict(cfg, nm=nm, nets=nets, ctx=lab.run_context(nm, cfg["prereg"], nets[1]))


def play(w, row, record=True):
    # One manifest row through `lab2_tree_probe.play_row` (the stage-0 path), the Capture armed around it. D-L2: with
    # `--net-cand` / `--net-inc` the candidate net sits on the ROW'S seat and the incumbent's on the other (mirrored by seat).
    net = SeatNets({row["seat"]: w["nets"][1], 3 - row["seat"]: w["nets"][2]}) if w.get("net_cand") or w.get("net_inc") else w["nets"][1]
    with (Capture().armed() if record else contextlib.nullcontext()) as cap:
        meta = lab.play_row(w["nm"], sp, row, w["repo"], w["bank"], dict(w["knobs"], record_cands=record), net, w["allowance"], w["ctx"])
    return meta, cap.rows if cap else []


def _work(w, cid, rows):
    out = []
    for row in rows:
        base = os.path.join(w["out"], row["row_id"])
        if not os.path.exists(base + ".json"):
            meta, rows_ = play(w, row)
            if meta["valid"] and not rows_:
                meta["valid"], meta["reason"] = False, "no decision captured"
            if meta["valid"]:
                with open(base + ".npz.tmp", "wb") as fh:
                    np.savez(fh, **pack(rows_, meta["winner"]))
                os.replace(base + ".npz.tmp", base + ".npz")
            meta["teacher"] = {"schema": "teacher-game/1", "rows": len(rows_), "tree_rows": int(sum(int(r["tree_fired"]) for r in rows_)),
                               "y_cand": {"draw": 0.5}.get(meta["winner"], float(meta["winner"] == "p%d" % row["seat"])),
                               "budget": w["budget"], "pair": list(w["pair"]), "nets": [w.get("net_cand", ""), w.get("net_inc", "")]}
            lab.write_row(w["out"], meta)
        t = json.load(open(base + ".json"))
        out.append({"row_id": row["row_id"], "valid": t["valid"], "rows": t["teacher"]["rows"], "tree_rows": t["teacher"]["tree_rows"]})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for k, d in (("--blocks", None), ("--out", None), ("--bank", None), ("--repo", None), ("--arm", "L"), ("--knobs", ""),
                 ("--deep-pair", "10,3"), ("--seats", "1,2"), ("--dice", "0,1"), ("--prereg-sha256", "none"),
                 ("--net-cand", ""), ("--net-inc", ""), ("--tree-budget", 128), ("--deadline-us", 0), ("--workers", 1)):
        ap.add_argument(k, default=d, required=d is None, **({"type": int} if isinstance(d, int) else {}))
    a = ap.parse_args(argv)
    seats, dice = {int(x) for x in a.seats.split(",")}, {int(x) for x in a.dice.split(",")}
    rows = [r for r in lab.game_rows(json.load(open(a.blocks)), (a.arm,)) if r["seat"] in seats and r["d"] in dice]
    cfg = {"repo": a.repo, "bank": a.bank, "out": a.out, "knobs": json.load(open(a.knobs)) if a.knobs else {}, "budget": a.tree_budget,
           "pair": tuple(int(x) for x in a.deep_pair.split(",")), "allowance": a.deadline_us, "prereg": a.prereg_sha256,
           "net_cand": a.net_cand, "net_inc": a.net_inc}
    os.makedirs(a.out, exist_ok=True)
    res = [x for r in lab2_pool.run_clusters({r["row_id"]: [r] for r in rows}, a.workers, _init, _work, (cfg,)) for x in r["result"]]
    print("[record] games=%d valid=%d rows=%d tree_rows=%d out=%s" % (len(res), sum(x["valid"] for x in res), sum(x["rows"] for x in res),
                                                                     sum(x["tree_rows"] for x in res), a.out))
    return 0 if all(x["valid"] for x in res) else 1


if __name__ == "__main__":
    sys.exit(main())
