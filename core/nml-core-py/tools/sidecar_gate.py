"""GATE M3-9 (NML-1073) — the Godot-free `core_s<seed>.json` against the Godot
trainer's, FIELD BY FIELD.

M3-5 held the two harnesses to the same GAME (winner, objectives, VP, picks).
This one holds them to the same FILE: every top-level field, and inside
`planner_positions`, every row's `board` / `ids` / `features` and the two
counterfactual sidecars `pair` (E0b) and `fork` (E2-v2).

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/sidecar_gate.py \\
        --ref ~/selfplay_out/m3_ref_v2 --bank ~/selfplay_out/terrain_bank \\
        --army1 ~/nml-mission/farm/ai_lists/robot_legions_1000.json \\
        --army2 ~/nml-mission/farm/ai_lists/blessed_sisters_1000.json \\
        --seeds 27-46

COMPARISON. Ints exact. Floats at `--tol` (1e-9 by default), which is what the
two number formats need: Godot prints a double with 14 significant digits, so a
column the two harnesses computed to the same bits can still come back 3e-15
apart. The float fields are `planner_positions[].value`, every value of
`planner_positions[].features`, and board columns 1, 2 (the snapped position in
inches) and 12, 13 (`shoot_ev12`, `melee_ev`). Everything else on both sides is
an integer or a string and is compared exactly.

HELD SINCE M3-9b: `terrain` (the drawing list, off the bank's `pieces`) and
`magic` (the cast telemetry), both exactly.

EXCLUDED, and named rather than quietly skipped (`--excluded` prints the list):

  * `tool` — deliberate provenance ("core_selfplay" vs "core_selfplay_py").

`armies` is held by list BASENAME: a reference recorded on the fleet carries that
machine's path for the same list, and the path is not a rule.
  * `planner_positions[].intent` — the planner's prose sentence, a report string
    rather than a rule; the Python row carries the key, empty.
  * The Python-only extras `rounds_played`, `rounds_log`, `wall_seconds` and the
    per-row `unit` / `kind` / `action` (the M3-5 pick columns).

RED PROOFS, one per thing this gate claims to read:

  * `--red N` replays every seed with each SIDECAR generator advanced by N draws
    before its clone is resolved — same seeds, same clone points, same played
    game, only the counterfactual dice moved. The pair/fork blocks must then
    DIVERGE on every seed; a gate that stays green under that is not reading the
    sidecars.
  * `--red-source-qd` encodes board columns 10/11 as the pre-#392 blank-OPRUnit
    4/4. Every unit row whose profile is not 4/4 must then differ; a gate that
    stays green under that is not reading the quality/defense columns.
  * `--red-terrain-shift N` writes the drawing list with every piece centre moved
    N 3" cells along +x. `terrain` must then differ on every seed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402

import selfplay as sp  # noqa: E402

#: Top-level result fields this gate does not hold — see the module docstring.
EXCLUDED_TOP = ("tool", "rounds_played", "rounds_log", "wall_seconds")
#: Per-row fields this gate does not hold.
EXCLUDED_ROW = ("intent", "unit", "kind", "action")
#: `planner_positions[].board` column indices that carry a FLOAT.
BOARD_FLOAT_COLS = (1, 2, 12, 13)


def parse_seeds(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def diff(ref, got, path: str, tol: float, out: list[tuple], floats: bool = False) -> None:
    """Every place `got` departs from `ref`, appended as `(path, ref, got)`.
    Stops descending at the first difference of a branch so the report names the
    smallest thing that moved, not every leaf under it."""
    if out:
        return
    if isinstance(ref, dict):
        if not isinstance(got, dict):
            out.append((path, type(ref).__name__, type(got).__name__))
            return
        if set(ref) != set(got):
            out.append(
                (path + " keys", sorted(set(ref) - set(got)), sorted(set(got) - set(ref)))
            )
            return
        for k in ref:
            diff(ref[k], got[k], "%s.%s" % (path, k), tol, out, floats)
            if out:
                return
        return
    if isinstance(ref, list):
        if not isinstance(got, list):
            out.append((path, type(ref).__name__, type(got).__name__))
            return
        if len(ref) != len(got):
            out.append((path + " len", len(ref), len(got)))
            return
        for i, (a, b) in enumerate(zip(ref, got)):
            diff(a, b, "%s[%d]" % (path, i), tol, out, floats)
            if out:
                return
        return
    if isinstance(ref, bool) or isinstance(got, bool):
        if ref != got:
            out.append((path, ref, got))
        return
    if isinstance(ref, (int, float)) and isinstance(got, (int, float)):
        if floats or isinstance(ref, float) or isinstance(got, float):
            if abs(float(ref) - float(got)) > tol:
                out.append((path, ref, got))
        elif ref != got:
            out.append((path, ref, got))
        return
    if ref != got:
        out.append((path, ref, got))


def diff_board(ref: list, got: list, path: str, tol: float, out: list[tuple]) -> None:
    """One `board` block: ints exact, the four float columns at `tol`."""
    if len(ref) != len(got):
        out.append((path + " rows", len(ref), len(got)))
        return
    for r, (a, b) in enumerate(zip(ref, got)):
        if len(a) != len(b):
            out.append(("%s[%d] len" % (path, r), len(a), len(b)))
            return
        for c, (x, y) in enumerate(zip(a, b)):
            if c in BOARD_FLOAT_COLS:
                if abs(float(x) - float(y)) > tol:
                    out.append(("%s[%d][%d]" % (path, r, c), x, y))
                    return
            elif int(x) != int(y):
                out.append(("%s[%d][%d]" % (path, r, c), x, y))
                return


def _armies_by_name(block: dict) -> dict:
    """`armies` is a pair of list PATHS, and a reference recorded on the fleet
    carries that machine's path (`/root/ai_lists_gf/...`). The LIST is the held
    quantity, so both sides are compared by basename — held, not excluded."""
    return {k: Path(str(v)).name for k, v in block.items()}


def compare(ref: dict, got: dict, tol: float) -> list[tuple]:
    """Every held quantity, in report order. Empty = field-for-field equal."""
    bad: list[tuple] = []
    ref_top = {k: v for k, v in ref.items() if k not in EXCLUDED_TOP and k != "planner_positions"}
    got_top = {k: v for k, v in got.items() if k not in EXCLUDED_TOP and k != "planner_positions"}
    for top in (ref_top, got_top):
        if isinstance(top.get("armies"), dict):
            top["armies"] = _armies_by_name(top["armies"])
    if set(ref_top) != set(got_top):
        bad.append(
            ("top-level keys", sorted(set(ref_top) - set(got_top)), sorted(set(got_top) - set(ref_top)))
        )
        return bad
    for k in sorted(ref_top):
        diff(ref_top[k], got_top[k], k, tol, bad)
        if bad:
            return bad
    rp_ref, rp_got = ref["planner_positions"], got["planner_positions"]
    if len(rp_ref) != len(rp_got):
        bad.append(("planner_positions len", len(rp_ref), len(rp_got)))
        return bad
    for i, (a, b) in enumerate(zip(rp_ref, rp_got)):
        ka = {k for k in a if k not in EXCLUDED_ROW}
        kb = {k for k in b if k not in EXCLUDED_ROW}
        if ka != kb:
            bad.append(("row[%d] keys" % i, sorted(ka - kb), sorted(kb - ka)))
            return bad
        for k in sorted(ka):
            path = "row[%d].%s" % (i, k)
            if k == "board":
                diff_board(a[k], b[k], path, tol, bad)
            elif k == "pair":
                if set(a[k]) != set(b[k]):
                    bad.append((path + " keys", sorted(a[k]), sorted(b[k])))
                else:
                    for sub in sorted(a[k]):
                        if sub.endswith("_ids"):
                            diff(a[k][sub], b[k][sub], path + "." + sub, tol, bad)
                        else:
                            diff_board(a[k][sub], b[k][sub], path + "." + sub, tol, bad)
                        if bad:
                            break
            else:
                diff(a[k], b[k], path, tol, bad, floats=(k in ("value", "features")))
            if bad:
                return bad
    return bad


def sidecar_shape(res: dict) -> tuple[int, int]:
    """(rows with a `pair`, rows with a `fork`) — what the gate is holding."""
    rp = res["planner_positions"]
    return sum(1 for r in rp if "pair" in r), sum(1 for r in rp if "fork" in r)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of Godot core_s<seed>.json")
    ap.add_argument("--bank", required=True, help="terrain bank directory")
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--seeds", required=True, help='e.g. "27-46" or "1,4,9"')
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--tol", type=float, default=1e-9, help="float tolerance")
    ap.add_argument(
        "--red",
        type=int,
        default=0,
        metavar="N",
        help="RED PROOF: advance every sidecar generator by N draws; the gate must FAIL",
    )
    ap.add_argument(
        "--red-source-qd",
        action="store_true",
        help="RED PROOF: encode columns 10/11 as the pre-#392 4/4; the gate must FAIL",
    )
    ap.add_argument(
        "--red-terrain-shift",
        type=int,
        default=0,
        metavar="N",
        help="RED PROOF: shift every drawn piece N cells along +x; the gate must FAIL",
    )
    ap.add_argument("--excluded", action="store_true", help="print the excluded fields and exit")
    a = ap.parse_args(argv)

    if a.excluded:
        print("excluded top-level: %s" % ", ".join(EXCLUDED_TOP))
        print("excluded per row:   %s" % ", ".join(EXCLUDED_ROW))
        return 0

    ref_dir = Path(a.ref)
    seeds = parse_seeds(a.seeds)
    core = nml_core.load(a.repo)

    compared = equal = missing = 0
    first: tuple | None = None
    seconds: list[float] = []
    pairs = forks = 0
    for seed in seeds:
        rp = ref_dir / ("core_s%d.json" % seed)
        if not rp.exists():
            missing += 1
            print("seed %d: NO REFERENCE (%s)" % (seed, rp))
            continue
        with open(rp, encoding="utf-8") as f:
            ref = json.load(f)
        t0 = time.perf_counter()
        got = sp.play_game(
            seed, a.army1, a.army2, a.repo, a.bank, core, sidecar_skip=a.red,
            legacy_source_qd=a.red_source_qd,
            terrain_shift_cells=a.red_terrain_shift,
        )
        seconds.append(time.perf_counter() - t0)
        compared += 1
        np, nf = sidecar_shape(got)
        pairs += np
        forks += nf
        bad = compare(ref, got, a.tol)
        if not bad:
            equal += 1
            print(
                "seed %d EQUAL (%d rows, %d pair, %d fork, %.1fs)"
                % (seed, len(got["planner_positions"]), np, nf, seconds[-1])
            )
        else:
            if first is None:
                first = (seed, bad)
            print("seed %d DIFF %s" % (seed, bad[0][0]))

    label = "GATE M3-9"
    if a.red:
        label = "RED (sidecar dice +%d draws)" % a.red
    elif a.red_source_qd:
        label = "RED (columns 10/11 forced to the pre-#392 4/4)"
    elif a.red_terrain_shift:
        label = "RED (drawing list shifted %d cells)" % a.red_terrain_shift
    print(
        "\n%s: %d/%d seeds field-for-field equal (%d without a reference)"
        % (label, equal, compared, missing)
    )
    print("held: %d pair blocks, %d fork blocks" % (pairs, forks))
    print("excluded top-level: %s" % ", ".join(EXCLUDED_TOP))
    print("excluded per row:   %s" % ", ".join(EXCLUDED_ROW))
    if seconds:
        print("throughput: %.2fs/game (mean of %d)" % (sum(seconds) / len(seconds), len(seconds)))
    if first:
        seed, bad = first
        print("first divergence: seed %d" % seed)
        for field, want, mine in bad[:3]:
            print("  %-28s ref %s  got %s" % (field, want, mine))
    if a.red or a.red_source_qd or a.red_terrain_shift:
        # A red proof PASSES when every seed diverged; one that stays equal
        # means the gate is not reading the thing the knob moved.
        return 0 if compared and equal == 0 else 1
    return 0 if compared and equal == compared else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
