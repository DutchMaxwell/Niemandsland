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


EXTENSIONS = (".so", ".pyd", ".dylib")


def binary_path(nm):
    """The loaded nml_core BINARY. A wheel installs the package shim `nml_core/__init__.py` (the same few lines in
    every build) plus the compiled submodule `nml_core/nml_core*.so`, so the submodule's file is hashed; a bare
    extension module on sys.path is its own file. None when no compiled file is found (a strict stamp then fails)."""
    for mod in (getattr(nm, "nml_core", None), nm):
        path = getattr(mod, "__file__", None)
        if path and path.endswith(EXTENSIONS) and os.path.exists(path):
            return path
    return None


def env_stamp(nm, net_path, expect, strict=False):
    """The environment, and the list of mismatches against the expected values. `strict` (a real pilot): every
    expectation must be given ("missing:<key>") and the build must be clean (`dirty` is False)."""
    info = dict(getattr(nm, "BUILD_INFO", {}))
    sha = hashlib.sha256(open(net_path, "rb").read()).hexdigest() if net_path else None
    so = binary_path(nm)   # the compiled extension module, never the package shim
    wheel = hashlib.sha256(open(so, "rb").read()).hexdigest() if so else None
    stamp = {"python": sys.version.split()[0], "commit": info.get("commit"), "rules_epoch": info.get("rules_epoch"),
             "model_sha256": sha, "dirty": info.get("dirty"), "wheel_sha256": wheel}
    bad = [k for k, v in expect.items() if v is not None and stamp.get(k) != v]
    if strict:
        bad += ["missing:" + k for k, v in expect.items() if v is None]
        if stamp["dirty"] is not False:
            bad.append("dirty")
    return stamp, bad


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


def source_of(rec):
    """The source game of a transition, timing state or position: `slot:candidate` (lab2_source's header key)."""
    return rec.get("source") or ("%s:%s" % (rec["slot"], rec["candidate"]) if "candidate" in rec else None)


def game_header(headers, source, base, extra=None):
    """The header a recorded state is played under. A header carries ITS game's profiles, terrain and knobs, so with
    `headers` (lab2_source's `<transitions>.headers`, source -> that game's recorded header) it is the source game's
    header with the base header's knobs, then the arm's, overlaid; without, the one base header (one-game fixtures)."""
    if headers is None:
        hdr = base
    elif source in headers:
        hdr = headers[source]
    else:
        raise SystemExit("no recorded game header for source %r" % source)
    return dict(hdr, knobs={**hdr.get("knobs", {}), **base.get("knobs", {}), **(extra or {})})


def make_core(nm, repo, base, headers):
    """core(extra, source) -> (a fresh core under that game's header + the arm's knobs, the header's sha)."""
    import lab2_rows

    def core(extra, source=None):
        hdr = game_header(headers, source, base, extra)
        c = nm.load(repo)
        c.set_header(hdr)
        return c, lab2_rows.sha_of(hdr)
    return core


def replay_records(nm, repo, recs, headers):
    """Part 1: every record and both REDs replayed on a fresh core under the record's OWN game header."""
    core = make_core(nm, repo, {}, headers)
    run = lambda rec, shown: replay_transition(nm, core({}, source_of(rec))[0], shown)
    red_rec = next(r for r in recs if r["after"].get("vp") is not None)
    die_rec = next(r for r in recs if any(x["faces"] for x in r["rolls"]))
    return [run(r, r) for r in recs], {"RED-VP": run(red_rec, red_vp(red_rec))["ok"],
                                       "RED-DIE": run(die_rec, red_die(die_rec))["ok"]}


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
    from lab2_net import ShippedNet
    states = pick_states(json.load(open(a.states)), a.per_cell)
    core, net = nm.load(a.repo), ShippedNet(a.repo)
    base, headers = json.load(open(a.header)), (json.load(open(a.headers)) if a.headers else None)
    if a.statics:
        statics = json.loads(a.statics)
    else:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "core", "nml-core-py", "python"))
        import selfplay
        statics = selfplay.TRAINER_STATICS
    rows, report = {}, ["# Tree pilot timing set (hardware: %s, net %s...)" % (a.hardware, net.model_sha256[:8]), ""]
    for cell, sts in sorted(states.items()):
        def run(st, extra):
            core.set_header(game_header(headers, source_of(st), base, extra))  # the state's own game header
            # the shipped net prices the leaves of EVERY timed call (section 6: encoding/inference inside the call)
            return lambda: core.plan_with_rollout(core.state_of(st["state"]), st["player"], statics,
                                                  leaf_value_fn=net.hook(st["player"]), leaf_value_w=1.0)
        inc = [t for st in sts for t in measure(run(st, {}))]
        rows[cell] = {"incumbent_median_ms": statistics.median(inc), "B_us": allowance_us(inc), "tree": {}}
        for b in BUDGETS:
            ex = {"search_mode": "tree", "tree_budget": b, "deadline_us": rows[cell]["B_us"]}  # from the planner call
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
    report.append("\nThe 32/64/128/256 tree_budget sweep is a D-ONLY DIAGNOSTIC, not configuration.")
    report.append("peak RSS %.0f MiB" % peak_rss_mib())
    if a.block_variance:
        var = json.load(open(a.block_variance))
        report.append("projected MDE A %.2f pts, B %.2f pts" % (projected_mde(var["A"], 40), projected_mde(var["B"], 104)))
    open(a.out, "w").write("\n".join(report) + "\n")
    rows["_meta"] = {"hardware": a.hardware, "model_sha256": net.model_sha256,
                     "sweep": "D-only diagnostic, not configuration"}
    json.dump(rows, open(a.out + ".json", "w"), sort_keys=True)
    return 0


