"""D6a (NML-1073 M5) — sight_gate: the SHARP sighting instrument `sight_oracle.py` (#405) could
only approximate by residue search. The qbe corpus now records the table's own per-shot facts
(`shots.jsonl`, scripts/solo/shot_recorder.gd) -- the sighted count is read, not inferred.

FORMULA (solo_controller.gd `scaled_attacks_report`), picked by the recorded `bearers`:
  - `bearers == -1` (copies >= max_models, or no per-model loadout): FLAT ratio path,
    `effective_attacks(base, s, max_models) = round(base * s / max_models)`, `base` = the
    weapon GROUP total = per-model attacks x copies (sight_oracle.py's calibration note).
  - `bearers >= 0`: BEARER-CAP path, `per_model_attacks * min(bearers, s)` -- no ratio.
`s` is `sighted` (GREEN); `--red-formula alive` swaps in `alive` (D6a RED requirement).

    python core/nml-core-py/tools/sight_gate.py --ref ~/selfplay_out/qbe_ref
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sight_oracle as so  # noqa: E402


def gd_round(x: float) -> int:
    """Godot's `round()`: nearest, ties away from zero. `x` >= 0 here."""
    return int(math.floor(x + 0.5))


def effective_attacks(base_attacks: int, s: int, max_models: int) -> int:
    """solo_controller.gd `effective_attacks` -- the FLAT ratio path."""
    if max_models <= 0:
        return max(base_attacks, 0)
    return max(0, gd_round(base_attacks * s / max_models))


def expected_attacks(per_model: int, copies: int, bearers: int, s: int, max_models: int) -> int:
    """`scaled_attacks_report` -- flat ratio when `bearers` is the -1 sentinel, else the
    bearer-CAP (no ratio): `per_model x min(bearers, s)`."""
    if bearers < 0:
        return effective_attacks(per_model * copies, s, max_models)
    return per_model * min(bearers, s)


def resolve_weapon(head: dict, member: str, weapon: str) -> tuple[int, int] | None:
    """(per-model attacks, copies) by name -- every copy of a unit "type" shares one stat
    line (OPR army-list rule), so a name match needs no unit_id."""
    for prof in head.get("profiles", {}).values():
        if prof.get("name") != member:
            continue
        for w in prof.get("weapons", []):
            if w.get("name") == weapon:
                return int(w.get("attacks", 0)), max(int(w.get("count", 1)), 1)
    return None


def reach_bucket(reach_in: float) -> str:
    for cap in (12, 24, 36):
        if reach_in <= cap:
            return "<=%d" % cap
    return ">36"


def read_shots(d: Path) -> list[dict]:
    p = d / "shots.jsonl"
    return [json.loads(x) for x in p.read_text().splitlines() if x.strip()] if p.exists() else []


def instrument_check(games: list[Path], s_field: str) -> dict:
    """Part (a): recompute `attacks` from `s_field` ('sighted' or, for --red-formula, 'alive')
    and compare to the recorded value. Returns per-line counters."""
    checked = ok = bad = misses = 0
    violations: list[str] = []
    for d in games:
        head = so.read_game(d)[0]
        for sh in read_shots(d):
            found = resolve_weapon(head, sh["member"], sh["weapon"])
            if found is None:
                misses += 1
                continue
            per_model, copies = found
            checked += 1
            exp = expected_attacks(per_model, copies, sh["bearers"], sh[s_field], sh["max_models"])
            if exp == sh["attacks"]:
                ok += 1
            else:
                bad += 1
                if len(violations) < 10:
                    violations.append("%s act=%s %s/%s exp=%d got=%d (s=%d alive=%d bearers=%d)" % (
                        d.name, sh["act"], sh["member"], sh["weapon"], exp, sh["attacks"],
                        sh[s_field], sh["alive"], sh["bearers"]))
    return {"checked": checked, "ok": ok, "violations": bad, "lookup_misses": misses,
            "examples": violations}


def pct(n: int, t: int) -> float:
    return round(100.0 * n / t, 2) if t else 0.0


def _bucket_stats(buckets: dict[str, Counter]) -> dict:
    return {k: {"n": v["n"], "lt_alive_pct": pct(v["lt_alive"], v["n"]),
                "silent_pct": pct(v["silent"], v["n"])} for k, v in buckets.items()}


