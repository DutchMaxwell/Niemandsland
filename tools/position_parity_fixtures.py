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
    # ---- Wide sweep -------------------------------------------------------
    # The recorded games are one faction pair on one board size. These cases add
    # the axes they never vary: base footprint, game system, board size, terrain
    # density against each movement exemption, charge reach and charger width,
    # formation shape, skirmish spread, board edges, wall lanes and attached
    # heroes. Every case is a fixed action on a self-contained board, so the
    # sweep is reproducible without the recording corpus.
    shapes = [("round", 25, 25), ("round", 32, 32), ("round", 40, 40), ("round", 50, 50),
              ("round", 60, 60), ("round", 90, 90), ("oval", 60, 35), ("oval", 75, 42),
              ("oval", 90, 52), ("oval", 120, 92)]
    boards, rulesets = [(72, 48), (48, 48), (44, 60), (36, 36)], ["", "Strider", "Flying", "Traversal"]

    def line(key, pid, count, x, z, step=1.7, **kw):
        return unit(key, pid, [(x + i * step, z) for i in range(count)], **kw)

    for shape, w, d in shapes:
        for system in ["gf", "gff"]:
            span = max(1.7, w / 25.4 + 0.4)
            out.append(case("faction-%s%dx%d-%s" % (shape, w, d, system),
                [line("u00", 1, 3, 0, 0, span, shape=shape, width=w, depth=d, system=system),
                 line("u01", 2, 3, 14, 0, span, system=system)],
                band=6, dest=(6, 0), tags=["faction", "base_shapes", "coherency"]))
    for board in boards:
        edge = board[0] / 2.0 - 6.0
        for kind, band, tag in [(1, 6, "advance"), (2, 12, "rush"), (3, 12, "charge")]:
            c = case("board-%dx%d-%s" % (board[0], board[1], tag), kind=kind, band=band,
                units=[line("u00", 1, 3, -edge, 0), line("u01", 2, 2, -edge + 10, 0)],
                dest=(-edge + 10, 0), tags=["board_type", tag])
            c["board_in"], c["terrain"]["cell_params"]["table_size_feet"] = list(board), \
                [board[0] / 12.0, board[1] / 12.0]
            out.append(c)
    # Cell type 2/3/4 are difficult, dangerous and impassable; the exemptions
    # (Strider, Flying, Traversal) must each meet the same board.
    for density in range(1, 6):
        cells = [[x, y, 2 + (x + y) % 3] for x in range(12, 12 + density * 2)
                 for y in range(12, 12 + density * 2)]
        for rule in rulesets:
            out.append(case("terrain-d%d-%s" % (density, rule.lower() or "plain"),
                [line("u00", 1, 3, 0, 0, rules=[rule] if rule else []), line("u01", 2, 2, 16, 0)],
                kind=2, band=12, dest=(12, 0), cells=cells, tags=["terrain_cap",
                "terrain_exemptions", "walls"], walls=[[[(2 + k) * IN2M, -6 * IN2M],
                [(2 + k) * IN2M, 6 * IN2M]] for k in range(density)]))
    for distance in [4, 6, 8, 10, 12, 14, 16, 18, 20]:
        for count in [1, 3]:
            out.append(case("charge-d%d-n%d" % (distance, count),
                [line("u00", 1, count, 0, 0), line("u01", 2, 2, distance, 0)],
                kind=3, band=12, dest=(distance, 0),
                tags=["charge_final_placement", "charge_snap",
                      "charge_contact" if distance <= 12 else "charge_no_contact"]))
    for shape, w, d in shapes[5:]:
        out.append(case("charge-%s%dx%d" % (shape, w, d),
            [line("u00", 1, 2, 0, 0, 4.0, shape=shape, width=w, depth=d),
             line("u01", 2, 2, 10, 0, 4.0, shape=shape, width=w, depth=d)],
            kind=3, band=12, dest=(10, 0),
            tags=["charge_final_placement", "base_shapes", "large_base"]))
    for k, rule in enumerate(rulesets):
        out.append(case("charge-terrain-%s" % (rule.lower() or "plain"),
            [line("u00", 1, 2, 0, 0, rules=[rule] if rule else []), line("u01", 2, 2, 12, 0)],
            kind=3, band=12, dest=(12, 0),
            cells=[[x, y, 2] for x in range(15, 19) for y in range(14, 17)],
            walls=[[[6 * IN2M, -8 * IN2M], [6 * IN2M, 8 * IN2M]]] if k % 2 else [],
            tags=["charge_final_placement", "terrain_cap", "walls"]))
    for cols, rows in [(2, 1), (3, 1), (5, 1), (4, 2), (5, 2), (2, 4), (1, 8)]:
        for spread in [1.7, 2.6]:
            out.append(case("formation-%dx%d-s%d" % (cols, rows, int(spread * 10)),
                [unit("u00", 1, [(c * spread, r * spread) for r in range(rows)
                 for c in range(cols)]), line("u01", 2, 2, 16, 0)], kind=2, band=12, dest=(10, 0),
                tags=["coherency", "final_placement", "whole_unit_shorten"]))
    for system in ["gff", "aofs"]:
        for count in [2, 4, 6]:
            for spread in [1.7, 2.4]:
                out.append(case("skirmish-%s-n%d-s%d" % (system, count, int(spread * 10)),
                    [line("u00", 1, count, 0, 0, spread, system=system),
                     line("u01", 2, 2, 18, 0, system=system)],
                    kind=2, band=12, dest=(12, 0), tags=["skirmish_chain", "coherency"]))
    for name, x, z, dest in [("west", -33, 0, (-27, 0)), ("east", 33, 0, (27, 0)),
                             ("north", 0, -21, (0, -15)), ("south", 0, 21, (0, 15)),
                             ("corner-nw", -33, -21, (-27, -15)), ("corner-se", 33, 21, (27, 15))]:
        out.append(case("edge-" + name, [line("u00", 1, 3, x, z), line("u01", 2, 1, 0, 0)],
            kind=2, band=12, dest=dest, tags=["bounds", "final_placement"]))
    for k in range(4):
        out.append(case("wall-lane-%d" % k, [line("u00", 1, 3, 0, 0), line("u01", 2, 1, 16, 0)],
            kind=2, band=12, dest=(12, 0),
            walls=[[[(4 + k) * IN2M, -3 * IN2M], [(4 + k) * IN2M, 9 * IN2M]],
                   [[(4 + k) * IN2M, -9 * IN2M], [(4 + k) * IN2M, -5 * IN2M]]],
            tags=["walls", "final_placement"]))
    for count in [1, 3, 5]:
        for shape, w, d in [("round", 32, 32), ("oval", 60, 35)]:
            host, hero = line("u00", 1, count, 0, 0), unit("u02", 1, [(-1.7, 0)], shape, w, d)
            host["attached"], hero["attached_to"] = ["u02"], "u00"
            out.append(case("hero-%s-n%d" % (shape, count),
                [host, line("u01", 2, 2, 16, 0), hero], kind=2, band=12, dest=(10, 0),
                tags=["attached", "coherency", "base_shapes"]))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path)
    parser.add_argument("--reuse-recorded", type=Path, help="keep the recorded cases of this "
                        "cases.json and rebuild only the generated ones")
    parser.add_argument("--out", type=Path, default=DEST)
    args = parser.parse_args()
    # The generated half is self-contained, so the sweep can be regenerated
    # without the recording corpus by reusing the checked-in recorded cases.
    if args.reuse_recorded:
        recorded = [c for c in json.loads(args.reuse_recorded.read_text())["cases"]
                    if c["game"] is not None]
    elif args.corpus:
        recorded = convert(args.corpus)
    else:
        parser.error("--corpus or --reuse-recorded is required")
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