# ---- part A: the endings (PREREG section 8-9) ---------------------------------------------------
ARMS = ("I", "L", "T")
#: The 8 played streams of a position come from its `eval` list (decimal key seeds: `Rng(general)`, `Tray(tray)`),
#: the SAME pair for every arm (common random numbers).
STREAMS = 8
ARM_KNOBS = {"I": {}, "L": {"search_mode": "tree", "tree_leaf": "blend"},
             "T": {"search_mode": "tree", "tree_leaf": "terminal"},
             # P9 tray arms: configured here, run only by the tray probe (step 27), never by `endings`
             "L_tray": {"search_mode": "tree", "tree_leaf": "blend", "tree_dice": "tray"},
             "T_tray": {"search_mode": "tree", "tree_leaf": "terminal", "tree_dice": "tray"}}
CONTRASTS = (("A_T", "T", "I"), ("A_L", "L", "I"), ("A_TL", "T", "L"))


def eval_streams(nm, pos, r):
    return nm.Rng(int(pos["eval"][r]["general"])), nm.Tray(int(pos["eval"][r]["tray"]))


def search_streams(nm, pos, arm, r):
    """One search stream per seat for (position, replicate, arm): `pos["search"][arm][r][owner]` decimal keys."""
    return {int(o): {"rng": nm.Rng(int(k)), "seed": int(k), "counter": 0, "pending": None}
            for o, k in pos["search"][arm][r].items()}


def finish_ending(nm, sp, cores, pos, rng, tray, net=None, search=None, log=None):
    """Finish the last round from a pre-pick state: the mover's EVERY decision from `cores["cand"]`, the
    other side's from `cores["inc"]`; then the round-end referee (round count from the state's own ledger)
    and the mission verdict. Returns (final state, owners, verdict). With `net` every side's planner prices its
    leaves with the shipped net (weight 1.0); with `search` a tree core draws its `sig` from its seat's stream
    (two draws per decision, as `play_game(search_seeds=)`) and the draw is appended to `log`."""
    mover, state = pos["mover"], cores["inc"].state_of(pos["state"])
    core_of = lambda side: cores["cand"] if side == mover else cores["inc"]
    owners, led, turn = list(pos["owners_before_round"]), sp._ledger_of(state), mover
    hooks = {side: {"leaf_value_fn": {side: net.hook(side)}, "leaf_value_w": 1.0} for side in (1, 2)} if net else {}
    for _ in range(state.units * 2 + 4):
        for side in (turn, 3 - turn):
            sg = sp._search_sig(search, side, core_of(side))
            act = sp._pick_for(core_of(side), state, side, **hooks.get(side, {}), **({"sig": sg["sig"]} if sg else {}))
            if act:
                if sg:
                    search[side].update(pending=None, counter=sg["counter"] + 1)
                    log.append({"side": side, "seed": sg["seed"], "counter": sg["counter"], "sig": sg["sig"]})
                break
        else:
            break
        state, _ = core_of(side).resolve_with_tray(state, act["action"], rng, tray)
        state = cores["inc"].restamp_los(state)
        turn = 3 - side
    state, owners = sp._round_end(cores["inc"], state, owners, led, led["rounds"])
    return state, owners, sp._verdict(cores["inc"], owners, led)


