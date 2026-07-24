#!/usr/bin/env python3
"""KI-Schmiede — tactic audit over arena selfplay captures (NML-209, D1-D6).

Reads capture dirs (decisions.json + battlelog.txt) and scores every game with the named
tactical-failure detectors from ~/Niemandsland_KI_Schmiede_Plan.md. The detectors are the
DAUER-MESSLATTE: every AI change must not worsen any detector on the fixed seed batch.

Usage:  python3 tools/tactic_audit.py <capture_dir> [<capture_dir> ...]
        python3 tools/tactic_audit.py --glob '~/selfplay_out/schmiede1/g*'
Output: per-game detector table + aggregate JSON on stdout (last line, machine-readable).
"""
import json, re, sys, glob, os


def load(cap):
    dec, log = [], ""
    try:
        dec = json.load(open(os.path.join(cap, "decisions.json")))
    except Exception:
        pass
    try:
        log = open(os.path.join(cap, "battlelog.txt")).read()
    except Exception:
        pass
    return dec, log


def audit(cap):
    dec, log = load(cap)
    r = {"cap": os.path.basename(cap.rstrip("/"))}

    # Final mission truth from the battlelog's GAME OVER block.
    m = re.search(r"Objectives — P2 [^:]*: (\d+) · P1 [^:]*: (\d+) · neutral: (\d+)", log)
    r["obj_p2"], r["obj_p1"], r["obj_neutral"] = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else (0, 0, 0)
    # M0 — the PRIMARY outcome: markers actually HELD at game end (both sides). Activity metrics
    # (D1 short/seized counts) are process signals only — a swarm parked on one marker inflates
    # "seized" events without winning anything.
    r["held_total"] = r["obj_p1"] + r["obj_p2"]
    r["rounds"] = max([int(e.get("round", 0)) for e in dec] + [0])

    # D1 marker hunger: seize_checks ending "short of marker" while toward_objective; per side.
    d1 = {1: 0, 2: 0}
    seized = {1: 0, 2: 0}
    for e in dec:
        if e.get("kind") != "seize_check":
            continue
        s = int(e.get("side", 0))
        if str(e.get("chosen", "")).startswith("short"):
            d1[s] = d1.get(s, 0) + 1
        else:
            seized[s] = seized.get(s, 0) + 1
    r["d1_short"] = d1
    r["d1_seized"] = seized

    # D2 congestion: move records whose spent budget collapsed far below the band.
    d2 = 0
    moves = 0
    for e in dec:
        if e.get("kind") != "move":
            continue
        moves += 1
        band = float(e.get("data", {}).get("band_in", 0))
        budget = float(e.get("data", {}).get("budget_in", band))
        if band >= 5.9 and budget < 0.6 * band:
            d2 += 1
    r["d2_congested"] = d2
    r["d2_moves"] = moves

    # D3 difficult paralysis: same unit charge-capped in >=2 distinct rounds.
    capped = {}
    for e in dec:
        if e.get("kind") == "mission" and "difficult" in str(e.get("why", "")):
            capped.setdefault(e.get("unit"), set()).add(int(e.get("round", 0)))
    r["d3_paralysed_units"] = sorted(u for u, rs in capped.items() if len(rs) >= 2)

    # D4 futile fire: chosen-volley target EV under floor; plus 0-hit weapon volleys from the log.
    d4 = 0
    tgts = 0
    for e in dec:
        if e.get("kind") != "target":
            continue
        tgts += 1
        ch = [c for c in e.get("candidates", []) if c.get("name") == e.get("chosen")]
        if ch and float(ch[0].get("ev", 0)) < 0.5:
            d4 += 1
    vol = re.findall(r"fires .+? at .+? — (\d+) hits", log)
    r["d4_lowev_picks"] = d4
    r["d4_targets"] = tgts
    r["d4_zero_volleys"] = sum(1 for v in vol if v == "0")
    r["d4_volleys"] = len(vol)

    # D5 caster waste: coin-flip casts left AFFORDABLE boost tokens unspent (tokens_after >= 1
    # means a boost was payable and skipped; a cast that drained the pool is not waste).
    d5 = 0
    casts = 0
    for e in dec:
        if e.get("kind") != "cast":
            continue
        casts += 1
        d = e.get("data", {})
        if float(d.get("p_cast", 1)) <= 0.5 and int(d.get("boost", 0)) == 0 and int(d.get("tokens_after", 0)) >= 1:
            d5 += 1
    r["d5_waste_casts"] = d5
    r["d5_casts"] = casts

    # D6 endgame lateness: first ENDGAME release round (0 = never) — the urgency kind also carries
    # the EV-floor overlay, so filter on the endgame whys.
    rel = [int(e.get("round", 0)) for e in dec if e.get("kind") == "urgency"
           and str(e.get("why", "")) in ("final-round urgency", "endgame convergence")]
    # Planner mode: a round PLAN from round 1 IS the release — D6 only flags games where NEITHER
    # a plan nor an endgame release ever appeared.
    if not rel:
        rel = [int(e.get("round", 0)) for e in dec if e.get("kind") == "plan"]
    r["d6_first_release_round"] = min(rel) if rel else 0

    # D7 silent no-shot (wave 4, B2/B6): armed units ending an Advance/Hold without any volley.
    # The transparency line names the reason; LOS-blocked cases are the positioning failures the
    # position solver should shrink — range cases are usually honest early-game distance.
    no_shot = re.findall(r": no shot — (.+)", log)
    r["d7_no_shot"] = len(no_shot)
    r["d7_no_shot_los"] = sum(1 for s in no_shot if "line of sight" in s)
    return r


