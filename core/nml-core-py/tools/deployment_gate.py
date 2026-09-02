#!/usr/bin/env python3
"""Deployment gate — per-unit pregame parity over the whole fixture (NML-1152 step 9).

For every dump in the committed fixture extracts (core/nml-core/tests/fixtures/
pregame_*.json, sanitized from tools/pregame_dump.gd's raw dumps) the gate runs
the twin's pipeline from the same inputs — roll-off over py `Rng` FIRST
(game stream, tie re-roll), `deploy_side` per side, `deploy_finish` with the
twin's own winner as first slot — and compares:

- roll-off attempts + opener EXACT; deploy order (winner first) EXACT;
- per unit: spot EXACT at the dump's 1e-4 snappedf quantum / within one
  0.025 m scan step / MISMATCH; settled models pairwise EXACT;
- per side (hard fails): fills, reserved, seed_value, sections, placement order;
- `interleave_order` (hard fail): the dump's CROSS-SIDE `placement_sequence`
  against the rulebook's own order (GF v3.5.1 p.6) derived from the two sides'
  placement orders — winner first, one unit each in turn, the Scout phase (B9)
  after BOTH armies' normals. Whole-side deployment reads 1,1,1,2,2,2 and
  fails. A dump WITHOUT the field is counted `pending`, never `OK`: every
  committed dump predates tools/pregame_dump.gd's `placement_sequence` (#575)
  and was recorded whole-side, so the class goes green only on a re-recorded
  fixture. RED knob --red-whole-side synthesizes that whole-side order for
  every dump and requires the class to reject all of them.

Dumps are processed one by one and carry their own lists tag — position records
are NEVER joined by seed alone: the fixture carries BOTH seat orders per seed
(step-7 finding). The roll-off / board / bank lookups join by seed (layout
seed for boards) and are seat-order invariant (same game seed -> same draws).

N/N summary lines per class + per side. BASELINE below is the recorded
step-6e pipeline result on the full corpus — the baked floor: a full-corpus
run that regresses below any floor exits non-zero. `within` needs no floor of
its own: exact >= 921 and mismatch <= 115 imply within <= 24 at 1060 units.
Partial corpora print the floor SKIPPED. Exit 0 green / 1 red / 2 error.

RED knob --red-shift N: shift every twin spot by N * 0.025 m (x) after the
pipeline. Red = the EXACT count collapses below its no-shift level (full
corpus: the baked 921; partial corpus: zero) — exit 1 as designed. Measured
aliasing on the real corpus: within-class units whose recorded truth sits
exactly one +x step off the twin snap back to EXACT under the shift (12 of
1060) — the shift cannot be direction-agnostic, so "everything leaves EXACT"
holds for the 921 aligned units and the collapse carries the proof.

--bank-dir DIR: load the prop layer (walls/blockers/blocker_boxes) per
layout-seed board (500000+seed) from an UNCOMMITTED terrain_bank_v2 dump
(board_<layout_seed>.json) instead of the committed pregame_bank_v2.json
extract. The twin's RUNTIME bank is game-seed keyed (board_<seed>.json =
generate(seed)) and carries no v2 props (step-8 UNSURE (a)); the committed
extract is the fixture's sanitized layout-seed subset. Never commit new
boards — point --bank-dir at the dump.
"""
import argparse
import json
import math
import os
import struct
import sys

import nml_core

FIXTURES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "core", "nml-core", "tests", "fixtures"
)
SCAN_STEP = 0.025
DUMP_QUANT = 1.5e-4
ZONES = {"1": [-0.9144, -0.6096, 1.8288, 0.3048], "2": [-0.9144, 0.3048, 1.8288, 0.3048]}
ZONE_STYLE = {"zones": {"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
                        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]]}}
# Recorded step-6e pipeline numbers on the full fixture (200 sides, 1060 placed
# units) — the floor no class may regress below on a full-corpus run.
BASELINE = {"units": 1060, "exact": 921, "within": 24, "mismatch": 115, "models": 889, "sides": 117}


def f32(v):
    return struct.unpack("f", struct.pack("f", v))[0]


def quant(v):
    return math.floor(v / 1e-4 + 0.5) * 1e-4  # Godot snappedf(v, 0.0001)