def play_ending(nm, sp, cores, pos, rng, tray):
    """`finish_ending`'s verdict as the candidate seat's score 1 / 0.5 / 0."""
    win = finish_ending(nm, sp, cores, pos, rng, tray)[2]
    return 0.5 if win == "draw" else float(win == "p%d" % pos["mover"])


def run_ending(nm, sp, cores, pos, rng, tray, arm, net=None, search=None):
    """One ending row: the candidate's score, the net calls it cost, the search draws; INVALID "net_inactive"
    unless the net priced leaves for the I opponent always and for the candidate side in the I and L arms."""
    before = {s: dict(c) for s, c in (net.counts if net else {}).items()}
    log = []
    win = finish_ending(nm, sp, cores, pos, rng, tray, net, search, log)[2]
    calls = {s: c["calls"] - before.get(s, {"calls": 0})["calls"] for s, c in (net.counts if net else {}).items()}
    need = [3 - pos["mover"]] + ([pos["mover"]] if arm in ("I", "L") else [])
    ok = net is None or all(calls.get(s, 0) > 0 for s in need)
    return {"arm": arm, "y": 0.5 if win == "draw" else float(win == "p%d" % pos["mover"]), "valid": ok,
            "reason": None if ok else "net_inactive", "net_calls": calls, "search": log}


def ending_row(nm, sp, cores, pos, arm, r, net, ctx):
    """One endings row of the shared schema (lab2_rows): decisions timed, INVALID instead of a crash on a decline.
    ctx = {prereg, build, hdr: {"inc": sha, arm: sha}}."""
    import lab2_rows as rows
    mover = pos["mover"]
    rec = rows.Recorder(lambda side: arm if side == mover else "I", net)
    search = search_streams(nm, pos, arm, r) if arm != "I" else None
    before, t0 = {s: dict(c) for s, c in net.counts.items()}, time.perf_counter()

    def play():
        with rec.armed(sp):
            return run_ending(nm, sp, cores, pos, *eval_streams(nm, pos, r), arm, net, search)
    out, why = rows.guarded(nm, play)
    if out:
        rec.attach_search(out["search"])
    used = {str(s): {k: c[k] - before.get(s, {"calls": 0, "leaves": 0})[k] for k in ("calls", "leaves")}
            for s, c in net.counts.items()}
    seeds = {"eval_general": pos["eval"][r]["general"], "eval_tray": pos["eval"][r]["tray"]}
    if arm != "I":
        seeds["search_general"] = pos["search"][arm][r][str(mover)]
    ident = {"prereg_sha256": ctx["prereg"], "row_id": "%s_%s_r%d" % (pos["slot"], arm, r), "split": "D", "part": "A",
             "cell": pos["cell"], "source": pos["slot"], "arm": arm, "opponent": "I", "seat": mover, "replicate": r,
             "seeds": seeds}
    hdr = {str(mover): ctx["hdr"][arm], str(3 - mover): ctx["hdr"]["inc"]}
    ok = bool(out and out["valid"])
    return rows.make_row(ident, ctx["build"], net.model_sha256, hdr, used, rec, out["y"] if out else None,
                         None, ok, why or (out and out["reason"]), round(time.perf_counter() - t0, 3))


def arm_headers_differ_only_in_leaf(base, allowance_us):
    """The L and T knob sets (prereg section 6: same EV model and operator settings) differ ONLY in tree_leaf."""
    knobs = {a: dict(base["knobs"], **ARM_KNOBS[a], deadline_us=allowance_us) for a in ("L", "T")}
    return {k for k in set(knobs["L"]) | set(knobs["T"]) if knobs["L"].get(k) != knobs["T"].get(k)} == {"tree_leaf"}


def position_gains(y):
    """y[arm] = the 8 stream scores; a_X(p) = mean_r (Y_X - Y_Y) for the three registered contrasts."""
    return {n: statistics.fmean(a - b for a, b in zip(y[x], y[z])) for n, x, z in CONTRASTS}


