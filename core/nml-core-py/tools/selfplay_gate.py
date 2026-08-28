"""GATE M3-5 (NML-1073) — the Godot-free harness against the Godot trainer,
seed for seed.

`python/selfplay.py` claims to play the SAME game `tools/core_selfplay.gd`
plays. This runner holds it to that, on games recorded from the trainer itself:

    godot --headless --path . -s res://tools/core_selfplay.gd -- \\
        army1=<list> army2=<list> seed=<n> games=1 out=<dir>

recorded with `NML_ACT_DUMP=<dir>/acts_<n>` so each game also leaves the
per-activation oracle next to its result. Then:

    ~/venvs/nmlcore/bin/python core/nml-core-py/tools/selfplay_gate.py \\
        --ref ~/selfplay_out/m3_ref_v2 --bank ~/selfplay_out/terrain_bank \\
        --army1 ~/nml-mission/farm/ai_lists/robot_legions_1000.json \\
        --army2 ~/nml-mission/farm/ai_lists/blessed_sisters_1000.json \\
        --seeds 27-46

Five quantities per seed, all EXACT — no tolerance anywhere:

  winner, objectives{p1,p2,neutral}, vp{p1,p2}, rounds played, and the
  SEQUENCE of picks (round, side, unit key, action kind) from the act corpus.

The picks are the sharp one. Two harnesses can agree on a winner by accident;
they cannot agree on fifty activations in order unless they are playing the same
game with the same dice.

RED PROOF (`--red`): replay every seed with the deployment drawn from a
generator seeded `seed + 1` while the game's own generator is advanced past the
same draws and discards them — so the opener roll-off and every die of every
activation are bit-identical and the ONLY difference is where the models stand.
A gate that stays green under that is not measuring the deployment.
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


def ref_picks(ref_dir: Path, seed: int) -> list[tuple] | None:
    """The recorded pick sequence — one `(round, side, unit_key, kind)` per
    activation, straight off the act corpus `core_selfplay` wrote alongside its
    result. `None` when the game was recorded without `NML_ACT_DUMP`."""
    path = ref_dir / ("acts_%d" % seed) / "acts.jsonl"
    if not path.exists():
        return None
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            if d.get("kind") == "act":
                out.append((d["round"], d["player"], d["pick"]["unit_key"], d["pick"]["action"]["kind"]))
    return out


def compare(ref: dict, got: dict, want_picks: list[tuple] | None) -> list[tuple]:
    """Every quantity the gate holds, in report order. Empty = seed-for-seed
    equal."""
    bad: list[tuple] = []
    if got["winner"] != ref["winner"]:
        bad.append(("winner", ref["winner"], got["winner"]))
    if got["objectives"] != ref["objectives"]:
        bad.append(("objectives", ref["objectives"], got["objectives"]))
    if got["vp"] != ref["vp"]:
        bad.append(("vp", ref["vp"], got["vp"]))
    # The Godot result carries no `rounds_played`; its rows do.
    ref_rounds = len({r["round"] for r in ref["planner_positions"]})
    if got["rounds_played"] != ref_rounds:
        bad.append(("rounds", ref_rounds, got["rounds_played"]))
    if want_picks is not None:
        mine = [(r["round"], r["side"], r["unit"], r["kind"]) for r in got["planner_positions"]]
        if mine != want_picks:
            for i, (a, b) in enumerate(zip(want_picks, mine)):
                if a != b:
                    bad.append(("pick#%d" % i, a, b))
                    break
            else:
                bad.append(("pick count", len(want_picks), len(mine)))
    return bad


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of Godot core_s<seed>.json + acts_<seed>/")
    ap.add_argument("--bank", required=True, help="terrain bank directory")
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--seeds", required=True, help='e.g. "27-46" or "1,4,9"')
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument(
        "--hero-attach",
        choices=("auto",) + sp.HERO_ATTACH_MODES,
        default="auto",
        help='hero mode to replay; "auto" (default) reads it off the reference '
        "corpus itself (`selfplay.hero_attach_of_corpus`)",
    )
    ap.add_argument("--red", action="store_true", help="run the deployment red proof instead")
    a = ap.parse_args(argv)

    ref_dir = Path(a.ref)
    seeds = parse_seeds(a.seeds)
    core = nml_core.load(a.repo)
    hero_attach, source = sp.resolve_hero_attach_mode(
        a.hero_attach, (ref_dir / ("acts_%d" % s) / "acts.jsonl" for s in seeds)
    )
    if a.hero_attach == "auto":
        print("hero_attach   %s (read off %s)" % (hero_attach, source or "nothing — default"))

    compared = equal = missing = 0
    first: tuple | None = None
    seconds: list[float] = []
    godot_seconds: list[float] = []
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
            seed,
            a.army1,
            a.army2,
            a.repo,
            a.bank,
            core,
            deploy_rng_seed=(seed + 1) if a.red else None,
            hero_attach=hero_attach,
        )
        seconds.append(time.perf_counter() - t0)
        log = ref_dir / ("run_%d.log" % seed)
        if log.exists():
            for line in log.read_text(errors="replace").splitlines():
                if "[CORE]" in line and "games in" in line:
                    try:
                        godot_seconds.append(float(line.split("games in")[1].split("s")[0]))
                    except (IndexError, ValueError):
                        pass
        compared += 1
        bad = compare(ref, got, ref_picks(ref_dir, seed))
        if not bad:
            equal += 1
            print("seed %d EQUAL (%d activations, %.1fs)" % (seed, len(got["planner_positions"]), seconds[-1]))
        else:
            if first is None:
                first = (seed, bad)
            print("seed %d DIFF %s" % (seed, bad[:2]))

    label = "RED (deploy from seed+1)" if a.red else "GATE M3-5"
    print(
        "\n%s: %d/%d seeds seed-for-seed equal (%d without a reference)"
        % (label, equal, compared, missing)
    )
    if seconds:
        print(
            "throughput: python %.2fs/game (mean of %d)%s"
            % (
                sum(seconds) / len(seconds),
                len(seconds),
                ""
                if not godot_seconds
                else "  vs godot %.1fs/game (mean of %d) — %.0fx"
                % (
                    sum(godot_seconds) / len(godot_seconds),
                    len(godot_seconds),
                    (sum(godot_seconds) / len(godot_seconds)) / (sum(seconds) / len(seconds)),
                ),
            )
        )
    if first:
        seed, bad = first
        print("first divergence: seed %d" % seed)
        for field, want, mine in bad:
            print("  %-12s ref %s  got %s" % (field, want, mine))
    if a.red:
        # A red proof passes when the games DIVERGE.
        return 0 if equal == 0 else 1
    return 0 if compared and equal == compared else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
