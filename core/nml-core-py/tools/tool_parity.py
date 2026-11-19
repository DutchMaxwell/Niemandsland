"""PLAN G step 2/3 — parity driver: `selfplay.py` (Rust core) against a recorded `tools/core_selfplay.gd` oracle.

Plays each seed ONCE with `selfplay.play_game` at the oracle's knobs
(`LEGACY_FIDELITY_KNOBS = epoch 0, pre-fidelity: the old tool's game, not the trainer's`; use a FRESH oracle) and runs
BOTH gates' own `compare()` on it (`selfplay_gate`: winner/objectives/VP/rounds/picks; `sidecar_gate`: the file field by
field; each stops at a seed's first difference). Writes `parity_summary.json` (sha, core_commit, core_dirty,
allow_core_mismatch, config, rules_epoch, knobs_played, ref, seeds_requested/compared, rows_compared, missing, refused,
diffs [{seed, gate, path, ref, got, accepted}]). Exit 2 = refused (`core mismatch` when `nml_core.BUILD_DIRTY` or
`nml_core.BUILD_COMMIT != HEAD` of `--repo` unless `--allow-core-mismatch`, a requested seed lacks `core_s<seed>.json`
or `acts_<seed>/acts.jsonl`, or nothing compared), 1 = an unexplained difference or a stale accept, 0 = all equal,
3 = blind. `--accept FILE` ([{gate, path_regex, reason, epoch, pr}]) names expected differences; an entry matching
nothing is `stale accept`. `--plant` must turn a corrupted copy of the first seed red (exit 1), else exit 3:
instrument blind.
"""

from __future__ import annotations

import argparse
import json
import re
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
PLANT_DIR = Path.home() / ".cache/nml-g/tmp/plant"
CONFIG = "legacy"


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
    if missing or not refs:
        out["refused"] = "seeds %s have no reference (absent or unreadable core_s<seed>.json / acts.jsonl)" % missing if refs else "compared 0 seeds"
        return out
    play = make_play()
    for seed in seeds:
        diffs = compare_seed(seed, refs[seed], play(seed), selfplay_gate.ref_picks(ref_dir, seed))
        rows = len(refs[seed]["planner_positions"])
        out["seeds_compared"], out["rows_compared"], out["diffs"] = out["seeds_compared"] + 1, out["rows_compared"] + rows, out["diffs"] + diffs
        log("seed %d rows %d diffs %d" % (seed, rows, len(diffs)))
    return out


def apply_accept(summary: dict, accept: list[dict]) -> None:
    """Mark each diff `accepted` when an entry names its gate and fully matches its path; list the entries that matched nothing."""
    used = set()
    for d in summary["diffs"]:
        hit = next((i for i, e in enumerate(accept) if e["gate"] == d["gate"] and re.fullmatch(e["path_regex"], d["path"])), None)
        d["accepted"], _ = hit is not None, used.add(hit)
    summary["stale_accepts"] = [e for i, e in enumerate(accept) if i not in used]


def plant(ref_dir: Path, seed: int, dest: Path) -> Path:
    """A copy of one oracle seed with board row 0 column 3 +1 and its first two picks swapped: a run on it must be red."""
    ref = json.loads((ref_dir / ("core_s%d.json" % seed)).read_text(encoding="utf-8"))
    ref["planner_positions"][0]["board"][0][3] += 1
    acts = (ref_dir / ("acts_%d" % seed) / "acts.jsonl").read_text(encoding="utf-8").splitlines()
    i, j = [k for k, ln in enumerate(acts) if json.loads(ln).get("kind") == "act"][:2]
    acts[i], acts[j] = acts[j], acts[i]
    (dest / ("acts_%d" % seed)).mkdir(parents=True, exist_ok=True)
    (dest / ("core_s%d.json" % seed)).write_text(json.dumps(ref), encoding="utf-8")
    (dest / ("acts_%d" % seed) / "acts.jsonl").write_text("\n".join(acts) + "\n", encoding="utf-8")
    return dest


