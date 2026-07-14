#!/usr/bin/env python3
"""Plausibility scorecard for the solo/arena AI self-play artifacts.

Stage 0 of the AI-plausibility program: MEASURE before we FIX. The maintainer
judged the AI "rule-correct but tactically implausible". This tool turns that
eyeball verdict into deterministic numbers computed purely from the artifacts an
arena/self-play match already writes -- no game engine, no randomness, no clock.
Every later stage of the program must show these numbers going up.

It reads one or more game directories, each expected to contain some of:

    decisions.json   verbatim AI decision records (list of {kind,round,side,
                     unit,rule,why,data,candidates,chosen})
    result.json      match summary (winner, objectives, survivors, grades,
                     knobs, rounds_played, armies pointer, optional move_usage)
    battlelog.txt    human-readable resolved log (shots, casts, charges, damage,
                     deaths, "not automated" rule notes)
    army_p1.json     rosters (unit name, cost, size, weapons -> ranged?)
    army_p2.json     -- resolved locally, or via result.json's `armies` field,
                     since a rerun of the same matchup reuses the same rosters.
    arena_*.json     alternative to result.json + Wave-1 `move_usage` telemetry

Missing / partial inputs are handled gracefully: a metric that cannot be
computed reports `null` and is dropped from the (renormalised) headline.

METRICS (each -> a 0-100 sub-score PLUS raw counts, so nothing is hidden):

    M1  no_idle          fraction of activated units that had real IMPACT
                         (shot / fought in melee / cast / held an objective).
                         Pure movement is NOT impact -- that is exactly the
                         295pt-biker failure the maintainer flagged.
    M2  move_commitment  did advances commit? median achieved/budget ratio,
                         open-field sub-inch dribbles flagged (terrain-boxed
                         moves are excused via the record's `why`).
    M3  objective_urgency  in the FINAL round, of units within one push of a
                         marker, how many chose to close/seize vs walk off to
                         fight (the showcase-losing behaviour).
    M4  firepower        ranged units that actually shot, plus wasted points
                         (cost of units with zero offensive/objective output).
    M5  focus            of enemy units that took damage, how many were
                         finished off vs left damaged-but-alive (scatter).
    M6  decisiveness     share of objective markers actually controlled at the
                         end; surfaces seizes, survivors and the honest
                         "not automated" rule gaps.

HEADLINE = weighted mean of the available sub-scores. Few, documented weights
(research's "one or two weights" principle):

    M1 .30   M3 .20   M4 .20   M2 .10   M5 .10   M6 .10

Usage:
    python3 tools/plausibility_score.py <game_dir> [<game_dir> ...]
    python3 tools/plausibility_score.py <game_dir> --json scorecard.json
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections import defaultdict

# ---------------------------------------------------------------------------
# Tunable constants (documented; no magic numbers buried in the logic).
# ---------------------------------------------------------------------------
SUBINCH_IN = 1.0          # a "move" achieving less than this is sub-inch
COMMIT_RATIO_MIN = 0.5    # a move using >= this fraction of budget "commits"
URGENCY_REACH_IN = 9.0    # gap-to-marker a unit can plausibly close in one turn
RANGED_MIN_RANGE = 4      # a weapon with range >= this makes a unit "ranged"
                          # (excludes range-0 melee; keeps 6" fusion pistols)

# Words in a move record's `why` that mark it as genuinely terrain-constrained,
# so a short move there is legitimate rather than an aimless dribble.
BOXED_WHY_TOKENS = (
    "difficult", "around", "gate", "shorten", "cap", "terrain",
    "avoid", "box", "blocked", "clear of", "wall",
)

HEADLINE_WEIGHTS = {
    "no_idle": 0.30,
    "objective_urgency": 0.20,
    "firepower": 0.20,
    "move_commitment": 0.10,
    "focus": 0.10,
    "decisiveness": 0.10,
}


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
def _load_json(path):
    """json.load tolerates Infinity/-Infinity/NaN, which the records contain."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def _first_existing(paths):
    for p in paths:
        if p and os.path.isfile(p):
            return p
    return None


