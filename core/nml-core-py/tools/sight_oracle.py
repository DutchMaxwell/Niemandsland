"""D6a-B1 (NML-1073) — sight_oracle: which SIGHTED COUNT explains the table's
attack dice, per shooting act, over the EXISTING read-only reference corpus.

The trainer scales an attack by `alive` models; the table scales by the
per-model SIGHTED count instead (`sighted_models`, solo_controller.gd:7693-
7711). `sighted` is in NO act field (PLAN_fast_rules_core.md D6a S3), so it
can only be found as a residue: per act, search s in 0..alive for the
value(s) whose `effective_attacks` (:7652-7655) reproduce the recorded
OWN-owner die COUNTS. Stdlib only, no `nml_core`, no build — MEASURING only.

ACT SELECTION mirrors `shoot_replay_gate.py` (PR #404): `kind` in
HOLD/ADVANCE (0, 1) with a `shoot` target. An act's ordinal is the 1-based
position of its `act` line among `kind == "act"` lines — no seed/tray replay,
this tool never touches the dice STREAM, only the per-act tally.

OWN vs HERO vs OTHER: `dice.jsonl` lines carry `owner` as "AI (Name)". Own =
owner names the shooter's profile (`head.profiles[shooter]`, NOT
`state.units[k]`, which carries only a `prof` override stub, no weapons);
hero = owner names one of `state.units[shooter].attached`'s profiles;
anything else is "other" (name collision or unattributed roll).

FORMULA (own rolls only; per-copy bearer scaling, D6a S4 item 3, is a KNOWN
blind spot — shows up as residue, not a bug):
`effective_attacks(attacks, s, max) = round(attacks * s / max)` per ranged
weapon (range > 0); s is accepted when the MULTISET of non-zero expected
counts equals the recorded own rolls (order-independent — a scaled-to-zero
weapon draws no dice line at all).

    python core/nml-core-py/tools/sight_oracle.py --ref ~/selfplay_out/qbd_ref
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

#: `AiPlanner` action kinds that shoot (`BattleSim.HOLD` / `.ADVANCE`).
SHOOTING_KINDS = (0, 1)


def gd_round(x: float) -> int:
    """Godot's `round()`: nearest, ties away from zero. `x` >= 0 here."""
    return int(math.floor(x + 0.5))


def effective_attacks(attacks: int, s: int, max_models: int) -> int:
    """solo_controller.gd:7652-7655, OPR "Determine Attacks"."""
    if max_models <= 0:
        return attacks
    return max(0, gd_round(attacks * s / max_models))


def read_game(d: Path) -> tuple[dict, list[dict], list[dict]]:
    acts = [json.loads(x) for x in (d / "acts.jsonl").read_text().splitlines() if x.strip()]
    act_lines = [a for a in acts[1:] if a.get("kind") == "act"]
    dice = [json.loads(x) for x in (d / "dice.jsonl").read_text().splitlines() if x.strip()]
    return acts[0], act_lines, dice


def split_owners(dice_for_act: list[dict], shooter_name: str, hero_names: set[str]):
    own, hero, other = [], [], []
    for r in dice_for_act:
        if r.get("roll_kind") != "attack":
            continue
        owner, count = str(r.get("owner", "")), int(r["count"])
        if ("(%s)" % shooter_name) in owner:
            own.append(count)
        elif any(("(%s)" % hn) in owner for hn in hero_names):
            hero.append(count)
        else:
            other.append(count)
    return own, hero, other


def group_attacks(weapon: dict) -> int:
    """The recorded `weapons[]` entry stores PER-MODEL attacks (army-book
    convention); `scaled_attacks_report` (solo_controller.gd:452-467) scales a
    weapon GROUP's total at full strength, i.e. attacks-per-model x bearer
    `count`, confirmed against the corpus: a full-alive, count>=model_count,
    single-ranged-weapon act reproduces its own die count 24/30 times with
    this product vs 16/30 with the raw per-model field alone."""
    return int(weapon.get("attacks", 0)) * max(int(weapon.get("count", 1)), 1)


def candidate_s(own: list[int], ranged_weapons: list[dict], alive: int, max_models: int) -> list[int]:
    want = sorted(own)
    return [s for s in range(alive + 1)
            if sorted(e for e in (effective_attacks(group_attacks(w), s, max_models)
                                   for w in ranged_weapons) if e > 0) == want]


