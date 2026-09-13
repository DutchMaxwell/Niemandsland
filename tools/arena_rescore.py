#!/usr/bin/env python3
# Re-score arena A/B runs with a block-mean statistic that carries an interval.
#
# netlab/gen0/ab_score.py (the historical scorer) reports a paired-seed SIGN
# test over seed blocks and discards every tied block as uninformative, and it
# emits no confidence interval. That is why a measured +4.3-point arm
# (token_ab_d2mix_b_6f, 54.3 %, its own sign test p = 0.003) was filed as a null
# instead of as a real but sub-bar effect.
#
# This tool is deliberately SEPARATE from ab_score.py (a live agent owns that
# file). It reads the same raw arena_*.json files and reports, per arm: the
# per-seed block mean score % (ties carry their 0.5), block sd, SE, 95 % CI, z
# and two-sided p against 50 %, and the old sign test side by side.
#
# A block is one seed (all games sharing that seed field: for the 6-faction
# bank 2 dice seeds x 2 seat orders = 4 games; for the WIDE bank a single game,
# no seat swap). Equal weight per block, so an unequal game count per block
# cannot silently reweight the arm.
#
# Usage:
#   python3 tools/arena_rescore.py <dir> [<dir> ...] [--net GRADE] [--json OUT]

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import random
from collections import defaultdict

Z95 = 1.959963984540054


def two_sided_p(z: float) -> float:
    return math.erfc(abs(z) / math.sqrt(2.0))


def sign_p(plus: int, minus: int) -> float:
    # Exact two-sided sign-test p (doubles the smaller tail).
    m = plus + minus
    if m == 0:
        return 1.0
    k = min(plus, minus)
    tail = sum(math.comb(m, j) for j in range(0, k + 1)) / 2 ** m
    return min(1.0, 2.0 * tail)


def game_p1(record: dict, net: str):
    # (p1_score, net_is_p1) for a game that involves net, else None. Keeping the
    # winner in p1's frame (not folded onto the net) is what lets the
    # shuffled-winner placebo break the arm association; permuting net scores
    # would preserve the arm's mean exactly.
    grades = record.get("grades") or {}
    p1g, p2g = grades.get("p1"), grades.get("p2")
    if net not in (p1g, p2g):
        return None
    winner = record.get("winner")
    p1_score = 1.0 if winner == "p1" else 0.0 if winner == "p2" else 0.5
    return p1_score, p1g == net


def load_run(dirs, net: str = "token_value_v2"):
    # Collect one or more run directories into per-seed blocks (+ raw seat info).
    if isinstance(dirs, str):
        dirs = [dirs]
    blocks: dict = defaultdict(list)
    raw = []
    collisions = []
    seen_seed_dir: dict = {}
    total = skipped = 0
    for d in dirs:
        d = os.path.expanduser(d)
        for f in sorted(glob.glob(d + "/arena_*.json")):
            try:
                with open(f, "r", encoding="utf-8") as fh:
                    rec = json.load(fh)
            except (OSError, ValueError):
                skipped += 1
                continue
            got = game_p1(rec, net)
            if got is None:
                continue
            p1_score, net_is_p1 = got
            net_score = p1_score if net_is_p1 else 1.0 - p1_score
            total += 1
            seed = rec.get("seed")
            if seed in blocks and seen_seed_dir.get(seed) != d:
                collisions.append(seed)
            seen_seed_dir[seed] = d
            blocks[seed].append(net_score)
            raw.append((seed, net_is_p1, p1_score))
    return {"games": total, "skipped": skipped, "blocks": blocks, "raw": raw,
            "collisions": sorted(set(collisions)), "dirs": list(dirs)}


def block_stats(blocks) -> dict:
    # Block-mean statistic: score %, sd, SE, 95 % CI, z/p + the old sign test.
    means = [sum(v) / len(v) for v in blocks.values()]
    K = len(means)
    n = sum(len(v) for v in blocks.values())
    if K == 0:
        return {"K": 0, "n": 0}
    score = sum(means) / K
    if K > 1:
        var = sum((m - score) ** 2 for m in means) / (K - 1)
        sd = math.sqrt(var)
    else:
        sd = 0.0
    se = sd / math.sqrt(K)
    z = (score - 0.5) / se if se > 0 else 0.0
    plus = sum(1 for v in blocks.values() if sum(v) > len(v) / 2)
    minus = sum(1 for v in blocks.values() if sum(v) < len(v) / 2)
    return {
        "K": K, "n": n, "score": score, "block_sd": sd, "se": se,
        "ci_lo": score - Z95 * se, "ci_hi": score + Z95 * se,
        "z": z, "p": two_sided_p(z), "ci_excludes_50": abs(score - 0.5) > Z95 * se,
        "sign_plus": plus, "sign_minus": minus, "sign_ties": K - plus - minus,
        "sign_p": sign_p(plus, minus),
    }


def shuffle_blocks(run, seed: int):
    # Placebo: permute winners across games, keep each block's seats. The
    # shuffled arm must read ~50 % with a CI containing 50, else the harness is
    # biased and every verdict off it is void.
    rng = random.Random(seed)
    p1_scores = [p1 for (_, _, p1) in run["raw"]]
    rng.shuffle(p1_scores)
    out: dict = defaultdict(list)
    for (seed_key, net_is_p1, _), p1_score in zip(run["raw"], p1_scores):
        out[seed_key].append(p1_score if net_is_p1 else 1.0 - p1_score)
    return out


def format_run(name: str, st: dict) -> str:
    if st.get("K", 0) == 0:
        return name + ": no games"
    return (f"{name}: K {st['K']} blocks, n {st['n']} games  score {st['score']:.2%}  "
            f"sd {st['block_sd']:.4f}  SE {st['se'] * 100:.3f} pts  "
            f"95% CI [{st['ci_lo']:.2%}, {st['ci_hi']:.2%}]  z {st['z']:.2f}  p {st['p']:.4f}  "
            f"excl50={'YES' if st['ci_excludes_50'] else 'no'}  |  "
            f"sign {st['sign_plus']}/{st['sign_minus']}/{st['sign_ties']} p {st['sign_p']:.3f}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="block-mean A/B re-scorer with a 95% CI")
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--net", default="token_value_v2", help="grade label of the arm under test")
    ap.add_argument("--shuffle", type=int, default=None,
                    help="placebo: permute per-game winners with this RNG seed")
    args = ap.parse_args(argv)

    run = load_run(args.dirs, net=args.net)
    blocks = shuffle_blocks(run, args.shuffle) if args.shuffle is not None else run["blocks"]
    st = block_stats(blocks)
    name = "+".join(os.path.basename(d.rstrip("/")) for d in args.dirs)
    if args.shuffle is not None:
        name += f" [shuffled:{args.shuffle}]"
    print(format_run(name, st))
    if run["collisions"]:
        print(f"WARNING: {len(run['collisions'])} seed(s) in >1 dir: {run['collisions'][:10]}")
    return 0 if st.get("K", 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())