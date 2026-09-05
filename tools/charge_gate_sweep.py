#!/usr/bin/env python3
"""Run and aggregate the fixed-seed arena gate for charge declarations.

Each game uses the production arena_match.gd path and writes a full decision/log
capture. Runs are sequential and resumable so this remains safe on development
machines shared with other long-running jobs.

Example:
  python3 tools/charge_gate_sweep.py --out /tmp/charge-before
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


DEFAULT_SEED_START = 71700
DEFAULT_GAMES = 100
REPO = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_BIN", "godot")
P1 = P2 = "kriegsherr"
TIMEOUT_SECONDS = 300
MIN_MEMORY_MB = 3500
SHORT_RE = re.compile(r"charge falls short", re.IGNORECASE)


def available_memory_mb() -> int:
    match = re.search(r"^MemAvailable:\s+(\d+)", Path("/proc/meminfo").read_text(), re.MULTILINE)
    return int(match.group(1)) // 1024 if match else 0


def capture_metrics(capture_dir: Path) -> tuple[int, int, int]:
    decisions = json.loads((capture_dir / "decisions.json").read_text(encoding="utf-8"))
    battle_log = (capture_dir / "battlelog.txt").read_text(encoding="utf-8")
    declared = sum(
        1
        for record in decisions
        if record.get("kind") == "action"
        and str(record.get("chosen", "")).lower() == "charges"
    )
    ended_short = len(SHORT_RE.findall(battle_log))
    # A short charge cannot shoot and never reaches the melee resolver. Its whole
    # activation is therefore spent on the failed charge declaration.
    return declared, ended_short, ended_short


def result_path(out_dir: Path, seed: int) -> Path:
    return out_dir / f"arena_{P1}_vs_{P2}_s{seed}_d{seed}.json"


def game_row(out_dir: Path, seed: int) -> dict:
    result = json.loads(result_path(out_dir, seed).read_text(encoding="utf-8"))
    declared, ended_short, wasted = capture_metrics(out_dir / f"seed_{seed}")
    return {
        "seed": seed,
        "winner": result.get("winner", "draw"),
        "charges_declared": declared,
        "charges_ended_short": ended_short,
        "wasted_activations": wasted,
    }


def aggregate(rows: list[dict]) -> dict:
    outcomes = {"p1": 0, "draw": 0, "p2": 0}
    for row in rows:
        winner = row["winner"] if row["winner"] in outcomes else "draw"
        outcomes[winner] += 1
    return {
        "games": len(rows),
        "charges_declared": sum(row["charges_declared"] for row in rows),
        "charges_ended_short": sum(row["charges_ended_short"] for row in rows),
        "wasted_activations": sum(row["wasted_activations"] for row in rows),
        "outcomes": outcomes,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--games", type=int, default=DEFAULT_GAMES)
    parser.add_argument("--seed-start", type=int, default=DEFAULT_SEED_START)
    parser.add_argument("--resume", action="store_true")
    return parser.parse_args()


def run_game(args: argparse.Namespace, seed: int) -> None:
    while available_memory_mb() < MIN_MEMORY_MB:
        print(f"seed {seed}: waiting for {MIN_MEMORY_MB} MB available memory", flush=True)
        time.sleep(30)
    capture_dir = args.out / f"seed_{seed}"
    capture_dir.mkdir(parents=True, exist_ok=True)
    log_path = capture_dir / "arena.log"
    cmd = [
        GODOT, "--headless", "--path", str(REPO),
        "-s", "res://tools/arena_match.gd", "--",
        f"p1={P1}", f"p2={P2}", f"seed={seed}", f"dice_seed={seed}",
        f"out={args.out}", f"capture={capture_dir}",
    ]
    with log_path.open("w", encoding="utf-8") as log_file:
        completed = subprocess.run(cmd, cwd=REPO, stdout=log_file,
                                   stderr=subprocess.STDOUT, timeout=TIMEOUT_SECONDS, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"seed {seed}: Godot exited {completed.returncode}; see {log_path}")
    expected = result_path(args.out, seed)
    if not expected.exists() or not (capture_dir / "decisions.json").exists():
        raise RuntimeError(f"seed {seed}: arena artifacts missing; see {log_path}")


def main() -> int:
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for index, seed in enumerate(range(args.seed_start, args.seed_start + args.games), start=1):
        expected = result_path(args.out, seed)
        capture_dir = args.out / f"seed_{seed}"
        complete = expected.exists() and (capture_dir / "decisions.json").exists() \
            and (capture_dir / "battlelog.txt").exists()
        if not (args.resume and complete):
            print(f"[{index}/{args.games}] seed {seed}", flush=True)
            run_game(args, seed)
        row = game_row(args.out, seed)
        rows.append(row)
        print(json.dumps(row, sort_keys=True), flush=True)

    report = {
        "schema": 1,
        "seed_start": args.seed_start,
        "games_requested": args.games,
        "p1": P1,
        "p2": P2,
        "rows": rows,
        "aggregate": aggregate(rows),
    }
    report_path = args.out / "charge_gate_sweep.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("AGG " + json.dumps(report["aggregate"], sort_keys=True))
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
