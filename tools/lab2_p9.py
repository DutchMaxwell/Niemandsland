#!/usr/bin/env python3
"""P9, the tray-control placement: MODE_A, MODE_B or PILOT_STOP from timings and completeness only.

After the primary pilot rows the probe runs L_tray and T_tray on the first D ending of each cell, replicate 0
(`probe_slots`, 24 rows). `decide` projects, at twice the largest observed control cost per cell, the rest of BOTH
controls on all D endings (384 continuations including the 24 probes) into what is left of the pilot cap and the A
controls (7,680) into what is left of the confirmation cap -> MODE_A. Otherwise L_tray/I on the 24 D blocks x 4 (96
games), at twice the largest observed primary L game cost per cell, into the pilot cap -> MODE_B; else PILOT_STOP.
An L game is the MODE_B basis because every tree decision is capped by the same `deadline_us` allowance, EV or tray.
A tray decline (TreeUnported) is an INVALID probe row: incompleteness, so MODE_A is out. No outcome is ever read.
"""
CONTROLS = ("L_tray", "T_tray")
CELLS = 12
D_ENDINGS, A_POSITIONS, STREAMS = 2, 40, 8  # per cell: 24 D endings, 480 A positions, 8 played streams each
B_GAMES = 8  # per cell: 24 D blocks x 4 games / 12 cells


def _cell_no(cell):
    return int(str(cell).lstrip("c"))


def probe_slots(positions):
    """[(position, arm, replicate)]: the first D ending of each cell in manifest order, both controls, replicate 0."""
    first = {}
    for pos in positions:
        first.setdefault(pos["cell"], pos)
    return [(first[c], arm, 0) for c in sorted(first, key=_cell_no) for arm in CONTROLS]


def decide(probe_rows, l_game_s, pilot_left_h, confirm_left_h, workers):
    """probe_rows: [{cell, arm, wall_s, valid}] (the 24 probes); l_game_s: {cell: [wall_s of the pilot's L games]}.
    Returns (mode, projection); every hour figure is wall hours over `workers` parallel workers."""
    cost = {}
    for r in probe_rows:
        cost[r["cell"]] = max(cost.get(r["cell"], 0.0), float(r["wall_s"]))
    complete = len(probe_rows) == len(CONTROLS) * CELLS and len(cost) == CELLS and all(r["valid"] is True for r in probe_rows)
    per_cell = len(CONTROLS) * STREAMS
    proj = {
        "cost_s": cost, "complete": complete,
        "mode_a_pilot_h": sum(2 * c * (D_ENDINGS * per_cell - len(CONTROLS)) for c in cost.values()) / 3600 / workers,
        "mode_a_confirm_h": sum(2 * c * A_POSITIONS * per_cell for c in cost.values()) / 3600 / workers,
        "mode_b_pilot_h": sum(2 * max(v) * B_GAMES for v in l_game_s.values()) / 3600 / workers,
    }
    if complete and proj["mode_a_pilot_h"] <= pilot_left_h and proj["mode_a_confirm_h"] <= confirm_left_h:
        return "MODE_A", proj
    if len(l_game_s) == CELLS and proj["mode_b_pilot_h"] <= pilot_left_h:
        return "MODE_B", proj
    return "PILOT_STOP", proj
