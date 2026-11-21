#!/usr/bin/env python3
"""Verdict of build.yml's "All required checks": every needed job is green, or skipped for a reason
the `changes` outputs prove. Env: NEEDS (toJSON(needs)), EVENT, REF, NOT_CORE_ONLY, RUST_RELEVANT.

A skip is green ONLY for the pairs below (they mirror the jobs' own `if:`); any other skip is red.
"""
import json
import os
import sys


def _fast_lane_pr(env):
    return env.get("EVENT") == "pull_request" and env.get("NOT_CORE_ONLY") != "true"


def _rust_not_needed(env):
    tag = env.get("REF", "").startswith("refs/tags/v")
    return not tag and (env.get("EVENT") != "pull_request" or env.get("RUST_RELEVANT") != "true")


SKIP_OK = {
    "core-linux": _fast_lane_pr,
    "core-py-linux": _fast_lane_pr,
    "test": _fast_lane_pr,
    "rust-gate": _rust_not_needed,
}


def verdict(env):
    bad = []
    for job, info in json.loads(env["NEEDS"]).items():
        result = info.get("result")
        print(f"{job}: {result}")
        if result == "success":
            continue
        if result == "skipped" and job in SKIP_OK and SKIP_OK[job](env):
            continue
        bad.append(f"{job}={result}")
    if bad:
        print("::error::required job(s) not green (or skipped without a path reason): " + ", ".join(bad))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(verdict(os.environ))