def _find_arena_file(game_dir):
    hits = sorted(
        f for f in os.listdir(game_dir)
        if f.startswith("arena_") and f.endswith(".json")
    )
    return os.path.join(game_dir, hits[0]) if hits else None


def _resolve_army(game_dir, embedded_path, side_tag):
    """Find an army file: local copy first, then the artifact's own pointer."""
    base = os.path.basename(embedded_path) if embedded_path else f"army_{side_tag}.json"
    return _first_existing([
        os.path.join(game_dir, base),
        os.path.join(game_dir, f"army_{side_tag}.json"),
        embedded_path,
        os.path.join(os.path.dirname(embedded_path or ""), base) if embedded_path else None,
    ])


def load_game(game_dir):
    """Gather every artifact we can find for one game directory."""
    game_dir = os.path.abspath(game_dir)
    decisions = _load_json(os.path.join(game_dir, "decisions.json"))

    meta = _load_json(os.path.join(game_dir, "result.json"))
    if meta is None:
        arena = _find_arena_file(game_dir)
        meta = _load_json(arena) if arena else None
    # move_usage only lives in the arena file; fold it in if result.json lacked it.
    if isinstance(meta, dict) and "move_usage" not in meta:
        arena = _find_arena_file(game_dir)
        arena_meta = _load_json(arena) if arena else None
        if isinstance(arena_meta, dict) and "move_usage" in arena_meta:
            meta["move_usage"] = arena_meta["move_usage"]

    battlelog = None
    bl_path = os.path.join(game_dir, "battlelog.txt")
    if os.path.isfile(bl_path):
        with open(bl_path, "r", encoding="utf-8") as fh:
            battlelog = fh.read()

    armies = {}
    embedded = (meta or {}).get("armies", {}) if isinstance(meta, dict) else {}
    for side, tag in ((1, "p1"), (2, "p2")):
        path = _resolve_army(game_dir, embedded.get(tag), tag)
        data = _load_json(path) if path else None
        if isinstance(data, dict) and isinstance(data.get("units"), list):
            armies[side] = data

    return {
        "dir": game_dir,
        "name": os.path.basename(game_dir.rstrip("/")) or game_dir,
        "decisions": decisions if isinstance(decisions, list) else [],
        "meta": meta if isinstance(meta, dict) else {},
        "battlelog": battlelog,
        "armies": armies,
    }


