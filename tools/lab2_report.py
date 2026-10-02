#!/usr/bin/env python3
"""Pilot report part 1 (PREREG_AILAB2_STAGE0 section 7): projected MDEs and one boolean per power/validity gate.

`part1(rows, validation_ok, ...)` takes stage0-row/1 rows. A: position gains a_T, a_L, a_TL (mean over replicates of the
paired difference); B: block gains b_LI = b_L - 0.5, b_LC = b_L - b_C (mean of a block's four candidate scores). Per contrast
and cell s_c^2 is the variance over the cell's two pilot clusters; V = sum_c (1/12)^2 s_c^2 / n_c (n_c = 40 for A, 105 in
c1/c2 and 104 elsewhere for B), MDE = 100 (z.995 + z.80) sqrt(F V), F = 12 / chi2(0.10, 12). Bars: A <= 3 each, B_LI <= 2,
B_LC reported only. Missing / invalid rows or a failed validation -> PILOT_STOP and every flag withheld.
Deadline gate: every decision that had an allowance has a finite elapsed time. RSS gate: workers x max VmHWM <= 6 GiB and
max VmHWM <= 512 MiB. All contrasts at zero variance pass only with `red_sensitive` (the RED fixtures showed arm sensitivity).
"""
import json
import math
import os
import statistics
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import lab2_tree_probe as lab  # noqa: E402
import lab2_validate as val  # noqa: E402

CELLS = ["c%d" % i for i in range(1, 13)]
EXPECT = {"A": 576, "B": 288}            # 24 clusters x 8 replicates x I/L/T ; 24 blocks x 4 games x I/L/C
BARS = {"A_T": 3.0, "A_L": 3.0, "A_TL": 3.0, "B_LI": 2.0}
F = 12 / lab.CHI2_Q10_DF12


def n_c(part, cell):
    return 40 if part == "A" else 105 if cell in ("c1", "c2") else 104


def _mean(xs):
    return sum(xs) / len(xs)


def gains(rows):
    """{contrast: {cell: {cluster: value}}} from the valid rows."""
    a, b = {}, {}
    for r in (r for r in rows if r.get("valid")):
        key = (r["cell"], r["source"])
        if r["part"] == "A":
            a.setdefault(key, {}).setdefault(r["arm"], {})[r["replicate"]] = r["y"]
        elif r["arm"] in ("L", "C"):
            b.setdefault(key, {}).setdefault(r["arm"], []).append(r["y"])
    out = {n: {} for n in ("A_T", "A_L", "A_TL", "B_LI", "B_LC")}
    for (cell, src), arms in a.items():
        for name, (x, y) in (("A_T", "TI"), ("A_L", "LI"), ("A_TL", "TL")):
            if x in arms and y in arms:
                out[name].setdefault(cell, {})[src] = _mean([arms[x][i] - arms[y][i] for i in arms[x] if i in arms[y]])
    for (cell, src), arms in b.items():
        if "L" in arms and "C" in arms:
            bl, bc = _mean(arms["L"]), _mean(arms["C"])
            out["B_LI"].setdefault(cell, {})[src], out["B_LC"].setdefault(cell, {})[src] = bl - 0.5, bl - bc
    return out


def mde(var_by_cell, part):
    v = sum((1 / 12) ** 2 * s2 / n_c(part, c) for c, s2 in var_by_cell.items())
    return 100 * (lab.Z_995 + lab.Z_80) * math.sqrt(F * v)


def part1(rows, validation_ok, red_sensitive=False, workers=1):
    problems = ["%s rows: %d valid of %d expected" % (p, sum(1 for r in rows if r["part"] == p and r.get("valid")), n)
                for p, n in EXPECT.items() if sum(1 for r in rows if r["part"] == p and r.get("valid")) != n]
    g = gains(rows)
    var, mdes = {}, {}
    for name, cells in g.items():
        var[name] = {c: (statistics.variance(list(cl.values())) if len(cl) == 2 else None) for c, cl in cells.items()}
        if set(cells) != set(CELLS) or None in var[name].values():
            problems.append("%s: not 2 clusters in every one of the 12 cells" % name)
            continue
        mdes[name] = mde(var[name], name[0])
    hwm = max([r.get("rss_hwm_mib") or 0 for r in rows] or [0])
    late = [d for r in rows for d in r.get("decisions") or () if d.get("allocated_us") is not None and not val._finite(d.get("elapsed_us"))]
    flags = {"rows_complete": not problems, "validated": bool(validation_ok), "deadlines": not late,
             "rss": workers * hwm <= 6144 and hwm <= 512,
             "zero_variance_shows_sensitivity": red_sensitive or any(s2 for v in var.values() for s2 in v.values() if s2),
             **{"mde_" + k: k in mdes and mdes[k] <= bar for k, bar in BARS.items()}}
    flags = val.pass_flags(validation_ok and not problems, flags)
    stop = not (validation_ok and not problems)
    return {"verdict": "PILOT_STOP" if stop else "PASS" if all(flags.values()) else "FAIL", "problems": problems,
            "mde": mdes, "variance": var, "n_c": {p: {c: n_c(p, c) for c in CELLS} for p in EXPECT}, "F": F,
            "flags": flags, "max_rss_mib": hwm, "late_decisions": len(late)}


def freeze(report, rows, p1=None, timing=None):
    """freeze.json: P1 (workers / RSS rule), P2 (the frozen allowances per cell), P3 (the variance inputs) + the raw gains."""
    return {"p1": p1, "p2": {c: v.get("B_us") for c, v in (timing or {}).items() if isinstance(v, dict)},
            "p3": {"variance": report["variance"], "n_c": report["n_c"], "F": report["F"]}, "raw_gains": gains(rows)}


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", nargs="+", required=True, help="directories of stage0-row/1 JSON files")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--red-sensitive", action="store_true")
    ap.add_argument("--p1", default="", help="the p1 rule's JSON (workers, rss)")
    ap.add_argument("--timing", default="", help="the timing subcommand's JSON (B_us per cell)")
    ap.add_argument("--out", required=True, help="pilot.json (freeze.json is written next to it)")
    a = ap.parse_args(argv)
    rows = [json.load(open(os.path.join(d, f))) for d in a.rows for f in sorted(os.listdir(d)) if f.endswith(".json")]
    ok, found = val.validate(rows, json.load(open(a.manifest)))
    out = dict(part1(rows, ok, a.red_sensitive, a.workers), validation_problems=found[:50])
    json.dump(out, open(a.out, "w"), indent=1, sort_keys=True)
    fz = freeze(out, rows, json.load(open(a.p1)) if a.p1 else None, json.load(open(a.timing)) if a.timing else None)
    json.dump(fz, open(os.path.join(os.path.dirname(os.path.abspath(a.out)), "freeze.json"), "w"), indent=1, sort_keys=True)
    print("[report] %s  MDE %s  flags false: %s" % (out["verdict"], {k: round(v, 3) for k, v in out["mde"].items()},
                                                    [k for k, v in out["flags"].items() if not v]))
    return 0 if out["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