def distribution(games: list[Path]) -> dict:
    """Part (b): the shape the sighting rung needs."""
    hist: Counter = Counter()
    by_indirect = {"true": Counter(), "false": Counter()}
    by_reach: dict[str, Counter] = {}
    total = lt_alive = silent = 0
    for d in games:
        for sh in read_shots(d):
            total += 1
            hist[sh["alive"] - sh["sighted"]] += 1
            below, quiet = sh["sighted"] < sh["alive"], sh["sighted"] == 0
            lt_alive, silent = lt_alive + below, silent + quiet
            for b in (by_indirect["true" if sh["indirect"] else "false"],
                      by_reach.setdefault(reach_bucket(sh["reach_in"]), Counter())):
                b["n"] += 1
                b["lt_alive"] += below
                b["silent"] += quiet
    return {"shots": total, "alive_minus_sighted_hist": {str(k): v for k, v in sorted(hist.items())},
            "sighted_lt_alive_share": pct(lt_alive, total), "silent_share": pct(silent, total),
            "by_indirect": _bucket_stats(by_indirect), "by_reach_bucket": _bucket_stats(by_reach)}


def oracle_cross_check(games: list[Path]) -> dict:
    """Part (c): run sight_oracle.py's own residue search AS-IS -- its act ordinal `k` is the
    1-based position among `kind == "act"` lines only, so it can pull the wrong dice slice once
    an `auto` line precedes it (the approximation this gate exists to size, not silently fix).
    Ground truth is looked up by the TRUE global ordinal (position among ALL body lines)."""
    gt_total = oracle_covered = 0
    sighting_total = sighting_confirmed = 0
    unexplained_total = unexplained_weapon = unexplained_bearers = unexplained_union = 0
    for d in games:
        body = [json.loads(x) for x in (d / "acts.jsonl").read_text().splitlines() if x.strip()][1:]
        head = so.read_game(d)[0]
        dice = [json.loads(x) for x in (d / "dice.jsonl").read_text().splitlines() if x.strip()]
        act_idx = [i for i, e in enumerate(body) if e.get("kind") == "act"]
        act_lines = [body[i] for i in act_idx]
        shots_by_act: dict[int, list[dict]] = {}
        for sh in read_shots(d):
            shots_by_act.setdefault(sh["act"], []).append(sh)
        gt_total += len(shots_by_act)
        for k, act in enumerate(act_lines, 1):
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) not in so.SHOOTING_KINDS or not action.get("shoot"):
                continue
            true_k = act_idx[k - 1] + 1
            gt_lines = shots_by_act.get(true_k)
            if not gt_lines:
                continue
            oracle_covered += 1
            dice_for_act = [r for r in dice if int(r["act"]) == k]
            rec = so.analyze_act(head, act["state"], action, dice_for_act)
            bucket = so.bucket_of(rec)
            if bucket == "sighting":
                sighting_total += 1
                if any(g["sighted"] < g["alive"] for g in gt_lines):
                    sighting_confirmed += 1
            elif bucket == "unexplained":
                unexplained_total += 1
                by_weapon = len({g["sighted"] for g in gt_lines}) > 1
                by_bearers = any(g["bearers"] >= 0 for g in gt_lines)
                if by_weapon:
                    unexplained_weapon += 1
                if by_bearers:
                    unexplained_bearers += 1
                if by_weapon or by_bearers:
                    unexplained_union += 1
    return {"gt_shooting_acts": gt_total, "oracle_covered": oracle_covered,
            "oracle_coverage_pct": round(100.0 * oracle_covered / gt_total, 2) if gt_total else 0.0,
            "sighting_bucket_total": sighting_total, "sighting_confirmed": sighting_confirmed,
            "unexplained_bucket_total": unexplained_total,
            "unexplained_explained_by_weapon": unexplained_weapon,
            "unexplained_explained_by_bearers": unexplained_bearers,
            "unexplained_explained_union": unexplained_union}


