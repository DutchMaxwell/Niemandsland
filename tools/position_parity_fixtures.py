#!/usr/bin/env python3
"""Convert paired movement/activation recordings into compact Stage A inputs.

No raw army text or local filenames are published. Each source is identified by
its SHA-256 and one-based JSONL line numbers. All 168 games contribute one
matched action; the sampling rule is independent of parity outcomes.
"""

from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

IN2M = 0.0254
REPO = Path(__file__).resolve().parents[1]
DEST = REPO / "test/fixtures/position_parity/cases.json"
MOVEMENT_RULES = {"Flying", "Strider", "Traversal", "Aircraft"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_lines(path):
    with path.open() as stream:
        return [
            (i, json.loads(line)) for i, line in enumerate(stream, 1) if line.strip()
        ]


def compact_unit(key, su, profile):
    p = dict(profile)
    p.update(su.get("prof", {}))
    return {
        "id": key,
        "player": su["player"],
        "positions": su.get("positions", []),
        "radii": su.get("radii", []),
        "wounds": su.get("wounds", []),
        "attached": su.get("attached", []),
        "attached_to": su.get("attached_to", ""),
        "aircraft": su.get("aircraft", False),
        "dormant": su.get("dormant", False),
        "charge_no_difficult": su.get("charge_no_difficult", False),
        "charge_probe_r": su.get("charge_probe_r", 0),
        "base_shape": p.get("base_shape", "round"),
        "base_w_mm": p.get("base_w_mm", 32),
        "base_d_mm": p.get("base_d_mm", 32),
        "game_system": p.get("game_system", "gf"),
        "tough": p.get("tough", 1),
        "rules": [
            r
            for r in p.get("special_rules", [])
            if r.split("(", 1)[0].strip() in MOVEMENT_RULES
        ],
    }


def matched_inputs(directory):
    acts = read_lines(directory / "acts.jsonl")
    moves = read_lines(directory / "moves_calls.jsonl")
    ah, mh = acts[0][1], moves[0][1]
    board = mh["board_in"]
    lookup = {}
    for line, call in moves[1:]:
        lookup.setdefault((call["round"], call["unit"]), []).append((line, call))
    matches = []
    for al, act in acts[1:]:
        pick = act.get("pick", {})
        action = pick.get("action", {})
        key = pick.get("unit_key", "")
        if (
            not pick.get("used")
            or action.get("kind") not in [1, 2, 3]
            or "dest" not in action
        ):
            continue
        state = act["state"]
        su = state["units"][key]
        # The table moves hosts followed by attached heroes, in their recorded order.
        positions = list(su["positions"])
        for hero in su.get("attached", []):
            positions.extend(state["units"][hero]["positions"])
        expected = [
            [p[0] / IN2M + board[0] / 2, p[2] / IN2M + board[1] / 2] for p in positions
        ]
        for ml, call in lookup.get((act["round"], ah["profiles"][key]["name"]), []):
            actual = call["model_pos"]
            if len(expected) != len(actual) or not actual:
                continue
            error = max(math.dist(a, b) for a, b in zip(actual, expected))
            if error > 0.0001 or call["allow_contact"] != (action["kind"] == 3):
                continue
            band = float(re.search(r"reach_in=([0-9.]+)", call["rung"])[1])
            if band <= 0 or action["kind"] == 3 and not action.get("charge"):
                continue
            matches.append((al, ml, act, call, band))
            break
    return ah, mh, matches


def convert(root):
    directories = sorted(
        p.parent
        for p in root.rglob("moves_calls.jsonl")
        if (p.parent / "acts.jsonl").is_file()
    )
    cases = []
    for index, directory in enumerate(directories):
        ah, mh, matches = matched_inputs(directory)
        if not matches:
            raise ValueError(f"paired source {index} has no exact start-position match")
        al, ml, act, call, band = matches[index % len(matches)]
        state, action = act["state"], act["pick"]["action"]
        order = state.get("unit_order", list(state["units"]))
        names = {key: f"u{i:02}" for i, key in enumerate(order)}
        units = []
        for key in order:
            u = compact_unit(names[key], state["units"][key], ah["profiles"][key])
            u["attached"] = [names[h] for h in u["attached"]]
            u["attached_to"] = names.get(u["attached_to"], "")
            units.append(u)
        actor = names[act["pick"]["unit_key"]]
        player = state["units"][act["pick"]["unit_key"]]["player"]
        cases.append(
            {
                "id": f"recorded-{index:03}",
                "game": f"game-{index:03}",
                "source": {
                    "acts_sha256": digest(directory / "acts.jsonl"),
                    "moves_sha256": digest(directory / "moves_calls.jsonl"),
                    "act_line": al,
                    "move_line": ml,
                    "matched_actions": len(matches),
                },
                "board_in": mh["board_in"],
                "terrain": mh["terrain"],
                "units": units,
                "action": {
                    "unit": actor,
                    "kind": action["kind"],
                    "dest": action["dest"],
                    "target": names.get(action.get("charge", ""), ""),
                    "band_in": band,
                },
                "candidate_targets": [
                    u["id"]
                    for u in units
                    if u["player"] != player and u["positions"] and not u["dormant"]
                ],
                "round": act["round"],
                "fast_planner": mh["fast_planner"],
                "fast_planner_guard": mh["fast_planner_guard"],
                "tags": ["recorded"],
                # The raw seam is checked independently, using the recorded input and
                # recorded GDScript output, without pretending it is final placement.
                "formation_call": {
                    **call,
                    "unit": actor,
                    "walls": (
                        mh["walls"] if call["walls"] == "header" else call["walls"]
                    ),
                },
            }
        )
        cases[-1]["formation_call"].pop("trace", None)
    return cases


def generated():
    def unit(
        key, pid, points, shape="round", width=32, depth=32, rules=(), system="gf"
    ):
        # Production movement clearance uses the circumscribed radius for ovals.
        radius = math.hypot(width, depth) / 2000 if shape == "oval" else width / 2000
        return {
            "id": key,
            "player": pid,
            "positions": [[x * IN2M, 0, z * IN2M] for x, z in points],
            "radii": [radius] * len(points),
            "wounds": [1] * len(points),
            "attached": [],
            "attached_to": "",
            "aircraft": False,
            "dormant": False,
            "charge_no_difficult": bool(set(rules) & {"Flying", "Strider"}),
            "charge_probe_r": radius,
            "base_shape": shape,
            "base_w_mm": width,
            "base_d_mm": depth,
            "game_system": system,
            "tough": 1,
            "rules": list(rules),
        }

    def case(
        name, units=None, kind=1, band=6, dest=(6, 0), cells=(), walls=(), tags=()
    ):
        return {
            "id": "generated-" + name,
            "game": None,
            "source": {"generator": 1},
            "board_in": [72, 48],
            "round": 1,
            "fast_planner": True,
            "fast_planner_guard": 320,
            "terrain": {
                "cells": list(cells),
                "sandbox": [],
                "walls": list(walls),
                "cell_params": {
                    "grid_rotation_degrees": 0,
                    "grid_size_inches": 3,
                    "inches_to_meters": IN2M,
                    "table_size_feet": [6, 4],
                },
            },
            "units": units or [unit("u00", 1, [(0, 0)]), unit("u01", 2, [(20, 0)])],
            "action": {
                "unit": "u00",
                "kind": kind,
                "dest": [dest[0] * IN2M, 0, dest[1] * IN2M],
                "target": "u01" if kind == 3 else "",
                "band_in": band,
            },
            "candidate_targets": ["u01"],
            "tags": list(tags),
        }

    out = [
        case("open", tags=["formation"]),
        case("hold", kind=0, band=0, dest=(0, 0), tags=["hold"]),
    ]
    for shape, w, d in [("round", 120, 120), ("oval", 60, 120)]:
        out.append(
            case(
                shape + "-large",
                [unit("u00", 1, [(0, 0)], shape, w, d), unit("u01", 2, [(8, 1)])],
                tags=["large_base", "base_shapes"],
            )
        )
    out.append(
        case(
            "formation",
            [unit("u00", 1, [(0, 0), (0, 1.7), (0, 3.4)]), unit("u01", 2, [(20, 0)])],
            tags=["coherency"],
        )
    )
    out.append(
        case(
            "skirmish-chain",
            [
                unit(
                    "u00",
                    1,
                    [(0, 0), (1.7, 0), (3.4, 0), (5.1, 0), (6.8, 0), (8.5, 0)],
                    system="gff",
                ),
                unit("u01", 2, [(20, 0)]),
            ],
            dest=(14, 0),
            tags=["skirmish_chain", "coherency"],
        )
    )
    for rule in ["", "Strider", "Flying"]:
        out.append(
            case(
                "difficult-" + (rule.lower() or "capped"),
                [
                    unit("u00", 1, [(0, 0)], rules=[rule] if rule else []),
                    unit("u01", 2, [(20, 0)]),
                ],
                kind=2,
                band=12,
                dest=(12, 0),
                cells=[[x, y, 2] for x in range(15, 20) for y in range(14, 17)],
                tags=["terrain_cap", "terrain_exemptions"],
            )
        )
    for distance in [8, 14, 20]:
        out.append(
            case(
                "charge-" + str(distance),
                [
                    unit("u00", 1, [(0, 0), (0, 1.7)]),
                    unit("u01", 2, [(distance, 0), (distance, 1.7)]),
                ],
                kind=3,
                band=12,
                dest=(distance, 0),
                tags=[
                    "charge_final_placement",
                    "charge_snap",
                    "charge_contact" if distance == 8 else "charge_no_contact",
                ],
            )
        )
    out.append(
        case(
            "wall",
            walls=[[[3 * IN2M, -2 * IN2M], [3 * IN2M, 2 * IN2M]]],
            tags=["walls"],
        )
    )
    out.append(
        case(
            "charge-wall",
            [unit("u00", 1, [(0, 0)]), unit("u01", 2, [(10, 0)])],
            kind=3,
            band=12,
            dest=(10, 0),
            walls=[[[3 * IN2M, -20 * IN2M], [3 * IN2M, 20 * IN2M]]],
            tags=["walls", "charge_no_contact", "charge_snap"],
        )
    )
    out.append(
        case(
            "packed-gate",
            [
                unit("u00", 1, [(0, 0), (0, 1.7), (0, 3.4)]),
                unit("u01", 2, [(6, 0), (6, 1.7), (6, 3.4)]),
            ],
            dest=(6, 0),
            tags=["final_placement", "whole_unit_shorten", "gate_budget"],
        )
    )
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=DEST)
    args = parser.parse_args()
    recorded = convert(args.corpus)
    if len(recorded) != 168:
        raise ValueError(f"expected 168 paired games, got {len(recorded)}")
    result = {
        "schema": 1,
        "boundary": "stage_a",
        "recorded_games": len(recorded),
        "cases": recorded + generated(),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        f'fixtures: recorded={len(recorded)} generated={len(result["cases"])-len(recorded)}'
    )


if __name__ == "__main__":
    main()