# ---------------------------------------------------------------------------
# Battlelog parsing (deterministic regex over the resolved text log)
# ---------------------------------------------------------------------------
def parse_battlelog(text):
    """Extract per-unit resolved activity + damage/deaths + honest gap notes."""
    out = {
        "fires": defaultdict(int),      # weapon-resolution shots per unit
        "shot_any": set(),              # units that fired at least once
        "casts": defaultdict(int),
        "charges": defaultdict(int),
        "models_lost": defaultdict(int),
        "wounds_taken": defaultdict(int),
        "destroyed": set(),
        "damaged": set(),               # took a model loss or wounds
        "not_automated": [],            # distinct rule names flagged manual
        "seized_by": [],                # (round, side_label)
    }
    if not text:
        return out
    seen_notes = set()
    for raw in text.splitlines():
        m = re.match(r"^R(\d+)\s+(.*)$", raw.strip())
        if not m:
            continue
        body = m.group(2).strip()

        mm = re.match(r'^Note: "(.+?)" is not automated', body)
        if mm:
            if mm.group(1) not in seen_notes:
                seen_notes.add(mm.group(1))
                out["not_automated"].append(mm.group(1))
            continue

        mm = re.match(r"^(.+?) fires .+? at .+? — (\d+) hits", body)
        if mm:
            out["fires"][mm.group(1)] += 1
            out["shot_any"].add(mm.group(1))
            continue
        mm = re.match(r"^(.+?) fires at ", body)   # declaration line
        if mm:
            out["shot_any"].add(mm.group(1))
            continue

        # "casts X at Y" is the declaration; the resolution lines contain
        # "needs"/"cast roll" -- count only the declaration to avoid double count.
        mm = re.match(r"^(.+?) casts ", body)
        if mm and "needs" not in body and "cast roll" not in body:
            out["casts"][mm.group(1)] += 1
            continue

        mm = re.match(r"^(.+?) charges", body)
        if mm:
            out["charges"][mm.group(1)] += 1
            continue

        mm = re.match(r"^(.+?) loses a model", body)
        if mm:
            out["models_lost"][mm.group(1)] += 1
            out["damaged"].add(mm.group(1))
            continue

        mm = re.match(r"^(.+?) takes (\d+) wounds?", body)
        if mm:
            out["wounds_taken"][mm.group(1)] += int(mm.group(2))
            out["damaged"].add(mm.group(1))
            continue

        mm = re.match(r"^(.+?) destroyed$", body)
        if mm:
            out["destroyed"].add(mm.group(1))
            out["damaged"].add(mm.group(1))
            continue

        mm = re.match(r"^Objective \d+ seized by (P\d)", body)
        if mm:
            out["seized_by"].append(mm.group(1))
            continue
    return out


# ---------------------------------------------------------------------------
# Roster
# ---------------------------------------------------------------------------
def _unit_max_range(unit):
    return max((w.get("range", 0) or 0) for w in unit.get("weapons", [])) if unit.get("weapons") else 0


def build_roster(game):
    """One record per unit: side, cost, is_ranged, and whether it ever activated.

    Roster identity comes from the army files when available (authoritative
    names + costs + weapon ranges). Units that never appear in a decision record
    or the battlelog are treated as joined heroes / reserves (they act through a
    host unit) and are excluded from the idle denominators but reported.
    """
    decisions = game["decisions"]
    bl = game.get("_bl") or {}

    # Names that took an independent action this game.
    active_names = set()
    for r in decisions:
        u = r.get("unit")
        if u and u not in ("-",) and r.get("kind") not in ("roll_off", "seize"):
            active_names.add(u)
    for key in ("fires", "casts", "charges"):
        active_names |= set(bl.get(key, {}).keys())
    active_names |= set(bl.get("shot_any", set()))

    roster = {}
    for side, army in game["armies"].items():
        for u in army.get("units", []):
            name = u.get("name")
            if not name:
                continue
            roster[(side, name)] = {
                "side": side,
                "name": name,
                "cost": u.get("cost", 0) or 0,
                "size": u.get("size", 1) or 1,
                "is_ranged": _unit_max_range(u) >= RANGED_MIN_RANGE,
                "max_range": _unit_max_range(u),
                "activated": name in active_names,
                "have_cost": True,
            }

    # If army files were missing, synthesise a roster from the decision records
    # (side is carried on every record). Costs / ranges are then unknown.
    if not roster:
        seen = {}
        for r in decisions:
            u = r.get("unit")
            side = r.get("side")
            if u and u not in ("-",) and side in (1, 2) and r.get("kind") not in ("roll_off", "seize"):
                seen[(side, u)] = True
        for (side, name) in seen:
            roster[(side, name)] = {
                "side": side, "name": name, "cost": 0, "size": 1,
                "is_ranged": None, "max_range": None,
                "activated": True, "have_cost": False,
            }
    return roster


