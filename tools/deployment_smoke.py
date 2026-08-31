#!/usr/bin/env python3
"""One-seed smoke: the pyo3 deployment pipeline vs the pregame fixture (NML-1152 step 7).

Feeds `nml_core.deploy_side` + `nml_core.deploy_finish` the SAME inputs the Rust
integration test consumes (core/nml-core/tests/fixtures/pregame_*.json) for one
seed, then compares the deployed result against the fixture with the committed
gate law (core/nml-core/tests/deployment.rs):

- spot EXACT   = Godot snappedf(v, 0.0001) quantum equal on both axes;
- spot within  = euclidean distance <= one 0.025 m scan step + the dump quantum;
- models EXACT = same count + pairwise snappedf equality.

Byte parity with the Rust pipeline is pinned by EXPECTED_HASH: the SHA-256 of
the binding's canonical output, recorded from the test's own dump for this seed
(deep-reasoning-reviewed binding; the dump recipe lives in the plan's log).
Any drift through the marshalling seam trips the smoke, not a tolerance.

The roll-off is checked too, drawn in Python over `Rng` the way step 8 will
consume the game stream (design §3.3): attempts and opener must equal the
fixture's.

RED knob: NML_SMOKE_ZONE_SHIFT (int n) shifts both zones' forward edge by
n * 0.025 m — the smoke must then FAIL (result hash moves, fixture mismatches
appear). Unset, it must pass. Exit 0 green / 1 red-as-designed / 2 unexpected.
"""
import hashlib
import json
import math
import os
import struct
import sys

import nml_core

FIXTURES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "core", "nml-core", "tests", "fixtures"
)
SEED = int(os.environ.get("NML_SMOKE_SEED", "25"))
# The fixture carries BOTH seat orders per seed (lists tag); pin one so the
# EXPECTED_HASH reference is unambiguous. The roll-off is seat-order invariant
# (same game seed -> same draws); the board and objectives likewise.
LISTS = os.environ.get("NML_SMOKE_LISTS", "alien_hives_1000,battle_brothers_1000")
SHIFT_N = int(os.environ.get("NML_SMOKE_ZONE_SHIFT", "0"))
EXPECTED_HASH = "36bbaf61d1f45ac1ca37d49299fd3a4a673dbe55001b094a9015369c8af1fecb"
SCAN_STEP = 0.025
DUMP_QUANT = 1.5e-4
ZONES = {"1": [-0.9144, -0.6096, 1.8288, 0.3048], "2": [-0.9144, 0.3048, 1.8288, 0.3048]}
ZONE_STYLE = {
    "zones": {
        "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
    }
}


def load(name):
    with open(os.path.join(FIXTURES, name)) as f:
        return json.load(f)


def f32(v):
    return struct.unpack("f", struct.pack("f", v))[0]


def quant(v):
    return math.floor(v / 1e-4 + 0.5) * 1e-4  # Godot snappedf(v, 0.0001)


