"""ANALYSIS MODE — the IN-BAND charges the RIGID mover loses that the table's own
mover (`mv::step::charge_move`) lands, on the SAME recorded states.

Gen-0 plays `movement="rigid"`, so the mover ladder is inert and a charge is
`resolve`'s rigid arm: `dest` is the target unit's CENTRE (menu.rs:552), the
delta is clamped to the rush band (sim.rs:2691), and `spacing_fraction`
(sim.rs:1877) scales the WHOLE delta by ONE scalar that keeps every mover model
outside every other unit's 1" buffer — one model of a THIRD unit stops the whole
formation. Columns: the DECLARED folded base-edge gap (`sim::engage_gap_in`
:1164), the RIGID landing the recording played, and `Core.charge_move` from the
identical before-state; IN-BAND + RIGID-short + TABLE-contact = a charge the
rigid arm LOST. `--red-farthest` aims the port at the farthest living enemy and
every conversion must collapse. States come from `game_narrator.replay`, the
fidelity tripwire; corpus files are READ-ONLY."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import game_narrator as gn  # noqa: E402
import gen0_replay_one as gr  # noqa: E402

# `BattleSim.IN2M`; `SeparationChecker.DEFAULT_BASE_RADIUS_M` :81;
# `SoloController.MELEE_ENGAGE_IN` :57 = sim.rs:53; `AiDecision.Action` :16.
IN2M, BASE_R_M, MELEE_ENGAGE_IN, CHARGE_KIND = 0.0254, 0.016, 1.0, 3


def folded_gap_in(units: dict, a: str, b: str, override: dict | None = None) -> float:
    """`sim::engage_gap_in` — `geom::edge_gap_in` minimised over both chains (unit
    plus attached heroes); `override` supplies the port's landing, unwritten."""
    chain = lambda k: [k] + [h for h in units[k]["attached"] if units[h]["positions"]]  # noqa: E731
    pos = lambda k: (override or {}).get(k, units[k]["positions"])                      # noqa: E731
    best = float("inf")
    for x in chain(a):
        rx = units[x]["radii"]
        for y in chain(b):
            ry = units[y]["radii"]
            for i, p in enumerate(pos(x)):
                for j, q in enumerate(units[y]["positions"]):
                    d = math.hypot(p[0] - q[0], p[2] - q[2])
                    best = min(best, d - (rx[i] if i < len(rx) else BASE_R_M)
                               - (ry[j] if j < len(ry) else BASE_R_M))
    return best / IN2M


def tap_state() -> None:
    """Widen `game_narrator.Tapped` to keep the STATE and the core; the narrator
    itself stays the fidelity tripwire and nothing else."""
    inner = gn.Tapped.resolve_with_tray

    def tapped(self, state, action, rng, tray):
        nxt, rep = inner(self, state, action, rng, tray)
        gn.A["acts"][-1].update(state=state, core=self.core)
        return nxt, rep

    gn.Tapped.resolve_with_tray = tapped


def census(path: str, lists: str, red_farthest: bool = False) -> list:
    """One recorded game, one row per chosen CHARGE."""
    rec, acts = gn.replay(path, lists, gr.REPO, gr.BANK)
    names, keys, rows = dict(zip(acts[0]["keys"], rec["roster"])), acts[0]["keys"], []
    for n, act in enumerate(acts, 1):
        row = act["row"]
        target = row["cands"]["list"][row["cands"]["best"]].get("charge")
        before, after = act["before"]["units"], act["after"]["units"]
        if int(row["kind"]) != CHARGE_KIND or not target or target not in before:
            continue
        unit = row["unit"]
        band, declared = before[unit]["bands"]["rush"], folded_gap_in(before, unit, target)
        rigid = folded_gap_in(after, unit, target) if after[target]["positions"] else 0.0
        aim = target
        if red_farthest:  # RED: reach, not the recorded pairing, is what is measured
            foes = [k for k, v in before.items() if v["player"] != before[unit]["player"]
                    and v["alive"] > 0 and v["positions"]] or [target]
            aim = max(foes, key=lambda k: folded_gap_in(before, unit, k))
        land = act["core"].charge_move(act["state"], unit, aim)
        moved: dict[str, list] = {}
        for (ui, mi), end in zip(land["movers"] if land else [], land["end"] if land else []):
            m = moved.setdefault(keys[ui], [list(p) for p in before[keys[ui]]["positions"]])
            if mi < len(m):
                m[mi] = list(end)
        table = folded_gap_in(before, unit, aim, moved) if land else float("nan")
        rows.append({
            "game": Path(path).stem, "act": n, "round": row["round"], "side": row["side"],
            "unit": names.get(unit, unit), "target": names.get(aim, aim), "band_in": round(band, 2),
            "target_is_joined_hero": bool(before[target]["attached_to"]), "in_band": declared <= band,
            "declared_in": round(declared, 3), "rigid_gap_in": round(rigid, 3),
            "rigid_contact": rigid <= MELEE_ENGAGE_IN, "dice": len(act["rep"]["rolls"]),
            "table_gap_in": None if land is None else round(table, 3),
            "table_arc_in": None if land is None else round(land["arc_in"], 3),
            "table_contact": bool(land is not None and table <= MELEE_ENGAGE_IN)})
    return rows


def tally(rows: list) -> dict:
    """The headline: IN-BAND charges the RIGID arm lost and the TABLE lands."""
    ib = [r for r in rows if r["in_band"]]
    short = [r for r in ib if not r["rigid_contact"]]
    return {"charges": len(rows), "in_band": len(ib), "in_band_rigid_short": len(short),
            "rigid_contact": sum(r["rigid_contact"] for r in rows),
            "rigid_lost_table_lands": sum(r["table_contact"] for r in short),
            "honest_miss": sum(not r["table_contact"] for r in short),
            "at_a_joined_hero": sum(r["target_is_joined_hero"] for r in rows)}


def line(r: dict) -> str:
    hit = lambda b: "CONTACT" if b else "short"  # noqa: E731
    return ('R%d A%-3d p%d %-22s -> %-22s%-14s band %5.1f" declared %6.2f" %-7s | RIGID %6.2f" %-7s'
            ' | TABLE %6.2f" %-7s (arc %.2f")'
            % (r["round"], r["act"], r["side"], r["unit"][:22], r["target"][:22],
               " [joined hero]" if r["target_is_joined_hero"] else "", r["band_in"],
               r["declared_in"], "IN-BAND" if r["in_band"] else "over", r["rigid_gap_in"],
               hit(r["rigid_contact"]), r["table_gap_in"] or float("nan"),
               hit(r["table_contact"]), r["table_arc_in"] or float("nan")))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("games", nargs="+", help="corpus gen0_s<seed>_d<dice>.json")
    ap.add_argument("--lists", default=gr.LISTS, help="mirror of the fleet's ai_lists")
    ap.add_argument("--red-farthest", action="store_true", help="RED: aim the ported mover "
                    "at the FARTHEST enemy; every 'table converts' verdict must collapse")
    a = ap.parse_args()
    tap_state()
    rows: list = [r for g in a.games for r in census(g, a.lists, a.red_farthest)]
    print("\n".join(line(r) for r in rows))
    print("\nTOTAL %s" % json.dumps(t := tally(rows)))
    print("READING: %d of the %d in-band charges never reached contact under the RIGID arm; the"
          " table's own mover lands %d on the SAME state (%d honest misses — the straight line"
          " fits the band, the routed path does not)."
          % (t["in_band_rigid_short"], t["in_band"], t["rigid_lost_table_lands"], t["honest_miss"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