def cell_key(cell):
    """c1 .. c12 numerically (a string sort puts c10 before c2)."""
    tail = str(cell).lstrip("c")
    return (0, int(tail), "") if tail.isdigit() else (1, 0, str(cell))


def order_stat(sorted_draws, q):
    """The 1-indexed round(q R)-th of R sorted draws, never interpolated: 500 / 99,500 of 100,000 at K=5."""
    return float(sorted_draws[max(1, round(q * len(sorted_draws))) - 1])


def bootstrap_intervals(gains, resamples=100_000, seed=0, k=5):
    """gains[cell][cluster] = {contrast: a}; cluster bootstrap within each cell (n_c clusters drawn with
    replacement, resample index first, then cell c1..c12 numerically, clusters in ID order), 100 x equal-cell mean.
    `seed` is the part's hashed bootstrap key (PCG64). Bounds: the Bonferroni K order statistics (0.005 / 0.995 at
    K=5) and the descriptive 95 % ones (2,500 / 97,500 of 100,000) of the same draws, plus the sha256 of the drawn
    index stream."""
    import hashlib
    import numpy as np
    rng, digest = np.random.Generator(np.random.PCG64(int(seed))), hashlib.sha256()
    cells = sorted(gains, key=cell_key)
    names = sorted(gains[cells[0]][sorted(gains[cells[0]])[0]])
    vec = {n: [np.array([gains[c][cl][n] for cl in sorted(gains[c])]) for c in cells] for n in names}
    draws = {n: np.empty(resamples) for n in names}
    for i in range(resamples):
        idx = [rng.integers(0, len(vec[names[0]][j]), len(vec[names[0]][j])) for j in range(len(cells))]
        for ix in idx:
            digest.update(ix.astype("<i8").tobytes())
        for n in draws:
            draws[n][i] = 100 * np.mean([vec[n][j][ix].mean() for j, ix in enumerate(idx)])
    q = (0.05 / k / 2, 1 - 0.05 / k / 2)  # alpha .05 / K = .01 two-sided -> the .005 and .995 order statistics
    out = {}
    for n, d in draws.items():
        d.sort()
        out[n] = {"point": 100 * float(np.mean([v.mean() for v in vec[n]])), "lo": order_stat(d, q[0]),
                  "hi": order_stat(d, q[1]), "lo95": order_stat(d, 0.025), "hi95": order_stat(d, 0.975),
                  "index_sha256": digest.hexdigest()}
    return out


def run_context(nm, prereg, net):
    """Identity every row carries: the prereg hash and the build stamp (commit, dirty, rules_epoch, wheel sha)."""
    stamp = env_stamp(nm, None, {})[0]
    return {"prereg": prereg, "build": {k: stamp[k] for k in ("commit", "dirty", "rules_epoch", "wheel_sha256")}}


def write_row(directory, row):
    path = os.path.join(directory, row["row_id"] + ".json")
    json.dump(row, open(path + ".tmp", "w"), sort_keys=True)
    os.replace(path + ".tmp", path)  # atomic per row


def _libs():
    import nml_core as nm  # lazy
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "core", "nml-core-py", "python"))
    import selfplay as sp
    from lab2_net import ShippedNet
    return nm, sp, ShippedNet


def _endings_init(cfg):
    """Once per worker: the core, the net, the headers and the row identity (one core + one net per worker)."""
    nm, sp, ShippedNet = _libs()
    net, base = ShippedNet(cfg["repo"]), json.load(open(cfg["header"]))
    headers = json.load(open(cfg["headers"])) if cfg.get("headers") else None
    return {"nm": nm, "sp": sp, "net": net, "core": make_core(nm, cfg["repo"], base, headers), "cfg": cfg,
            "allow": json.load(open(cfg["timing"])), "ctx": run_context(nm, cfg["prereg"], net)}


def _endings_work(w, cid, pos):
    """One complete position cluster: every arm x every replicate, every core under the position's own game header;
    rows written, y per arm returned."""
    src = source_of(pos)
    inc, inc_sha = w["core"]({}, src)
    y, bad, hdr = {}, [], {"inc": inc_sha}
    for arm in ARMS:
        cand, hdr[arm] = w["core"](dict(ARM_KNOBS[arm], **({"deadline_us": w["allow"][pos["cell"]]["B_us"]} if arm != "I" else {})), src)
        rows = [ending_row(w["nm"], w["sp"], {"inc": inc, "cand": cand}, pos, arm, r, w["net"], dict(w["ctx"], hdr=hdr))
                for r in range(STREAMS)]
        for row in rows:
            write_row(w["cfg"]["rows_dir"], row)
        bad += [row["row_id"] for row in rows if not row["valid"]]
        y[arm] = [row["y"] for row in rows]
    return {"y": y, "invalid": bad, "cell": pos["cell"], "cluster": pos["cluster"]}


