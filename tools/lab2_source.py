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
applied silently. Exit 1 when a slot is MISSING. With `--timing-out F` the same games also feed the timing set (first 12
legal pre-pick states per cell, all rounds); a cell below 12 fails the timing instrument (exit 1).
With `--transitions-out F` a core proxy (`Tap`) records the first 9 / 8 resolves per cell in the
`replay_transition` shape (+ `F.headers`: source -> the game header a replay needs); a cell below its quota exits 1.
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


class TimingSet:
    """The first `per_cell` legal pre-pick states of every cell, in source-game / activation order (the
    `--states` shape of lab2_tree_probe timing). A cell below `per_cell` fails the timing instrument."""

    def __init__(self, per_cell=12):
        self.per_cell, self.states, self.count = per_cell, [], {}

    def full(self, cell):
        return self.count.get(cell, 0) >= self.per_cell

    def add(self, rec):
        self.states.append(rec)
        self.count[rec["cell"]] = self.count.get(rec["cell"], 0) + 1

    def short(self, cells):
        return {c: self.count.get(c, 0) for c in sorted(cells) if not self.full(c)}


def default_quota(cell):
    """9 transitions in cells 1-4, 8 in cells 5-12 (100 in all); the cell label's digits are its number."""
    return 9 if int("".join(ch for ch in cell if ch.isdigit())) <= 4 else 8


class TransitionSet:
    """The first `quota(cell)` recorded resolves per cell, in source-game / activation order."""

    def __init__(self, quota=default_quota):
        self.quota, self.records, self.count, self.headers = quota, [], {}, {}  # headers: source -> game header

    def full(self, cell):
        return self.count.get(cell, 0) >= self.quota(cell)

    def add(self, rec):
        self.records.append(rec)
        self.count[rec["cell"]] = self.count.get(rec["cell"], 0) + 1

    def short(self, cells):
        return {c: self.count.get(c, 0) for c in sorted(cells) if not self.full(c)}


class Tap:
    """A core proxy for ONE source game: every call is the real core's; `resolve_with_tray` also records the
    `replay_transition` shape (before, action, streams before/after, tray faces consumed so far, rolls)."""

    def __init__(self, core, row, sink):
        self.core, self.row, self.sink, self.faces, self.seq, self.last = core, row, sink, 0, 0, None

    def __getattr__(self, name):
        return getattr(self.core, name)

    def set_header(self, header):  # `Core` has no header getter; a replay needs the game's own header
        if self.sink is not None:
            self.sink.headers[self.row["slot"] + ":" + self.row["candidate"]] = header
        return self.core.set_header(header)

    def streams(self):
        """The played streams NOW (None before the first resolve): what a continuation restores."""
        if self.last is None:
            return None
        return {"rng_state": self.last[0].state, "tray_state": self.last[1].state, "faces_before": self.faces,
                "dice_seed": int(self.row["tray"])}

    def resolve_with_tray(self, state, action, rng, tray):
        cell = self.row["cell"]
        keep = self.sink is not None and not self.sink.full(cell)
        self.last = (rng, tray)
        before = (state.plain(), rng.state, tray.state) if keep else None
        faces_before = self.faces
        nxt, rep = self.core.resolve_with_tray(state, action, rng, tray)
        self.seq += 1
        self.faces += sum(len(r["faces"]) for r in rep["rolls"])
        if keep:
            self.sink.add({"cell": cell, "source": self.row["slot"] + ":" + self.row["candidate"], "seq": self.seq,
                           "before": before[0], "action": action, "rng_state": before[1], "tray_state": before[2],
                           "faces_before": faces_before, "after": nxt.plain(), "rolls": rep["rolls"],
                           "tray_state_after": tray.state, "rng_state_after": rng.state,
                           "dice_seed": int(self.row["tray"])})
        return nxt, rep


class Spy:
    """State-only watcher for ONE source game: counts round ends, remembers the owners, and raises
    `_Eligible` at the first eligible pre-pick state. It never reads a game outcome."""

    def __init__(self, sp, row, timing=None):
        self.sp, self.row, self.timing, self.seq = sp, row, timing, 0
        self.ended, self.owners, self.total, self.stage = 0, None, None, 0

    def look(self, core, state, player):
        sp, row = self.sp, self.row
        if self.total is None:
            self.total = int(state.plain().get("rounds_total") or sp.ROUNDS)
        if self.timing is not None and state.pool(player, bool(core.knobs().get("hero_attach", True))):
            self.seq += 1  # every legal pre-pick state counts, collected or not
            if not self.timing.full(row["cell"]):
                self.timing.add({"cell": row["cell"], "source": row["slot"] + ":" + row["candidate"],
                                 "seq": self.seq, "state": state.plain(), "player": player})
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
                         "slot": row["slot"], "candidate": row["candidate"], "cell": row["cell"], "cluster": row["slot"],
                         "streams": core.streams() if isinstance(core, Tap) else None,
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


