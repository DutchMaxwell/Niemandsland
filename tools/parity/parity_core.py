#!/usr/bin/env python3
"""Core half of the table-vs-core parity gate (shoot lane).

Reads a neutral scenario (schema nml-scenario-v1, lengths in inches), builds the core's header/state/action from it,
runs one shooting activation per seed through Core.resolve_with_tray(state, action, Rng(0), Tray(seed)) and writes one
JSONL record per seed: {"seed", "epoch", "def_alive", "rolls": [{kind, count, target, faces, owner}]}.
Optional scenario keys: "volleys": n runs n activations at the same defender per seed (one Tray, the state carried
through, so a once-per-game latch spends in the first); "strafe": {"dest_x_in": x} replaces the volley by a RUSH of the
attacker to x through the defender (the move-through volley fires inside that act); "allow_unported": [names] lists
core markers this scenario accepts (named per scenario, printed, never a default).

usage: parity_core.py <scenario.json> --repo <root> --out <out.jsonl> [--seeds N]
exit: 0 ok; 3 core rules_epoch != scenario epoch; 4 the core reported unported rule branches the scenario does not allow.
"""
import argparse
import json
import sys

import nml_core

INCH = 0.0254
BANDS = {"advance": 6.0, "rush": 12.0}


def build(sc):
    att, dfn, w = sc["attacker"], sc["defender"], sc["weapon"]
    pos = lambda u: [[round(u["x_in"] * INCH, 6), 0.0, round(u["z_step_in"] * INCH * i, 6)] for i in range(u["models"])]
    rad = lambda u: round(u["base_radius_in"] * INCH, 6)
    wpn = [dict(name=w["name"], range=w["range_in"], attacks=w["attacks"], count=w["count"], rules=w["rules"])]

    def profile(u, weapons):
        return dict(unit_id=u["key"], name=u["name"], quality=u["quality"], defense=u["defense"], tough=u["tough"],
                    wounds_max=[u["tough"]] * u["models"], model_count=u["models"], caster_value=0,
                    base_radius=rad(u), game_system=u["game_system"], faction_folder=u["faction_folder"],
                    special_rules=u["rules"], item_grants=[], attached_hero_rules=[], move_bands=BANDS,
                    weapons=weapons)

    def unit(u):
        n = u["models"]
        return dict(player=u["player"], alive=n, wounds=[u["tough"]] * n, radii=[rad(u)] * n, positions=pos(u),
                    in_cover=False, shaken=False, fatigued=False, activated=False, casts=0, morale_bonus=0,
                    aircraft=False, dormant=False, ambush_arrived_round=-1, earliest_arrival_round=-1,
                    wound_frac=0.0, mods={}, mods_base={}, bands=BANDS)

    header = {"profiles": {att["key"]: profile(att, wpn), dfn["key"]: profile(dfn, [])},
              "knobs": {"rules_epoch": sc["epoch"]}}
    state = dict(round=1, rounds_total=4, scoring="end", units={att["key"]: unit(att), dfn["key"]: unit(dfn)})
    action = {"kind": nml_core.HOLD, "unit": att["key"], "shoot": dfn["key"]}
    if "strafe" in sc:
        go = dict(att, x_in=sc["strafe"]["dest_x_in"])
        dest = [round(sum(p[i] for p in pos(go)) / go["models"], 6) for i in range(3)]
        action = {"kind": nml_core.RUSH, "unit": att["key"], "dest": dest}
    return header, state, action


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    for flag in ("--repo", "--out"):
        ap.add_argument(flag, required=True)
    ap.add_argument("--seeds", type=int)
    a = ap.parse_args()
    sc = json.load(open(a.scenario))
    assert sc.get("schema") == "nml-scenario-v1", "unknown scenario schema"
    header, state, action = build(sc)
    core = nml_core.load(a.repo)
    core.set_header(header)
    epoch = core.knobs()["rules_epoch"]
    if epoch != sc["epoch"]:
        return print("FATAL: core epoch %d != scenario epoch %d" % (epoch, sc["epoch"]), file=sys.stderr) or 3
    unported = set()
    with open(a.out, "w") as out:
        for s in range(a.seeds if a.seeds is not None else sc["seeds"]):
            new, tray, rolls = core.state_of(state), nml_core.Tray(s), []
            for _ in range(sc.get("volleys", 1)):
                new, rep = core.resolve_with_tray(new, action, nml_core.Rng(0), tray)
                unported.update(rep["unported"])
                rolls += [{k: (list(r[k]) if k == "faces" else r[k]) for k in ("kind", "count", "target", "faces", "owner")}
                          for r in rep["rolls"]]
            out.write(json.dumps({"seed": s, "epoch": epoch, "rolls": rolls,
                                  "def_alive": new.plain()["units"][sc["defender"]["key"]]["alive"]}) + "\n")
    open_marks = unported - set(sc.get("allow_unported", []))
    print("UNPORTED: %s (allowed by the scenario: %s)" % (sorted(open_marks), sorted(unported - open_marks)),
          file=sys.stderr) if unported else None
    return 4 if open_marks else 0


if __name__ == "__main__":
    sys.exit(main())