def analyze_act(head: dict, state: dict, action: dict, dice_for_act: list[dict]) -> dict:
    shooter = action["unit"]
    prof = head["profiles"].get(shooter, {})
    shooter_name, model_count = prof.get("name", ""), int(prof.get("model_count", 1))
    ranged = [w for w in prof.get("weapons", []) if int(w.get("range", 0)) > 0]
    su = state["units"].get(shooter, {})
    alive = int(su.get("alive", 0))
    hero_names = {head["profiles"][h]["name"] for h in su.get("attached", []) if h in head["profiles"]}
    own, hero, other = split_owners(dice_for_act, shooter_name, hero_names)
    return {"profile": shooter_name, "alive": alive, "own": own, "other": other,
            "candidates": candidate_s(own, ranged, alive, model_count), "hero_present": bool(hero)}


def bucket_of(rec: dict) -> str:
    c = rec["candidates"]
    if not c:
        return "unexplained"
    if rec["alive"] in c:
        return "s_eq_alive"
    return "table_silent" if 0 in c else "sighting"


def representative_s(rec: dict, bucket: str):
    return {"s_eq_alive": rec["alive"], "table_silent": 0,
            "sighting": min(rec["candidates"]) if rec["candidates"] else None}.get(bucket)


def collect(ref: Path, limit: int) -> list[dict]:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "dice.jsonl").exists())
    games = games[:limit] if limit else games
    records = []
    for d in games:
        head, act_lines, dice = read_game(d)
        for k, act in enumerate(act_lines, 1):
            action = (act.get("pick") or {}).get("action") or {}
            if int(action.get("kind", -1)) not in SHOOTING_KINDS or not action.get("shoot"):
                continue
            dice_for_act = [r for r in dice if int(r["act"]) == k]
            rec = analyze_act(head, act["state"], action, dice_for_act)
            rec["game"], rec["act_no"] = d.name, k
            records.append(rec)
    return records


def pct(n: int, total: int) -> float:
    return 100.0 * n / total if total else 0.0


def run(ref: Path, limit: int, oracle: str, top: int = 5) -> int:
    records = collect(ref, limit)
    total = len(records)
    if total == 0:
        print("no shooting acts found under %s" % ref)
        return 1

    if oracle == "alive":
        # RED-GREEN: force s == alive only — how many acts does the port's
        # OWN assumption already reproduce (own-owner rolls, multiset match;
        # NOT the gate's full-stream FULL-equal — no order/hero/target check).
        n = sum(1 for r in records if r["alive"] in r["candidates"])
        print("--oracle alive: %d/%d acts reproduce the recorded own-owner die "
              "counts at s == alive" % (n, total))
        return 0

    hero_n = sum(1 for r in records if r["hero_present"])
    other_n = sum(1 for r in records if r["other"])
    buckets = Counter(bucket_of(r) for r in records)
    hist: Counter = Counter()
    patterns: Counter = Counter()
    for r in records:
        b = bucket_of(r)
        s = representative_s(r, b)
        if s is not None:
            hist[r["alive"] - s] += 1
        if b == "sighting":
            patterns[(r["profile"], r["alive"], s)] += 1

    print("=== sight_oracle summary (%d games, %d shooting acts) ===" % (
        len({r["game"] for r in records}), total))
    print("acts with hero-owned rolls   : %d (%.1f%%)" % (hero_n, pct(hero_n, total)))
    print("acts with unattributed rolls : %d (%.1f%%)" % (other_n, pct(other_n, total)))
    print("fully explained, s == alive  : %d (%.1f%%)" % (buckets["s_eq_alive"], pct(buckets["s_eq_alive"], total)))
    print("explained, s < alive (sight) : %d (%.1f%%)" % (buckets["sighting"], pct(buckets["sighting"], total)))
    print("table silent, s == 0         : %d (%.1f%%)" % (buckets["table_silent"], pct(buckets["table_silent"], total)))
    print("unexplained (no s fits)      : %d (%.1f%%)" % (buckets["unexplained"], pct(buckets["unexplained"], total)))
    print("histogram alive - s (explained acts only):")
    for k in sorted(hist):
        print("  alive-s=%2d : %d" % (k, hist[k]))
    print("top %d (profile, alive, s) patterns in the sighting bucket:" % top)
    for (profile, alive, s), n in patterns.most_common(top):
        print("  %-24s alive=%d s=%d : %d acts" % (profile, alive, s, n))
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs with dice.jsonl")
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--oracle", choices=("search", "alive"), default="search",
                    help="'search' (default) finds every consistent s; 'alive' is the "
                         "RED-GREEN check that forces s == alive only")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.limit, a.oracle)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
