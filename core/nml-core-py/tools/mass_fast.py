"""The planner-lane training corpus, on the fast trainer (NML-1073 GATE Q).

Reproduces `farm/mass_wave_template.sh` (private fleet script; formula copied
here verbatim) with `python/selfplay.py` in the loop instead of a headless
Godot process per game. That script drove the OLD training corpus:

    F=(alien_hives battle_brothers blessed_sisters blood_brothers
       change_disciples robot_legions)
    S=(1000 1500 2000)
    fa=${F[$((s % 6))]}; fb=${F[$(((s / 6) % 6))]}; sz=${S[$(((s / 36) % 3))]}

for seed `s`, one game each, `NML_TOP_K=2 NML_HORIZON=1`, seeds from 300000,
flat output `core_s<seed>.json` per seed. This module derives the same
(fa, fb, sz) triple from the same arithmetic (`derive_pairing`, pinned by
`tests/python/test_mass_fast.py` against the first 40 seeds of the real run),
plays each seed through `selfplay.play_game` in a worker pool, and writes the
same flat, non-recursive directory shape the net-training readers
(`~/nml-mission/netlab/e1b_run.py`'s `load8`, `fork_train.py`'s
`load_world2`) already glob.

RESUMABILITY. A seed whose `core_s<seed>.json` already exists is never
replayed — the file on disk is the only truth the run consults, not a
sidecar state file, so a killed and restarted run costs nothing but the
`os.path.exists` calls for the seeds it already finished.

SELF-CHECKING. `--check-sample FRACTION` re-plays that fraction of the run's
seeds SINGLE-PROCESS after the parallel run finishes and compares
`selfplay.result_digest` of the fresh replay against the digest of the
WRITTEN FILE on disk (not the in-memory result — a corpus's proof has to read
what a later reader will actually read). Any mismatch is fatal: exit 1,
every mismatching seed named. This is the corpus's own determinism proof,
independent of `tools/throughput.py`'s (which checks a --n run against
itself, never against a file on disk).
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
import random
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
import selfplay as sp  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]

# The private fleet script's own faction/size arrays, verbatim (see module
# docstring) -- this order is the pinned contract, not a convenience list.
FACTIONS = [
    "alien_hives",
    "battle_brothers",
    "blessed_sisters",
    "blood_brothers",
    "change_disciples",
    "robot_legions",
]
DEFAULT_SIZES = [1000, 1500, 2000]

DEFAULT_LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
DEFAULT_BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))


def derive_pairing(seed: int, sizes: list[int] = DEFAULT_SIZES) -> tuple[str, str, int]:
    """`(fa, fb, sz)` for `seed`, the SAME arithmetic
    `farm/mass_wave_template.sh` uses: `fa=F[s%6]`, `fb=F[(s/6)%6]`,
    `sz=S[(s/36)%3]` (bash integer division == `//`). `sizes` generalises the
    modulus to `len(sizes)` so a caller may pass a different size list; the
    default (3 sizes) reproduces the old corpus's `%3` bit for bit."""
    fa = FACTIONS[seed % len(FACTIONS)]
    fb = FACTIONS[(seed // len(FACTIONS)) % len(FACTIONS)]
    sz = sizes[(seed // (len(FACTIONS) * len(FACTIONS))) % len(sizes)]
    return fa, fb, sz


def list_paths(seed: int, lists_dir: Path, sizes: list[int]) -> tuple[Path, Path, str, str, int]:
    fa, fb, sz = derive_pairing(seed, sizes)
    return lists_dir / f"{fa}_{sz}.json", lists_dir / f"{fb}_{sz}.json", fa, fb, sz


def _atomic_write_json(path: Path, obj: dict) -> None:
    """tmp-in-same-dir + `os.replace` -- a reader (this tool's own resume
    check, or a net-training glob) never observes a partially written file,
    because `os.replace` is atomic on the same filesystem and no reader ever
    sees the tmp name (it does not match `core_s*.json`)."""
    tmp = path.with_name(f".tmp-{path.name}.{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


#: The mode knobs `selfplay.play_game` takes beyond `top_k`/`horizon`, with the
#: value each one has when nothing is passed. A corpus generator that cannot
#: reach them can only ever write PRE-M5 games: `dice="expected"` (no tray),
#: `movement="rigid"` (no M4 charge route), `hero_attach="off"` (no joined
#: heroes), `charge_landing="off"` (no second engage question) -- silently, and
#: with a header that correctly says so, which is the only reason it was never
#: caught by a gate.
FIDELITY_DEFAULTS = {
    "charge_gate": "off",
    "hero_attach": "off",
    "dice": "expected",
    "charge_landing": "off",
    "movement": "rigid",
    "sighting": "unit",
    "objectives": "constant",
    "engage_fold": True,
    "cond_ap": None,
}


def _worker(
    seeds: list[int],
    lists_dir: str,
    repo: str,
    bank: str,
    out_dir: str,
    sizes: list[int],
    top_k: int,
    horizon: int,
    fidelity: dict,
) -> list[dict]:
    """One process's slice of NEEDED seeds (the caller has already dropped
    seeds whose file exists). Writes each result to disk itself (atomically)
    rather than returning the full game payload through the pool -- a
    training-scale run is many thousands of these, and pickling the whole
    result dict back to the parent for every game would be the bottleneck this
    tool exists to avoid.

    ONE `Core` PER GAME, unlike `throughput.py`'s worker: `RowEncoder.unknown`
    (rows.rs) is never cleared -- neither `set_header` nor `set_vocab_version`
    touches it -- so a reused core makes `unknown_rules` CUMULATIVE, and every
    result file after the first in a slice claims rule names that came off an
    earlier game's roster. `qa_gate.py` already builds one core per game for
    exactly this reason. The cost is nil: `set_header` rebuilds `Registries`
    per game anyway (nml-core-py/src/lib.rs), which is the expensive part."""
    out = Path(out_dir)
    rows = []
    for seed in seeds:
        core = nml_core.load(repo)
        list1, list2, fa, fb, sz = list_paths(seed, Path(lists_dir), sizes)
        t0 = time.perf_counter()
        res = sp.play_game(seed, list1, list2, repo, bank, core, top_k=top_k, horizon=horizon,
                           **fidelity)
        wall = time.perf_counter() - t0
        res["wall_seconds"] = round(wall, 3)
        digest = sp.result_digest(res)
        _atomic_write_json(out / f"core_s{seed}.json", res)
        rows.append(
            {"seed": seed, "fa": fa, "fb": fb, "sz": sz, "digest": digest, "wall_s": round(wall, 3)}
        )
    return rows


def _split(seeds: list[int], n: int) -> list[list[int]]:
    """Round-robin so every worker gets a near-equal slice (throughput.py's
    own `_split`)."""
    buckets: list[list[int]] = [[] for _ in range(n)]
    for i, s in enumerate(seeds):
        buckets[i % n].append(s)
    return [b for b in buckets if b]


def _commit(repo: str) -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True, check=True
        ).stdout.strip()
    except Exception:
        return "unknown"


def _read_manifest(path: Path) -> dict[int, dict]:
    rows: dict[int, dict] = {}
    if not path.exists():
        return rows
    with open(path, encoding="utf-8") as f:
        header = f.readline()
        cols = header.rstrip("\n").split("\t")
        for line in f:
            parts = line.rstrip("\n").split("\t")
            row = dict(zip(cols, parts))
            try:
                seed = int(row["seed"])
            except (KeyError, ValueError):
                continue
            row["sz"] = int(row["sz"]) if row.get("sz") else 0
            rows[seed] = row
    return rows


def _write_manifest(path: Path, rows: dict[int, dict]) -> None:
    cols = ["seed", "fa", "fb", "sz", "digest", "wall_s"]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\t".join(cols) + "\n")
        for seed in sorted(rows):
            row = rows[seed]
            f.write("\t".join(str(row.get(c, "")) for c in cols) + "\n")


def _row_from_existing(seed: int, path: Path, fa: str, fb: str, sz: int) -> dict:
    """Backfill a manifest row for a seed whose file already existed but
    carried no manifest entry yet (a directory seeded by another tool, or an
    older MANIFEST.tsv) -- read the file once, hash it, done."""
    with open(path, encoding="utf-8") as f:
        result = json.load(f)
    digest = sp.result_digest(result)
    wall_s = result.get("wall_seconds", "")
    return {"seed": seed, "fa": fa, "fb": fb, "sz": sz, "digest": digest, "wall_s": wall_s}


def run_check_sample(
    seeds: list[int],
    frac: float,
    lists_dir: Path,
    repo: str,
    bank: str,
    out_dir: Path,
    sizes: list[int],
    top_k: int,
    horizon: int,
    fidelity: dict,
) -> tuple[bool, list[int]]:
    """Re-play `frac` of `seeds` single-process and compare
    `selfplay.result_digest` against the digest of the WRITTEN FILE on disk
    -- the corpus's own determinism proof (module docstring). Returns
    `(all_match, mismatched_seeds)`."""
    if frac <= 0.0 or not seeds:
        return True, []
    k = max(1, round(len(seeds) * frac)) if frac < 1.0 else len(seeds)
    k = min(k, len(seeds))
    rng = random.Random("mass_fast_check_sample:%d:%d:%d" % (seeds[0], len(seeds), round(frac * 1e6)))
    sample = sorted(rng.sample(seeds, k))

    mismatched = []
    for seed in sample:
        core = nml_core.load(repo)
        list1, list2, _fa, _fb, _sz = list_paths(seed, lists_dir, sizes)
        fresh = sp.play_game(seed, list1, list2, repo, bank, core, top_k=top_k, horizon=horizon,
                             **fidelity)
        fresh_digest = sp.result_digest(fresh)
        path = out_dir / f"core_s{seed}.json"
        with open(path, encoding="utf-8") as f:
            written = json.load(f)
        written_digest = sp.result_digest(written)
        if fresh_digest != written_digest:
            mismatched.append(seed)
    return not mismatched, mismatched


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed-start", type=int, required=True)
    ap.add_argument("--games", type=int, required=True)
    ap.add_argument("--workers", type=int, required=True)
    ap.add_argument("--out", required=True, help="flat output dir for core_s<seed>.json")
    ap.add_argument(
        "--top-k", type=int, default=2, help="planner ROLLOUT_TOP_K (old corpus: NML_TOP_K=2)"
    )
    ap.add_argument(
        "--horizon", type=int, default=1, help="planner ROLLOUT_HORIZON_ROUNDS (old corpus: NML_HORIZON=1)"
    )
    ap.add_argument("--lists", default=str(DEFAULT_LISTS), help="dir of <faction>_<size>.json lists")
    ap.add_argument("--bank", default=str(DEFAULT_BANK), help="terrain bank dir")
    ap.add_argument("--repo", default=str(REPO_ROOT), help="repo root -- assets/solo/*.json live here")
    ap.add_argument("--sizes", default="1000,1500,2000", help="comma-separated point sizes, S[] above")
    ap.add_argument("--dice", choices=list(sp.DICE_MODES), default=FIDELITY_DEFAULTS["dice"])
    ap.add_argument("--charge-gate", choices=list(sp.CHARGE_GATE_MODES),
                    default=FIDELITY_DEFAULTS["charge_gate"])
    ap.add_argument("--hero-attach", choices=list(sp.HERO_ATTACH_MODES),
                    default=FIDELITY_DEFAULTS["hero_attach"])
    ap.add_argument("--charge-landing", choices=list(sp.CHARGE_LANDING_MODES),
                    default=FIDELITY_DEFAULTS["charge_landing"])
    ap.add_argument("--movement", choices=list(sp.MOVEMENT_MODES),
                    default=FIDELITY_DEFAULTS["movement"])
    ap.add_argument("--sighting", choices=list(sp.SIGHTING_MODES),
                    default=FIDELITY_DEFAULTS["sighting"])
    ap.add_argument("--objectives", choices=list(sp.OBJECTIVES_MODES),
                    default=FIDELITY_DEFAULTS["objectives"])
    ap.add_argument("--no-engage-fold", dest="engage_fold", action="store_false", default=True,
                    help="RED switch for the D5-4 attached-hero fold of the engage test")
    ap.add_argument(
        "--net",
        default="",
        help="NML-1142 -- a netlab/fork_train.py ENCODER net JSON. Every game of "
        "the run then plays the FITTED eval (`AiMissionEval.fit_mode`); empty "
        "(the default) is the hand eval and every corpus written before it",
    )
    ap.add_argument("--cond-ap", choices=["auto", "on", "off"], default="auto",
                    help="conditional AP (NML-1103); 'auto' leaves the process global alone")
    ap.add_argument(
        "--check-sample",
        type=float,
        default=0.0,
        help="re-play this fraction of the run's seeds single-process and diff "
        "result_digest against the written files; 0 skips the check",
    )
    a = ap.parse_args(argv)

    fidelity = {
        "charge_gate": a.charge_gate,
        "hero_attach": a.hero_attach,
        "dice": a.dice,
        "charge_landing": a.charge_landing,
        "movement": a.movement,
        "sighting": a.sighting,
        "objectives": a.objectives,
        "engage_fold": a.engage_fold,
        "cond_ap": None if a.cond_ap == "auto" else (a.cond_ap == "on"),
        # NML-1142: WHICH eval played. `None` is the hand eval -- the default,
        # and what every corpus written before this knob carries. It rides
        # `fidelity` like the rest, so `.RUN.json` records the brain too.
        "net": a.net or None,
    }

    sizes = [int(x) for x in a.sizes.split(",")]
    lists_dir = Path(a.lists)
    out_dir = Path(a.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    repo = str(Path(a.repo).resolve())
    bank = str(Path(a.bank).resolve())

    seeds = list(range(a.seed_start, a.seed_start + a.games))

    # Resolve every list file this run touches BEFORE dispatching workers --
    # a missing list is a fast, clear SystemExit here rather than a worker
    # traceback the pool then has to unwind.
    needed_lists: set[Path] = set()
    for seed in seeds:
        l1, l2, _fa, _fb, _sz = list_paths(seed, lists_dir, sizes)
        needed_lists.add(l1)
        needed_lists.add(l2)
    missing = sorted(p for p in needed_lists if not p.exists())
    if missing:
        raise SystemExit(
            "missing army list(s), resolved from --lists %s:\n  %s"
            % (lists_dir, "\n  ".join(str(p) for p in missing))
        )

    manifest_path = out_dir / "MANIFEST.tsv"
    manifest = _read_manifest(manifest_path)

    needed = [s for s in seeds if not (out_dir / f"core_s{s}.json").exists()]
    resumed = [s for s in seeds if s not in needed]

    t_start = time.perf_counter()
    start_iso = datetime.now(timezone.utc).isoformat()

    if needed:
        buckets = _split(needed, a.workers)
        ctx = mp.get_context("spawn")
        with ctx.Pool(processes=len(buckets)) as pool:
            chunks = pool.starmap(
                _worker,
                [
                    (b, str(lists_dir), repo, bank, str(out_dir), sizes, a.top_k, a.horizon,
                     fidelity)
                    for b in buckets
                ],
            )
        for chunk in chunks:
            for row in chunk:
                manifest[row["seed"]] = row

    wall_played = time.perf_counter() - t_start
    end_iso = datetime.now(timezone.utc).isoformat()

    for seed in resumed:
        if seed in manifest:
            continue
        fa, fb, sz = derive_pairing(seed, sizes)
        manifest[seed] = _row_from_existing(seed, out_dir / f"core_s{seed}.json", fa, fb, sz)

    _write_manifest(manifest_path, manifest)

    games_per_h = round(len(needed) / wall_played * 3600.0, 1) if needed and wall_played > 0 else 0.0

    run_info = {
        "args": vars(a),
        "commit": _commit(repo),
        "knobs": dict(fidelity, top_k=a.top_k, horizon=a.horizon),
        "start": start_iso,
        "end": end_iso,
        "games": a.games,
        "games_played": len(needed),
        "games_resumed": len(resumed),
        "wall_played_seconds": round(wall_played, 3),
        "games_per_hour": games_per_h,
    }
    # `.RUN.json`, not `RUN.json`: `~/nml-mission/netlab/e1b_run.py`'s `load8`
    # and `fork_train.py`'s `load_world2` glob `DATA + "/*.json"` NON-
    # recursively over this same directory (GATE Q proof (e)) -- Python's
    # glob module never matches a dotfile against a bare `*`, so a plain
    # `RUN.json` would be handed to the corpus gate as a 217th "game" and
    # fail it (`board_schema_mismatch`, fatal unless whitelisted). The dot
    # keeps the run's own metadata OUT of every corpus reader's sight while
    # still living inside `DIR` next to the files it describes.
    with open(out_dir / ".RUN.json", "w", encoding="utf-8") as f:
        json.dump(run_info, f, indent=2)

    check_status = "ok"
    exit_code = 0
    if a.check_sample > 0.0:
        ok, mismatched = run_check_sample(
            seeds, a.check_sample, lists_dir, repo, bank, out_dir, sizes, a.top_k, a.horizon,
            fidelity,
        )
        if ok:
            print("CHECK_SAMPLE match=true seeds=%d" % max(1, round(len(seeds) * a.check_sample)))
        else:
            check_status = "FAIL"
            exit_code = 1
            print(
                "CHECK_SAMPLE match=false mismatched_seeds=%s"
                % ",".join(str(s) for s in mismatched)
            )

    print(
        "MASS_FAST_DONE games=%d out=%s games_per_h=%s check_sample=%s"
        % (a.games, out_dir, games_per_h, check_status)
    )
    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