def main():
    caps = []
    args = sys.argv[1:]
    if args and args[0] == "--glob":
        caps = sorted(glob.glob(os.path.expanduser(args[1])))
    else:
        caps = args
    caps = [c for c in caps if os.path.isdir(c)]
    if not caps:
        print("no capture dirs", file=sys.stderr)
        sys.exit(1)
    out = [audit(c) for c in caps]
    agg = {
        "games": len(out),
        "held_total": sum(o["held_total"] for o in out),
        "obj_diff_p1_minus_p2": sum(o["obj_p1"] - o["obj_p2"] for o in out),
        "neutral_total": sum(o["obj_neutral"] for o in out),
        "d1_short_total": sum(sum(o["d1_short"].values()) for o in out),
        "d1_seized_total": sum(sum(o["d1_seized"].values()) for o in out),
        "d2_congestion_rate": round(sum(o["d2_congested"] for o in out) / max(1, sum(o["d2_moves"] for o in out)), 3),
        "d3_paralysed_units": sum(len(o["d3_paralysed_units"]) for o in out),
        "d4_lowev_rate": round(sum(o["d4_lowev_picks"] for o in out) / max(1, sum(o["d4_targets"] for o in out)), 3),
        "d4_zero_volley_rate": round(sum(o["d4_zero_volleys"] for o in out) / max(1, sum(o["d4_volleys"] for o in out)), 3),
        "d5_waste_casts": sum(o["d5_waste_casts"] for o in out),
        "d6_never_released": sum(1 for o in out if o["d6_first_release_round"] == 0),
        "d7_no_shot_total": sum(o["d7_no_shot"] for o in out),
        "d7_no_shot_los": sum(o["d7_no_shot_los"] for o in out),
    }
    for o in out:
        print(f"{o['cap']}: P1 {o['obj_p1']} : {o['obj_p2']} P2 (neutral {o['obj_neutral']}, R{o['rounds']}) | "
              f"D1 short {sum(o['d1_short'].values())}/seized {sum(o['d1_seized'].values())} | D2 {o['d2_congested']}/{o['d2_moves']} | "
              f"D3 {len(o['d3_paralysed_units'])} | D4 lowEV {o['d4_lowev_picks']}/{o['d4_targets']}, 0-hit {o['d4_zero_volleys']}/{o['d4_volleys']} | "
              f"D5 {o['d5_waste_casts']}/{o['d5_casts']} | D6 rel R{o['d6_first_release_round']} | "
              f"D7 no-shot {o['d7_no_shot']} (LOS {o['d7_no_shot_los']})")
    print("AGG " + json.dumps(agg))


if __name__ == "__main__":
    main()
