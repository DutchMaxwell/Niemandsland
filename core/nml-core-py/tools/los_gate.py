#!/usr/bin/env python
"""NML-1073 M3-4 — the terrain/LOS gate for the Rust twins.

Three checks, each against a GDScript-produced oracle:

(a) TYPE_AT   `nml_core.Board.type_at` over the 3" lattice every banked board
              carries (tools/terrain_bank_dump.gd), versus the
              `SchoolTerrain.type_at` answers the generator wrote into it.
              Also checks the derived grid width `n` against the generator's.
(b) LOS_PAIRS `nml_core.Board.los_pairs` versus the `"los_pairs"` rows the act
              recorder wrote for every activation of a corpus
              (battle_sim.gd:1492-1506) — whole strings, exact.
(c) LOS_BLOCKED the same rows one PAIR at a time through
              `nml_core.Board.los_blocked`, with the unit centres computed HERE
              (the f32 mirror of `BattleSim._centre_of`) instead of inside the
              port — the same diff `tools/act_recheck.gd` prints as
              `LOS_GRID pairs=N mismatch=0`.

RED knobs (each must turn its gate red, and only its own):
  --red-lattice-shift-in=0.5   ask the port half an inch away from where the
                               generator answered. The lattice sits 0.25" short
                               of each cell's far corner, so half an inch lands
                               in the NEXT cell.
  the blocker-rule flip lives in the Rust source (terrain.rs `los_blocked`) —
  drop one of RUINS/CONTAINER/FOREST, rebuild, and (b)+(c) go red while (a)
  stays green.

Run:
  ~/venvs/nmlcore/bin/python core/nml-core-py/tools/los_gate.py \
      --bank ~/selfplay_out/terrain_bank --boards 20 \
      --corpus ~/selfplay_out/m3_oracle
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import struct
import sys

import nml_core


def f32(x: float) -> float:
    """One f32 rounding — Godot's `real_t` is 32-bit."""
    return struct.unpack("f", struct.pack("f", x))[0]


def centre_of(positions):
    """`BattleSim._centre_of` battle_sim.gd:799-806, in Godot's own precision:
    a `Vector3` sum in f32, then `Vector3::operator/(real_t)` in f32. Empty is
    `Vector3.ZERO`."""
    if not positions:
        return [0.0, 0.0, 0.0]
    c = [0.0, 0.0, 0.0]
    for p in positions:
        for i in range(3):
            c[i] = f32(c[i] + f32(p[i]))
    n = f32(float(len(positions)))
    return [f32(c[i] / n) for i in range(3)]


# ------------------------------------------------------------------ gate (a) ---


def gate_type_at(bank: str, boards: int, shift_in: float):
    files = sorted(glob.glob(os.path.join(bank, "board_*.json")),
                   key=lambda p: int(os.path.basename(p)[6:-5]))
    if not files:
        sys.exit(f"[GATE] no boards under {bank}")
    files = files[:boards]
    shift_m = shift_in * 0.0254
    pts = bad = n_bad = 0
    shown = 0
    for path in files:
        d = json.load(open(path))
        b = nml_core.board(d["terrain"])
        if b.n() != d["n"]:
            n_bad += 1
            print(f"  TYPE_AT n: seed {d['seed']} generator={d['n']} derived={b.n()}")
        lat = d["lattice"]
        types = lat["types"]
        for i, (x, z) in enumerate(lat["pts"]):
            pts += 1
            got = b.type_at([x + shift_m, 0.0, z + shift_m])
            if got != int(types[i]):
                bad += 1
                if shown < 3:
                    shown += 1
                    print(f"  TYPE_AT seed {d['seed']} pt {i}: gdscript={types[i]} rust={got}")
    return len(files), pts, bad, n_bad


# ------------------------------------------------------------- gates (b)/(c) ---


def gate_los(corpus: str):
    games = sorted(g for g in glob.glob(os.path.join(corpus, "*", "acts.jsonl")))
    if not games:
        sys.exit(f"[GATE] no acts.jsonl under {corpus}")
    acts = rows = rows_bad = pairs = pairs_bad = 0
    no_grid = 0
    shown = 0
    for path in games:
        with open(path) as f:
            header = json.loads(f.readline())
            b = nml_core.board(header.get("terrain"))
            for line in f:
                line = line.strip()
                if not line:
                    continue
                state = json.loads(line)["state"]
                want = state.get("los_pairs")
                if not want:
                    no_grid += 1
                    continue
                acts += 1
                units = state["units"]
                # (b) the whole block, built inside the port
                got = b.los_pairs(units)
                for i, (w, g) in enumerate(zip(want, got)):
                    rows += 1
                    if w != g:
                        rows_bad += 1
                        if shown < 3:
                            shown += 1
                            print(f"  LOS_PAIRS {os.path.basename(os.path.dirname(path))} "
                                  f"act {acts} row {i}: recorded={w} rust={g}")
                if len(want) != len(got):
                    rows_bad += abs(len(want) - len(got))
                # (c) the same answers one pair at a time, centres computed here
                keys = sorted(units)
                centres = [centre_of(units[k].get("positions", [])) for k in keys]
                for i, ca in enumerate(centres):
                    row = want[i] if i < len(want) else ""
                    for j, cb in enumerate(centres):
                        if j >= len(row):
                            continue
                        pairs += 1
                        if b.los_blocked(ca, cb) != (row[j] == "0"):
                            pairs_bad += 1
                            if shown < 6:
                                shown += 1
                                print(f"  LOS_BLOCKED {keys[i]}->{keys[j]}: "
                                      f"recorded_blocked={row[j] == '0'}")
    return len(games), acts, rows, rows_bad, pairs, pairs_bad, no_grid


def main() -> int:
    ap = argparse.ArgumentParser()
    home = os.path.expanduser("~")
    ap.add_argument("--bank", default=os.path.join(home, "selfplay_out/terrain_bank"))
    ap.add_argument("--boards", type=int, default=20)
    ap.add_argument("--corpus", default=os.path.join(home, "selfplay_out/m3_oracle"))
    ap.add_argument("--red-lattice-shift-in", type=float, default=0.0)
    ap.add_argument("--skip-bank", action="store_true")
    ap.add_argument("--skip-corpus", action="store_true")
    args = ap.parse_args()

    ok = True
    if not args.skip_bank:
        nb, pts, bad, n_bad = gate_type_at(args.bank, args.boards, args.red_lattice_shift_in)
        print(f"TYPE_AT boards={nb} points={pts} mismatch={bad} n_mismatch={n_bad}")
        ok = ok and bad == 0 and n_bad == 0
    if not args.skip_corpus:
        g, acts, rows, rows_bad, pairs, pairs_bad, no_grid = gate_los(args.corpus)
        print(f"LOS_PAIRS games={g} acts={acts} rows={rows} mismatch={rows_bad}")
        print(f"LOS_BLOCKED pairs={pairs} mismatch={pairs_bad}")
        if no_grid:
            print(f"  ({no_grid} acts carried no los_pairs block and were skipped)")
        ok = ok and rows_bad == 0 and pairs_bad == 0
    print("GATE " + ("green" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
