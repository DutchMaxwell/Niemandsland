#!/usr/bin/env python3
"""Core half of the table-vs-core parity gate (melee lane).

Reads a neutral scenario (schema nml-scenario-v1, kind "melee", inches): the attacker starts at x_in and charges to
charge.dest_x_in (base contact); both sides carry one melee weapon (range 0). Builds the core's header/state with the
per-model `kits` the tree's own recorder writes (without them the core removes casualties in array order), runs one
CHARGE per seed through Core.resolve_with_tray(state, action, Rng(0), Tray(seed)) and writes one JSONL record per seed:
{"seed", "epoch", "def_alive", "rolls": [{kind, count, target, faces, owner}]}. Same CLI as parity_core.py.

usage: parity_melee_core.py <scenario.json> --repo <root> --out <out.jsonl> [--seeds N]
exit: 0 ok; 3 core rules_epoch != scenario epoch; 4 the core reported unported rule branches.
"""
import argparse
import json
import sys

import nml_core

INCH = 0.0254
BANDS = {"advance": 6.0, "rush": 12.0}


def build(sc):
    att, dfn = sc["attacker"], sc["defender"]
    rad = round(att["base_radius_in"] * INCH, 6)
    pos = lambda u, x: [[round(x * INCH, 6), 0.0, round(u["z_step_in"] * INCH * i, 6)] for i in range(u["models"])]

    def profile(u, w):
        n = u["models"]
        wpn = dict(name=w["name"], range=0, attacks=w["attacks"], count=w["count"], rules=w["rules"])
        return dict(unit_id=u["key"], name=u["name"], quality=u["quality"], defense=u["defense"], tough=u["tough"],
                    wounds_max=[u["tough"]] * n, model_count=n, caster_value=0, base_radius=rad,
                    game_system=u["game_system"], faction_folder=u["faction_folder"], special_rules=u["rules"],
                    item_grants=[], attached_hero_rules=[], move_bands=BANDS, weapons=[wpn])

    def unit(u, x):
        n = u["models"]
        kits = [{"weapons": [], "equipment": 0, "wounds_max": u["tough"]} for _ in range(n)]
        return dict(player=u["player"], alive=n, wounds=[u["tough"]] * n, radii=[rad] * n, positions=pos(u, x),
                    kits=kits, in_cover=False, shaken=False, fatigued=False, activated=False, casts=0,
                    morale_bonus=0, aircraft=False, dormant=False, ambush_arrived_round=-1,
                    earliest_arrival_round=-1, wound_frac=0.0, mods={}, mods_base={}, bands=BANDS)

    post = pos(att, sc["charge"]["dest_x_in"])
    dest = [round(sum(p[i] for p in post) / len(post), 6) for i in range(3)]
    header = {"profiles": {att["key"]: profile(att, sc["weapon"]), dfn["key"]: profile(dfn, sc["defender_weapon"])},
              "knobs": {"rules_epoch": sc["epoch"]}}
    state = dict(round=1, rounds_total=4, scoring="end", units={att["key"]: unit(att, att["x_in"]),
                                                                  dfn["key"]: unit(dfn, dfn["x_in"])})
    return header, state, {"kind": nml_core.CHARGE, "unit": att["key"], "charge": dfn["key"], "dest": dest}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    for flag in ("--repo", "--out"):
        ap.add_argument(flag, required=True)
    ap.add_argument("--seeds", type=int)
    a = ap.parse_args()
    sc = json.load(open(a.scenario))
    assert sc.get("schema") == "nml-scenario-v1" and sc.get("kind") == "melee", "not a melee nml-scenario-v1"
    header, state, action = build(sc)
    core = nml_core.load(a.repo)
    core.set_header(header)
    epoch = core.knobs()["rules_epoch"]
    if epoch != sc["epoch"]:
        return print("FATAL: core epoch %d != scenario epoch %d" % (epoch, sc["epoch"]), file=sys.stderr) or 3
    unported = set()
    with open(a.out, "w") as out:
        for s in range(a.seeds if a.seeds is not None else sc["seeds"]):
            new, rep = core.resolve_with_tray(core.state_of(state), action, nml_core.Rng(0), nml_core.Tray(s))
            unported.update(rep["unported"])
            rolls = [{k: (list(r[k]) if k == "faces" else r[k]) for k in ("kind", "count", "target", "faces", "owner")}
                     for r in rep["rolls"]]
            out.write(json.dumps({"seed": s, "epoch": epoch, "rolls": rolls,
                                  "def_alive": new.plain()["units"][sc["defender"]["key"]]["alive"]}) + "\n")
    print("UNPORTED: %s" % sorted(unported), file=sys.stderr) if unported else None
    return 4 if unported else 0


if __name__ == "__main__":
    sys.exit(main())
