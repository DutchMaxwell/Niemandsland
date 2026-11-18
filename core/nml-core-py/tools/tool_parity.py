"""PLAN G step 2 — parity driver: `selfplay.py` (Rust core) against a recorded `tools/core_selfplay.gd` oracle.

Plays each seed ONCE with `selfplay.play_game` at the oracle's knobs (`selfplay.LEGACY_FIDELITY_KNOBS`, agrees with
`TRAINER_KNOBS`; shipped loader, so use a FRESH oracle) and runs BOTH gates' own `compare()` on it (`selfplay_gate`:
winner/objectives/VP/rounds/picks; `sidecar_gate`: the file field by field; each stops at a seed's first difference).
Writes `parity_summary.json`: sha, core_commit, core_dirty, ref, seeds_requested/compared, rows_compared, missing,
refused, diffs [{seed, gate, path, ref, got}]. Refuse, never skip: exit 2 when a requested seed lacks `core_s<seed>.json`
or `acts_<seed>/acts.jsonl`, or nothing was compared. Exit 1 = a difference, 0 = all equal.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import nml_core  # noqa: E402

import list_to_profile  # noqa: E402
import selfplay as sp  # noqa: E402
import selfplay_gate  # noqa: E402
import sidecar_gate  # noqa: E402

TOL = 1e-9  # the sidecar gate's float tolerance


def scan_ref(ref_dir: Path, seeds: list[int]) -> tuple[dict[int, dict], list[int]]:
    """({seed: ref}, missing seeds). A seed needs a readable core_s<seed>.json with `planner_positions` AND its
    acts.jsonl (the picks; without them the M3-5 gate would silently drop its sharpest quantity)."""
    refs, missing = {}, []
    for seed in seeds:
        try:
            ref = json.loads((ref_dir / ("core_s%d.json" % seed)).read_text(encoding="utf-8"))
            ok = isinstance(ref["planner_positions"], list) and (ref_dir / ("acts_%d" % seed) / "acts.jsonl").is_file()
        except (OSError, ValueError, KeyError, TypeError):
            ok = False
        if ok:
            refs[seed] = ref
        else:
            missing.append(seed)
    return refs, missing


def compare_seed(seed: int, ref: dict, got: dict, picks) -> list[dict]:
    """Every difference of one seed, from both gates' own compare()."""
    found = {"selfplay": selfplay_gate.compare(ref, got, picks), "sidecar": sidecar_gate.compare(ref, got, TOL)}
    return [{"seed": seed, "gate": g, "path": p, "ref": r, "got": m} for g, ds in found.items() for p, r, m in ds]


def run_parity(ref_dir: Path, seeds: list[int], make_play, log=print) -> dict:
    """Judge `seeds` of the oracle at `ref_dir`. `make_play()` -> `play(seed) -> result dict` is called only once
    every seed has its reference: a refused run never loads a core and never plays a game."""
    refs, missing = scan_ref(ref_dir, seeds)
    out = {"ref": str(ref_dir), "seeds_requested": len(seeds), "seeds_compared": 0, "rows_compared": 0,
           "missing": missing, "refused": None, "diffs": []}
    for s in missing:
        log("seed %d MISSING core_s%d.json / acts_%d/acts.jsonl (absent or unreadable)" % (s, s, s))
    if missing or not refs:
        out["refused"] = "%d of %d requested seeds have no reference" % (len(missing), len(seeds)) if refs else "compared 0 seeds"
        return out
    play = make_play()
    for seed in seeds:
        diffs = compare_seed(seed, refs[seed], play(seed), selfplay_gate.ref_picks(ref_dir, seed))
        rows = len(refs[seed]["planner_positions"])
        out["seeds_compared"], out["rows_compared"], out["diffs"] = out["seeds_compared"] + 1, out["rows_compared"] + rows, out["diffs"] + diffs
        log("seed %d rows %d diffs %d" % (seed, rows, len(diffs)))
    return out


def exit_code(summary: dict) -> int:
    """2 = refused (nothing compared, or only part of the range), 1 = differences, 0 = equal."""
    return 2 if summary["refused"] else int(bool(summary["diffs"]))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for flag in ("--ref", "--bank", "--army1", "--army2", "--seeds"):
        ap.add_argument(flag, required=True)
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--out", default="parity_summary.json", help="where the summary JSON goes")
    a = ap.parse_args(argv)
    ref_dir, seeds = Path(a.ref), selfplay_gate.parse_seeds(a.seeds)

    def make_play():
        core = nml_core.load(a.repo)
        list_to_profile.LEGACY_CORE_SELFPLAY = False   # a fresh oracle: the shipped loader and conditional-AP EV
        nml_core.set_legacy_no_cond_ap(False)
        acts = [ref_dir / ("acts_%d" % s) / "acts.jsonl" for s in seeds]
        hero, vocab = sp.resolve_hero_attach_mode("auto", acts)[0], sp.resolve_vocab_version("auto", acts)[0]
        print("hero_attach %s, vocab_version %d (read off the corpus)" % (hero, vocab))
        return lambda seed: sp.play_game(seed, a.army1, a.army2, a.repo, a.bank, core, hero_attach=hero,
                                         vocab_version=vocab, **sp.LEGACY_FIDELITY_KNOBS)

    sha = subprocess.run(["git", "-C", a.repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    summary = {"sha": sha or "unknown", "core_commit": nml_core.BUILD_COMMIT, "core_dirty": nml_core.BUILD_DIRTY,
               **run_parity(ref_dir, seeds, make_play)}
    Path(a.out).write_text(json.dumps(summary, indent=1, sort_keys=True, default=repr) + "\n", encoding="utf-8")
    print("PARITY: %d/%d seeds compared, %d rows, %d differences%s -> %s" % (
        summary["seeds_compared"], summary["seeds_requested"], summary["rows_compared"], len(summary["diffs"]),
        " (REFUSED: %s)" % summary["refused"] if summary["refused"] else "", a.out))
    return exit_code(summary)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