def roll_off(seed):
    """ai_deployment law over the game stream: d6 pair per attempt, ties re-roll, cap 100."""
    rng = nml_core.Rng(seed)
    attempts = []
    while len(attempts) < 100:
        a, b = rng.randi_range(1, 6), rng.randi_range(1, 6)
        attempts.append([a, b])
        if a != b:
            break
    return attempts, (1 if attempts[-1][0] > attempts[-1][1] else 2)


def expected_interleave(orders, scouts, first):
    """The rulebook's cross-side placement order (GF v3.5.1 p.6) DERIVED from
    the two sides' own `placement_order`s — data the gate already proves the
    twin reproduces exactly. The winner places one unit, the opponent places
    one, alternating; a side whose queue has run dry is skipped, so the longer
    roster finishes alone; the Scout phase (B9) runs after BOTH armies' normals.
    `orders` maps slot -> placement order, `scouts` slot -> its scout keys."""
    seq = []
    lead = str(first)
    other = "1" if lead == "2" else "2"
    for scout_phase in (False, True):
        q = {s: [k for k in orders[s] if (k in scouts[s]) == scout_phase] for s in ("1", "2")}
        at = {"1": 0, "2": 0}
        while any(at[s] < len(q[s]) for s in ("1", "2")):
            for s in (lead, other):
                if at[s] < len(q[s]):
                    seq.append((int(s), q[s][at[s]]))
                    at[s] += 1
    return seq


def whole_side_sequence(dump, first):
    """What a PRE-#575 dump recorded, made explicit: the winner's whole army,
    then the other's. The RED knob's input — the deviation the class rejects."""
    return [(int(s), k) for s in (str(first), str(3 - first))
            for k in dump["sides"][str(s)]["placement_order"]]


def bank_props(bank_dir, board_key):
    b = json.load(open(os.path.join(bank_dir, "board_%s.json" % board_key)))
    return b["walls"], b["blockers"], b["blocker_boxes"]


def run_dump(dump, cells, cell_params, bank, red_shift):
    """The twin's pipeline on one dump's inputs -> (attempts, opener, finished, side_deploy)."""
    board_json = {"cells": cells, "sandbox": [], "cell_params": cell_params}
    board = nml_core.board(board_json)
    board.set_bank_props(*bank)
    lay = nml_core.objective_layout(board_json, 500000 + dump["seed"], "d3+2", ZONE_STYLE, 72.0, 48.0)
    objectives = [[f32(x * 0.0254), f32(z * 0.0254)] for x, z in lay["positions"]]
    attempts, opener = roll_off(dump["seed"])  # FIRST from the game stream (step-8 flow)
    sides, sds = {}, {}
    for slot in ("1", "2"):
        side = dump["sides"][slot]
        units = []  # full roster incl. ambush rows (reserved: no geometry, empty shapes)
        for row in side["roster"]:
            g = side["units"].get(row[0])
            units.append(
                {"key": row[0], "model_count": g["n_models"], "base_r_m": g["base_r_m"],
                 "footprint": g["footprint"], "scout": row[1], "ambush": row[2],
                 "ignores_terrain": g["ignores_terrain"], "vanguard": g["vanguard_pushed"],
                 "transport_capacity": 0, "facing_rad": g["facing_rad"], "model_shapes": g["model_shapes"]}
                if g else
                {"key": row[0], "model_count": 0, "base_r_m": 0.0, "footprint": [], "scout": row[1],
                 "ambush": row[2], "ignores_terrain": False, "vanguard": False,
                 "transport_capacity": 0, "facing_rad": 0.0, "model_shapes": []})
        sd = nml_core.deploy_side(units, ZONES[slot], objectives, board, side["seed_value"])
        sds[slot] = sd
        sides[slot] = {"units": units, "placements": sd["placements"], "zone": ZONES[slot]}
    trays = {slot: [m for row in dump["sides"][slot]["tray_models"] for m in row["models"]]
             for slot in ("1", "2")}
    finished = nml_core.deploy_finish(sides, board, trays, opener)
    if red_shift:  # RED knob: every twin spot one grid step off the recorded truth
        for plist in finished.values():
            for p in plist:
                p["spot"][0] += red_shift * SCAN_STEP
    return attempts, opener, finished, sds


