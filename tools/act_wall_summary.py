#!/usr/bin/env python3
"""Summarise the [ACT_WALL] AI decision wait lines printed under NML_ACT_WALL=1.

Usage: python3 tools/act_wall_summary.py [--driver interactive|harness|any] [--json] <log> [<log> ...]
One summary line (acts, files, p50/p90/p99/max/mean ms, share over 1 s) + one line per round.
ms = floor(us/1000); percentile = nearest rank values[min(len-1, int(p*len))]; over1s = share
of decisions above 1,000,000 us, one decimal; files = logs contributing at least one line.
Exit 2 with "no [ACT_WALL] lines found" on stderr when nothing matched — a missing instrument
must be loud, never a silent zero.
"""

import argparse
import json
import re
import sys

RE = re.compile(r"\[ACT_WALL\] (interactive|harness) r(\d+) p(\d+) us=(\d+)")


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


def stats(us):
    ms = sorted(u // 1000 for u in us)

    def pick(p):
        return ms[min(len(ms) - 1, int(p * len(ms)))]

    over = float(f"{100.0 * sum(u > 1_000_000 for u in us) / len(ms):.1f}")
    return {"acts": len(ms), "p50_ms": pick(0.5), "p90_ms": pick(0.9),
            "p99_ms": pick(0.99), "max_ms": ms[-1],
            "mean_ms": (sum(us) // len(us)) // 1000, "over1s_pct": over}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="summarise [ACT_WALL] decision wait lines")
    ap.add_argument("logs", nargs="+", metavar="log")
    ap.add_argument("--driver", choices=("interactive", "harness", "any"), default="any")
    ap.add_argument("--json", action="store_true", help="one JSON object instead of lines")
    args = ap.parse_args(argv)
    acts, files = collect(args.logs, args.driver)
    if not acts:
        print("no [ACT_WALL] lines found", file=sys.stderr)
        return 2
    overall = stats([u for _, u in acts])
    rounds = {r: stats([u for rr, u in acts if rr == r]) for r in sorted({r for r, _ in acts})}
    if args.json:
        print(json.dumps({**overall, "files": files, "rounds": {
            str(r): {k: v[k] for k in ("acts", "p50_ms", "p90_ms")}
            for r, v in rounds.items()}}))
    else:
        print(f"acts={overall['acts']} files={files} p50={overall['p50_ms']} "
              f"p90={overall['p90_ms']} p99={overall['p99_ms']} max={overall['max_ms']} "
              f"mean={overall['mean_ms']} over1s={overall['over1s_pct']:.1f}%")
        for r, v in rounds.items():
            print(f"r{r}: acts={v['acts']} p50={v['p50_ms']} p90={v['p90_ms']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
