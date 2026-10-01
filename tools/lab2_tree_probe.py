#!/usr/bin/env python3
"""Lab driver for the stage-0 tree pilot (tree plan step 11a, PREREG_AILAB2_STAGE0 section 6).

`pilot` part 1: the environment stamp (a mismatch STOPS), 100 recorded transition replays, the
snapshot round trip, and the two RED controls (a corrupted VP ledger and a corrupted die must FAIL
the replay check). `--dry-run` prints the plan and exits 0 without touching nml_core.

A transition record is one `Tapped.acts` entry of headroom_s2 plus its game's `dice_seed`:
before, action, rng_state, tray_state, faces_before, after, rolls, tray_state_after, rng_state_after.
Run:  python3 tools/lab2_tree_probe.py pilot --transitions t.json --namespace ns [--dry-run]
"""
import argparse
import copy
import hashlib
import json
import os
import resource
import statistics
import sys
import time


def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=True, allow_nan=True)


def env_stamp(nm, net_path, expect):
    """The environment, and the list of mismatches against the expected values."""
    info = dict(getattr(nm, "BUILD_INFO", {}))
    sha = hashlib.sha256(open(net_path, "rb").read()).hexdigest() if net_path else None
    stamp = {"python": sys.version.split()[0], "commit": info.get("commit"),
             "rules_epoch": info.get("rules_epoch"), "model_sha256": sha}
    return stamp, [k for k, v in expect.items() if v is not None and stamp.get(k) != v]


def replay_transition(nm, core, rec):
    """One recorded transition re-simulated from its snapshot (headroom_s2 `resim`, copied) plus
    the snapshot round trip: the live state is unchanged by the resolve."""
    st = core.state_of(rec["before"])
    snap = canon(st.plain())
    rng = nm.Rng(0)
    rng.state = rec["rng_state"]
    tray = nm.Tray(rec["dice_seed"])
    n = rec["faces_before"]
    while n > 0:
        tray.roll(min(n, 4096))
        n -= min(n, 4096)
    prefix = tray.state == rec["tray_state"]
    nxt, rep = core.resolve_with_tray(st, rec["action"], rng, tray)
    checks = {
        "snapshot_roundtrip": snap == canon(rec["before"]),
        "snapshot_untouched": snap == canon(st.plain()),
        "tray_prefix": prefix,
        "state": canon(nxt.plain()) == canon(rec["after"]),
        "rolls": rep["rolls"] == rec["rolls"],
        "streams_after": tray.state == rec["tray_state_after"] and rng.state == rec["rng_state_after"],
    }
    return {"ok": all(checks.values()), "checks": checks}


def red_vp(rec):
    """RED-VP: one recorded VP +1, everything else kept."""
    bad = copy.deepcopy(rec)
    bad["after"]["vp"][0] += 1
    return bad


def red_die(rec):
    """RED-DIE: one recorded tray face changed, the recorded expected state retained."""
    bad = copy.deepcopy(rec)
    roll = next(r for r in bad["rolls"] if r["faces"])
    roll["faces"][0] = roll["faces"][0] % 6 + 1
    return bad


# ---- part 2: the timing set (PREREG section 6) ---------------------------------------------------
BUDGETS = (32, 64, 128, 256)
#: chi2 quantile(0.10, 12) — the prereg's small-pilot variance allowance F = 12 / this.
CHI2_Q10_DF12 = 6.303801
Z_995, Z_80 = statistics.NormalDist().inv_cdf(0.995), statistics.NormalDist().inv_cdf(0.80)


def pick_states(states, per_cell=12):
    """The first `per_cell` legal pre-pick states of every cell, in source order; a short cell fails."""
    out = {}
    for st in states:
        out.setdefault(st["cell"], [])
        if len(out[st["cell"]]) < per_cell:
            out[st["cell"]].append(st)
    short = {c: len(v) for c, v in out.items() if len(v) < per_cell}
    if short:
        raise SystemExit("timing instrument fails: short cells %s" % short)
    return out