def _unit_impact(name, decisions_by_unit, bl):
    """Did this unit have real offensive / objective impact all game?

    Impact = fired a shot, fought in melee (charge/consolidate/melee action),
    cast a spell, or deliberately held/seized an objective. Movement alone is
    deliberately excluded -- a unit that only ever rushes toward a foe it never
    reaches is the flagged failure, not an active unit.
    """
    reasons = []
    # A shot is only real if the battlelog resolved one, or the chosen action is
    # itself a firing move (aircraft "strafing run"). `shoot_after_advance` is an
    # ELIGIBILITY flag ("may shoot after moving"), NOT a confirmed shot -- units
    # flagged eligible still fire nothing when no target ends up in range, so it
    # is deliberately excluded to avoid crediting the idle 295pt-biker case.
    if name in bl.get("shot_any", set()) or bl.get("fires", {}).get(name):
        reasons.append("shot")
    if bl.get("charges", {}).get(name):
        reasons.append("melee")
    if bl.get("casts", {}).get(name):
        reasons.append("cast")

    for r in decisions_by_unit.get(name, []):
        kind = r.get("kind")
        chosen = str(r.get("chosen", "")).lower()
        data = r.get("data", {}) if isinstance(r.get("data"), dict) else {}
        if kind == "cast" and "cast" not in reasons:
            reasons.append("cast")
        elif kind == "consolidate" and "melee" not in reasons:
            reasons.append("melee")
        elif kind == "action":
            if ("fire" in chosen or "shoot" in chosen or "strafing" in chosen) and "shot" not in reasons:
                reasons.append("shot")
            if "charge" in chosen and "melee" not in reasons:
                reasons.append("melee")
        elif kind == "seize_check":
            if data.get("in_seize_range") or "seize range" in chosen or "hold" in chosen:
                if "held_objective" not in reasons:
                    reasons.append("held_objective")
    return reasons


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def _clamp(v, lo=0.0, hi=100.0):
    return max(lo, min(hi, v))


def _round(v):
    return None if v is None else round(v, 1)


def m1_no_idle(roster, decisions_by_unit, bl):
    activated = [u for u in roster.values() if u["activated"]]
    joined = sorted(u["name"] + f" (P{u['side']})" for u in roster.values() if not u["activated"])
    if not activated:
        return {"score": None, "note": "no activated units found"}

    engaged, idle = [], []
    for u in activated:
        reasons = _unit_impact(u["name"], decisions_by_unit, bl)
        rec = {"unit": u["name"], "side": u["side"], "cost": u["cost"], "impact": reasons}
        if reasons:
            engaged.append(rec)
        else:
            idle.append(rec)
    score = 100.0 * len(engaged) / len(activated)
    idle.sort(key=lambda r: (-(r["cost"] or 0), r["unit"]))
    return {
        "score": _round(score),
        "activated_units": len(activated),
        "engaged_units": len(engaged),
        "idle_units": len(idle),
        "idle_offenders": idle,
        "no_independent_activation": joined,
    }


def m2_move_commitment(decisions):
    moves = [r for r in decisions if r.get("kind") == "move" and isinstance(r.get("data"), dict)]
    if not moves:
        return {"score": None, "note": "no move records"}

    achieved, ratios, subinch_open, subinch_boxed = [], [], [], []
    committed = 0
    for r in moves:
        d = r["data"]
        ach = float(d.get("achieved_in", 0.0) or 0.0)
        budget = float(d.get("budget_in", 0.0) or 0.0)
        why = str(r.get("why", "")).lower()
        boxed = any(tok in why for tok in BOXED_WHY_TOKENS)
        achieved.append(ach)
        if budget > 0:
            ratio = ach / budget
            ratios.append(ratio)
            if ratio >= COMMIT_RATIO_MIN:
                committed += 1
        if ach < SUBINCH_IN:
            tag = f"{r.get('unit')} R{r.get('round')} {why or 'move'} ({ach:.2f}\" of {budget:.1f}\")"
            (subinch_boxed if boxed else subinch_open).append(tag)

    frac_committed = committed / len(moves)
    score = _clamp(100.0 * frac_committed - 12.0 * len(subinch_open))
    achieved_sorted = sorted(achieved)
    ratios_sorted = sorted(ratios)
    return {
        "score": _round(score),
        "moves": len(moves),
        "median_achieved_in": _round(_median(achieved_sorted)),
        "median_commit_ratio": _round(_median(ratios_sorted)),
        "committed_moves": committed,
        "subinch_open": subinch_open,
        "subinch_boxed_ct": len(subinch_boxed),
    }


