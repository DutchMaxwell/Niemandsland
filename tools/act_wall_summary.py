#!/usr/bin/env python3
"""Summarise the [ACT_WALL] AI decision wait lines printed under NML_ACT_WALL=1.

Usage: python3 tools/act_wall_summary.py [--driver interactive|harness|any] [--phases] [--json]
       <log> [<log> ...]
One summary line (acts, files, p50/p90/p99/max/mean ms, share over 1 s) + one line per round.
ms = floor(us/1000); percentile = nearest rank values[min(len-1, int(p*len))]; over1s = share
of decisions above 1,000,000 us, one decimal; files = logs contributing at least one line.
--phases additionally splits every [ACT_PHASE] line (the phase probes of one activation, no
driver on them, so --driver does not apply) into two blocks printed after the summary: all
activations and the slowest tenth = top max(1, int(0.1*n)) by total_us — one line per phase,
`<phase>: sum_ms=<int> share=<pct>% median_ms=<int>`, share = phase us sum / total_us sum of
the block (phases are nested probes, so shares may add up to more than 100 %), one decimal,
ordered by share descending; median = nearest-rank p50 of the per-act phase ms. --json adds
"phases": {"all": ..., "slowest10": ...} with acts and per-phase sum_ms/share_pct/median_ms.
Exit 2 with "no [ACT_WALL] lines found" on stderr when nothing matched — a missing instrument
must be loud, never a silent zero. --phases on a log without phase lines prints
"no [ACT_PHASE] lines found" on stderr and still exits 0 (the wall summary still counts),
2 when the wall summary is empty too.
"""

import argparse
import json
import re
import sys

RE = re.compile(r"\[ACT_WALL\] (interactive|harness) r(\d+) p(\d+) us=(\d+)")
RE_PHASE = re.compile(r"\[ACT_PHASE\] r(\d+) p(\d+) total_us=(\d+)")
RE_PAIR = re.compile(r"(\w+)=(\d+)")


def collect(paths, driver):
    # Matching lines of every log -> (round, us) acts; files = logs with >= 1 act.
    acts, files = [], 0
    for path in paths:
        n = 0
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = RE.search(line)
                if m and (driver == "any" or m.group(1) == driver):
                    acts.append((int(m.group(2)), int(m.group(4))))
                    n += 1
        files += bool(n)
    return acts, files


def collect_phases(paths):
    # Every [ACT_PHASE] line -> (total_us, {phase: us}) of the name=us pairs after total_us.
    rows = []
    for path in paths:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = RE_PHASE.search(line)
                if m:
                    pairs = {k: int(v) for k, v in RE_PAIR.findall(line[m.end():])}
                    rows.append((int(m.group(3)), pairs))
    return rows


def stats(us):
    ms = sorted(u // 1000 for u in us)

    def pick(p):
        return ms[min(len(ms) - 1, int(p * len(ms)))]

    over = float(f"{100.0 * sum(u > 1_000_000 for u in us) / len(ms):.1f}")
    return {"acts": len(ms), "p50_ms": pick(0.5), "p90_ms": pick(0.9),
            "p99_ms": pick(0.99), "max_ms": ms[-1],
            "mean_ms": (sum(us) // len(us)) // 1000, "over1s_pct": over}


def phase_block(rows):
    # (total_us, {phase: us}) rows -> {"acts": n, phase: {sum_ms, share_pct, median_ms}} by share.
    total = sum(t for t, _ in rows)
    block = {"acts": len(rows)}
    ordered = []
    for name in sorted({n for _, d in rows for n in d}):
        us = [d.get(name, 0) for _, d in rows]
        ms = sorted(u // 1000 for u in us)
        share = sum(us) / total
        ordered.append((share, name, {
            "sum_ms": sum(us) // 1000,
            "share_pct": float(f"{100.0 * share:.1f}"),
            "median_ms": ms[min(len(ms) - 1, int(0.5 * len(ms)))]}))
    for share, name, st in sorted(ordered, key=lambda e: (-e[0], e[1])):
        block[name] = st
    return block


def slowest_tenth(rows):
    # Top max(1, int(0.1*n)) activations by total_us, nearest rank after sorting.
    return sorted(rows, key=lambda r: -r[0])[:max(1, int(0.1 * len(rows)))]


def print_phase_block(label, block):
    print(f"phases {label} (acts={block['acts']}):")
    for name, st in block.items():
        if name != "acts":
            print(f"{name}: sum_ms={st['sum_ms']} share={st['share_pct']:.1f}% "
                  f"median_ms={st['median_ms']}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="summarise [ACT_WALL] decision wait lines")
    ap.add_argument("logs", nargs="+", metavar="log")
    ap.add_argument("--driver", choices=("interactive", "harness", "any"), default="any")
    ap.add_argument("--phases", action="store_true",
                    help="also split the [ACT_PHASE] lines by phase (--driver does not apply)")
    ap.add_argument("--json", action="store_true", help="one JSON object instead of lines")
    args = ap.parse_args(argv)
    acts, files = collect(args.logs, args.driver)
    phases = collect_phases(args.logs) if args.phases else []
    if not acts:
        print("no [ACT_WALL] lines found", file=sys.stderr)
        if args.phases and not phases:
            print("no [ACT_PHASE] lines found", file=sys.stderr)
        return 2
    overall = stats([u for _, u in acts])
    rounds = {r: stats([u for rr, u in acts if rr == r]) for r in sorted({r for r, _ in acts})}
    if args.phases and not phases:
        print("no [ACT_PHASE] lines found", file=sys.stderr)
    if args.json:
        obj = {**overall, "files": files, "rounds": {
            str(r): {k: v[k] for k in ("acts", "p50_ms", "p90_ms")}
            for r, v in rounds.items()}}
        if phases:
            obj["phases"] = {"all": phase_block(phases),
                             "slowest10": phase_block(slowest_tenth(phases))}
        print(json.dumps(obj))
    else:
        print(f"acts={overall['acts']} files={files} p50={overall['p50_ms']} "
              f"p90={overall['p90_ms']} p99={overall['p99_ms']} max={overall['max_ms']} "
              f"mean={overall['mean_ms']} over1s={overall['over1s_pct']:.1f}%")
        for r, v in rounds.items():
            print(f"r{r}: acts={v['acts']} p50={v['p50_ms']} p90={v['p90_ms']}")
        if phases:
            print_phase_block("all", phase_block(phases))
            print_phase_block("slowest10", phase_block(slowest_tenth(phases)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
