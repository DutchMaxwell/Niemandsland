#!/usr/bin/env python3
"""Time-balanced gdUnit4 shard assignment (LPT), shared by the test job and the coverage guard.

  shard_assign.py --shards N --index I   print the *_test.gd suites of shard I, one per line
  shard_assign.py --shards N --check     prove every suite on disk lands in exactly one shard

Weights come from test/shard_weights.json (suite -> seconds, regenerated from a main run).
A suite missing from the file gets the median weight, so a new suite is still assigned
exactly once. Longest-processing-time-first: heaviest suite into the lightest shard.
"""
import argparse
import json
import statistics
import subprocess
import sys

WEIGHTS = "test/shard_weights.json"


def suites_on_disk():
    out = subprocess.run(["find", "test", "-name", "*_test.gd"], capture_output=True, text=True, check=True).stdout
    return sorted(out.split("\n")[:-1], key=lambda s: s.encode())


def assign(suites, weights, shards):
    known = [weights[s] for s in suites if s in weights]
    default = statistics.median(known) if known else 1.0
    load = [0.0] * shards
    out = [[] for _ in range(shards)]
    for s in sorted(suites, key=lambda s: (-weights.get(s, default), s.encode())):
        i = min(range(shards), key=lambda k: (load[k], k))
        out[i].append(s)
        load[i] += weights.get(s, default)
    return out, load


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", type=int, required=True)
    ap.add_argument("--index", type=int)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    suites = suites_on_disk()
    weights = json.load(open(WEIGHTS))
    shards, load = assign(suites, weights, a.shards)
    if not a.check:
        print("\n".join(sorted(shards[a.index], key=lambda s: s.encode())))
        return 0
    seen = [s for sh in shards for s in sh]
    for i, sh in enumerate(shards):
        print(f"shard {i}: {len(sh)} suite(s), {load[i]:.0f} s")
    missing = sorted(set(suites) - set(seen))
    dupes = sorted({s for s in seen if seen.count(s) > 1})
    print(f"*_test.gd files on disk: {len(suites)} | assigned: {len(seen)}")
    if missing or dupes or len(seen) != len(suites):
        print(f"::error::shard coverage broken - missing from every shard: {missing}, in several shards: {dupes}")
        return 1
    print(f"OK: the {a.shards} shards cover every *_test.gd suite exactly once")
    return 0


if __name__ == "__main__":
    sys.exit(main())