def write_pilot_json(path, reports):
    """Per-worker VmHWM and their sum (P1 reads the peaks, P1's 6 GiB cap the sum)."""
    import lab2_pool
    peaks, total = lab2_pool.worker_hwms(reports)
    json.dump({"workers": len(peaks), "worker_hwm_mib": {str(k): v for k, v in peaks.items()}, "sum_hwm_mib": total},
              open(path, "w"), sort_keys=True)


def cmd_endings(a) -> int:
    import lab2_pool
    base, allow = json.load(open(a.header)), json.load(open(a.timing))
    positions = json.load(open(a.positions))
    os.makedirs(a.rows_dir, exist_ok=True)
    for cell in sorted({pos["cell"] for pos in positions}):
        if not arm_headers_differ_only_in_leaf(base, allow[cell]["B_us"]):
            print("[endings] STOP: the L and T headers of %s differ in more than tree_leaf" % cell)
            return 2
    if a.headers:
        missing = sorted({str(source_of(p)) for p in positions} - set(json.load(open(a.headers))))
        if missing:
            print("[endings] STOP: no recorded game header for %s" % missing)
            return 2
    cfg = {"repo": a.repo, "header": a.header, "headers": a.headers, "timing": a.timing, "rows_dir": a.rows_dir,
           "prereg": a.prereg_sha256}
    reports = lab2_pool.run_clusters({pos["slot"]: pos for pos in positions}, a.workers, _endings_init, _endings_work,
                                     (cfg,), key=a.scheduler_key)
    if a.pilot_json:
        write_pilot_json(a.pilot_json, reports)
    invalid = [i for r in reports for i in r["result"]["invalid"]]
    if invalid:
        print("[endings] INVALID rows (run continued): %s" % invalid)
        return 1
    gains = {}
    for r in reports:
        gains.setdefault(r["result"]["cell"], {})[r["result"]["cluster"]] = position_gains(r["result"]["y"])
    res = bootstrap_intervals(gains, a.resamples, a.seed)
    open(a.out, "w").write(canon({"gains": gains, "intervals": res}))
    print("[endings] " + canon(res))
    return 0


# ---- part B: the full games (PREREG section 8-9) ------------------------------------------------
B_ARMS = ("L", "C")
ALL_ARMS = ("I",) + B_ARMS


def row_search(block, arm, d, seat):
    """One game's registered search keys {owner: seed}. The adapter registers them per dice stream AND candidate
    seat, `search["d<d>c<seat>"][arm]` (prereg section 4: one stream per game/arm/owner). I searches nothing; a tree
    arm without its key refuses the whole manifest before any game is played."""
    if arm == "I":
        return {}
    keys = block["seeds"]["search"].get("d%dc%d" % (d, seat), {}).get(arm, {})
    if not keys and arm in ("L", "L_tray"):
        raise SystemExit("block %s has no registered search key d%dc%d/%s" % (block["block"], d, seat, arm))
    return keys


def game_rows(blocks, arms=ALL_ARMS):
    """The manifest: per block, per arm, two dice streams x candidate in seat 1 then 2 (4 games per arm/block; "I" =
    the incumbent pair on both seats, no deep core). Armies and terrain stay on their physical seats; only the
    policy swaps. A block carries cell, mission and seeds {terrain, layout, deploy, play_general[d], tray[d],
    search["d<d>c<seat>"][arm][owner]}; a row carries the seeds of its own dice stream and candidate seat."""
    return [{"row_id": "%s_%s_d%d_s%d" % (b["block"], arm, d, seat), "block": b["block"], "cell": b["cell"], "arm": arm,
             "mission": b["mission"], "seat": seat, "d": d, "army1": b["army1"], "army2": b["army2"],
             "seeds": {"terrain": b["seeds"]["terrain"], "layout": b["seeds"]["layout"], "deploy": b["seeds"]["deploy"],
                       "play_general": b["seeds"]["play_general"][d], "tray": b["seeds"]["tray"][d],
                       "search": row_search(b, arm, d, seat)}}
            for b in blocks for arm in arms for d in (0, 1) for seat in (1, 2)]