def red_check(games: list[Path]) -> dict:
    """`--red-formula alive`: force `s = alive`. On the FLAT ratio path (bearers == -1) this
    must diverge from the recorded `attacks` on every shot where sighted < alive -- proves the
    ratio scaling is sensitive, not vacuous. On the BEARER-CAP path (`per_model * min(bearers,
    s)`) it is mathematically insensitive whenever bearers <= sighted (the weapon's own copy
    count, not the sightline, was already the binding constraint) -- reported separately, not
    folded into one number, so that case can't quietly pass as "the check doesn't work"."""
    flat_n = flat_broken = 0
    cap_binding_n = cap_binding_broken = 0  # bearers > sighted: sightline is the constraint
    cap_slack_n = 0  # bearers <= sighted: bearer count already binds, red is expected to NOT break
    for d in games:
        head = so.read_game(d)[0]
        for sh in read_shots(d):
            if sh["sighted"] >= sh["alive"]:
                continue
            found = resolve_weapon(head, sh["member"], sh["weapon"])
            if found is None:
                continue
            per_model, copies = found
            exp = expected_attacks(per_model, copies, sh["bearers"], sh["alive"], sh["max_models"])
            broke = exp != sh["attacks"]
            if sh["bearers"] < 0:
                flat_n += 1
                flat_broken += broke
            elif sh["bearers"] > sh["sighted"]:
                cap_binding_n += 1
                cap_binding_broken += broke
            else:
                cap_slack_n += 1
    candidates = flat_n + cap_binding_n + cap_slack_n
    broken = flat_broken + cap_binding_broken
    return {"candidate_shots_sighted_lt_alive": candidates, "broken": broken,
            "not_broken": candidates - broken,
            "flat_path": {"n": flat_n, "broken": flat_broken},
            "bearer_cap_sightline_binding": {"n": cap_binding_n, "broken": cap_binding_broken},
            "bearer_cap_slack_expected_unbroken": cap_slack_n}


def run(ref: Path, limit: int, red_formula: str, out: Path) -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "shots.jsonl").exists())
    games = games[:limit] if limit else games
    if not games:
        print("no games with shots.jsonl under %s" % ref)
        return 1

    inst = instrument_check(games, red_formula)
    dist = distribution(games)
    cross = oracle_cross_check(games)
    red = red_check(games) if red_formula == "sighted" else None

    print("=== sight_gate (%d games, %d shots) ===" % (len(games), dist["shots"]))
    print("instrument [%s]: %d/%d ok, %d violations, %d lookup misses" % (
        red_formula, inst["ok"], inst["checked"], inst["violations"], inst["lookup_misses"]))
    for ex in inst["examples"]:
        print("  VIOLATION: %s" % ex)
    print("alive-sighted histogram: %s" % dist["alive_minus_sighted_hist"])
    print("sighted < alive: %.2f%%   table silent (sighted==0): %.2f%%" % (
        dist["sighted_lt_alive_share"], dist["silent_share"]))
    print("by indirect: %s" % dist["by_indirect"])
    print("by reach bucket: %s" % dist["by_reach_bucket"])
    print("oracle cross-check: %d ground-truth shooting acts, %d covered by the oracle's own filter (%.2f%%)" % (
        cross["gt_shooting_acts"], cross["oracle_covered"], cross["oracle_coverage_pct"]))
    print("  sighting bucket: %d, confirmed (recorded sighted < alive): %d" % (
        cross["sighting_bucket_total"], cross["sighting_confirmed"]))
    print("  unexplained bucket: %d, explained by per-weapon split: %d, by bearers: %d, union: %d" % (
        cross["unexplained_bucket_total"], cross["unexplained_explained_by_weapon"],
        cross["unexplained_explained_by_bearers"], cross["unexplained_explained_union"]))

    summary = {"games": len(games), "shots": dist["shots"], "instrument": inst,
               "instrument_ok": inst["violations"] == 0, "distribution": dist,
               "oracle_cross_check": cross, "per_weapon_split_acts": cross["unexplained_explained_by_weapon"]}
    if red is not None:
        print("red-formula alive: %d/%d candidate shots (sighted<alive) broke the instrument, %d did not" % (
            red["broken"], red["candidate_shots_sighted_lt_alive"], red["not_broken"]))
        print("  flat ratio path: %d/%d broke (must be 100%%)" % (
            red["flat_path"]["broken"], red["flat_path"]["n"]))
        print("  bearer-cap, sightline binding (bearers>sighted): %d/%d broke (must be 100%%)" % (
            red["bearer_cap_sightline_binding"]["broken"], red["bearer_cap_sightline_binding"]["n"]))
        print("  bearer-cap, bearer count already binding (bearers<=sighted): %d shots, math says unbroken" % (
            red["bearer_cap_slack_expected_unbroken"]))
        summary["red_check"] = red

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=1))
    print("summary written to %s" % out)
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of game dirs with shots.jsonl")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--red-formula", choices=("sighted", "alive"), default="sighted",
                     help="'sighted' (default, GREEN) or 'alive' (RED: must break the instrument)")
    ap.add_argument("--out", default="~/selfplay_out/qbe_sight_summary.json")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.limit, a.red_formula, Path(a.out).expanduser())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
