#!/usr/bin/env python3
"""Regenerate test/shard_weights.json from downloaded gdUnit4 shard job logs.

  gh api repos/<owner>/<repo>/actions/jobs/<job id>/logs > shard3.log      (one per shard job)
  shard_weights_from_logs.py shard*.log [-o test/shard_weights.json]

A suite's seconds = the timestamp of the next `Run Test Suite:` line (the `Overall Summary:` line
for the last suite of a log) minus its own. Logs of several runs are fine: the median per suite wins.
Suites that no longer exist on disk (cwd = repo root) are dropped, because shard_assign.py --check
rejects a weight line for a deleted suite; --keep-missing turns that off. Output format = the
existing file: sorted keys, one decimal, minimum 0.1.
"""
import argparse
import json
import os
import re
import statistics
import sys
from datetime import datetime, timezone

ANSI = re.compile(r"\x1b\[[0-9;]*m")
STAMP = r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?Z"
SUITE = re.compile(rf"^{STAMP} Run Test Suite: res://(\S+)")
SUMMARY = re.compile(rf"^{STAMP} Overall Summary:")


def epoch(sec, frac):
    t = datetime.strptime(sec, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    return t.timestamp() + (float("0." + frac) if frac else 0.0)


def suite_seconds(text):
    """{suite: seconds} of one log. A last suite without an Overall Summary line has no end: skipped."""
    starts, end = [], None
    for raw in text.splitlines():
        line = ANSI.sub("", raw).lstrip("\ufeff")
        m = SUITE.match(line)
        if m:
            starts.append((epoch(m[1], m[2]), m[3]))
            continue
        m = SUMMARY.match(line)
        if m:
            end = epoch(m[1], m[2])
    stops = [t for t, _ in starts[1:]] + ([end] if end is not None else [])
    return {path: stop - t for (t, path), stop in zip(starts, stops)}


def median_weights(logs):
    """The per-suite median over the given log texts, one decimal, minimum 0.1."""
    seen = {}
    for text in logs:
        for path, sec in suite_seconds(text).items():
            seen.setdefault(path, []).append(sec)
    return {p: max(0.1, round(statistics.median(v), 1)) for p, v in seen.items()}


def render(weights):
    body = ",\n".join(f'"{p}": {weights[p]:.1f}' for p in sorted(weights, key=lambda s: s.encode()))
    return "{\n" + body + "\n}\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("logs", nargs="+", help="downloaded gdUnit4 shard job logs")
    ap.add_argument("-o", "--output", help="write here instead of stdout")
    ap.add_argument("--keep-missing", action="store_true", help="keep suites that are not on disk")
    a = ap.parse_args()
    weights = median_weights([open(p, encoding="utf-8", errors="replace").read() for p in a.logs])
    if not a.keep_missing:
        gone = sorted(p for p in weights if not os.path.exists(p))
        weights = {p: w for p, w in weights.items() if p not in gone}
        if gone:
            print(f"dropped {len(gone)} suite(s) not on disk: {gone}", file=sys.stderr)
    out = render(weights)
    if a.output:
        open(a.output, "w", encoding="utf-8").write(out)
    else:
        sys.stdout.write(out)
    print(f"{len(weights)} suites, {sum(weights.values()):.0f} s of suite time", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