def exit_code(summary: dict) -> int:
    return 2 if summary["refused"] else int(any(not d.get("accepted") for d in summary["diffs"]) or bool(summary.get("stale_accepts")))


def _repo_head(repo: str) -> str:
    r = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def _core_mismatch(sha: str) -> str | None:
    reasons = []
    if nml_core.BUILD_DIRTY:
        reasons.append("BUILD_DIRTY")
    if not sha or nml_core.BUILD_COMMIT != sha:
        reasons.append("BUILD_COMMIT %s != HEAD %s" % (nml_core.BUILD_COMMIT, sha or "unknown"))
    return "; ".join(reasons) if reasons else None


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for flag in ("--ref", "--bank", "--army1", "--army2", "--seeds"):
        ap.add_argument(flag, required=True)
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--out", default="parity_summary.json", help="where the summary JSON goes")
    ap.add_argument("--accept", help="JSON list of accepted difference classes")
    ap.add_argument("--plant", action="store_true", help="also prove the instrument red on a corrupted copy of the first seed")
    ap.add_argument("--allow-core-mismatch", action="store_true",
                    help="run even when nml_core is dirty or its BUILD_COMMIT != HEAD of --repo")
    a = ap.parse_args(argv)
    ref_dir, seeds, knobs = Path(a.ref), selfplay_gate.parse_seeds(a.seeds), dict(sp.LEGACY_FIDELITY_KNOBS)

    def make_play():
        core = nml_core.load(a.repo)
        list_to_profile.LEGACY_CORE_SELFPLAY = False   # a fresh oracle: the shipped loader and conditional-AP EV
        nml_core.set_legacy_no_cond_ap(False)
        acts = [ref_dir / ("acts_%d" % s) / "acts.jsonl" for s in seeds]
        knobs.update(hero_attach=sp.resolve_hero_attach_mode("auto", acts)[0],
                     vocab_version=sp.resolve_vocab_version("auto", acts)[0])
        return lambda seed: sp.play_game(seed, a.army1, a.army2, a.repo, a.bank, core, **knobs)

    sha = _repo_head(a.repo)
    mismatch = _core_mismatch(sha)
    body = ({"ref": str(ref_dir), "seeds_requested": len(seeds), "seeds_compared": 0, "rows_compared": 0,
             "missing": [], "refused": "core mismatch: %s" % mismatch, "diffs": []}
            if mismatch and not a.allow_core_mismatch else run_parity(ref_dir, seeds, make_play))
    summary = {"sha": sha or "unknown", "core_commit": nml_core.BUILD_COMMIT, "core_dirty": nml_core.BUILD_DIRTY,
               "allow_core_mismatch": a.allow_core_mismatch, "config": CONFIG,
               "rules_epoch": knobs["rules_epoch"], "knobs_played": dict(knobs), **body}
    if a.accept:
        apply_accept(summary, json.loads(Path(a.accept).read_text(encoding="utf-8")))
    code = exit_code(summary)
    if a.plant and not summary["refused"]:
        summary["plant_exit"] = exit_code(run_parity(plant(ref_dir, seeds[0], PLANT_DIR), seeds[:1], make_play, log=lambda *_: None))
        code = code if summary["plant_exit"] == 1 else 3
        print("plant: exit %d -> %s" % (summary["plant_exit"], "red, as it must be" if code != 3 else "instrument blind"))
    Path(a.out).write_text(json.dumps(summary, indent=1, sort_keys=True, default=repr) + "\n", encoding="utf-8")
    for e in summary.get("stale_accepts", []):
        print("stale accept: %s" % json.dumps(e))
    override = (" (--allow-core-mismatch%s)" % (": " + mismatch if mismatch else "")) if a.allow_core_mismatch else ""
    refused = " (REFUSED: %s)" % summary["refused"] if summary["refused"] else ""
    print("PARITY: %d/%d seeds compared, %d rows, %d differences (%d unexplained)%s%s -> %s" % (
        summary["seeds_compared"], summary["seeds_requested"], summary["rows_compared"], len(summary["diffs"]),
        sum(not d.get("accepted") for d in summary["diffs"]), override, refused, a.out))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
