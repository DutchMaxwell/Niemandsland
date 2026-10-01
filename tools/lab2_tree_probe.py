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
    a = ap.parse_args(argv)
    return cmd_timing(a) if a.cmd == "timing" else cmd_pilot(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