def _median(sorted_vals):
    n = len(sorted_vals)
    if n == 0:
        return None
    mid = n // 2
    if n % 2:
        return sorted_vals[mid]
    return (sorted_vals[mid - 1] + sorted_vals[mid]) / 2.0


def m3_objective_urgency(decisions, meta):
    rounds_played = meta.get("rounds_played")
    seize_checks = [r for r in decisions if r.get("kind") == "seize_check"]
    if not seize_checks:
        return {"score": None, "note": "no seize_check records"}
    final_round = rounds_played or max((r.get("round", 0) for r in seize_checks), default=0)

    relevant, answered, offenders = 0, 0, []
    for r in seize_checks:
        if r.get("round") != final_round:
            continue
        d = r.get("data", {}) if isinstance(r.get("data"), dict) else {}
        gap = d.get("obj_gap_after_in")
        if gap is None or gap > URGENCY_REACH_IN:
            continue
        relevant += 1
        chosen = str(r.get("chosen", "")).lower()
        if d.get("in_seize_range") or "seize range" in chosen or d.get("toward_objective"):
            answered += 1
        else:
            offenders.append({
                "unit": r.get("unit"), "side": r.get("side"),
                "obj_gap_in": _round(gap), "chose": r.get("chosen"),
            })
    obj = meta.get("objectives", {}) if isinstance(meta.get("objectives"), dict) else {}
    neutral_left = obj.get("neutral")
    if relevant == 0:
        return {
            "score": None, "note": "no unit within one push of a marker in final round",
            "final_round": final_round, "neutral_markers_at_end": neutral_left,
        }
    score = 100.0 * answered / relevant
    offenders.sort(key=lambda r: (r["obj_gap_in"] if r["obj_gap_in"] is not None else 1e9))
    return {
        "score": _round(score),
        "final_round": final_round,
        "reachable_units": relevant,
        "answered_urgency": answered,
        "ignored_reachable_marker": offenders,
        "neutral_markers_at_end": neutral_left,
    }


def m4_firepower(roster, decisions_by_unit, bl, m1):
    activated = [u for u in roster.values() if u["activated"]]
    ranged = [u for u in activated if u["is_ranged"]]
    have_ranged_info = any(u["is_ranged"] is not None for u in activated)
    have_cost = all(u["have_cost"] for u in activated) and activated

    fired = []
    if have_ranged_info:
        for u in ranged:
            if u["name"] in bl.get("shot_any", set()) or bl.get("fires", {}).get(u["name"]):
                fired.append(u["name"])
            else:
                # Fall back to a firing ACTION verb (e.g. aircraft strafing run)
                # only -- never `shoot_after_advance`, which is mere eligibility.
                for r in decisions_by_unit.get(u["name"], []):
                    chosen = str(r.get("chosen", "")).lower()
                    if r.get("kind") == "action" and ("fire" in chosen or "shoot" in chosen or "strafing" in chosen):
                        fired.append(u["name"])
                        break
    fired = sorted(set(fired))
    fire_frac = (100.0 * len(fired) / len(ranged)) if ranged else None

    wasted_pts, total_pts, wasted_units = 0, 0, []
    if have_cost:
        idle_names = {(o["unit"]) for o in m1.get("idle_offenders", [])}
        for u in activated:
            total_pts += u["cost"]
            if u["name"] in idle_names:
                wasted_pts += u["cost"]
                wasted_units.append({"unit": u["name"], "side": u["side"], "cost": u["cost"]})
    points_eff = (100.0 * (1 - wasted_pts / total_pts)) if total_pts else None

    parts = [s for s in (fire_frac, points_eff) if s is not None]
    score = sum(parts) / len(parts) if parts else None
    wasted_units.sort(key=lambda r: (-r["cost"], r["unit"]))
    return {
        "score": _round(score),
        "ranged_units": len(ranged) if have_ranged_info else None,
        "ranged_units_that_fired": len(fired),
        "ranged_fired_pct": _round(fire_frac),
        "wasted_points": wasted_pts if have_cost else None,
        "total_points_activated": total_pts if have_cost else None,
        "wasted_points_pct": _round(100.0 * wasted_pts / total_pts) if have_cost and total_pts else None,
        "wasted_units": wasted_units,
        "note": None if (have_ranged_info or have_cost) else "no army/cost data available",
    }


