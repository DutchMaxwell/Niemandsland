#!/usr/bin/env python3
"""Sequential developer acceptance; run only in a reserved headless test slot.

Both roots must already contain their own built/installed NmlCore library.
This does not build, change sources, merge, or remove prior result directories.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


def run_game(args, repo, mode, seed):
    directory = args.out / (mode + "_" + str(seed))
    directory.mkdir(parents=True, exist_ok=False)
    log_path = directory / "game.log"
    env = {k: v for k, v in os.environ.items() if not k.startswith("NML_")}
    env.update(NML_CORE="1", NML_TRACE="1", NML_TOP_K="1", NML_HORIZON="1")
    brain = None
    killed = False
    game = None
    try:
        if mode in ("on", "killed"):
            port_file = directory / "port"
            brain = subprocess.Popen([sys.executable, str(repo / "test/e2e/brain_fixture.py"), str(port_file)])
            deadline = time.monotonic() + 10
            while not port_file.exists():
                if brain.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("fake brain failed to start")
                time.sleep(0.02)
            env["NML_BRAIN_URL"] = "http://127.0.0.1:" + port_file.read_text().strip()
        with log_path.open("w") as log:
            game = subprocess.Popen([args.godot, "--headless", "--path", str(repo),
                "-s", "res://tools/arena_match.gd", "--", "p1=planner_v0", "p2=planner_v0",
                "seed=" + str(seed), "batch=1", "out=" + str(directory),
                "capture=" + str(directory / "capture")], stdout=log, stderr=subprocess.STDOUT, env=env)
            deadline = time.monotonic() + args.timeout
            while game.poll() is None:
                if mode == "killed" and not killed and "[CORE] ACT" in log_path.read_text(errors="replace"):
                    brain.terminate()
                    brain.wait(timeout=5)
                    killed = True
                if time.monotonic() > deadline:
                    raise RuntimeError("arena game timed out: " + str(directory))
                time.sleep(0.05)
        if game.returncode != 0:
            raise RuntimeError("arena crashed/failed: " + str(directory))
        results = list(directory.glob("arena_*.json"))
        if len(results) != 1:
            raise RuntimeError("arena did not finish/write its result: " + str(directory))
        result = json.loads(results[0].read_text())
        assert result["rounds_played"] >= 1
        raw = (directory / "capture/decisions.json").read_bytes()
        decisions = json.loads(raw)
        assert any(r.get("kind") == "digest" for r in decisions), "missing state-digest trace"
        assisted = [r["data"] for r in decisions if r.get("kind") == "brain"]
        log = log_path.read_text(errors="replace")
        if mode in ("on", "killed"):
            assert assisted and "brain: constant-test zeros-v1" in log, "brain never consumed"
            assert all(r["name"] == "constant-test" and r["batches"] == 1 for r in assisted)
        else:
            assert not assisted and "brain:" not in log, "unset URL reached the brain"
        if mode == "killed":
            assert killed and "LeafValueBridge" in log, "no typed mid-game decline"
        print("ARENA_ACCEPT", mode, seed, "PASS", "decisions=" + str(len(decisions)), flush=True)
        return raw, assisted
    finally:
        for process in (game, brain):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--seeds", type=int, default=20)
    parser.add_argument("--timeout", type=float, default=600)
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=False)
    # Warm each checkout's imports/cache through the same real game path first.
    for root in (args.baseline, args.candidate):
        subprocess.run([args.godot, "--headless", "--editor", "--quit", "--path", str(root)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
    run_game(args, args.baseline, "warm-base", 0)
    run_game(args, args.candidate, "warm-off", 0)
    hashes = {}
    latency = []
    for seed in range(1, args.seeds + 1):
        baseline, _ = run_game(args, args.baseline, "base", seed)
        candidate, _ = run_game(args, args.candidate, "off", seed)
        assert baseline == candidate, "decision bytes differ for seed %d (includes state digests)" % seed
        hashes[seed] = hashlib.sha256(candidate).hexdigest()
        _, assisted = run_game(args, args.candidate, "on", seed)
        latency.extend(r["batch_us"] / 1000 for r in assisted)
    run_game(args, args.candidate, "killed", args.seeds + 1)
    report = {"matching_seeds": args.seeds, "dummy_completed": args.seeds,
              "killed_server_completed": True, "decision_sha256": hashes,
              "batch_count": len(latency), "batch_ms_median": statistics.median(latency),
              "batch_ms_max": max(latency), "batches_per_assisted_activation": 1}
    (args.out / "summary.json").write_text(json.dumps(report, indent=2))
    print("ARENA_ACCEPT SUMMARY", json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