def arm_kwargs(row, allowance_us):
    """L: the tree on the candidate seat (10/3 = the incumbent pair); L_tray: L through the true tray (P9 MODE_B's
    control, `--arms L_tray`); C: the one-ply 32/3 rung. All carry the allowance as `deadline_us`, measured from
    the planner call."""
    if row["arm"] in ("L", "L_tray"):
        tray = {"deep_tree_dice": "tray"} if row["arm"] == "L_tray" else {}
        return dict(deep_top_k=10, deep_horizon=3, deep_search_mode="tree", deep_deadline_us=allowance_us, **tray)
    if row["arm"] != "C":
        raise ValueError("no fullgames arm %r" % row["arm"])
    return dict(deep_top_k=32, deep_horizon=3, deep_deadline_us=allowance_us)


def board_scores(done):
    """done: [(row, candidate-seat score)] -> {cell: {block: {B_LI: b_L - .5, B_LC: b_L - b_C}}} (a board is the cluster)."""
    by = {}
    for row, y in done:
        by.setdefault((row["cell"], row["block"]), {}).setdefault(row["arm"], []).append(y)
    out = {}
    for (cell, block), arms in by.items():
        if any(len(arms.get(x, ())) != 4 for x in B_ARMS):
            raise SystemExit("board %s has %s games, 4 per arm required" % (block, {k: len(v) for k, v in arms.items()}))
        bl, bc = statistics.fmean(arms["L"]), statistics.fmean(arms["C"])
        out.setdefault(cell, {})[block] = {"B_LI": bl - 0.5, "B_LC": bl - bc}
    return out


def play_row(nm, sp, row, repo, bank, knobs, net, allowance_us, ctx):
    """One full game of a manifest row on the live ledger, the step-10 seeds and the shipped net on BOTH seats,
    as a stage0-row/1 row. INVALID "net_inactive" unless the net priced leaves on both seats; a core decline
    or timeout is an INVALID row too and the run continues."""
    import lab2_rows
    seat, sd = row["seat"], row["seeds"]
    rec = lab2_rows.Recorder(lambda side: row["arm"] if row["arm"] != "I" and side == seat else "I", net)
    extra = dict(deep_player=seat, **arm_kwargs(row, allowance_us)) if row["arm"] != "I" else {}
    search = {int(s): int(k) for s, k in sd["search"].items()}
    before, t0 = {s: dict(c) for s, c in net.counts.items()}, time.perf_counter()

    def play():
        with rec.armed(sp):
            return sp.play_game(int(sd["terrain"]), row["army1"], row["army2"], repo, bank, None, mission=row["mission"],
                                objectives="mission", live_ledger=True, layout_seed=int(sd["layout"]),
                                deploy_seed=int(sd["deploy"]), play_seed=int(sd["play_general"]), dice_seed=int(sd["tray"]),
                                leaf_value_fn={1: net.hook(1), 2: net.hook(2)}, leaf_value_w=1.0,
                                **({"search_seeds": search} if search else {}), **extra, **knobs)
    res, why = lab2_rows.guarded(nm, play)
    used = {str(s): {k: c[k] - before.get(s, {"calls": 0, "leaves": 0})[k] for k in ("calls", "leaves")}
            for s, c in net.counts.items()}
    ok = bool(res) and all(used.get(str(s), {"calls": 0})["calls"] > 0 for s in (1, 2))
    why = why or (None if ok else "net_inactive")
    if res:
        rec.attach_logged_search(res.get("planner_positions", []))
    score_seat = 1 if row["arm"] == "I" else seat  # I/I: seat 1's score, descriptive
    y = None if not res else 0.5 if res["winner"] == "draw" else float(res["winner"] == "p%d" % score_seat)
    by_seat = (res or {}).get("knobs_by_seat", {})
    hdr = {str(s): lab2_rows.sha_of(by_seat.get(s) or by_seat.get(str(s)) or (res or {}).get("knobs", {})) for s in (1, 2)}
    seeds = {"terrain": sd["terrain"], "layout": sd["layout"], "deploy": sd["deploy"], "play_general": sd["play_general"],
             "tray": sd["tray"], **({"search_general": sd["search"][str(seat)]} if search else {})}
    ident = {"prereg_sha256": ctx["prereg"], "row_id": row["row_id"], "split": "D", "part": "B", "cell": row["cell"],
             "source": row["block"], "arm": row["arm"], "opponent": "I", "seat": seat, "replicate": row["d"], "seeds": seeds}
    return lab2_rows.make_row(ident, ctx["build"], net.model_sha256, hdr, used, rec, y, res and res["winner"], ok, why,
                              round(time.perf_counter() - t0, 3))


