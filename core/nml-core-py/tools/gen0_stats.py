#!/usr/bin/env python3
"""Gen-0 training design step 1 (DESIGN_gen0_training_2026-09-02 SS5.1): the
corpus reader that proves SS1's measured numbers. Read-only, never writes
into the corpus. gen0_stats.py --corpus DIR [--every K] [--limit N] [--out F]."""
import argparse, json, re, sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from narrator_render import played_index  # noqa: E402

# kind ids per SS1.3 (lib.rs cand_plain): 0 HOLD, 1 ADVANCE, 2 RUSH, 3 CHARGE.
KIND_NAMES = {0: "HOLD", 1: "ADVANCE", 2: "RUSH", 3: "CHARGE"}


def pct(sv, p):  # nearest-rank percentile on an already-sorted list
    if not sv:
        return None
    i = round((p / 100.0) * (len(sv) - 1))
    return sv[max(0, min(i, len(sv) - 1))]


def stats(vals):
    s = sorted(vals)
    if not s:
        return {"n": 0}
    return {"n": len(s), "mean": sum(s) / len(s), "p10": pct(s, 10), "p50": pct(s, 50),
            "p90": pct(s, 90), "min": s[0], "max": s[-1]}


def shares(counter):
    n = sum(counter.values()) or 1
    return {k: v / n for k, v in counter.items()}


