#!/usr/bin/env python3
"""Fresh full-game blocks for the teacher recorder (loop prep, 07.10.2026), in the stage-0 manifest shape
`tools/lab2_tree_probe.game_rows` reads: every seed derived from one base seed, terrain = a board id of `--bank`
(its own files), list pairs and missions cycled, search keys for the L, T and L_tray arms. Fresh seeds, never the
sealed stage-0 families (PREREG_AILAB2_STAGE0: reserved boards stay reserved).
  teacher_blocks.py --out B.json --n N --seed S --lists L1,L2[,..] --bank BANK [--missions duel,..]
"""
import argparse
import json
import os
import sys

import numpy as np

MISSIONS = ("duel", "pitched_battle", "seize_ground", "domination", "king_of_the_hill", "headquarters")


def make_blocks(n, seed, lists, bank, missions=MISSIONS):
    boards = sorted(int(f[6:-5]) for f in os.listdir(bank) if f.startswith("board_") and f.endswith(".json"))
    rng, out = np.random.default_rng(seed), []
    for i in range(n):
        s = int(rng.integers(1, 2 ** 62))
        keys = {"d%dc%d" % (d, c): {arm: {"1": str(s + 1000 + 100 * d + 10 * c + k), "2": str(s + 2000 + 100 * d + 10 * c + k)}
                                    for k, arm in enumerate(("L", "T", "L_tray"))} for d in (0, 1) for c in (1, 2)}
        out.append({"block": "G%06d" % i, "cell": "c%d" % (i % 4 + 1), "mission": missions[i % len(missions)],
                    "army1": lists[i % len(lists)], "army2": lists[(i + 1) % len(lists)],
                    "seeds": {"terrain": str(boards[int(rng.integers(len(boards)))]), "layout": str(s + 1), "deploy": str(s + 2),
                              "play_general": [str(s + 3), str(s + 4)], "tray": [str(s + 5), str(s + 6)], "search": keys}})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for k in ("--out", "--lists", "--bank"):
        ap.add_argument(k, required=True)
    ap.add_argument("--n", type=int, default=1)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--missions", default=",".join(MISSIONS))
    a = ap.parse_args(argv)
    blocks = make_blocks(a.n, a.seed, a.lists.split(","), a.bank, tuple(a.missions.split(",")))
    json.dump(blocks, open(a.out, "w"), indent=1, sort_keys=True)
    print("[blocks] %d blocks -> %s" % (len(blocks), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