def i_seat1_means(done):
    """Descriptive only, never a contrast: the I/I mean seat-1 score per board -> {cell: {block: mean}}."""
    by = {}
    for row, y in done:
        if row["arm"] == "I":
            by.setdefault(row["cell"], {}).setdefault(row["block"], []).append(y)
    return {c: {b: statistics.fmean(v) for b, v in blocks.items()} for c, blocks in by.items()}


def control_scores(done, arm="L_tray"):
    """Descriptive only (P9 MODE_B): the control's candidate-seat score per board minus .5 -> {cell: {block: {..}}}."""
    by = {}
    for row, y in done:
        if row["arm"] == arm:
            by.setdefault(row["cell"], {}).setdefault(row["block"], []).append(y)
    return {c: {b: {arm + "_I": statistics.fmean(v) - 0.5} for b, v in bl.items()} for c, bl in by.items()}


def _fullgames_init(cfg):
    nm, sp, ShippedNet = _libs()
    net = ShippedNet(cfg["repo"])
    return {"nm": nm, "sp": sp, "net": net, "cfg": cfg, "allow": json.load(open(cfg["timing"])),
            "knobs": json.load(open(cfg["knobs"])), "ctx": run_context(nm, cfg["prereg"], net)}


def _fullgames_work(w, cid, rows):
    """One complete block cluster: every arm x dice x seat; a rerun resumes, never replays a valid game."""
    cfg, out = w["cfg"], []
    for row in rows:
        path = os.path.join(cfg["out_dir"], row["row_id"] + ".json")
        if not os.path.exists(path):
            write_row(cfg["out_dir"], play_row(w["nm"], w["sp"], row, cfg["repo"], cfg["bank"], w["knobs"], w["net"],
                                               w["allow"][row["cell"]]["B_us"], w["ctx"]))
        rec = json.load(open(path))
        out.append({"row_id": row["row_id"], "y": rec["y"], "valid": rec["valid"]})
    return out


def cmd_fullgames(a) -> int:
    import lab2_pool
    os.makedirs(a.out_dir, exist_ok=True)
    rows = game_rows(json.load(open(a.blocks)), tuple(a.arms.split(",")))
    by_id, blocks = {r["row_id"]: r for r in rows}, {}
    for r in rows:
        blocks.setdefault(r["block"], []).append(r)
    cfg = {"repo": a.repo, "timing": a.timing, "knobs": a.knobs, "bank": a.bank, "out_dir": a.out_dir, "prereg": a.prereg_sha256}
    reports = lab2_pool.run_clusters(blocks, a.workers, _fullgames_init, _fullgames_work, (cfg,), key=a.scheduler_key)
    if a.pilot_json:
        write_pilot_json(a.pilot_json, reports)
    results = {x["row_id"]: x for r in reports for x in r["result"]}
    done = [(by_id[i], results[i]["y"]) for i in by_id]
    invalid = [i for i, x in results.items() if not x["valid"]]
    if invalid:
        print("[fullgames] INVALID rows (run continued): %s" % invalid)
        return 1
    arms = {d[0]["arm"] for d in done}
    res = bootstrap_intervals(board_scores([d for d in done if d[0]["arm"] in B_ARMS]), a.resamples, a.seed) \
        if set(B_ARMS) <= arms else {}
    ctl = {"L_tray_descriptive_95": bootstrap_intervals(control_scores(done), a.resamples, a.seed, k=1)} \
        if "L_tray" in arms else {}
    open(a.out, "w").write(canon({"intervals": res, "I_seat1_descriptive": i_seat1_means(done), **ctl}))
    print("[fullgames] " + canon(res))
    return 0


