#!/usr/bin/env python3
"""Pilot report part 2 (PREREG_AILAB2_STAGE0 section 7): throughput, venue and fleet allocation.

Per (part, cell, arm) the unit time is 2 x the larger of the two D clusters' summed row times; a matched cluster costs the
sum over its arms (+ the A source generation: games per slot = 2 / the lower observed state-only yield of the slot's
(cell, mover) stratum, x its mean source-game time; zero yield fails). Clusters go to the currently least-loaded worker in
manifest order (tie: lowest worker ID); projected wall = the largest worker load + the measured overhead. P5 = laptop hours
on 4 workers; P6 = laptop when <= 12 h, else fleet; P7 = 1-4 cpx62 boxes x 4 workers, <= 40 STARTED box-hours at
EUR 0.2478: fewest wall hours, then fewest boxes, none -> COST_STOP. `arms` names the confirmation arms per part, selected P9
controls included (A: I, L, T [+ L_tray, T_tray]; B: L, C [+ L_tray]).
"""
import math

RATE_EUR = 0.2478
BOX_HOUR_CAP = 40
CELLS = ["c%d" % i for i in range(1, 13)]
A_SLOTS = [(c, k) for c in CELLS for k in range(1, 41)]
B_BLOCKS = [(c, k) for c in CELLS for k in range(1, 106 if c in ("c1", "c2") else 105)]


def schedule(costs, workers):
    """Complete clusters in manifest order to the least-loaded worker (tie: lowest ID) -> (loads, max load)."""
    loads = [0.0] * workers
    for c in costs:
        loads[loads.index(min(loads))] += c
    return loads, max(loads)


def venue(laptop_hours):
    return "laptop" if laptop_hours <= 12.0 else "fleet"


def unit_costs(rows):
    """{(part, cell, arm): 2 x the larger cluster's summed wall_s}."""
    per = {}
    for r in rows:
        k = (r["part"], r["cell"], r["arm"])
        per.setdefault(k, {}).setdefault(r["source"], 0.0)
        per[k][r["source"]] += r["wall_s"]
    return {k: 2 * max(v.values()) for k, v in per.items()}


def cluster_cost(units, part, cell, arms):
    return sum(units[(part, cell, a)] for a in arms)


def source_yield(logs):
    """{(cell, mover): (yield, mean wall_s)} from source logs {cell, mover, eligible, wall_s}."""
    per = {}
    for g in logs:
        per.setdefault((g["cell"], g["mover"]), []).append(g)
    return {k: (sum(1 for g in v if g["eligible"]) / len(v), sum(g["wall_s"] for g in v) / len(v)) for k, v in per.items()}


def fleet_choice(costs, overhead_s, cap=BOX_HOUR_CAP, speed=1.0):
    best = None
    for boxes in range(1, 5):
        hours = (schedule([c * speed for c in costs], 4 * boxes)[1] + overhead_s) / 3600
        started = boxes * math.ceil(hours)
        if started <= cap and (best is None or (hours, boxes) < (best["hours"], best["boxes"])):
            best = {"boxes": boxes, "workers": 4 * boxes, "hours": hours, "started_box_hours": started, "eur": started * RATE_EUR}
    return best


def report(rows, source_logs, overhead_s, arms, speed=1.0):
    units, problems, yields = unit_costs(rows), [], source_yield(source_logs)
    p4, costs = {}, []
    for part, slots in (("A", A_SLOTS), ("B", B_BLOCKS)):
        for cell, k in slots:
            missing = [a for a in arms[part] if (part, cell, a) not in units]
            if missing:
                problems.append("no pilot time for %s %s %s" % (part, cell, missing))
                continue
            cost = cluster_cost(units, part, cell, arms[part])
            if part == "A":
                y, wall = yields.get((cell, 1 + ((k - 1) // 2) % 2), (0.0, 0.0))
                if y <= 0:
                    problems.append("zero yield in stratum %s mover %d" % (cell, 1 + ((k - 1) // 2) % 2))
                    continue
                p4[(cell, 1 + ((k - 1) // 2) % 2)] = {"yield": y, "games_per_slot": 2 / y}
                cost += 2 / y * wall
            costs.append(cost)
    problems = sorted(set(problems))
    hours = (schedule(costs, 4)[1] + overhead_s) / 3600 if not problems else None
    where = venue(hours) if hours is not None else None
    fleet = fleet_choice(costs, overhead_s, speed=speed) if hours is not None else None
    verdict = "PILOT_STOP" if problems else "COST_STOP" if where == "fleet" and fleet is None else "OK"
    return {"verdict": verdict, "problems": problems, "p4": {"%s/%d" % k: v for k, v in p4.items()},
            "laptop_hours": hours, "venue": where, "fleet": fleet, "clusters": len(costs)}


def main(argv=None):
    import argparse
    import json
    import os
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", nargs="+", required=True, help="directories of stage0-row/1 JSON files (D pilot rows)")
    ap.add_argument("--source-logs", required=True, help="JSON list of {cell, mover, eligible, wall_s}")
    ap.add_argument("--overhead-s", type=float, required=True, help="measured startup + replay + scoring seconds")
    ap.add_argument("--arms", required=True, help='JSON {"A": [...], "B": [...]} confirmation arms incl. selected P9 controls')
    ap.add_argument("--speed", type=float, default=1.0, help="fleet box time / laptop time (default 1)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    rows = [json.load(open(os.path.join(d, f))) for d in a.rows for f in sorted(os.listdir(d)) if f.endswith(".json")]
    out = report(rows, json.load(open(a.source_logs)), a.overhead_s, json.loads(a.arms), a.speed)
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    print("[throughput] %s laptop_hours=%s venue=%s fleet=%s" % (out["verdict"], out["laptop_hours"], out["venue"], out["fleet"]))
    return 0 if out["verdict"] == "OK" else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
