#!/usr/bin/env python3
"""Compare the table's and the core's per-seed JSONL for ONE scenario (gate reading) and apply the exception list.

A seed matches when every roll agrees on (kind, count, target, faces, roller) and the survivors agree. Gate reading
(replay-gate convention): the table's special kinds fold to "attack", defense targets clamp to 2..6, "AI (<n>)" -> "<n>".

usage: parity_compare.py --table T.jsonl --core C.jsonl --scenario NAME --exceptions E.json --out RESULT.json
exit: 0 ok (no mismatch, or every mismatch excused); 1 mismatch, stale exception or future-dated exception;
      2 the two files do not cover the same seeds.
Exceptions only shrink: an entry whose scenario is now fully equal fails (stale), an entry dated after BASELINE fails.
"""
import argparse
import json

BASELINE = "2026-11-11"
FOLD = {k: "attack" for k in ("morale", "fearless", "no_retreat", "regeneration", "ravage", "battleborn", "dangerous")}


def load(path):
    rows = {}
    for line in open(path):
        if line.strip():
            r = json.loads(line)
            if r["seed"] in rows:
                raise SystemExit("duplicate seed %d in %s" % (r["seed"], path))
            rows[r["seed"]] = r
    return rows


def key(r, table):
    kind, target, owner = FOLD.get(r["kind"], r["kind"]), r["target"], r["owner"]
    if kind == "defense":
        target = min(max(target, 2), 6)
    if table and owner.startswith("AI (") and owner.endswith(")"):
        owner = owner[4:-1]
    return (kind, r["count"], target, tuple(r["faces"]), owner)


def same(t, c):
    return t["def_alive"] == c["def_alive"] and [key(r, True) for r in t["rolls"]] == [key(r, False) for r in c["rolls"]]


def main():
    ap = argparse.ArgumentParser()
    for flag in ("--table", "--core", "--scenario", "--exceptions", "--out"):
        ap.add_argument(flag, required=True)
    a = ap.parse_args()
    t, c = load(a.table), load(a.core)
    if set(t) != set(c):
        return print("FATAL: seed sets differ") or 2
    seeds = sorted(t)
    bad = [s for s in seeds if not same(t[s], c[s])]
    entries = json.load(open(a.exceptions))
    excused = [e for e in entries if e.get("scenario") == a.scenario]
    problems = ["exception %s is dated %s, after the baseline %s" % (e["id"], e["since"], BASELINE)
                for e in entries if e["since"] > BASELINE]
    if excused and not bad:
        problems.append("stale exception %s: scenario %s is now fully equal, delete the entry" % (
            excused[0]["id"], a.scenario))
    problems += ["%d of %d seeds differ" % (len(bad), len(seeds))] * bool(bad and not excused)
    json.dump({"scenario": a.scenario, "seeds": len(seeds), "identical": len(seeds) - len(bad),
               "mismatching_seeds": bad, "excused": bool(excused), "problems": problems,
               "first_mismatches": [{"seed": s, "table": t[s], "core": c[s]} for s in bad[:3]]},
              open(a.out, "w"), indent=1)
    for p in problems:
        print("PARITY FAIL [%s]: %s" % (a.scenario, p))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
