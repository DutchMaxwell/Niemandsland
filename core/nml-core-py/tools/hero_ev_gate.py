#!/usr/bin/env python
"""GATE (NML-1132) — does the IMAGINATION carry the weapons the TABLE fired with?

WHAT IS BEING GATED. A joined hero fights inside its host: the live table builds
"a shot per ranged weapon of the unit + attached heroes" (`main._run_ai_shooting`
:2910-2941) and a melee strike phase per member (`_solo_attack_groups`
main.gd:4284-4290). Both IMAGINATIONS — `BattleSim._profiles_of` battle_sim.gd
and its Rust twin `sim::profiles_of` — read the HOST's weapons alone. Because the
two imaginations agreed with EACH OTHER, no parity gate could see it: the planner
valued, targeted and charged a rifle squad as if the fusion-pistol hero riding
with it did not exist. This gate asks the third party — the RECORDING of the real
table — and it is the first one that can go red on that.

THE BAR, per ACT, and it is a count of acts, not of weapons:

  SHOOT  — the act's pick is a HOLD/ADVANCE with a `shoot` target and the
           attacker carries at least one ALIVE attached hero. `shots.jsonl`
           records one row per (member, weapon) the table actually resolved, so
           the rows whose `member` is a hero and whose `attacks` > 0 are the
           table's own proof that the hero fired. The act is RED when a weapon
           name from that set is missing from the twin's imagined profile.
  MELEE  — the act's pick is a CHARGE with a target and the attacker carries an
           alive attached hero. `dice.jsonl` signs every roll with the MEMBER
           that drew it (main.gd:7173), so an `attack` roll under this act owned
           by a hero is the table's proof that the hero struck. The act is RED
           when the twin's imagined MELEE profile carries none of that hero's
           melee weapons.

ONLY HERO-ONLY WEAPON NAMES COUNT, on purpose. A name the HOST also carries
cannot tell a missing hero profile from a merged one (`AiShooting` merges equal
weapons and the imagination reports one entry), so comparing those would either
flatter the gate or invent misses out of the merge. The hero-only set is what
the table can prove and the imagination can be held to. Weapons a hero shares
with its host are reported as `shared_skipped` and are the gate's own blind spot.

THE INSTRUMENT is the twin itself: `Core.imagined_profiles(state, unit, melee,
target)` runs `sim::member_profiles_of` — the very function `resolve`'s
expected-value half calls — on the act's own recorded state, with the reach
measured by `sim::fold_dist_in` exactly as `resolve` measures it. Nothing here
restates the rule in Python.

THE RED. `--fold off` asks the same question with `hero_attach` OFF in the
header, which is `member_profiles_of`'s pass-through to the plain
`profiles_of`/`melee_profiles_of` — i.e. the imagination as it stood BEFORE this
ticket, function for function. Every act whose hero fired must go red there, and
the run refuses to call a corpus with no joined hero a proof.

    ~/venvs/nml1132/bin/python core/nml-core-py/tools/hero_ev_gate.py \\
        --ref ~/selfplay_out/qbg_ref
    ~/venvs/nml1132/bin/python core/nml-core-py/tools/hero_ev_gate.py \\
        --ref ~/selfplay_out/qbg_ref --fold off
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
from shoot_replay_gate import (  # noqa: E402
    SHOOTING_KINDS, read_game, resolve_vintage_flag, vintage_report_line,
)

CHARGE_KIND = 3
IN2M = 0.0254


def hero_weapons(profiles: dict, host_key: str, hero_keys: list) -> tuple[set, set, set]:
    """(hero-only ranged names, hero-only melee names, names shared with the host).
    A weapon is MELEE when its printed range is 0 — the same door
    `AiShooting.melee_profiles` uses (ai_shooting.gd:44-56)."""
    host = {str(w["name"]) for w in profiles[host_key]["weapons"]}
    ranged, melee, shared = set(), set(), set()
    for hk in hero_keys:
        for w in profiles[hk]["weapons"]:
            name = str(w["name"])
            if name in host:
                shared.add(name)
            elif int(w["range"]) > 0:
                ranged.add(name)
            else:
                melee.add(name)
    return ranged, melee, shared


def host_dist_in(units: dict, a: str, b: str) -> float:
    """`BattleSim.dist_in(su["positions"], tu["positions"])` — the HOST-ONLY
    nearest-model distance the imagination measured before this ticket. Computed
    here, not asked of the twin, so the range half has a reading that does not
    move when the twin's does."""
    pa, pb = units[a]["positions"], units[b]["positions"]
    if not pa or not pb:
        return float("inf")
    best = float("inf")
    for u in pa:
        for v in pb:
            d = sum((u[i] - v[i]) ** 2 for i in range(3)) ** 0.5
            best = min(best, d)
    return best / IN2M