def cmd_pilot(a) -> int:
    plan = {"transitions": a.count, "reds": ["RED-VP", "RED-DIE"], "workers": a.workers,
            "wall_hours": a.wall_hours, "rss_gib": a.rss_gib, "namespace": a.namespace}
    if a.dry_run:
        print("[pilot] dry-run plan: " + canon(plan))
        return 0
    import nml_core as nm  # lazy: a dry run needs no core
    stamp, bad = env_stamp(nm, a.net, {"commit": a.expect_commit, "rules_epoch": a.expect_epoch,
                                       "model_sha256": a.expect_model_sha, "wheel_sha256": a.expect_wheel_sha},
                           strict=True)
    if bad:
        print("[pilot] STOP: environment mismatch on %s: %s" % (bad, canon(stamp)))
        return 2
    recs = json.load(open(a.transitions))[: a.count]
    headers = json.load(open(a.headers or a.transitions + ".headers"))
    missing = sorted({str(source_of(r)) for r in recs} - set(headers))
    if missing:
        print("[pilot] STOP: no recorded game header for %s" % missing)
        return 2
    results, reds = replay_records(nm, a.repo, recs, headers)
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
    p.add_argument("--headers", default="", help="source -> recorded game header (default: <transitions>.headers)")
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
    p.add_argument("--expect-wheel-sha", help="sha256 of the loaded nml_core binary (the wheel's .so)")
    p.add_argument("--dry-run", action="store_true")
    t = sub.add_parser("timing")
    t.add_argument("--states", required=True, help="JSON list of {cell, state, player}")
    t.add_argument("--header", required=True, help="JSON header with a knobs block (the incumbent 10/3)")
    t.add_argument("--headers", default="", help="lab2_source's <transitions>.headers: each state's own game header")
    t.add_argument("--statics", default=None)
    t.add_argument("--per-cell", type=int, default=12)
    t.add_argument("--hardware", required=True, help="the hardware class label (m_h(c) is per class), stamped into the output")
    t.add_argument("--block-variance", default="", help='JSON {"A": {cell: s2}, "B": {cell: s2}}')
    t.add_argument("--repo", default=".")
    t.add_argument("--out", required=True)
    e = sub.add_parser("endings")
    e.add_argument("--positions", required=True, help="JSON list of {cell, cluster, mover, state, owners_before_round}")
    e.add_argument("--header", required=True)
    e.add_argument("--headers", default="", help="lab2_source's <transitions>.headers: each position's own game header")
    e.add_argument("--timing", required=True, help="the timing subcommand's .json (B_us per cell)")
    e.add_argument("--resamples", type=int, default=100_000)
    e.add_argument("--seed", type=int, default=0, help="PCG64 seed: part A hashed bootstrap key (decimal)")
    e.add_argument("--rows-dir", required=True, help="one stage0-row/1 JSON per ending")
    e.add_argument("--prereg-sha256", required=True)
    e.add_argument("--workers", type=int, default=1, help="spawn-mode workers over complete clusters (P1 fixes N)")
    e.add_argument("--scheduler-key", default="", help="the part's hashed scheduler key (decimal)")
    e.add_argument("--pilot-json", default="", help="write per-worker VmHWM and their sum")
    e.add_argument("--repo", default=".")
    e.add_argument("--out", required=True)
    f = sub.add_parser("fullgames")
    f.add_argument("--blocks", required=True, help="JSON list of {block, cell, mission, army1, army2, seeds}")
    f.add_argument("--timing", required=True)
    f.add_argument("--knobs", required=True, help="JSON of play_game kwargs of the shipped grade")
    f.add_argument("--arms", default="I,L,C", help='"I,L,C" (pilot) or "L,C" (confirmation)')
    f.add_argument("--bank", required=True)
    f.add_argument("--out-dir", required=True)
    f.add_argument("--resamples", type=int, default=100_000)
    f.add_argument("--seed", type=int, default=1, help="PCG64 seed: part B hashed bootstrap key (decimal)")
    f.add_argument("--prereg-sha256", required=True)
    f.add_argument("--workers", type=int, default=1, help="spawn-mode workers over complete clusters (P1 fixes N)")
    f.add_argument("--scheduler-key", default="", help="the part's hashed scheduler key (decimal)")
    f.add_argument("--pilot-json", default="", help="write per-worker VmHWM and their sum")
    f.add_argument("--repo", default=".")
    f.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    return {"timing": cmd_timing, "endings": cmd_endings, "fullgames": cmd_fullgames}.get(a.cmd, cmd_pilot)(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
