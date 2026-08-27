"""GATE Q-A (NML-1073) — the Godot-free trainer against the FIXED Godot trainer
over the WHOLE acceptance reference, not one pairing.

M3-9 held the two harnesses to the same file on a single army pairing. This one
holds them to it across every recorded pairing at once: the reference is a
directory of GAME directories, each named `<p1>_vs_<p2>_s<seed>` and carrying the
`core_s<seed>.json` that one Godot process wrote (plus its `acts.jsonl` and
`run.log`, which this gate does not read).

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/qa_gate.py \\
        --ref ~/selfplay_out/qa_ref --bank ~/selfplay_out/terrain_bank \\
        --lists ~/nml-mission/farm/ai_lists

The pairing and the seed come from the DIRECTORY NAME — never from inside the
file — so a reference laid down for one pairing cannot be silently compared
against another's armies.

COMPARISON. Exactly `sidecar_gate`'s: ints exact, floats at `--tol`, every
top-level field and every `planner_positions` row including `board` / `ids` /
`features` / `pair` / `fork` / `terrain` / `magic`. The excluded list is that
module's and is printed at the end rather than kept quiet.

ONE CORE PER GAME. Each reference game is one Godot PROCESS, so its
`BattleSim.unknown_rules` starts empty. `Core` carries that collector for its
lifetime, so a `Core` reused across games would report the union and diverge on
the second game of any faction with an unknown rule. `Core.set_header` rebuilds
the registries per game anyway, so a fresh `Core` costs only the row vocabulary.

RED PROOFS, forwarded to `selfplay.play_game` and inverted here: `--red N`
(sidecar dice), `--red-source-qd` (the pre-#392 4/4 columns) and
`--red-terrain-shift N` (the drawing list). Under any of them EVERY game must
diverge, or this gate is not reading what it claims to.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402

import selfplay as sp  # noqa: E402
import sidecar_gate as sg  # noqa: E402

#: `<p1>_vs_<p2>_s<seed>` — the army list basenames and the game seed. `p1` is
#: NON-greedy so a faction whose name contains the separator cannot swallow the
#: second half.
GAME_DIR = re.compile(r"^(?P<p1>.+?)_vs_(?P<p2>.+)_s(?P<seed>\d+)$")


def games(ref_dir: Path, seeds: set[int] | None, pairing: str | None) -> list[tuple]:
    """Every reference game under `ref_dir`, as `(pairing, seed, result_path)`,
    ordered by pairing then seed. A directory whose name is not the recorded
    layout is skipped by NAME rather than half-read."""
    out: list[tuple] = []
    for d in sorted(ref_dir.iterdir()):
        if not d.is_dir():
            continue
        m = GAME_DIR.match(d.name)
        if not m:
            continue
        seed = int(m.group("seed"))
        pair = "%s_vs_%s" % (m.group("p1"), m.group("p2"))
        if seeds is not None and seed not in seeds:
            continue
        if pairing and pairing not in pair:
            continue
        res = d / ("core_s%d.json" % seed)
        if res.exists():
            out.append((pair, m.group("p1"), m.group("p2"), seed, res))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of <p1>_vs_<p2>_s<seed> dirs")
    ap.add_argument("--bank", required=True, help="terrain bank directory")
    ap.add_argument(
        "--lists",
        default=str(Path("~/nml-mission/farm/ai_lists").expanduser()),
        help="directory the army list JSONs live in",
    )
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--tol", type=float, default=1e-9, help="float tolerance")
    ap.add_argument("--pairing", default="", help="only pairings containing this substring")
    ap.add_argument("--seeds", default="", help='e.g. "27-46" or "1,4,9"; default all')
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
    ap.add_argument(
        "--top-k",
        type=int,
        default=None,
        help="planner top_k override; default is NML_TOP_K env or 6 (ai_planner.gd:49-56)",
    )
    ap.add_argument(
        "--horizon",
        type=int,
        default=None,
        help="planner horizon override; default is NML_HORIZON env or 2 (ai_planner.gd:290-297)",
    )
    a = ap.parse_args(argv)

    lists = Path(a.lists).expanduser()
    seeds = set(sg.parse_seeds(a.seeds)) if a.seeds else None
    found = games(Path(a.ref).expanduser(), seeds, a.pairing)
    if not found:
        print("no reference games under %s" % a.ref)
        return 1

    red = bool(a.red or a.red_source_qd or a.red_terrain_shift)
    total = equal = rows = 0
    missing_lists: list[str] = []
    per_pairing: dict[str, list] = {}
    seconds: list[float] = []
    for pair, p1, p2, seed, res in found:
        army1 = lists / ("%s.json" % p1)
        army2 = lists / ("%s.json" % p2)
        if not (army1.exists() and army2.exists()):
            missing_lists.append(pair)
            continue
        with open(res, encoding="utf-8") as f:
            ref = json.load(f)
        t0 = time.perf_counter()
        # One process per reference game — see the module note on `unknown_rules`.
        core = nml_core.load(a.repo)
        got = sp.play_game(
            seed, army1, army2, a.repo, a.bank, core,
            sidecar_skip=a.red,
            legacy_source_qd=a.red_source_qd,
            terrain_shift_cells=a.red_terrain_shift,
            top_k=a.top_k, horizon=a.horizon,
        )
        seconds.append(time.perf_counter() - t0)
        total += 1
        rows += len(got["planner_positions"])
        bad = sg.compare(ref, got, a.tol)
        book = per_pairing.setdefault(pair, [0, 0, 0, None])
        book[0] += 1
        book[2] += len(got["planner_positions"])
        if bad:
            if book[3] is None:
                book[3] = (seed, bad[0])
        else:
            equal += 1
            book[1] += 1

    print()
    for pair in sorted(per_pairing):
        n, ok, nrows, first = per_pairing[pair]
        line = "%-52s %3d/%-3d games equal  (%5d rows)" % (pair, ok, n, nrows)
        if first:
            line += "   first diff seed %d: %s ref %s got %s" % (
                first[0], first[1][0], first[1][1], first[1][2]
            )
        print(line)
    if missing_lists:
        print("\nNO ARMY LIST for %d game(s): %s" % (len(missing_lists), sorted(set(missing_lists))))
    if seconds:
        print("\nthroughput: %.2fs/game (mean of %d)" % (sum(seconds) / len(seconds), len(seconds)))
    print("excluded top-level: %s" % ", ".join(sg.EXCLUDED_TOP))
    print("excluded per row:   %s" % ", ".join(sg.EXCLUDED_ROW))

    label = "GATE Q-A"
    if a.red:
        label = "RED Q-A (sidecar dice +%d draws)" % a.red
    elif a.red_source_qd:
        label = "RED Q-A (columns 10/11 forced to the pre-#392 4/4)"
    elif a.red_terrain_shift:
        label = "RED Q-A (drawing list shifted %d cells)" % a.red_terrain_shift
    print(
        "\n%s: %d/%d games field-for-field equal across %d pairings (%d planner rows)"
        % (label, equal, total, len(per_pairing), rows)
    )
    if red:
        # A red proof PASSES when every game diverged.
        return 0 if total and equal == 0 else 1
    return 0 if total and equal == total else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