def run(ref: Path, repo: str, fold: str, limit: int, verbose: int,
        engage_fold: str = "auto", cond_ap: str = "auto") -> int:
    games = sorted(d for d in ref.iterdir() if d.is_dir() and (d / "acts.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no acts.jsonl under %s" % ref)
        return 1

    t = {k: 0 for k in ("games", "hero_acts", "shoot_acts", "melee_acts", "shoot_fired",
                        "melee_struck", "shoot_missing", "melee_missing", "range_moved",
                        "shared_skipped", "off_target", "declined")}
    firsts: list[str] = []
    vintage_seen: set[tuple[bool, bool]] = set()
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, _seed = read_game(d)
        shots = [json.loads(x) for x in (d / "shots.jsonl").read_text().splitlines() if x.strip()]
        eff_engage_fold = resolve_vintage_flag(engage_fold, head, repo, "engage_fold")
        eff_cond_ap = resolve_vintage_flag(cond_ap, head, repo, "cond_ap")
        vintage_seen.add((eff_engage_fold, eff_cond_ap))
        nml_core.set_legacy_no_cond_ap(not eff_cond_ap)
        core = nml_core.load(repo)
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), hero_attach=fold == "on",
                                       engage_fold=eff_engage_fold)})
        profiles = head["profiles"]
        t["games"] += 1

        for act in lines:
            k = int(act["act"])
            action = (act.get("pick") or {}).get("action") or {}
            kind = int(action.get("kind", -1))
            melee = kind == CHARGE_KIND and bool(action.get("charge"))
            shoot = kind in SHOOTING_KINDS and bool(action.get("shoot"))
            if not (melee or shoot):
                continue
            units = act["state"]["units"]
            host = str(action["unit"])
            heroes = [h for h in units.get(host, {}).get("attached", [])
                      if int(units.get(h, {}).get("alive", 0)) > 0]
            if not heroes:
                continue
            t["hero_acts"] += 1
            target = str(action["charge" if melee else "shoot"])
            rng_names, ml_names, shared = hero_weapons(profiles, host, heroes)
            t["shared_skipped"] += len(shared)
            hero_labels = {"AI (%s)" % profiles[h]["name"] for h in heroes}

            try:
                state = core.state_of(act["state"])
                imagined = core.imagined_profiles(state, host, melee=melee, target=target)
            except Exception as exc:
                t["declined"] += 1
                if len(firsts) < 4:
                    firsts.append("%s act %d — DECLINED: %s" % (d.name, k, exc))
                continue
            seen = set(imagined["names"])

            if melee:
                t["melee_acts"] += 1
                # The table's own proof that a hero struck: an `attack` roll under
                # this activation signed by the hero. `dangerous`/`morale`/... are
                # their own kinds since NML-1104 and are NOT folded in here.
                struck = any(int(r["act"]) == k and r["roll_kind"] == "attack"
                             and r["owner"] in hero_labels and int(r["count"]) > 0
                             for r in dice)
                if not struck or not ml_names:
                    continue
                t["melee_struck"] += 1
                if not (ml_names & seen):
                    t["melee_missing"] += 1
                    if len(firsts) < 4:
                        firsts.append("%s act %d [melee] %s struck with %s — imagined %s"
                                      % (d.name, k, profiles[host]["name"],
                                         sorted(ml_names), sorted(seen)))
                continue

            t["shoot_acts"] += 1
            # SPLIT FIRE is not this gate's business and would poison its number:
            # the table picks a target PER WEAPON (`_solo_pick_overlay_target`
            # main.gd:2996-3005) while the imagination values ONE volley against
            # the pick's target, so a hero shot aimed elsewhere is measured
            # against a reach that was never asked about. Only rows the table
            # aimed at the PICK's own target count.
            aimed = str(profiles[target]["name"])
            rows = [r for r in shots if int(r["act"]) == k and int(r["attacks"]) > 0
                    and str(r["weapon"]) in rng_names]
            fired = {str(r["weapon"]) for r in rows if str(r["target"]) == aimed}
            t["off_target"] += len(rows) - len(
                [r for r in rows if str(r["target"]) == aimed])
            # The RANGE half (NML-1132 b), reported apart from the bar: the reach the
            # twin measured against the host-only one the imagination used before.
            # 1e-4" of slack: `geom::dist_in` computes in f32 (`to_f32`, geom.rs:90)
            # and this reading is f64, so the two part in the seventh digit even
            # when they measure the same two models. A fold moves INCHES.
            if abs(float(imagined["d_in"]) - host_dist_in(units, host, target)) > 1e-4:
                t["range_moved"] += 1
            if not fired:
                continue
            t["shoot_fired"] += 1
            gone = fired - seen
            if gone:
                t["shoot_missing"] += 1
                if len(firsts) < 4:
                    firsts.append("%s act %d [shoot] %s fired %s — imagined %s"
                                  % (d.name, k, profiles[host]["name"],
                                     sorted(gone), sorted(seen)))

    dt = time.perf_counter() - t0
    missing = t["shoot_missing"] + t["melee_missing"]
    print("=== HERO EV GATE (NML-1132) — %s, fold=%s, %s ===" % (
        ref, fold, vintage_report_line(vintage_seen)))
    print("games %d   acts with an alive joined hero %d   (%.1fs)"
          % (t["games"], t["hero_acts"], dt))
    print("SHOOT  acts %d   the hero fired %d   imagination MISSING the weapon %d"
          % (t["shoot_acts"], t["shoot_fired"], t["shoot_missing"]))
    print("MELEE  acts %d   the hero struck %d   imagination MISSING the weapon %d"
          % (t["melee_acts"], t["melee_struck"], t["melee_missing"]))
    print("range  acts whose imagined reach is NOT the host-only distance %d" % t["range_moved"])
    print("skipped: hero weapons the host also carries %d   hero shots the table aimed "
          "elsewhere (split fire) %d   declined acts %d"
          % (t["shared_skipped"], t["off_target"], t["declined"]))
    print("BAR: acts whose imagined profile lacks a weapon the table resolved = %d" % missing)
    for line in firsts:
        print("  %s" % line)
    if verbose:
        print(json.dumps(t, indent=2, sort_keys=True))
    if t["hero_acts"] == 0:
        print("VACUOUS — no act in this corpus carries a joined hero; not a proof either way")
        return 1
    return 0 if missing == 0 else 2


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", type=Path, required=True, help="recorded arena corpus")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--fold", choices=("on", "off"), default="on",
                    help="'off' = the imagination BEFORE NML-1132 (the red control)")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto")
    ap.add_argument("-v", "--verbose", action="count", default=0)
    a = ap.parse_args()
    return run(a.ref, a.repo, a.fold, a.limit, a.verbose, a.engage_fold, a.cond_ap)


if __name__ == "__main__":
    raise SystemExit(main())