def compare_dump(dump, roll, run, red_whole_side=False):
    """One dump vs the twin: per-unit classes + hard structural fails."""
    attempts, opener, finished, sds = run
    c = dict(units=0, exact=0, within=0, mismatch=0, models=0, models_exact=0,
             sides=0, sides_all=0, roll_ok=0, order_ok=0, struct_ok=0,
             inter_ok=0, inter_fail=0, inter_pending=0)
    # interleave_order: the recorded CROSS-SIDE order against the rulebook's.
    first = roll["deploy_order"][0]
    got = dump.get("placement_sequence")
    if got is None and red_whole_side:
        got = whole_side_sequence(dump, first)
    if got is None:
        c["inter_pending"] = 1   # pre-#575 recording — whole-side, no field to read
    else:
        want = expected_interleave(
            {s: dump["sides"][s]["placement_order"] for s in ("1", "2")},
            {s: {k for k, u in dump["sides"][s]["units"].items() if u["scout"]}
             for s in ("1", "2")},
            first)
        ok = [(int(a), b) for a, b in got] == want
        c["inter_ok"], c["inter_fail"] = int(ok), int(not ok)
    c["roll_ok"] = int(attempts == roll["attempts"] and opener == roll["opener"])
    c["order_ok"] = int([opener, 3 - opener] == roll["deploy_order"])
    struct_ok = True
    for slot in ("1", "2"):
        side, sd = dump["sides"][slot], sds[slot]
        ok = (sd["fills"] == side["fills"] and sd["reserved"] == side["reserved"]
              and sd["seed_value"] == side["seed_value"]
              and [p["key"] for p in finished[slot]] == side["placement_order"]
              and all(p["section"] == side["units"][p["key"]]["section"] for p in finished[slot]))
        struct_ok &= ok
        side_all = ok
        for p in finished[slot]:
            u = side["units"][p["key"]]
            c["units"] += 1
            if abs(quant(p["spot"][0]) - quant(u["spot"][0])) < 1e-9 \
                    and abs(quant(p["spot"][1]) - quant(u["spot"][1])) < 1e-9:
                c["exact"] += 1
            else:
                d = math.hypot(p["spot"][0] - u["spot"][0], p["spot"][1] - u["spot"][1])
                c["within" if d <= SCAN_STEP + DUMP_QUANT else "mismatch"] += 1
                side_all = False
            c["models"] += 1
            if len(p["models"]) == len(u["models"]) and all(
                    abs(quant(t[0]) - quant(m[0])) < 1e-9 and abs(quant(t[1]) - quant(m[1])) < 1e-9
                    for t, m in zip(p["models"], u["models"])):
                c["models_exact"] += 1
        c["sides"] += 1
        c["sides_all"] += side_all
    c["struct_ok"] = int(struct_ok)
    return c


# === ARRIVAL (S4, SPEC_rule_ambush_arrival_2026-09-02.md §4) ===================================
# Oracle: core/nml-core/tests/fixtures/ambush_arrival.json (tools/ambush_arrival_dump.gd,
# READ-ONLY against the table's shipped SoloController.arrive_one_ambush_unit). Same vocabulary
# as the pregame gate above — exact (DUMP_QUANT) / within (one SCAN_STEP) / mismatch — plus HELD
# (both the table and the twin answer "no legal spot"; one side holding while the other places is
# a MISMATCH, never a HELD — SPEC §6.2). CONTRACT for the twin, which has NOT landed as this
# section was written (S1-S3 build in parallel): nml_core.arrive_one(zone, objectives, occupied,
# enemies, own_ring_m, radius, footprint, base_r, flying) -> [x, y] | None, `radius` = the
# ALREADY-PORTED deploy_footprint_radius (solo_controller.gd:10258-10265, reused unchanged per
# SPEC §3) computed by radius_of() below. Beacon geometry is out of scope (SPEC §2.5 decision 2)
# — the fixture carries none, and every case here passes none.