def width_hist(widths):
    n = len(widths) or 1
    buckets = Counter(min(w // 10, 7) for w in widths)
    labels = ["0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70+"]
    return {"hist": {labels[k]: buckets.get(k, 0) for k in range(8)},
            "ge32": sum(w >= 32 for w in widths) / n, "ge64": sum(w >= 64 for w in widths) / n,
            "eq1": sum(w == 1 for w in widths) / n}


def points_of(army_path):  # ".../<faction>_<points>.json" -> points (SS1.5)
    m = re.search(r"_(\d+)\.json$", army_path)
    return int(m.group(1)) if m else None


def validate(name, positions):
    # REFUSE (raise), never warn: SS1.4's exact join on the PLAYED act's index — re-ranked Gen-1 rows must pass.
    for i, p in enumerate(positions):
        lst, pick = p["cands"]["list"], played_index(p["cands"])
        if not 0 <= pick < len(lst):
            raise ValueError(f"{name}#{i}: cands index {pick} out of range 0..{len(lst)}")
        if p["action"] != lst[pick]:
            raise ValueError(f"{name}#{i}: action != cands.list[pick]")


def unit_slots(p):
    # (first-seen index of the chosen unit, slot of the pick in its own block).
    lst, unit = p["cands"]["list"], p["unit"]
    seen = list(dict.fromkeys(c["unit"] for c in lst))
    own = [c for c in lst if c["unit"] == unit]
    return seen.index(unit), own.index(p["action"])


def load_games(corpus, every, limit):
    files = sorted(Path(corpus).expanduser().glob("gen0_s*_d*.json"))[::every]
    for f in files[:limit] if limit else files:
        yield f.name, json.loads(f.read_text())


# The four CONTEXT-FREE baselines (no board state, only menu order/counts):
# slot0 = always the menu's first entry; first_unit = always the first-seen
# unit; own_slot0 = always slot 0 of the acting unit's own block; majority_kind
# = the mode chosen kind, FIT on the train games only. Scored BY-GAME (SS6.3:
# acts of one game share a board/dice stream/winner, a position split leaks),
# a fixed 1-in-5 holdout. (SS3.4's own definition was outside this step's
# reading scope; this is the reader's best-effort reconstruction of it from
# what SS1 already measures, named as such rather than guessed silently.)
def baselines(rows, names):
    hold = {n for i, n in enumerate(names) if i % 5 == 0}
    train_kind = Counter(k for n, *_, k in rows if n not in hold)
    top = train_kind.most_common(1)[0][0] if train_kind else None
    ho = [r for r in rows if r[0] in hold]
    n = len(ho) or 1
    return {"holdout_games": len(hold), "holdout_positions": len(ho),
            "slot0": sum(r[1] for r in ho) / n, "first_unit": sum(r[2] for r in ho) / n,
            "own_slot0": sum(r[3] for r in ho) / n,
            "majority_kind": sum(r[4] == top for r in ho) / n}


def collect(games):
    positions, widths, played_idx = [], [], []
    chosen_kind, menu_kind, winner, rounds_played = Counter(), Counter(), Counter(), Counter()
    cu_idx, own_slot, distinct_units, acting_block = [], [], [], []
    width_by_points, rows, names = {}, [], []
    for name, g in games:
        pp = g["planner_positions"]
        validate(name, pp)
        names.append(name); positions.append(len(pp))
        winner[g["winner"]] += 1; rounds_played[g["rounds_played"]] += 1
        pts = points_of(g["armies"]["p1"])
        for p in pp:
            # output keys keep `best`'s old name; the index scored is the PLAYED act's
            lst, pick = p["cands"]["list"], played_index(p["cands"])
            cu, ws = unit_slots(p)
            kind = KIND_NAMES[p["kind"]]
            widths.append(len(lst))
            width_by_points.setdefault(pts, []).append(len(lst))
            chosen_kind[kind] += 1
            menu_kind.update(KIND_NAMES[c["kind"]] for c in lst)
            played_idx.append(pick); cu_idx.append(cu); own_slot.append(ws)
            distinct_units.append(len({c["unit"] for c in lst}))
            acting_block.append(sum(c["unit"] == p["unit"] for c in lst))
            rows.append((name, pick == 0, cu == 0, ws == 0, kind))
    return {"games": len(names), "positions_per_game": stats(positions),
            "menu_width": dict(stats(widths), **width_hist(widths)),
            "menu_width_by_points": {p: stats(v) for p, v in sorted(
                width_by_points.items(), key=lambda kv: (kv[0] is None, kv[0]))},
            "chosen_kind_share": shares(chosen_kind), "menu_kind_share": shares(menu_kind),
            "best_nonzero_share": sum(b != 0 for b in played_idx) / (len(played_idx) or 1),
            "best_idx": stats(played_idx), "distinct_units": stats(distinct_units),
            "acting_unit_block": stats(acting_block),
            "chosen_unit_first_share": cu_idx.count(0) / (len(cu_idx) or 1),
            "within_unit_slot0_share": own_slot.count(0) / (len(own_slot) or 1),
            "winner": dict(winner), "rounds_played": dict(rounds_played),
            "baselines": baselines(rows, names)}


# An Ambush/Infiltrate/Rapid Ambush/Ambush Beacon carrier never arrives for the
# twin (selfplay.py ~1528-1536: a reserved unit starts off-table and the twin
# does not bring it on) -- so any game whose army carries one was played
# short-handed. A unit is a CARRIER if any of its own rules, or any rule an
# item's `content` grants it, names one of those (substring match, case-free).
def is_carrier(u):
    names = [r.get("name", "") for r in u.get("rules", [])]
    names += [c.get("name", "") for it in u.get("items", []) for c in it.get("content", [])]
    return any(k in n.lower() for n in names for k in ("ambush", "infiltrate"))


def load_list(path, list_dir, cache):
    base = Path(path).name
    if base not in cache:
        cache[base] = json.loads((list_dir / base).read_text())
    return cache[base]


def ambush_audit(games, list_dir):
    cache, per_game, list_carriers, pts_hit = {}, [], {}, Counter()
    for name, g in games:
        carriers, pts = [], None
        for side in ("p1", "p2"):
            path = g["armies"][side]
            found = [u["name"] for u in load_list(path, list_dir, cache)["units"] if is_carrier(u)]
            if found:
                carriers += found
                list_carriers.setdefault(Path(path).name, set()).update(found)
            pts = points_of(path) if side == "p1" else pts
        per_game.append(len(carriers))
        if carriers:
            pts_hit[pts] += 1
    affected = [c for c in per_game if c > 0]
    return {"games": len(per_game), "affected_games": len(affected),
            "affected_share": len(affected) / (len(per_game) or 1),
            "carriers_per_affected_game": stats(affected),
            "affected_points_split": dict(pts_hit),
            "lists_with_ambushers": {k: sorted(v) for k, v in list_carriers.items()}}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", default=str(Path.home() / "selfplay_out/gen0_teacher"))
    ap.add_argument("--every", type=int, default=1, help="sample every Kth file, by name")
    ap.add_argument("--limit", type=int, default=0, help="cap on games after striding")
    ap.add_argument("--out", default=".forge/gen0_stats.json")
    ap.add_argument("--ambush-audit", action="store_true",
                    help="report Ambush/Infiltrate carriers per SS1.5's army lists, not the corpus stats")
    a = ap.parse_args(argv)
    if a.ambush_audit:
        list_dir = Path.home() / "nml-mission/farm/ai_lists"
        summary = ambush_audit(load_games(a.corpus, a.every, a.limit), list_dir)
    else:
        try:
            summary = collect(load_games(a.corpus, a.every, a.limit))
        except ValueError as e:
            sys.exit(f"refusing corrupt corpus record: {e}")
        if summary["games"] == 0:
            sys.exit(f"no gen0_s*_d*.json files matched under {a.corpus}")
    out = Path(a.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1))
    print(f"wrote {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