def m5_focus(decisions, bl):
    damaged = set(bl.get("damaged", set()))
    destroyed = set(bl.get("destroyed", set()))
    if not damaged and not bl.get("fires"):
        return {"score": None, "note": "no damage recorded in battlelog"}
    not_finished = sorted(damaged - destroyed)
    share = (len(not_finished) / len(damaged)) if damaged else 0.0
    score = 100.0 * (1 - share) if damaged else None

    # scatter context: how many distinct targets were selected for shooting?
    shot_targets = set()
    for r in decisions:
        if r.get("kind") == "target" and r.get("chosen"):
            shot_targets.add(r["chosen"])
    return {
        "score": _round(score),
        "enemy_units_damaged": len(damaged),
        "enemy_units_finished": len(damaged & destroyed),
        "damaged_not_finished": not_finished,
        "damaged_not_finished_pct": _round(100.0 * share) if damaged else None,
        "distinct_targets_selected": len(shot_targets),
    }


def m6_decisiveness(meta, decisions, bl):
    obj = meta.get("objectives", {}) if isinstance(meta.get("objectives"), dict) else {}
    p1, p2, neutral = obj.get("p1"), obj.get("p2"), obj.get("neutral")
    score = None
    total = None
    if None not in (p1, p2, neutral):
        total = p1 + p2 + neutral
        score = (100.0 * (p1 + p2) / total) if total else None

    seize_records = [r for r in decisions if r.get("kind") == "seize"]
    seized_objectives = sorted({
        r.get("data", {}).get("index") for r in seize_records
        if isinstance(r.get("data"), dict) and r.get("data", {}).get("index") is not None
    })
    survivors = meta.get("survivors")
    return {
        "score": _round(score),
        "objectives": {"p1": p1, "p2": p2, "neutral": neutral},
        "markers_controlled_at_end": (p1 + p2) if None not in (p1, p2) else None,
        "markers_total": total,
        "seize_events": len(seize_records),
        "distinct_objectives_seized": len(seized_objectives),
        "winner": meta.get("winner"),
        "survivors": survivors,
        "not_automated_rules": bl.get("not_automated", []),
    }


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
def score_game(game):
    game["_bl"] = parse_battlelog(game["battlelog"])
    bl = game["_bl"]
    decisions = game["decisions"]
    meta = game["meta"]

    decisions_by_unit = defaultdict(list)
    for r in decisions:
        if r.get("unit"):
            decisions_by_unit[r["unit"]].append(r)

    roster = build_roster(game)

    m1 = m1_no_idle(roster, decisions_by_unit, bl)
    metrics = {
        "no_idle": m1,
        "move_commitment": m2_move_commitment(decisions),
        "objective_urgency": m3_objective_urgency(decisions, meta),
        "firepower": m4_firepower(roster, decisions_by_unit, bl, m1),
        "focus": m5_focus(decisions, bl),
        "decisiveness": m6_decisiveness(meta, decisions, bl),
    }

    # Weighted headline over available (non-null) sub-scores; weights renormalise.
    num, den, used = 0.0, 0.0, {}
    for key, weight in HEADLINE_WEIGHTS.items():
        s = metrics[key]["score"]
        if s is not None:
            num += weight * s
            den += weight
            used[key] = weight
    headline = _round(num / den) if den else None

    return {
        "game": game["name"],
        "dir": game["dir"],
        "grades": meta.get("grades"),
        "knobs": {k: v.get("grade") for k, v in (meta.get("knobs") or {}).items()} if isinstance(meta.get("knobs"), dict) else None,
        "winner": meta.get("winner"),
        "rounds_played": meta.get("rounds_played"),
        "move_usage_wave1": meta.get("move_usage"),
        "headline_plausibility": headline,
        "weights_used": used,
        "metrics": metrics,
        "inputs_present": {
            "decisions": bool(decisions),
            "result_or_arena": bool(meta),
            "battlelog": game["battlelog"] is not None,
            "armies": len(game["armies"]),
        },
    }


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
def _bar(score, width=20):
    if score is None:
        return "[" + " " * width + "]  n/a"
    filled = int(round(score / 100.0 * width))
    return "[" + "#" * filled + "-" * (width - filled) + f"] {score:5.1f}"


