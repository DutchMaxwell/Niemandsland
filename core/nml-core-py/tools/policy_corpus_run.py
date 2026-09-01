#!/usr/bin/env python3
"""NML-1158b step 3 recipe — a whole recorded corpus into policy rows.

Runs tools/policy_dump.gd (headless Godot, read-only replay dump) over every
game directory of --corpus with a small worker pool, concatenates the
per-game dumps under one header, then calls policy_rows.py to join the game
outcome. A game whose dump exits nonzero had a flagged act (its rows are
withheld inside the dump, never written); it stays reported, its verified
rows stay in. All paths come from the command line — nothing is embedded.

Usage:
  python3 policy_corpus_run.py --corpus DIR --worktree GODOT_PROJECT \
      --rows-tool PATH --out DIR [--godot BIN] [--jobs 4] \
      [--import-project] [--tag NAME] [--rows-args "..."]
"""
import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def dump_one(a, game, dump_dir, log_dir, pid_dir):
    out_f = dump_dir / (game.name + ".jsonl")
    pid_f = pid_dir / (game.name + ".pid")
    cmd = [a.godot, "--headless", "-s", "res://tools/policy_dump.gd", "--",
           f"file={game / 'acts.jsonl'}", f"out={out_f}"]
    proc = subprocess.Popen(cmd, cwd=a.worktree, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)
    pid_f.write_text(str(proc.pid))
    _, err = proc.communicate()
    pid_f.unlink(missing_ok=True)
    (log_dir / (game.name + ".log")).write_text(err or "")
    return proc.returncode


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", required=True, type=Path)
    ap.add_argument("--worktree", required=True, type=Path)
    ap.add_argument("--rows-tool", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--import-project", action="store_true",
                    help="run `godot --headless --import` on the worktree first")
    ap.add_argument("--tag", default=None, help="name for dumps/ and the rows file")
    ap.add_argument("--rows-args", default="", help="extra args for policy_rows.py")
    a = ap.parse_args()
    games = sorted({p.parent for p in a.corpus.glob("*/acts.jsonl")})
    if not games:
        sys.exit(f"no games with acts.jsonl under {a.corpus}")
    for sub in ("dumps", "logs", "pids"):
        (a.out / sub).mkdir(parents=True, exist_ok=True)
    (a.out / "pids" / "runner.pid").write_text(str(os.getpid()))
    if a.import_project:
        subprocess.run([a.godot, "--headless", "--import"], cwd=a.worktree,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    tag = a.tag or a.corpus.name
    dump_dir = a.out / "dumps" / tag
    dump_dir.mkdir(exist_ok=True)
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        codes = list(ex.map(lambda g: dump_one(a, g, dump_dir, a.out / "logs",
                                               a.out / "pids"), games))
    bad = [g.name for g, c in zip(games, codes) if c]
    header, body = None, []
    for f in sorted(dump_dir.glob("*.jsonl")):
        for ln in f.read_text().splitlines():
            if '"kind":"header"' in ln:
                header = header or ln
            elif ln.strip():
                body.append(ln)
    if not body:
        sys.exit("every dump empty — refusing to join")
    all_f = a.out / "dumps" / f"{tag}_all.jsonl"
    all_f.write_text(header + "\n" + "\n".join(body) + "\n")
    rows_out = a.out / f"policy_rows_{tag}.jsonl"
    cmd = [sys.executable, str(a.rows_tool), f"--dump={all_f}",
           f"--corpus={a.corpus}", f"--out={rows_out}"]
    if a.rows_args:
        cmd += a.rows_args.split()
    r = subprocess.run(cmd)
    print(f"POLICY_CORPUS_RUN corpus={a.corpus} games={len(games)} flagged={len(bad)} "
          f"dumped_menus={len(body)} wall={time.time() - t0:.0f}s rows_exit={r.returncode}")
    if bad:
        print("flagged games:", ", ".join(bad[:10]) + (" ..." if len(bad) > 10 else ""))
    (a.out / f"run_{tag}.txt").write_text(f"games={len(games)} flagged={len(bad)} "
                                          f"menus={len(body)} wall={time.time() - t0:.0f}s\n")
    return r.returncode or (1 if bad else 0)


if __name__ == "__main__":
    sys.exit(main())