def main():
    picks = [d for d in load("pregame_pipeline.json")
             if d["seed"] == SEED and ",".join(d["lists"]) == LISTS]
    assert len(picks) == 1, f"expected exactly one {SEED}/{LISTS} dump, got {len(picks)}"
    dump = picks[0]
    roll = [r for r in load("pregame_roll_off.json") if r["seed"] == SEED][0]
    spots = load("pregame_deploy_spots.json")
    bank = load("pregame_bank_v2.json")["boards"][str(500000 + SEED)]

    # The roll-off FIRST from the game stream (step 8's flow): tie re-roll law.
    rng = nml_core.Rng(SEED)
    attempts = []
    while len(attempts) < 100:
        a, b = rng.randi_range(1, 6), rng.randi_range(1, 6)
        attempts.append([a, b])
        if a != b:
            break
    opener = 1 if attempts[-1][0] > attempts[-1][1] else 2
    assert attempts == roll["attempts"], f"roll-off attempts {attempts} != {roll['attempts']}"
    assert opener == roll["opener"], f"opener {opener} != {roll['opener']}"

    board_json = {
        "cells": spots["boards"][str(500000 + SEED)]["cells"],
        "sandbox": [],
        "cell_params": spots["cell_params"],
    }
    board = nml_core.board(board_json)
    board.set_bank_props(bank["walls"], bank["blockers"], bank["blocker_boxes"])
    lay = nml_core.objective_layout(board_json, 500000 + SEED, "d3+2", ZONE_STYLE, 72.0, 48.0)
    objectives = [[f32(x * 0.0254), f32(z * 0.0254)] for x, z in lay["positions"]]

    shift = SHIFT_N * SCAN_STEP
    zones = {s: [z[0], z[1] + shift, z[2], z[3]] for s, z in ZONES.items()}

    def unit_of(slot, row):
        key, g = row[0], dump["sides"][slot]["units"].get(row[0])
        if g is None:  # ambush row: no geometry, empty shapes
            return {"key": key, "model_count": 0, "base_r_m": 0.0, "footprint": [],
                    "scout": row[1], "ambush": row[2], "ignores_terrain": False,
                    "vanguard": False, "transport_capacity": 0, "facing_rad": 0.0,
                    "model_shapes": []}
        return {"key": key, "model_count": g["n_models"], "base_r_m": g["base_r_m"],
                "footprint": g["footprint"], "scout": row[1], "ambush": row[2],
                "ignores_terrain": g["ignores_terrain"], "vanguard": g["vanguard_pushed"],
                "transport_capacity": 0, "facing_rad": g["facing_rad"],
                "model_shapes": g["model_shapes"]}

    sides = {}
    for slot in ("1", "2"):
        side = dump["sides"][slot]
        units = [unit_of(slot, r) for r in side["roster"]]
        sd = nml_core.deploy_side(units, zones[slot], objectives, board, side["seed_value"])
        assert sd["seed_value"] == side["seed_value"] and sd["fills"] == side["fills"]
        assert sd["reserved"] == side["reserved"], (sd["reserved"], side["reserved"])
        sides[slot] = {"units": units, "placements": sd["placements"], "zone": zones[slot]}

    trays = {slot: [m for row in dump["sides"][slot]["tray_models"] for m in row["models"]]
             for slot in ("1", "2")}
    finished = nml_core.deploy_finish(sides, board, trays, roll["deploy_order"][0])

    n = exact = within = mismatch = 0
    models_exact = models_total = 0
    sides_all_exact = 0
    for slot in ("1", "2"):
        side = dump["sides"][slot]
        side_exact = True
        for p in finished[slot]:
            u = side["units"][p["key"]]
            sx, sz = u["spot"]
            n += 1
            if abs(quant(p["spot"][0]) - quant(sx)) < 1e-9 and abs(quant(p["spot"][1]) - quant(sz)) < 1e-9:
                exact += 1
            else:
                side_exact = False
                dist = math.hypot(p["spot"][0] - sx, p["spot"][1] - sz)
                if dist <= SCAN_STEP + DUMP_QUANT:
                    within += 1
                else:
                    mismatch += 1
            models_total += 1
            if len(p["models"]) == len(u["models"]) and all(
                abs(quant(t[0]) - quant(m[0])) < 1e-9 and abs(quant(t[1]) - quant(m[1])) < 1e-9
                for t, m in zip(p["models"], u["models"])
            ):
                models_exact += 1
        sides_all_exact += side_exact

    digest = hashlib.sha256(
        json.dumps(finished, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    print(f"seed {SEED}: roll-off {attempts} opener {opener} OK; "
          f"spots {exact} EXACT / {within} within / {mismatch} MISMATCH of {n}; "
          f"models {models_exact}/{models_total} exact; sides all-exact {sides_all_exact}/2; "
          f"hash {digest[:16]}…")
    if SHIFT_N:
        red = digest != EXPECTED_HASH and mismatch > 0
        print(f"RED knob {SHIFT_N}: {'MISMATCH as designed — the shifted zone breaks parity' if red else 'INERT — RED proof FAILED'}")
        sys.exit(1 if red else 2)
    assert digest == EXPECTED_HASH, f"binding drifted from the Rust pipeline: {digest}"
    print("GREEN: the binding reproduces the Rust pipeline byte-exact and the fixture numbers hold.")


if __name__ == "__main__":
    main()