def format_report(card):
    L = []
    L.append("=" * 72)
    L.append(f"PLAUSIBILITY SCORECARD  —  {card['game']}")
    L.append("=" * 72)
    grades = card.get("grades") or {}
    L.append(f"grades: p1={grades.get('p1','?')} p2={grades.get('p2','?')}   "
             f"winner: {card.get('winner','?')}   rounds: {card.get('rounds_played','?')}")
    ip = card["inputs_present"]
    L.append(f"inputs: decisions={ip['decisions']} result={ip['result_or_arena']} "
             f"battlelog={ip['battlelog']} armies={ip['armies']}/2")
    L.append("")
    hp = card["headline_plausibility"]
    L.append(f"HEADLINE PLAUSIBILITY  {_bar(hp, 30)}   (0=implausible .. 100=plausible)")
    L.append("")
    L.append("sub-scores:")
    order = ["no_idle", "move_commitment", "objective_urgency", "firepower", "focus", "decisiveness"]
    for key in order:
        m = card["metrics"][key]
        w = HEADLINE_WEIGHTS[key]
        L.append(f"  {key:18s} w={w:.2f}  {_bar(m['score'])}")

    m1 = card["metrics"]["no_idle"]
    if m1.get("idle_offenders"):
        L.append("")
        L.append("  IDLE / ZERO-IMPACT units (moved but never shot/fought/cast/held):")
        for o in m1["idle_offenders"]:
            c = f"{o['cost']}pt" if o.get("cost") else "cost?"
            L.append(f"    - {o['unit']} (P{o['side']}, {c}) — impact: none")
    if m1.get("no_independent_activation"):
        L.append(f"  joined/reserve (no independent activation): {', '.join(m1['no_independent_activation'])}")

    m2 = card["metrics"]["move_commitment"]
    if m2.get("score") is not None:
        L.append("")
        L.append(f"  movement: median achieved {m2.get('median_achieved_in')}\" | "
                 f"median commit-ratio {m2.get('median_commit_ratio')} | "
                 f"committed {m2.get('committed_moves')}/{m2.get('moves')}")
        if m2.get("subinch_open"):
            L.append("    open-field sub-inch dribbles: " + "; ".join(m2["subinch_open"]))
        if m2.get("subinch_boxed_ct"):
            L.append(f"    ({m2['subinch_boxed_ct']} more sub-inch moves excused by terrain)")

    m3 = card["metrics"]["objective_urgency"]
    L.append("")
    if m3.get("score") is not None:
        L.append(f"  objective urgency (final round {m3.get('final_round')}): "
                 f"{m3.get('answered_urgency')}/{m3.get('reachable_units')} reachable units pushed the marker; "
                 f"{m3.get('neutral_markers_at_end')} markers left neutral")
        for o in m3.get("ignored_reachable_marker", []):
            L.append(f"    - {o['unit']} (P{o['side']}) sat {o['obj_gap_in']}\" off a marker → '{o['chose']}'")
    else:
        L.append(f"  objective urgency: {m3.get('note')} "
                 f"(neutral markers at end: {m3.get('neutral_markers_at_end')})")

    m4 = card["metrics"]["firepower"]
    L.append("")
    if m4.get("score") is not None:
        L.append(f"  firepower: {m4.get('ranged_units_that_fired')}/{m4.get('ranged_units')} ranged units fired "
                 f"({m4.get('ranged_fired_pct')}%) | wasted points: {m4.get('wasted_points')}"
                 f" ({m4.get('wasted_points_pct')}% of {m4.get('total_points_activated')})")
        for w in m4.get("wasted_units", []):
            L.append(f"    - {w['unit']} (P{w['side']}) {w['cost']}pt produced nothing")
    else:
        L.append(f"  firepower: {m4.get('note')}")

    m5 = card["metrics"]["focus"]
    if m5.get("score") is not None:
        L.append("")
        L.append(f"  focus: finished {m5.get('enemy_units_finished')}/{m5.get('enemy_units_damaged')} damaged units | "
                 f"{m5.get('damaged_not_finished_pct')}% left damaged-but-alive "
                 f"({', '.join(m5.get('damaged_not_finished') or []) or 'none'}) | "
                 f"{m5.get('distinct_targets_selected')} distinct targets selected")

    m6 = card["metrics"]["decisiveness"]
    L.append("")
    L.append(f"  decisiveness: markers {m6.get('objectives')} | "
             f"{m6.get('seize_events')} seize events, {m6.get('distinct_objectives_seized')} distinct objectives held | "
             f"survivors {m6.get('survivors')}")
    if m6.get("not_automated_rules"):
        L.append(f"  honest gaps (rules NOT automated, applied manually): {', '.join(m6['not_automated_rules'])}")

    mu = card.get("move_usage_wave1")
    if mu:
        L.append("")
        L.append("  [Wave-1 in-sim move_usage cross-check]")
        for side in sorted(mu.keys()):
            s = mu[side]
            L.append(f"    P{side}: median_ratio={_round(s.get('median_achieved_ratio'))} "
                     f"aircraft_full_lanes={s.get('aircraft_full_lanes')}/{s.get('aircraft_moves')} "
                     f"large_stalls={s.get('large_stalls_by_unit') or {}}")
            for a in s.get("aimless_subinch", []):
                L.append(f"      aimless: {a}")
    L.append("")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None):
    parser = argparse.ArgumentParser(description="Plausibility scorecard for AI self-play artifacts.")
    parser.add_argument("game_dirs", nargs="+", help="one or more game directories")
    parser.add_argument("--json", dest="json_out", help="write machine scorecard JSON to this path")
    parser.add_argument("--quiet", action="store_true", help="suppress the human report on stdout")
    args = parser.parse_args(argv)

    cards = []
    for d in args.game_dirs:
        if not os.path.isdir(d):
            sys.stderr.write(f"warning: not a directory, skipping: {d}\n")
            continue
        card = score_game(load_game(d))
        cards.append(card)
        if not args.quiet:
            print(format_report(card))

    if not args.quiet and len(cards) > 1:
        print("=" * 72)
        print("SUMMARY")
        print("=" * 72)
        for c in cards:
            print(f"  {c['headline_plausibility'] if c['headline_plausibility'] is not None else 'n/a':>6}  {c['game']}")
        print("")

    if args.json_out:
        payload = {"schema": 1, "tool": "plausibility_score", "games": cards}
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=1, sort_keys=True, allow_nan=True)
        if not args.quiet:
            print(f"wrote scorecard JSON -> {args.json_out}")

    return 0 if cards else 1


if __name__ == "__main__":
    raise SystemExit(main())