def source_kwargs(row, net, play_kw):
    """The `play_game` kwargs of one source game; `net=None` plays the hand planner (a test affordance)."""
    kw = dict(play_kw, mission=row["mission"], objectives="mission", live_ledger=True, dice="table",
              layout_seed=int(row["layout"]), deploy_seed=int(row["deploy"]), play_seed=int(row["play"]),
              dice_seed=int(row["tray"]))
    if net is not None:
        kw.update(leaf_value_fn={1: net.hook(1), 2: net.hook(2)}, leaf_value_w=1.0)
    return kw


def play_candidate(sp, core, row, repo, bank, lists, net, play_kw, timing=None, transitions=None):
    """One source game for one candidate row -> (snapshot or None, log row)."""
    spy, t0 = Spy(sp, row, timing), time.perf_counter()
    kw = source_kwargs(row, net, play_kw)
    snapshot, core = None, Tap(core, row, transitions)
    try:
        with spy.armed():
            sp.play_game(int(row["terrain"]), os.path.join(lists, row["list_p1"]), os.path.join(lists, row["list_p2"]),
                         repo, bank, core, **kw)
    except _Eligible as hit:
        snapshot = hit.snapshot
    log = {"slot": row["slot"], "candidate": row["candidate"], "wall_s": round(time.perf_counter() - t0, 3),
           "reason": None if snapshot else STAGES[spy.stage]}
    return snapshot, log


def generate(sp, core, slots, repo, bank, lists, net, cap, play_kw, timing=None, transitions=None):
    """-> (positions, discarded, missing slot ids). At most `cap` candidates per slot, first eligible wins."""
    positions, discarded, missing = [], [], []
    for slot, rows in slots.items():
        for row in rows[:cap]:
            snapshot, log = play_candidate(sp, core, row, repo, bank, lists, net, play_kw, timing, transitions)
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


def attach_eval(positions, path):
    """`eval[r] = {general, tray}` and `search[arm][r][owner]` (decimal key seeds, r 0..7) from the long-format
    D_endings_eval.tsv (columns cell, source, replicate, purpose, owner, arm, seed); a position matches on
    (cell, keys["source"])."""
    table = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            table[(r["cell"], r["source"], r["replicate"], r["purpose"], r.get("arm", ""), r.get("owner", ""))] = r["seed"]
    for pos in positions:
        k = (pos["cell"], pos["keys"].get("source"))
        try:
            pos["eval"] = [{"general": table[k + (str(i), "eval_general", "", "")], "tray": table[k + (str(i), "eval_tray", "", "")]}
                           for i in range(8)]
            pos["search"] = {arm: [{o: table[k + (str(i), "search_general", arm, o)] for o in ("1", "2")} for i in range(8)]
                             for arm in ("L", "T", "L_tray", "T_tray")}
        except KeyError as miss:
            raise SystemExit("no eval keys for position %s: %s" % (pos["slot"], miss))


def cmd_source(a):
    import nml_core as nm
    sys.path.insert(0, os.path.join(os.path.dirname(_HERE), "core", "nml-core-py", "python"))
    import selfplay as sp
    from lab2_net import ShippedNet
    knobs = json.load(open(a.header)).get("knobs", {})
    play_kw = {k: knobs[k] for k in HEADER_KNOBS if k in knobs}
    ignored = sorted(set(knobs) - set(HEADER_KNOBS))
    net = ShippedNet(a.repo)
    slots = read_slots(a.slots)
    timing = TimingSet() if a.timing_out else None
    transitions = TransitionSet() if a.transitions_out else None
    positions, discarded, missing = generate(sp, nm.load(a.repo), slots, a.repo, a.bank, a.lists, net, a.cap,
                                             play_kw, timing, transitions)
    if a.eval:
        attach_eval(positions, a.eval)
    out = {"positions": positions, "discarded": discarded, "missing": missing, "ignored_header_knobs": ignored,
           "net": net.proof()}
    json.dump(out, open(a.out, "w"))  # no sort_keys: net.proof() mixes int seats with a str key
    print("[source] positions %d discarded %d missing %s" % (len(positions), len(discarded), missing))
    short = timing.short({r["cell"] for rows in slots.values() for r in rows}) if timing else {}
    if timing:
        json.dump(timing.states, open(a.timing_out, "w"))
        print("[source] timing states %d, short cells %s" % (len(timing.states), short))
    cells = {r["cell"] for rows in slots.values() for r in rows}
    if transitions:
        json.dump(transitions.records, open(a.transitions_out, "w"))
        json.dump(transitions.headers, open(a.transitions_out + ".headers", "w"))
        short.update({"transitions " + c: n for c, n in transitions.short(cells).items()})
        print("[source] transitions %d, short cells %s" % (len(transitions.records), transitions.short(cells)))
    return 1 if missing or short else 0


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
    s.add_argument("--eval", help="D_endings_eval.tsv: attach the 8 eval stream keys to every position")
    s.add_argument("--transitions-out", help="write the first 9 (cells 1-4) / 8 (cells 5-12) resolves per cell")
    s.add_argument("--timing-out", help="write the first 12 legal pre-pick states per cell (timing --states shape)")
    s.add_argument("--repo", default=os.path.dirname(_HERE))
    return cmd_source(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