def measure(call, reps=3):
    """One unmeasured warm-up, then `reps` monotonic wall times in ms of the full planner call."""
    call()
    times = []
    for _ in range(reps):
        t0 = time.perf_counter()
        call()
        times.append((time.perf_counter() - t0) * 1e3)
    return times


def allowance_us(times_ms):
    """B(cell) = min(4 x median, 1000 ms), rounded DOWN to integer microseconds, at least 1."""
    return max(1, int(min(4 * statistics.median(times_ms), 1000.0) * 1000))


def projected_mde(var_by_cell, n_c, cells=12):
    """Projected MDE in points: 100 (z.995 + z.80) sqrt(F V), V = sum_c (1/cells)^2 s_c^2 / n_c."""
    v = sum((1 / cells) ** 2 * s2 / n_c for s2 in var_by_cell.values())
    return 100 * (Z_995 + Z_80) * (cells / CHI2_Q10_DF12 * v) ** 0.5


def peak_rss_mib():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


def cmd_timing(a) -> int:
    import nml_core as nm  # lazy
    states = pick_states(json.load(open(a.states)), a.per_cell)
    core = nm.load(a.repo)
    base = json.load(open(a.header))
    if a.statics:
        statics = json.loads(a.statics)
    else:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "core", "nml-core-py", "python"))
        import selfplay
        statics = selfplay.TRAINER_STATICS
    rows, report = {}, ["# Tree pilot timing set", ""]
    for cell, sts in sorted(states.items()):
        def run(st, extra):
            core.set_header(dict(base, knobs=dict(base["knobs"], **extra)))
            return lambda: core.plan_with_rollout(core.state_of(st["state"]), st["player"], statics)
        inc = [t for st in sts for t in measure(run(st, {}))]
        rows[cell] = {"incumbent_median_ms": statistics.median(inc), "B_us": allowance_us(inc), "tree": {}}
        for b in BUDGETS:
            ex = {"search_mode": "tree", "tree_budget": b, "tree_wall_ms": rows[cell]["B_us"] // 1000}
            times, active, done, hit = [], 0, [], 0
            for st in sts:
                times += measure(run(st, ex))
                tr = (run(st, ex)() or {}).get("trace", {}).get("tree")
                active += tr is not None
                done += [tr["completed"]] if tr else []
                hit += bool(tr and tr.get("deadline_hit"))
            rows[cell]["tree"][b] = {"median_ms": statistics.median(times), "tree_active": active == len(sts),
                                     "completed": done, "deadline_hits": hit, "decisions": len(sts)}
        report.append("- %s: incumbent median %.1f ms, B=%d us; tree %s" % (
            cell, rows[cell]["incumbent_median_ms"], rows[cell]["B_us"],
            {b: (round(v["median_ms"], 1), "ACTIVE" if v["tree_active"] else "INVALID: knob not live") for b, v in rows[cell]["tree"].items()}))
    report.append("\npeak RSS %.0f MiB" % peak_rss_mib())
    if a.block_variance:
        var = json.load(open(a.block_variance))
        report.append("projected MDE A %.2f pts, B %.2f pts" % (projected_mde(var["A"], 40), projected_mde(var["B"], 104)))
    open(a.out, "w").write("\n".join(report) + "\n")
    json.dump(rows, open(a.out + ".json", "w"), sort_keys=True)
    return 0


# ---- part A: the endings (PREREG section 8-9) ---------------------------------------------------
ARMS = ("I", "L", "T")
#: Played streams: stream r of position p seeds `Rng(base)` and `Tray(base + TRAY_OFFSET)`, the SAME pair for
#: every arm (common random numbers).
STREAM_BASE, POS_STRIDE, TRAY_OFFSET, STREAMS = 740_000_000, 100_000, 50_000, 8
ARM_KNOBS = {"I": {}, "L": {"search_mode": "tree", "tree_leaf": "blend"},
             "T": {"search_mode": "tree", "tree_leaf": "terminal"}}
CONTRASTS = (("A_T", "T", "I"), ("A_L", "L", "I"), ("A_TL", "T", "L"))


def stream_pair(nm, pos_i, r):
    base = STREAM_BASE + pos_i * POS_STRIDE + r
    return nm.Rng(base), nm.Tray(base + TRAY_OFFSET)


def play_ending(nm, sp, cores, pos, rng, tray):
    """Finish the last round from a pre-pick state: the mover's EVERY decision from `cores["cand"]`, the
    other side's from `cores["inc"]`; then the round-end referee and the mission verdict. Returns the
    candidate seat's score 1 / 0.5 / 0."""
    mover, state = pos["mover"], cores["inc"].state_of(pos["state"])
    core_of = lambda side: cores["cand"] if side == mover else cores["inc"]
    owners, led, turn = list(pos["owners_before_round"]), sp._ledger_of(state), mover
    for _ in range(state.units * 2 + 4):
        for side in (turn, 3 - turn):
            act = sp._pick_for(core_of(side), state, side)
            if act:
                break
        else:
            break
        state, _ = core_of(side).resolve_with_tray(state, act["action"], rng, tray)
        state = cores["inc"].restamp_los(state)
        turn = 3 - side
    state, owners = sp._round_end(cores["inc"], state, owners, led, sp.ROUNDS)
    win = sp._verdict(cores["inc"], owners, led)
    return 0.5 if win == "draw" else float(win == "p%d" % mover)


def position_gains(y):
    """y[arm] = the 8 stream scores; a_X(p) = mean_r (Y_X - Y_Y) for the three registered contrasts."""
    return {n: statistics.fmean(a - b for a, b in zip(y[x], y[z])) for n, x, z in CONTRASTS}


def bootstrap_intervals(gains, resamples=100_000, seed=0, k=5):
    """gains[cell][cluster] = {contrast: a}; cluster bootstrap within each cell (n_c clusters drawn with
    replacement, resample index first, then cell), 100 x equal-cell mean, Bonferroni K=5 (0.005 / 0.995)."""
    import numpy as np
    rng = np.random.Generator(np.random.PCG64(seed))
    cells = sorted(gains)
    vec = {n: [np.array([gains[c][cl][n] for cl in sorted(gains[c])]) for c in cells] for n, _, _ in CONTRASTS}
    draws = {n: np.empty(resamples) for n, _, _ in CONTRASTS}
    for i in range(resamples):
        idx = [rng.integers(0, len(vec["A_T"][j]), len(vec["A_T"][j])) for j in range(len(cells))]
        for n in draws:
            draws[n][i] = 100 * np.mean([vec[n][j][ix].mean() for j, ix in enumerate(idx)])
    q = (0.05 / k / 2, 1 - 0.05 / k / 2)  # alpha .05 / K = .01 two-sided -> the .005 and .995 quantiles
    return {n: {"point": 100 * float(np.mean([v.mean() for v in vec[n]])),
                "lo": float(np.quantile(d, q[0])), "hi": float(np.quantile(d, q[1]))} for n, d in draws.items()}


def cmd_endings(a) -> int:
    import nml_core as nm  # lazy
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "core", "nml-core-py", "python"))
    import selfplay as sp
    base, allow = json.load(open(a.header)), json.load(open(a.timing))
    positions = json.load(open(a.positions))
    def core(extra):
        c = nm.load(a.repo)
        c.set_header(dict(base, knobs=dict(base["knobs"], **extra)))
        return c
    inc = core({})
    gains = {}
    for i, pos in enumerate(positions):
        wall = max(1, allow[pos["cell"]]["B_us"] // 1000)  # the knob is whole ms; 0 would mean OFF
        y = {}
        for arm in ARMS:
            cand = core(dict(ARM_KNOBS[arm], **({"tree_wall_ms": wall} if arm != "I" else {})))
            y[arm] = [play_ending(nm, sp, {"inc": inc, "cand": cand}, pos, *stream_pair(nm, i, r)) for r in range(STREAMS)]
        gains.setdefault(pos["cell"], {})[pos["cluster"]] = position_gains(y)
        print("[endings] %d/%d %s %s" % (i + 1, len(positions), pos["cell"], canon(gains[pos["cell"]][pos["cluster"]])), flush=True)
    res = bootstrap_intervals(gains, a.resamples, a.seed)
    open(a.out, "w").write(canon({"gains": gains, "intervals": res}))
    print("[endings] " + canon(res))
    return 0


def cmd_pilot(a) -> int:
    plan = {"transitions": a.count, "reds": ["RED-VP", "RED-DIE"], "workers": a.workers,
            "wall_hours": a.wall_hours, "rss_gib": a.rss_gib, "namespace": a.namespace}
    if a.dry_run:
        print("[pilot] dry-run plan: " + canon(plan))
        return 0
    import nml_core as nm  # lazy: a dry run needs no core
    stamp, bad = env_stamp(nm, a.net, {"commit": a.expect_commit, "rules_epoch": a.expect_epoch,
                                       "model_sha256": a.expect_model_sha})
    if bad:
        print("[pilot] STOP: environment mismatch on %s: %s" % (bad, canon(stamp)))
        return 2
    recs = json.load(open(a.transitions))[: a.count]
    core = nm.load(a.repo)
    results = [replay_transition(nm, core, r) for r in recs]
    red_rec = next(r for r in recs if r["after"].get("vp") is not None)
    reds = {"RED-VP": replay_transition(nm, core, red_vp(red_rec))["ok"],
            "RED-DIE": replay_transition(nm, core, red_die(next(r for r in recs if any(x["faces"] for x in r["rolls"]))))["ok"]}
    passed = len(results) == a.count and all(r["ok"] for r in results) and not any(reds.values())
    out = {"plan": plan, "stamp": stamp, "replayed": len(results), "failed": [i for i, r in enumerate(results) if not r["ok"]],
           "reds_passed_the_check": [k for k, v in reds.items() if v], "pass": passed}
    open("%s_pilot_part1.json" % a.namespace, "w").write(canon(out))
    print("[pilot] part 1 %s: %d/%d replays ok, REDs that FAILED to fail: %s"
          % ("PASS" if passed else "FAIL", len(results) - len(out["failed"]), a.count, out["reds_passed_the_check"]))
    return 0 if passed else 1


def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pilot")
    p.add_argument("--transitions", default="")
    p.add_argument("--count", type=int, default=100)
    p.add_argument("--workers", type=int, default=4)
    p.add_argument("--wall-hours", type=float, default=6)
    p.add_argument("--rss-gib", type=float, default=6)
    p.add_argument("--namespace", required=True)
    p.add_argument("--repo", default=".")
    p.add_argument("--net", default="")
    p.add_argument("--expect-commit")
    p.add_argument("--expect-epoch", type=int)
    p.add_argument("--expect-model-sha")
    p.add_argument("--dry-run", action="store_true")
    t = sub.add_parser("timing")
    t.add_argument("--states", required=True, help="JSON list of {cell, state, player}")
    t.add_argument("--header", required=True, help="JSON header with a knobs block (the incumbent 10/3)")
    t.add_argument("--statics", default=None)
    t.add_argument("--per-cell", type=int, default=12)
    t.add_argument("--block-variance", default="", help='JSON {"A": {cell: s2}, "B": {cell: s2}}')
    t.add_argument("--repo", default=".")
    t.add_argument("--out", required=True)
    e = sub.add_parser("endings")
    e.add_argument("--positions", required=True, help="JSON list of {cell, cluster, mover, state, owners_before_round}")
    e.add_argument("--header", required=True)
    e.add_argument("--timing", required=True, help="the timing subcommand's .json (B_us per cell)")
    e.add_argument("--resamples", type=int, default=100_000)
    e.add_argument("--seed", type=int, default=0)
    e.add_argument("--repo", default=".")
    e.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    return {"timing": cmd_timing, "endings": cmd_endings}.get(a.cmd, cmd_pilot)(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
