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
  `--cand-knobs JSON|FILE` / `--cand-preset NAME` (--arm I only) give the ROW'S seat one extra knob bundle (selfplay.KNOB_PRESETS or
inline), mirrored by `--seats 1,2`: "the shipped net + one knob vs the shipped net"; rows record cand_seat / cand_knobs(_sha256).
  `--knobs-seat1 / --knobs-seat2 JSON|FILE` (--arm I): a bundle per ABSOLUTE seat (the two seats may differ).
  `--explore-seed N` (>= 0; default -1 = off) / `--explore-seats 1,2`: NachtmahrZero E2 root exploration for recording -- the first 8
decisions of each exploring seat are sampled from 0.75 * root prior + 0.25 * Dirichlet(0.3) (pool softmax without a tree), seeded by
(row_id, N); rows then carry an `explored` column (1 = that decision was sampled) and the game json `teacher.explored` true; with it
OFF neither exists (= main's records). A gate/A-B reader drops games with `teacher.explored`.
  `--rs-value 1` (default 0): rows also carry an `rs_value` column (the search's rollout value per pool candidate, cands-aligned like
`hand_score`, NaN off-pool, from `trace.rs`) and the game json `teacher.rs_value` true; OFF = today's record.
  teacher_record.py --blocks B.json --arm L|T|L_tray|C|I --out D --bank BANK --repo WT [--knobs grade.json]
                    [--tree-budget 128] [--deadline-us 0] [--deep-pair 10,3] [--seats 1,2] [--dice 0,1] [--workers N]
                    [--net-cand X.onnx --net-inc Y.onnx]
"""
import argparse, contextlib, hashlib, json, os, sys  # noqa: E401
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, "..", "python"), os.path.join(HERE, "..", "..", "..", "tools")]
import lab2_net  # noqa: E402
import lab2_pool  # noqa: E402
import lab2_rows  # noqa: E402
import lab2_tree_probe as lab  # noqa: E402
import selfplay as sp  # noqa: E402

RAGGED = ("units", "objs", "terr", "cands")
FLAT = ("label", "actor", "target", "hand_score", "pi", "tree_fired", "v_root", "v_pick", "completed", "side", "round", "seq")
EXPLORE_ALPHA, EXPLORE_MIX, EXPLORE_MOVES = 0.3, 0.25, 8  # NachtmahrZero E2: Dirichlet(0.3) at 25 %, temperature 1 for 8 decisions
_W = {}  # the worker's config (spawn: set by `_init`, read by the arm_kwargs seam)


class Explorer:
    # Root exploration for RECORDING only (default off): an exploring seat's first EXPLORE_MOVES decisions are SAMPLED from
    # (1-MIX) * root prior + MIX * Dirichlet(ALPHA) -- the tree's root visits, else the pool's softmax of the hand scores --
    # and the sampled child replaces the pick (the vhook swap's fields); later decisions keep the argmax. Seeded per game.
    def __init__(self, seed, row_id, seats):
        self.rng = np.random.default_rng(int.from_bytes(hashlib.sha256(("%s:%s" % (row_id, seed)).encode()).digest()[:8], "big"))
        self.seats, self.n = set(seats), {1: 0, 2: 0}

    def apply(self, pick, player):
        n, self.n[player] = self.n[player], self.n[player] + 1
        if player not in self.seats or n >= EXPLORE_MOVES:
            return False
        trace, tree = pick["trace"], pick["trace"].get("tree")
        if tree and sum(r[1] for r in tree["root"]) > 0:
            idx, w = [r[0] for r in tree["root"]], np.array([r[1] for r in tree["root"]], float)
        else:
            idx, s = [e["idx"] for e in trace["scored"]], np.array([e["score"] for e in trace["scored"]], float)
            w = np.exp(s - s.max())
        p = (1 - EXPLORE_MIX) * w / w.sum() + EXPLORE_MIX * self.rng.dirichlet([EXPLORE_ALPHA] * len(idx))
        k = int(idx[self.rng.choice(len(idx), p=p / p.sum())])
        if k != pick.get("played_idx", trace["scored"][trace["best_idx"]]["idx"]):
            act = trace["cands"][k]
            pick["action"], pick["unit_key"], pick["played_idx"] = act, act["unit"], k
        return True


def make_explorer(seed, row_id, seats):
    return Explorer(seed, row_id, seats) if seed is not None and seed >= 0 else None


class Capture:
    # Wraps the live `_pick_for` (selfplay.forced_picks): one token row per landed pick with a menu; picks untouched
    # (unless an `Explorer` is given: then its sampled decisions are played and stamped `explored`).
    def __init__(self, explorer=None):
        self.rows, self.first, self.explorer = [], {}, explorer

    @contextlib.contextmanager
    def armed(self):
        real = sp._pick_for

        def seen(core, state, player, *args, **kwargs):
            pick = real(core, state, player, *args, **kwargs)
            if pick and "cands" in (pick.get("trace") or {}):
                flag = self.explorer.apply(pick, player) if self.explorer else None
                self.rows.append(self.row(core, state, player, pick, flag))
            return pick
        with sp.forced_picks(seen):
            yield self

    def row(self, core, state, player, pick, explored=None):
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
        rsv = {int(e["idx"]): float(e["rs"]) for e in tr.get("rs", [])} if _W.get("rs_value", False) else None
        return {"units": f16(t["units"][:nu]), "objs": f16(t["objs"][:no]), "terr": f16(t["terr"][:nt]),
                "cands": f16(t["cands"][:nc]), "glob": f16(t["glob"]), "label": np.int16(label), "pi": pi,
                "actor": np.asarray(t["actor"][:nc], np.int16), "target": np.asarray(t["target"][:nc], np.int16),
                "hand_score": f16([score.get(i, float("nan")) for i in range(nc)]), "tree_fired": np.int8(tree is not None),
                "v_root": np.float16(v_root), "v_pick": np.float16(v_pick), "completed": np.int32(tree["completed"] if tree else 0),
                "side": np.int8(player), "round": np.int8(rnd), "seq": np.int16(len(self.rows)),
                **({} if explored is None else {"explored": np.int8(explored)}),
                **({} if rsv is None else {"rs_value": f16([rsv.get(i, float("nan")) for i in range(nc)])})}


def pack(rows, winner):
    # netlab/SHARD_SCHEMA.md packing (ptr-based, live rows only) + the teacher columns; `game_id` is the shard packer's.
    out = {"game_id": np.zeros(len(rows), np.int32), "glob": np.stack([r["glob"] for r in rows])}
    out.update({k: np.concatenate([np.atleast_1d(r[k]) for r in rows]) for k in FLAT + (("explored",) if "explored" in rows[0] else ()) + (("rs_value",) if "rs_value" in rows[0] else ())})
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
    knobs = dict(w["knobs"], record_cands=record)
    seat_knobs = w.get("seat_knobs") or {}
    if w.get("cand_knobs"):
        # "one knob bundle vs the incumbent": the bundle rides the ROW'S seat only (selfplay.play_game's per-seat core)
        knobs.update(knob_override_player=row["seat"], knob_overrides=dict(w["cand_knobs"]))
    elif seat_knobs:
        # per-seat bundles by ABSOLUTE seat (--knobs-seat1/2): the first non-empty bundle is the override seat's, the other rides along
        first = 1 if seat_knobs.get(1) else 2
        knobs.update(knob_override_player=first, knob_overrides=dict(seat_knobs[first]), knob_overrides_other=dict(seat_knobs.get(3 - first) or {}))
    played = {}
    real_play = sp.play_game

    def spy(*a, **k):  # the knobs each seat REALLY played (res["knobs_by_seat"]), kept as the row's evidence
        res = real_play(*a, **k)
        played["by_seat"] = res.get("knobs_by_seat") if res else None
        return res

    if w.get("cand_knobs") or seat_knobs:
        sp.play_game = spy
    try:
        with (Capture(make_explorer(w.get("explore_seed", -1), row["row_id"], w.get("explore_seats", (1, 2)))).armed() if record
              else contextlib.nullcontext()) as cap:
            meta = lab.play_row(w["nm"], sp, row, w["repo"], w["bank"], knobs, net, w["allowance"], w["ctx"])
    finally:
        sp.play_game = real_play
    if w.get("cand_knobs") or seat_knobs:
        meta["cand_played"] = played.get("by_seat")
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
                               "budget": w["budget"], "pair": list(w["pair"]), "nets": [w.get("net_cand", ""), w.get("net_inc", "")],
                               **({"cand_seat": row["seat"], "cand_knobs": w["cand_knobs"],
                                   "cand_knobs_sha256": lab2_rows.sha_of(w["cand_knobs"]),
                                   "knobs_by_seat": meta.pop("cand_played", None)} if w.get("cand_knobs") else {}),
                               **({"seat_knobs": {str(s): b for s, b in w["seat_knobs"].items()}, "knobs_by_seat": meta.pop("cand_played", None)}
                                  if w.get("seat_knobs") else {}),
                               **({"explored": True, "explore_seed": w["explore_seed"], "explore_seats": sorted(w["explore_seats"])}
                                  if w.get("explore_seed", -1) >= 0 else {}),
                               **({"rs_value": True} if w.get("rs_value") else {})}
            lab.write_row(w["out"], meta)
        t = json.load(open(base + ".json"))
        out.append({"row_id": row["row_id"], "valid": t["valid"], "rows": t["teacher"]["rows"], "tree_rows": t["teacher"]["tree_rows"]})
    return out


def resolve_cand(cand_knobs, cand_preset, arm):
    """The candidate seat's knob bundle: `selfplay.KNOB_PRESETS[cand_preset]` overlaid by `cand_knobs` (an inline JSON object or a
    file path), {} when neither is given. Only `--arm I` (both seats the incumbent search) may carry one: a tree arm's deep
    core sits on the same seat and the per-seat knob core would replace it."""
    bundle = {}
    if cand_preset:
        if cand_preset not in sp.KNOB_PRESETS:
            raise SystemExit("unknown --cand-preset %r (have %s)" % (cand_preset, sorted(sp.KNOB_PRESETS)))
        bundle.update(sp.KNOB_PRESETS[cand_preset])
    if cand_knobs:
        text = open(cand_knobs).read() if os.path.exists(cand_knobs) else cand_knobs
        bundle.update(json.loads(text))
    if bundle and arm != "I":
        raise SystemExit("--cand-knobs/--cand-preset need --arm I (the tree arms put a deep core on the candidate seat)")
    return bundle


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for k, d in (("--blocks", None), ("--out", None), ("--bank", None), ("--repo", None), ("--arm", "L"), ("--knobs", ""),
                 ("--deep-pair", "10,3"), ("--seats", "1,2"), ("--dice", "0,1"), ("--prereg-sha256", "none"),
                 ("--net-cand", ""), ("--net-inc", ""), ("--cand-knobs", ""), ("--cand-preset", ""), ("--knobs-seat1", ""), ("--knobs-seat2", ""),
                 ("--explore-seed", -1), ("--rs-value", 0), ("--explore-seats", "1,2"), ("--tree-budget", 128), ("--deadline-us", 0), ("--workers", 1)):
        ap.add_argument(k, default=d, required=d is None, **({"type": int} if isinstance(d, int) else {}))
    a = ap.parse_args(argv)
    seats, dice = {int(x) for x in a.seats.split(",")}, {int(x) for x in a.dice.split(",")}
    rows = [r for r in lab.game_rows(json.load(open(a.blocks)), (a.arm,)) if r["seat"] in seats and r["d"] in dice]
    cfg = {"repo": a.repo, "bank": a.bank, "out": a.out, "knobs": json.load(open(a.knobs)) if a.knobs else {}, "budget": a.tree_budget,
           "pair": tuple(int(x) for x in a.deep_pair.split(",")), "allowance": a.deadline_us, "prereg": a.prereg_sha256,
           "net_cand": a.net_cand, "net_inc": a.net_inc, "cand_knobs": resolve_cand(a.cand_knobs, a.cand_preset, a.arm),
           "seat_knobs": {s: b for s, b in ((1, resolve_cand(a.knobs_seat1, "", a.arm)), (2, resolve_cand(a.knobs_seat2, "", a.arm))) if b},
           "explore_seed": a.explore_seed, "explore_seats": tuple(int(x) for x in a.explore_seats.split(",")), "rs_value": bool(a.rs_value)}
    if cfg["seat_knobs"] and cfg["cand_knobs"]:
        raise SystemExit("--knobs-seat1/2 and --cand-knobs/--cand-preset both set a seat's bundle; pick one")
    os.makedirs(a.out, exist_ok=True)
    res = [x for r in lab2_pool.run_clusters({r["row_id"]: [r] for r in rows}, a.workers, _init, _work, (cfg,)) for x in r["result"]]
    print("[record] games=%d valid=%d rows=%d tree_rows=%d out=%s" % (len(res), sum(x["valid"] for x in res), sum(x["rows"] for x in res),
                                                                     sum(x["tree_rows"] for x in res), a.out))
    return 0 if all(x["valid"] for x in res) else 1


if __name__ == "__main__":
    sys.exit(main())
