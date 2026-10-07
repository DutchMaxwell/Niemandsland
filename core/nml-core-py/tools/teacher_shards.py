#!/usr/bin/env python3
"""Shard packer + validator for teacher games (loop prep, 07.10.2026). A game = `<row_id>.npz` (netlab/SHARD_SCHEMA.md
packing + the teacher columns pi / tree_fired / v_root / v_pick / completed / outcome / side / round / seq) beside its
`<row_id>.json` (valid, winner, decisions). `shard` packs the VALID games, sorted by row_id, into
`teacher_shard_NNNNN.npz/.json` of `--shard-size` games, `game_id` = the game's index in that order (the json names the
games); only FULL shards unless `--final`; a shard whose json exists is skipped. Every shard passes `validate` first --
a tree row whose `pi` mass is not 1 or has no mass on its label, or a label outside its menu, refuses the shard by position.
  teacher_shards.py shard --games D --out S [--shard-size 500] [--final]      teacher_shards.py check --shard S.npz
"""
import argparse
import json
import os
import sys

import numpy as np

RAGGED = ("units", "objs", "terr", "cands")
FLAT = ("label", "glob", "actor", "target", "hand_score", "pi", "tree_fired", "v_root", "v_pick", "completed",
        "outcome", "side", "round", "seq")


def concat(games, game_ids):
    # Packed game arrays -> one packed shard: ptr columns re-based, `game_id` per position.
    out = {k: np.concatenate([z[k] for z in games]) for k in FLAT}
    out["game_id"] = np.concatenate([np.full(len(z["label"]), g, np.int32) for z, g in zip(games, game_ids)])
    for k in RAGGED:
        out[k] = np.concatenate([z[k] for z in games])
        ptrs, base = [np.zeros(1, np.int64)], 0
        for z in games:
            ptrs.append(z[k + "_ptr"][1:] + base)
            base += int(z[k + "_ptr"][-1])
        out[k + "_ptr"] = np.concatenate(ptrs)
    return out


def validate(z, name):
    # The checks a shard must pass (SystemExit names the first failing position).
    ptr, pi, fired, label = z["cands_ptr"], z["pi"].astype(np.float32), z["tree_fired"] > 0, z["label"]
    n = np.diff(ptr)
    if len(pi) != ptr[-1] or len(label) != len(n) or len(z["game_id"]) != len(n):
        raise SystemExit("%s: columns are not aligned (pi %d vs cands %d, labels %d)" % (name, len(pi), ptr[-1], len(label)))
    bad = np.flatnonzero((label < 0) | (label >= n))
    if len(bad):
        raise SystemExit("%s: position %d: label %d outside its %d-row menu" % (name, bad[0], label[bad[0]], n[bad[0]]))
    for i in np.flatnonzero(fired):
        seg = pi[ptr[i]:ptr[i + 1]]
        if abs(float(seg.sum()) - 1.0) > 0.02 or seg[label[i]] <= 0:
            raise SystemExit("%s: position %d: pi mass %.3f, mass on the label %.3f" % (name, i, seg.sum(), seg[label[i]]))
    return {"positions": int(len(n)), "tree_positions": int(fired.sum()), "games": int(len(np.unique(z["game_id"])))}


def valid_games(games_dir):
    names = sorted(f[:-5] for f in os.listdir(games_dir) if f.endswith(".json"))
    return [n for n in names if os.path.exists(os.path.join(games_dir, n + ".npz"))
            and json.load(open(os.path.join(games_dir, n + ".json"))).get("valid")]


def write_shard(base, games_dir, names, first_id):
    z = concat([np.load(os.path.join(games_dir, n + ".npz")) for n in names], range(first_id, first_id + len(names)))
    summary = validate(z, base)
    with open(base + ".npz.tmp", "wb") as fh:
        np.savez(fh, **z)
    os.replace(base + ".npz.tmp", base + ".npz")
    json.dump(dict(summary, schema="teacher-shard/1", games_named=names, game_id_base=first_id), open(base + ".json.tmp", "w"), indent=1)
    os.replace(base + ".json.tmp", base + ".json")
    return summary


def cmd_shard(a):
    games = valid_games(a.games)
    os.makedirs(a.out, exist_ok=True)
    new = total = 0
    for i in range(0, len(games), a.shard_size):
        chunk = games[i:i + a.shard_size]
        if len(chunk) < a.shard_size and not a.final:
            break
        base = os.path.join(a.out, "teacher_shard_%05d" % (i // a.shard_size))
        if not os.path.exists(base + ".json"):
            total += write_shard(base, a.games, chunk, i)["positions"]
            new += 1
    print("[shard] games=%d shards_new=%d positions_new=%d out=%s" % (len(games), new, total, a.out))
    return 0


def cmd_check(a):
    print("[check] %s" % json.dumps(validate(np.load(a.shard), a.shard), sort_keys=True))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("shard")
    s.add_argument("--games", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--shard-size", type=int, default=500)
    s.add_argument("--final", action="store_true", help="also write the trailing partial shard")
    sub.add_parser("check").add_argument("--shard", required=True)
    a = ap.parse_args(argv)
    return {"shard": cmd_shard, "check": cmd_check}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
