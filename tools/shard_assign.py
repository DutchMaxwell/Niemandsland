#!/usr/bin/env python3
"""Time-balanced gdUnit4 shard assignment (LPT), shared by the test job and the coverage guard.

  shard_assign.py --shards N --index I   print the *_test.gd suites of shard I, one per line
  shard_assign.py --shards N --check     prove every suite on disk lands in exactly one shard

Weights come from test/shard_weights.json (suite -> seconds, regenerated from a main run).
A new suite needs NO line there: a suite missing from the file gets the median weight and is
still assigned exactly once (--check prints how many suites sit at the median; the next
regeneration gives them a measured weight). A line for a suite that no longer exists fails
--check - delete the line together with the suite. Longest-processing-time-first: heaviest
suite into the lightest shard.
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


def default_weight(suites, weights):
    """The weight of a suite with no line: the median of the weights that exist."""
    known = [weights[s] for s in suites if s in weights]
    return statistics.median(known) if known else 1.0


def assign(suites, weights, shards):
    default = default_weight(suites, weights)
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
    unweighted = [s for s in suites if s not in weights]
    if unweighted:
        print(f"{len(unweighted)} unweighted suites at the median ({default_weight(suites, weights):g} s)")
    stale = sorted(set(weights) - set(suites), key=lambda s: s.encode())
    if stale:
        print(f"::error::{WEIGHTS} has lines for suites that no longer exist - delete them: {stale}")
    if missing or dupes or len(seen) != len(suites):
        print(f"::error::shard coverage broken - missing from every shard: {missing}, in several shards: {dupes}")
        return 1
    if stale:
        return 1
    print(f"OK: the {a.shards} shards cover every *_test.gd suite exactly once")
    return 0


if __name__ == "__main__":
    sys.exit(main())
