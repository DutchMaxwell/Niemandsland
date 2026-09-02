#!/usr/bin/env python3
# Corpus oracle for `deployment::arrive_one` (S4, coordinator correction 2026-09-02): the SPEC's
# "zero arrivals in the corpora" (finding 1) was wrong -- measured, qbg_ref carries 77/168 games
# with dormant units (91 arriving) and qag_ref 35 games (35 arriving). Scans both bundles' acts.jsonl
# for the dormant->alive transition (ambush_arrived_round newly == the act's round) and records the
# REAL arrival: post-arrival model positions (centroid = the drop anchor -- _deploy_footprint_offsets
# is symmetric around it, solo_controller.gd:10300-10304) plus what arrive_one needs: zone
# (table_size_feet), objectives, occupied (every OTHER alive unit's live models both sides, +0.005 m
# per occupied_from_live_bases, :10213), enemies ({pos,min_dist_m,pad_m}), own_ring_m (Infiltrate 3"
# else 9"), footprint (positions minus centroid), base_r, flying.
#
# Rounds where more than one unit arrives are skipped -- the act log has no record of the
# alternating loop's intermediate order, so `occupied` cannot be reconstructed for a second arrival
# in the same round-start batch.
#
# GAPS the corpora do NOT cover (grepped, zero hits either bundle) -- synthetic instead, via
# tools/ambush_arrival_dump.gd: Repel Ambushers (no enemy ever carries it) and HELD (no unit ever
# stays dormant to a game's end, and "still dormant next round" can't be told apart here from
# "hasn't had its alternating turn yet").
#
# Usage: ambush_arrival_corpus.py <out.json> <corpus_dir> [<corpus_dir> ...]
import glob
import json
import os
import sys


def game_cases(path):
    acts = [json.loads(l) for l in open(path)]
    tf = acts[0]["terrain"]["cell_params"]["table_size_feet"]
    zone = [-tf[0] * 0.1524, -tf[1] * 0.1524, tf[0] * 0.3048, tf[1] * 0.3048]
    dormant, arrivals, out = {}, {}, []
    for act in acts:
        if act.get("kind") != "act":
            continue
        rnd, st = act["round"], act["state"]
        for uid, u in st["units"].items():
            if dormant.get(uid, u.get("dormant", False)) and not u.get("dormant", False) and u.get("ambush_arrived_round", -1) == rnd:
                arrivals.setdefault(rnd, []).append((uid, st))
            dormant[uid] = u.get("dormant", False)
    for arr in arrivals.values():
        if len(arr) != 1:
            continue
        uid, st = arr[0]; units = st["units"]; u = units[uid]; pos = u["positions"]
        if not pos:
            continue
        cx, cz = sum(p[0] for p in pos) / len(pos), sum(p[2] for p in pos) / len(pos)
        rules = u["prof"]["special_rules"]
        others = [(ou, p, r) for oid, ou in units.items() if oid != uid and not ou.get("dormant") and ou.get("alive", 0) > 0
                  for p, r in zip(ou["positions"], ou.get("radii") or [0.016] * len(ou["positions"]))]
        occ = [{"pos": [p[0], p[2]], "radius": r + 0.005} for ou, p, r in others]
        ene = [{"pos": [p[0], p[2]], "min_dist_m": 0.3048 if "Repel Ambushers" in ou["prof"]["special_rules"] else 0.0, "pad_m": r}
               for ou, p, r in others if ou["player"] != u["player"]]
        out.append({"case": "%s_%s" % (os.path.basename(os.path.dirname(path)), uid[-8:]), "zone": zone,
            "objectives": [[o["pos"][0], o["pos"][2]] for o in st["objectives"]], "occupied": occ, "enemies": ene,
            "own_ring_m": 0.0762 if "Infiltrate" in rules else 0.2286, "footprint": [[p[0] - cx, p[2] - cz] for p in pos],
            "base_r": (u.get("radii") or [0.016])[0], "flying": "Strider" in rules or "Flying" in rules, "spot": [cx, cz]})
    return out


if __name__ == "__main__":
    all_cases = [c for d in sys.argv[2:] for f in sorted(glob.glob(os.path.join(d, "*", "acts.jsonl"))) for c in game_cases(f)]
    json.dump({"schema": 1, "tool": "ambush_arrival_corpus", "cases": all_cases}, open(sys.argv[1], "w"), indent=1)
    print("AMBUSH_ARRIVAL_CORPUS %d cases -> %s" % (len(all_cases), sys.argv[1]))
