"""Throughput probe for the Godot-free trainer (NML-1073 M3-8).

Measures how many games/hour `python/selfplay.py`'s `play_game` produces under
N parallel worker processes, one `nml_core.Core` per process — so the
maintainer can size a training fleet from a measured number, not a guess.

PROCESS-SAFETY. `nml_core` (core/nml-core-py, wrapping core/nml-core) carries
no mutable global state: the only `static` in either crate is
`mv::cost::empty_cells()` (core/nml-core/src/mv/cost.rs:60), a read-only
`OnceLock<CellSet>` computed identically wherever it runs, and neither crate
spawns a native thread (no `rayon`, no `std::thread::spawn` anywhere in
core/nml-core/src or core/nml-core-py/src). Every game-shaping value
(`Core`, `State`, the RNG) is an explicit Python object the caller holds, not
a module-level one. So the module is safe under both `fork` and `spawn`; this
probe uses `spawn` anyway, because a fresh interpreter per worker is the
portable default for a compiled extension module (no fork-inherited file
descriptors or partially-initialized Rust state to reason about) and costs
one `import nml_core` per WORKER, not per game.

Each worker gets its own `nml_core.Core` from `nml_core.load(repo_root)` and
reuses it across every seed in its slice, exactly as `selfplay.py`'s own
`main()` reuses one `Core` across `--games` — the registries and mechanics
maps are the expensive part of `load`, not the per-game `set_header`.

USAGE (one run = one N):
    python throughput.py --n 8 --games 40 --army1 ... --army2 ... \\
        --repo . --bank ~/selfplay_out/terrain_bank --out out_n8.json \\
        [--check-determinism-seed 27]

Seeds run [--seed-start, --seed-start + games). NOTE: the M3-4 terrain bank
only carries boards for seeds 1..200 (see core/nml-core-py/README.md, "The
terrain gate"); board_1000.json does not exist, so --seed-start defaults to 1
rather than the 1000 a fleet-sizing run would eventually use — this probe
measures wall time, which does not depend on which banked seeds are played.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing as mp
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay as sp  # noqa: E402


def digest_of(result: dict) -> str:
    """A short, comparable fingerprint of one game: winner, VP, objectives and
    the whole pick sequence (round, side, unit, action kind) — the same fields
    `tools/selfplay_gate.py`'s `compare()` holds a Godot reference to."""
    picks = [(r["round"], r["side"], r["unit"], r["kind"]) for r in result["planner_positions"]]
    payload = {
        "winner": result["winner"],
        "vp": result["vp"],
        "objectives": result["objectives"],
        "picks": picks,
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()


def _worker(seeds: list[int], army1: str, army2: str, repo: str, bank: str) -> list[dict]:
    """One process's slice: one `Core`, reused across every seed here — the
    unit under test for the 'N workers' throughput question."""
    core = nml_core.load(repo)
    out = []
    for seed in seeds:
        t0 = time.perf_counter()
        res = sp.play_game(seed, army1, army2, repo, bank, core)
        wall = time.perf_counter() - t0
        out.append({"seed": seed, "wall_seconds": wall, "digest": digest_of(res)})
    return out


def _split(seeds: list[int], n: int) -> list[list[int]]:
    """Round-robin so every worker gets a near-equal slice."""
    buckets: list[list[int]] = [[] for _ in range(n)]
    for i, s in enumerate(seeds):
        buckets[i % n].append(s)
    return [b for b in buckets if b]


def run(n: int, games: int, seed_start: int, army1: str, army2: str, repo: str, bank: str) -> dict:
    seeds = list(range(seed_start, seed_start + games))
    buckets = _split(seeds, n)
    ctx = mp.get_context("spawn")
    t_start = time.perf_counter()
    with ctx.Pool(processes=len(buckets)) as pool:
        chunks = pool.starmap(_worker, [(b, army1, army2, repo, bank) for b in buckets])
    wall_total = time.perf_counter() - t_start
    per_game = sorted((g for chunk in chunks for g in chunk), key=lambda g: g["seed"])
    mean_s = sum(g["wall_seconds"] for g in per_game) / len(per_game)
    return {
        "n_workers": n,
        "games": len(per_game),
        "seed_start": seed_start,
        "wall_total_seconds": round(wall_total, 3),
        "mean_seconds_per_game": round(mean_s, 4),
        "games_per_hour": round(len(per_game) / wall_total * 3600.0, 1),
        "per_game": per_game,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--n", type=int, required=True, help="worker process count")
    ap.add_argument("--games", type=int, default=40, help="games total, split across workers")
    ap.add_argument("--seed-start", type=int, default=1, help="first seed (bank covers 1..200)")
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--repo", required=True, help="repo root — assets/solo/*.json live here")
    ap.add_argument("--bank", required=True, help="terrain bank directory")
    ap.add_argument("--out", required=True, help="path for the JSON summary")
    ap.add_argument(
        "--check-determinism-seed",
        type=int,
        default=None,
        help="also play this seed alone in the parent process and compare its "
        "digest to the same seed's digest from the parallel run",
    )
    a = ap.parse_args(argv)

    repo = str(Path(a.repo).resolve())
    load_before = os.getloadavg()
    result = run(a.n, a.games, a.seed_start, a.army1, a.army2, repo, a.bank)
    load_after = os.getloadavg()
    result["cpu_count"] = os.cpu_count()
    result["load_avg_before"] = list(load_before)
    result["load_avg_after"] = list(load_after)

    if a.check_determinism_seed is not None:
        seed = a.check_determinism_seed
        parallel_digest = next((g["digest"] for g in result["per_game"] if g["seed"] == seed), None)
        if parallel_digest is None:
            raise SystemExit(
                "--check-determinism-seed %d is outside [%d, %d) — not played by this run"
                % (seed, a.seed_start, a.seed_start + a.games)
            )
        core = nml_core.load(repo)
        solo = sp.play_game(seed, a.army1, a.army2, repo, a.bank, core)
        solo_digest = digest_of(solo)
        result["determinism_check"] = {
            "seed": seed,
            "single_process_digest": solo_digest,
            "parallel_digest": parallel_digest,
            "match": solo_digest == parallel_digest,
        }

    out_path = Path(a.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    summary = {k: v for k, v in result.items() if k != "per_game"}
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