def radius_of(n_models, base_r):
    n = max(n_models, 1); cols = min(n, 5); rows = -(-n // cols)
    return math.hypot((cols - 1) * 0.02, (rows - 1) * 0.02) + base_r + 0.01   # DEPLOY_SPACING_M 0.04, halved


def arrival_class(truth, twin):
    if truth is None and twin is None: return "held"
    if truth is None or twin is None: return "mismatch"
    if abs(quant(twin[0]) - quant(truth[0])) < 1e-9 and abs(quant(twin[1]) - quant(truth[1])) < 1e-9: return "exact"
    return "within" if math.hypot(twin[0] - truth[0], twin[1] - truth[1]) <= SCAN_STEP + DUMP_QUANT else "mismatch"


def run_arrival(cases, fn, red_shift):
    c = dict(exact=0, within=0, mismatch=0, held=0)
    for case in cases:
        twin = None
        if fn is not None:
            twin = fn(case["zone"], case["objectives"], [dict(o) for o in case["occupied"]], [dict(e) for e in case["enemies"]],
                      case["own_ring_m"], radius_of(len(case["footprint"]), case["base_r"]), case["footprint"], case["base_r"], case["flying"])
            if twin is not None and red_shift: twin = [twin[0] + red_shift * SCAN_STEP, twin[1]]
        c[arrival_class(case["spot"], twin)] += 1
    return c


def main_arrival(args):
    cases = json.load(open(os.path.join(args.fixtures, "ambush_arrival.json")))["cases"]
    fn = getattr(nml_core, "arrive_one", None)   # import guard — the twin may not exist yet
    c = run_arrival(cases, fn, args.arrival_red_shift)
    n = len(cases)
    print("ARRIVAL %d cases: %d exact | %d within | %d mismatch | %d held" % (n, c["exact"], c["within"], c["mismatch"], c["held"]))
    if fn is None:
        print("ARRIVAL: nml_core.arrive_one absent (deployment::arrive_one not landed) — fixture loaded, cases ran the stub (every case mismatch/held) — NO VERDICT, refusing a pass")
        return 2
    if args.arrival_red_shift:
        red = c["exact"] == 0
        print("ARRIVAL RED knob %d: exact %d — %s" % (args.arrival_red_shift, c["exact"], "collapsed, exit 1 as designed" if red else "INERT — RED proof FAILED"))
        return 1 if red else 2
    ok = c["mismatch"] == 0   # SPEC §6.2: mismatch == 0 alone implies every held case agreed too
    print("ARRIVAL %s" % ("floor OK" if ok else "floor REGRESSION"))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="deployment parity gate (NML-1152 step 9)")
    ap.add_argument("--fixtures", default=FIXTURES, help="dir holding the pregame_* extract JSONs")
    ap.add_argument("--bank-dir", default=None, help="uncommitted terrain_bank_v2 dump (layout-seed boards)")
    ap.add_argument("--red-shift", type=int, default=0, metavar="N",
                    help="RED knob: shift every twin spot by N * 0.025 m")
    ap.add_argument("--red-whole-side", action="store_true",
                    help="RED knob: feed interleave_order the pre-#575 whole-side order")
    ap.add_argument("--arrival", action="store_true",
                    help="run the ARRIVAL section (ambush_arrival.json) instead of the pregame gate")
    ap.add_argument("--arrival-red-shift", type=int, default=0, metavar="N",
                    help="ARRIVAL's own RED knob: shift every twin spot by N * 0.025 m")
    args = ap.parse_args(argv)
    if args.arrival:
        return main_arrival(args)

    dumps = json.load(open(os.path.join(args.fixtures, "pregame_pipeline.json")))
    rolls = {r["seed"]: r for r in json.load(open(os.path.join(args.fixtures, "pregame_roll_off.json")))}
    spots = json.load(open(os.path.join(args.fixtures, "pregame_deploy_spots.json")))
    banks = json.load(open(os.path.join(args.fixtures, "pregame_bank_v2.json")))["boards"]
    tot = {k: 0 for k in ("dumps", "units", "exact", "within", "mismatch", "models", "models_exact",
                          "sides", "sides_all", "roll_ok", "order_ok", "struct_ok",
                          "inter_ok", "inter_fail", "inter_pending")}
    lines = []
    for dump in dumps:
        key = str(500000 + dump["seed"])
        bank = bank_props(args.bank_dir, key) if args.bank_dir else (
            banks[key]["walls"], banks[key]["blockers"], banks[key]["blocker_boxes"])
        board = spots["boards"][key]
        run = run_dump(dump, board["cells"], spots["cell_params"], bank, args.red_shift)
        c = compare_dump(dump, rolls[dump["seed"]], run, args.red_whole_side)
        tot["dumps"] += 1
        for k, v in c.items():
            tot[k] += v
        lines.append("seed %d %s: spots %d E / %d w / %d M; models %d/%d; roll %s; order %s; struct %s" % (
            dump["seed"], "/".join(dump["lists"]), c["exact"], c["within"], c["mismatch"],
            c["models_exact"], c["models"], "OK" if c["roll_ok"] else "FAIL",
            "OK" if c["order_ok"] else "FAIL", "OK" if c["struct_ok"] else "FAIL"))
    n = tot["units"]
    lines.append("corpus %d dumps / %d sides / %d placed units" % (tot["dumps"], tot["sides"], n))
    lines.append("roll-off %d/%d OK; deploy order %d/%d OK; structure %d/%d OK" % (
        tot["roll_ok"], tot["dumps"], tot["order_ok"], tot["dumps"], tot["struct_ok"], tot["dumps"]))
    lines.append("interleave_order %d OK / %d FAIL / %d pending (no placement_sequence — "
                 "pre-#575 whole-side recording, green needs the re-record)" % (
                     tot["inter_ok"], tot["inter_fail"], tot["inter_pending"]))
    lines.append("spots %d/%d EXACT | %d within | %d MISMATCH" % (tot["exact"], n, tot["within"], tot["mismatch"]))
    lines.append("models %d/%d exact; sides all-exact %d/%d" % (
        tot["models_exact"], n, tot["sides_all"], tot["sides"]))
    if args.red_whole_side:
        red = tot["inter_fail"] > 0 and tot["inter_ok"] == 0
        lines.append("RED whole-side: interleave_order %d FAIL / %d OK — %s" % (
            tot["inter_fail"], tot["inter_ok"],
            "the whole-side order is rejected, exit 1 as designed" if red
            else "INERT — RED proof FAILED"))
        code = 1 if red else 2
    elif args.red_shift:
        if n == BASELINE["units"]:
            red = tot["exact"] < BASELINE["exact"]
        else:
            red = n > 0 and tot["exact"] == 0
        target = BASELINE["exact"] if n == BASELINE["units"] else 0
        lines.append("RED knob %d: exact %d vs %d — %s" % (
            args.red_shift, tot["exact"], target,
            "displacement detected, exit 1 as designed" if red else "INERT — RED proof FAILED"))
        code = 1 if red else 2
    else:
        hard = (tot["roll_ok"] < tot["dumps"] or tot["order_ok"] < tot["dumps"]
                or tot["struct_ok"] < tot["dumps"] or tot["inter_fail"] > 0)
        if n != BASELINE["units"]:
            lines.append("floor SKIPPED (partial corpus %d/%d units)" % (n, BASELINE["units"]))
            code = 1 if hard else 0
        else:
            reg = [name for name, ok in (
                ("spots_exact %d" % tot["exact"], tot["exact"] >= BASELINE["exact"]),
                ("spots_mismatch %d" % tot["mismatch"], tot["mismatch"] <= BASELINE["mismatch"]),
                ("models %d" % tot["models_exact"], tot["models_exact"] >= BASELINE["models"]),
                ("sides %d" % tot["sides_all"], tot["sides_all"] >= BASELINE["sides"])) if not ok]
            if reg or hard:
                lines.append("floor REGRESSION below %s: %s" % (BASELINE, ", ".join(reg) or "hard fails"))
                code = 1
            else:
                lines.append("floor %d/%d/%d spots, %d/%d models, %d/%d sides — no regression" % (
                    BASELINE["exact"], BASELINE["within"], BASELINE["mismatch"], BASELINE["models"],
                    BASELINE["units"], BASELINE["sides"], tot["sides"]))
                code = 0
    for ln in lines:
        print(ln)
    return code


if __name__ == "__main__":
    sys.exit(main())
