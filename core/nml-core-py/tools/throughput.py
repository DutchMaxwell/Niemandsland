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
        [--check-determinism-seed 27] [--check-all] [--red-worker-jitter]

DETERMINISM (GATE Q C4, NML-1073). Both `--check-determinism-seed` and
`--check-all` hash with `selfplay.result_digest` — the WHOLE result dict, not
a handful of top-level numbers — and exit 1 on any mismatch, printing a
`DETERMINISM ...` line either way. `--check-all` compares every seed of the
`--n` run against a second, single-worker (N=1) pass over the same seeds.
`--red-worker-jitter` is the built-in RED PROOF: it makes worker 0 of the
`--n` run perturb its deployment (game-shaping, not cosmetic — see
`_worker`'s docstring), so a check that could not tell two different games
apart would stay green anyway; naming the jittered worker's seeds in
`--check-all`'s output is how the gate proves it noticed.

Seeds run [--seed-start, --seed-start + games). NOTE: the M3-4 terrain bank
only carries boards for seeds 1..200 (see core/nml-core-py/README.md, "The
terrain gate"); board_1000.json does not exist, so --seed-start defaults to 1
rather than the 1000 a fleet-sizing run would eventually use — this probe
measures wall time, which does not depend on which banked seeds are played.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay as sp  # noqa: E402


def _worker(
    seeds: list[int], army1: str, army2: str, repo: str, bank: str, jitter: bool = False
) -> list[dict]:
    """One process's slice: one `Core`, reused across every seed here — the
    unit under test for the 'N workers' throughput question.

    `jitter`, the `--red-worker-jitter` RED PROOF (GATE Q C4, NML-1073): when
    set, every seed THIS worker plays deploys from `seed + 1` instead of
    `seed` — `play_game`'s own `deploy_rng_seed` knob, which discards the same
    number of draws from the game's own generator so only the deployment
    moves (see `selfplay.play_game`'s docstring). `run()` sets this only on
    worker 0, so a clean N=1 pass over the same seeds disagrees on exactly
    that worker's seeds and nothing else."""
    core = nml_core.load(repo)
    out = []
    for seed in seeds:
        t0 = time.perf_counter()
        deploy_rng_seed = (seed + 1) if jitter else None
        res = sp.play_game(seed, army1, army2, repo, bank, core, deploy_rng_seed=deploy_rng_seed)
        wall = time.perf_counter() - t0
        out.append({"seed": seed, "wall_seconds": wall, "digest": sp.result_digest(res)})
    return out


def _split(seeds: list[int], n: int) -> list[list[int]]:
    """Round-robin so every worker gets a near-equal slice."""
    buckets: list[list[int]] = [[] for _ in range(n)]
    for i, s in enumerate(seeds):
        buckets[i % n].append(s)
    return [b for b in buckets if b]


def run(
    n: int,
    games: int,
    seed_start: int,
    army1: str,
    army2: str,
    repo: str,
    bank: str,
    jitter: bool = False,
) -> dict:
    """`jitter` is `--red-worker-jitter` (see `_worker`): applied to bucket 0
    ONLY, so `run(1, ...)` (the `--check-all` reference pass) is unaffected by
    it even when a caller forgets to pass `jitter=False` explicitly there —
    with one bucket, "worker 0" would be every seed, which is why callers of
    the clean reference pass never set this."""
    seeds = list(range(seed_start, seed_start + games))
    buckets = _split(seeds, n)
    ctx = mp.get_context("spawn")
    t_start = time.perf_counter()
    with ctx.Pool(processes=len(buckets)) as pool:
        chunks = pool.starmap(
            _worker,
            [(b, army1, army2, repo, bank, jitter and i == 0) for i, b in enumerate(buckets)],
        )
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
        "full-result digest to the same seed's digest from the parallel run "
        "(GATE Q C4, NML-1073) — exits 1 on mismatch",
    )
    ap.add_argument(
        "--check-all",
        action="store_true",
        help="compare EVERY seed of this run against a second, single-worker "
        "(N=1) pass over the same seeds — exits 1 on any mismatch and names "
        "the mismatching seeds",
    )
    ap.add_argument(
        "--red-worker-jitter",
        action="store_true",
        help="RED PROOF: worker 0 of the --n run deploys from seed+1 instead "
        "of seed (game-shaping, everything else on the game's own dice) — "
        "the determinism checks above must then fail on worker 0's seeds",
    )
    a = ap.parse_args(argv)

    repo = str(Path(a.repo).resolve())
    load_before = os.getloadavg()
    result = run(a.n, a.games, a.seed_start, a.army1, a.army2, repo, a.bank, jitter=a.red_worker_jitter)
    load_after = os.getloadavg()
    result["cpu_count"] = os.cpu_count()
    result["load_avg_before"] = list(load_before)
    result["load_avg_after"] = list(load_after)

    exit_code = 0

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
        solo_digest = sp.result_digest(solo)
        match = solo_digest == parallel_digest
        result["determinism_check"] = {
            "seed": seed,
            "single_process_digest": solo_digest,
            "parallel_digest": parallel_digest,
            "match": match,
        }
        print(
            "DETERMINISM seed=%d match=%s digest=%s"
            % (seed, "true" if match else "false", solo_digest)
        )
        if not match:
            print("  single_process_digest=%s" % solo_digest)
            print("  parallel_digest=%s" % parallel_digest)
            exit_code = 1

    if a.check_all:
        # The reference pass is ALWAYS clean (jitter=False) — see run()'s
        # docstring for why that is safe even though n=1 makes bucket 0 carry
        # every seed.
        solo_result = run(1, a.games, a.seed_start, a.army1, a.army2, repo, a.bank)
        solo_by_seed = {g["seed"]: g["digest"] for g in solo_result["per_game"]}
        parallel_by_seed = {g["seed"]: g["digest"] for g in result["per_game"]}
        mismatched = sorted(
            s for s in parallel_by_seed if solo_by_seed.get(s) != parallel_by_seed[s]
        )
        all_match = not mismatched
        result["determinism_check_all"] = {
            "n_workers": a.n,
            "games": len(parallel_by_seed),
            "match": all_match,
            "mismatched_seeds": mismatched,
        }
        print(
            "DETERMINISM check-all n=%d games=%d match=%s mismatched_seeds=%s"
            % (
                a.n,
                len(parallel_by_seed),
                "true" if all_match else "false",
                ",".join(str(s) for s in mismatched) if mismatched else "none",
            )
        )
        if not all_match:
            exit_code = 1

    out_path = Path(a.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    summary = {k: v for k, v in result.items() if k != "per_game"}
    print(json.dumps(summary, indent=2))
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
