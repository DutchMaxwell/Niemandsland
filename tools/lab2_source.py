#!/usr/bin/env python3
"""D source generator for the stage-0 tree pilot (tree plan step 16, PREREG_AILAB2_STAGE0 section 8).

Per slot in manifest order and per candidate in frozen key order, plays an I/I source game with the
shipped net on both seats and the live mission ledger, and snapshots the FIRST pre-pick state of the
last round that is eligible: the slot's mover is to act, each side has 2-3 living unactivated units,
and the mover's menu holds >= 2 generated choices. Eligibility reads state only, the snapshot ends the
game, so no later outcome is ever computed. The first eligible candidate fills the slot; none within
`cap` -> the slot is MISSING. A candidate row carries slot, cell, mission, mover, candidate, list_p1,
list_p2 (file names under `lists`), terrain, layout, deploy, play, tray (decimal seeds); other columns
ride along as `keys`.

`source --slots D_sources.tsv --bank B --lists L --header I.json --cap 20 --out positions.json`: the slots
file is tab-separated, one row per (slot, candidate) with the columns above in frozen key order. Header: only
`top_k` / `horizon` of its knobs reach `play_game`; every other header knob is reported as ignored, never
applied silently. Exit 1 when a slot is MISSING.
Run: ~/.cache/nml-stage0/venv/bin/python3 tools/lab2_source.py source ...
"""
import argparse
import contextlib
import csv
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
POOL_RANGE = (2, 3)
#: The furthest check a last-round state got through, in order; the discard reason of an ineligible game.
STAGES = ("no_last_round_state", "mover_mismatch", "pool_size", "menu_lt_2")
REQUIRED = ("slot", "cell", "mission", "mover", "candidate", "list_p1", "list_p2",
            "terrain", "layout", "deploy", "play", "tray")
HEADER_KNOBS = ("top_k", "horizon")


class _Eligible(Exception):
    def __init__(self, snapshot):
        self.snapshot = snapshot


class Spy:
    """State-only watcher for ONE source game: counts round ends, remembers the owners, and raises
    `_Eligible` at the first eligible pre-pick state. It never reads a game outcome."""

    def __init__(self, sp, row):
        self.sp, self.row = sp, row
        self.ended, self.owners, self.total, self.stage = 0, None, None, 0

    def look(self, core, state, player):
        sp, row = self.sp, self.row
        if self.total is None:
            self.total = int(state.plain().get("rounds_total") or sp.ROUNDS)
        if self.ended + 1 != self.total or self.owners is None:
            return
        self.stage = max(self.stage, 1)
        if player != int(row["mover"]):
            return
        attach = bool(core.knobs().get("hero_attach", True))
        sizes = [len(state.pool(p, attach)) for p in (1, 2)]
        self.stage = max(self.stage, 2)
        if not all(POOL_RANGE[0] <= n <= POOL_RANGE[1] for n in sizes):
            return
        self.stage = max(self.stage, 3)
        menu = core.plan_with_rollout(state, player, sp.TRAINER_STATICS, cands=True)
        if not menu.get("used") or len(menu["trace"]["cands"]) < 2:
            return
        raise _Eligible({"state": state.plain(), "owners_before_round": list(self.owners), "mover": player,
                         "slot": row["slot"], "candidate": row["candidate"], "cell": row["cell"],
                         "keys": {k: v for k, v in row.items() if k not in REQUIRED}})

    @contextlib.contextmanager
    def armed(self):
        """`_pick_for` and `_round_end` wrapped for the `with` block only (both restored on the way out)."""
        sp, real_end = self.sp, self.sp._round_end

        def pick(core, state, player, *args, **kwargs):
            self.look(core, state, player)
            return real_pick(core, state, player, *args, **kwargs)

        def round_end(core, state, owners, led, round_no, *args, **kwargs):
            out = real_end(core, state, owners, led, round_no, *args, **kwargs)
            self.ended, self.owners = self.ended + 1, list(out[1])
            return out

        real_pick = sp._pick_for
        sp._round_end = round_end
        try:
            with sp.forced_picks(pick):
                yield
        finally:
            sp._round_end = real_end


def play_candidate(sp, core, row, repo, bank, lists, net, play_kw):
    """One source game for one candidate row -> (snapshot or None, log row)."""
    spy, t0 = Spy(sp, row), time.perf_counter()
    kw = dict(play_kw, mission=row["mission"], objectives="mission", live_ledger=True,
              layout_seed=int(row["layout"]), deploy_seed=int(row["deploy"]), play_seed=int(row["play"]),
              dice_seed=int(row["tray"]), leaf_value_fn={1: net.hook(1), 2: net.hook(2)}, leaf_value_w=1.0)
    snapshot = None
    try:
        with spy.armed():
            sp.play_game(int(row["terrain"]), os.path.join(lists, row["list_p1"]), os.path.join(lists, row["list_p2"]),
                         repo, bank, core, **kw)
    except _Eligible as hit:
        snapshot = hit.snapshot
    log = {"slot": row["slot"], "candidate": row["candidate"], "wall_s": round(time.perf_counter() - t0, 3),
           "reason": None if snapshot else STAGES[spy.stage]}
    return snapshot, log


def generate(sp, core, slots, repo, bank, lists, net, cap, play_kw):
    """-> (positions, discarded, missing slot ids). At most `cap` candidates per slot, first eligible wins."""
    positions, discarded, missing = [], [], []
    for slot, rows in slots.items():
        for row in rows[:cap]:
            snapshot, log = play_candidate(sp, core, row, repo, bank, lists, net, play_kw)
            if snapshot:
                positions.append(snapshot)
                break
            discarded.append(log)
        else:
            missing.append(slot)
    return positions, discarded, missing


def read_slots(path):
    """Slot id -> candidate rows in file order; the slot order is the order of first appearance."""
    with open(path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit("slots file lacks columns: " + ",".join(missing))
        slots = {}
        for row in reader:
            slots.setdefault(row["slot"], []).append(row)
    return slots


def cmd_source(a):
    import nml_core as nm
    sys.path.insert(0, os.path.join(os.path.dirname(_HERE), "core", "nml-core-py", "python"))
    import selfplay as sp
    from lab2_net import ShippedNet
    knobs = json.load(open(a.header)).get("knobs", {})
    play_kw = {k: knobs[k] for k in HEADER_KNOBS if k in knobs}
    ignored = sorted(set(knobs) - set(HEADER_KNOBS))
    net = ShippedNet(a.repo)
    positions, discarded, missing = generate(sp, nm.load(a.repo), read_slots(a.slots), a.repo, a.bank, a.lists,
                                             net, a.cap, play_kw)
    out = {"positions": positions, "discarded": discarded, "missing": missing, "ignored_header_knobs": ignored,
           "net": net.proof()}
    json.dump(out, open(a.out, "w"))  # no sort_keys: net.proof() mixes int seats with a str key
    print("[source] positions %d discarded %d missing %s" % (len(positions), len(discarded), missing))
    return 1 if missing else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("source")
    s.add_argument("--slots", required=True)
    s.add_argument("--bank", required=True)
    s.add_argument("--lists", required=True)
    s.add_argument("--header", required=True)
    s.add_argument("--cap", type=int, default=20)
    s.add_argument("--out", required=True)
    s.add_argument("--repo", default=os.path.dirname(_HERE))
    return cmd_source(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
