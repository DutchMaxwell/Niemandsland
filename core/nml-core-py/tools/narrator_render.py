#!/usr/bin/env python3
"""ANALYSIS MODE's display layer: army tables, candidate text, the dice trail,
one board SVG per round. Plain SVG on the table's own 72x48 inches, origin at
the centre, y down — no plotting library, no external asset, so a board opens in
a browser and diffs in git. `game_narrator.py` owns the replay and the prose;
everything a reader LOOKS at lives here."""
import json
M_IN = 0.0254                       # the state is metres, the record inches
KIND = ("HOLD", "ADVANCE", "RUSH", "CHARGE")
# `TerrainRules.TerrainType` terrain_rules.gd:24 — FOREST is the only difficult
# class, RUINS+FOREST give cover, DANGEROUS rolls on entry.
TERRAIN = {1: ("#c3a76b", "ruins"), 2: ("#6f9e63", "forest"),
           3: ("#9aa0a6", "container"), 4: ("#c9605a", "dangerous")}
SIDE = {0: "#777777", 1: "#2f6fd0", 2: "#c8442b"}
W_IN, H_IN, PX = 72.0, 48.0, 13.0
DEFAULT_R_M = 0.016                 # geom::edge_gap_in's per-model radius fallback


def edge_gap_in(a_pos, a_r, b_pos, b_r):
    # `geom::edge_gap_in` core/nml-core/src/geom.rs:113 — min base-edge gap in inches.
    return min((((pa[0] - pb[0]) ** 2 + (pa[2] - pb[2]) ** 2) ** 0.5
               - (a_r[i] if i < len(a_r) else DEFAULT_R_M) - (b_r[j] if j < len(b_r) else DEFAULT_R_M)
               for i, pa in enumerate(a_pos) for j, pb in enumerate(b_pos)), default=float("inf")) / M_IN


def crosses_forest(a, b, terrain, n=20, ttype=2):
    # Whether leg a->b (table inches) samples inside a piece of class `ttype`
    # (2 = forest, 4 = dangerous); this corpus's rotations are axis-aligned
    # (0/90/180/270), so a swapped half-extent test is exact.
    fs = [p for p in terrain if p[0] == ttype]
    return any(abs(a[0] + (b[0] - a[0]) * i / n - p[1]) <= (p[3] / 2 if p[5] in (0, 180) else p[4] / 2)
               and abs(a[1] + (b[1] - a[1]) * i / n - p[2]) <= (p[4] / 2 if p[5] in (0, 180) else p[3] / 2)
               for i in range(n + 1) for p in fs)


def rule_label(r):
    # An OPR rule blob prints as "Tough(3)"/"AP(1)": `label` is already that on
    # a unit rule and absent on a weapon's, which carries only `rating`.
    n = str(r.get("name", r.get("label", "?")))
    return "%s(%s)" % (n, r["rating"]) if r.get("rating") not in (None, "") else n


def unit_rules(u):
    # The sheet's rules PLUS what an upgrade ITEM grants: "Winged Breed" is where
    # Ambush and Flying enter an Alien Hives list, and a reader who looks only at
    # `rules` never sees them.
    out = [rule_label(r) for r in u.get("rules", [])]
    for it in u.get("items", []):
        out += ["%s[%s]" % (rule_label(c), it.get("name", "item")) for c in it.get("content", [])]
    return out


def army_table(lst):
    out = ["| # | unit | models | Q | D | pts | weapons | special rules | joins |",
           "|---|---|---|---|---|---|---|---|---|"]
    for i, u in enumerate(lst.get("units", [])):
        w = "; ".join('%s (%s", A%s%s)' % (x.get("label", x.get("name", "?")), x.get("range", 0),
                      x.get("attacks", 0), "".join(", " + rule_label(r)
                      for r in x.get("specialRules", []))) for x in u.get("weapons", []))
        out.append("| %d | %s | %s | %s+ | %s+ | %s | %s | %s | %s |"
                   % (i, u.get("name", "?"), u.get("size", 1), u.get("quality", "?"),
                      u.get("defense", "?"), u.get("cost", 0), w or "-",
                      ", ".join(unit_rules(u)) or "-", u.get("joinToUnit") or "-"))
    return out


def terrain_summary(pieces):
    n = {}
    for p in pieces:
        t = TERRAIN.get(int(p[0]), ("", "type%d" % p[0]))[1]
        n[t] = n.get(t, 0) + 1
    return ", ".join("%d %s" % (v, k) for k, v in sorted(n.items()))


def unit_info(lists):
    # The state's unit KEY is `list_to_profile`'s own "p<side>_<index>_<list id>"
    # (list_to_profile.py:1257), so the army sheet joins to the state exactly.
    out = {}
    for s, lst in lists.items():
        for i, u in enumerate(lst.get("units", [])):
            out["%s_%d_%s" % (s, i, u.get("id", i))] = (u.get("quality"), u.get("defense"),
                                                        ", ".join(unit_rules(u)) or "-")
    return out


def cand_text(c, nm):
    # The menu spans EVERY un-activated unit of the side, so a candidate that does
    # not name its actor reads as a duplicate of the one above it.
    t = "%s %s" % (nm.get(c["unit"], c["unit"]), KIND[int(c["kind"])]
                   if int(c["kind"]) < 4 else "KIND%d" % c["kind"])
    if c.get("dest"):
        t += " to (%.1f,%.1f)" % (c["dest"][0] / M_IN, c["dest"][2] / M_IN)
    for k in ("shoot", "charge"):
        if c.get(k):
            t += " %s %s" % (k, nm.get(c[k], c[k]))
    return t + (" patient" if c.get("patient") else "") + (" wave" if c.get("wave") else "")


def hits(rolls, kind):
    """`DiceRules.count_successes` dice_rules.gd:55-71, over one roll class."""
    return sum(sum(1 for f in r["faces"] if f >= 6 or (f > 1 and f >= r["target"]))
               for r in rolls if r["kind"] == kind and r["target"] > 0)


def dice_md(rec, acts, nm):
    out = ["# Dice trail — seed %d, dice seed %d" % (rec["seed"], rec["dice_seed"]), "",
           "Every roll the twin draws from the tray, in draw order; the recording's own",
           "`dice_tally` was %s." % json.dumps(rec["dice_tally"]), "",
           "| # | R | act | actor | kind | target | roll | n | need | faces | successes |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    j = 0
    for n, act in enumerate(acts, 1):
        row = act["row"]
        c = act["menu"][row["cands"]["best"]]
        for r in act["rep"]["rolls"]:
            j += 1
            out.append("| %d | %d | A%d | %s | %s | %s | %s | %d | %d+ | %s | %d |"
                       % (j, row["round"], n, nm.get(row["unit"], row["unit"]),
                          KIND[int(row["kind"])], nm.get(c.get("shoot") or c.get("charge") or "", "-"),
                          r["kind"], r["count"], r["target"], r["faces"], hits([r], r["kind"])))
    return out + ["", "%d rolls over %d activations; an activation that drew none is absent."
                  " Under `dice=table` the tray serves shooting, melee AND the end-of-move"
                  " dangerous-terrain test. MORALE is the class that never reaches it (selfplay.py"
                  ":1182-1183), so no Fearless or No-Retreat re-roll appears anywhere below."
                  % (j, len(acts))]


def _xy(x_in, z_in):
    return round((x_in + W_IN / 2.0) * PX, 1), round((z_in + H_IN / 2.0) * PX, 1)


def board_svg(pieces, obs, units, moves, title):
    """`obs` = [(x_in, z_in, owner)]; `units` = [(side, label, r_in, [(x, z)])];
    `moves` = [(side, (x0, z0), (x1, z1))], all in table inches."""
    w, h = W_IN * PX, H_IN * PX
    s = ['<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g" viewBox="0 0 %g %g"'
         ' font-family="sans-serif"><rect width="%g" height="%g" fill="#f5f2ec"/><defs>'
         '<marker id="h" markerWidth="7" markerHeight="7" refX="6" refY="2.5" orient="auto">'
         '<path d="M0,0 L6,2.5 L0,5 z" fill="#333"/></marker></defs>' % (w, h, w, h, w, h)]
    for p in pieces:
        cx, cy = _xy(p[1], p[2])
        col = TERRAIN.get(int(p[0]), ("#dddddd", "?"))[0]
        s.append('<rect x="%g" y="%g" width="%g" height="%g" fill="%s" fill-opacity=".5"'
                 ' stroke="%s" transform="rotate(%g %g %g)"/>'
                 % (cx - p[3] * PX / 2, cy - p[4] * PX / 2, p[3] * PX, p[4] * PX, col, col,
                    p[5], cx, cy))
    # The centre line and the two 12" `zone12` deployment edges.
    s += ['<line x1="%g" y1="0" x2="%g" y2="%g" stroke="#bbb" stroke-dasharray="4 4"/>'
          % (_xy(x, 0)[0], _xy(x, 0)[0], h) for x in (-12.0, 0.0, 12.0)]
    for x, z, o in obs:
        s.append('<circle cx="%g" cy="%g" r="9" fill="none" stroke="%s" stroke-width="3"/>'
                 % (_xy(x, z) + (SIDE[o],)))
    for side, a, b in moves:
        s.append('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="1.4"'
                 ' stroke-opacity=".85" marker-end="url(#h)"/>'
                 % (_xy(*a) + _xy(*b) + (SIDE[side],)))
    for side, label, r_in, pts in units:
        xy = [_xy(x, z) for x, z in pts]
        s += ['<circle cx="%g" cy="%g" r="%g" fill="%s" fill-opacity=".8" stroke="#222"'
              ' stroke-width=".5"/>' % (c[0], c[1], max(3.0, r_in * PX), SIDE[side]) for c in xy]
        s.append('<text x="%g" y="%g" font-size="10" fill="#111" stroke="#f5f2ec"'
                 ' stroke-width="2.5" paint-order="stroke" text-anchor="middle">%s</text>'
                 % (sum(c[0] for c in xy) / len(xy), sum(c[1] for c in xy) / len(xy) - 11, label))
    return "\n".join(s + ['<text x="6" y="16" font-size="14" fill="#111">%s</text></svg>' % title])


def boards(rec, acts, nm, moved, out_dir):
    for rnd in sorted({a["row"]["round"] for a in acts}):
        got = [a for a in acts if a["row"]["round"] == rnd]
        mv = [(a["row"]["side"], p, q) for a in got
              for p, q, d in moved(a, a["row"]["unit"]) if d > 0.25]
        units = [(u["player"], nm.get(k, k)[:14], max(u["radii"]) / M_IN,
                  [(p[0] / M_IN, p[2] / M_IN) for p in u["positions"]])
                 for k, u in got[-1]["after"]["units"].items() if u["alive"] > 0 and u["positions"]]
        obs = [(o["pos"][0] / M_IN, o["pos"][2] / M_IN, w) for o, w
               in zip(got[-1]["after"]["objectives"], rec["rounds_log"][rnd - 1]["owners"])]
        (out_dir / ("round_%d.svg" % rnd)).write_text(
            board_svg(rec["terrain"], obs, units, mv, "Round %d end — VP p1 %d p2 %d"
                      % (rnd, rec["rounds_log"][rnd - 1]["vp"][0],
                         rec["rounds_log"][rnd - 1]["vp"][1])), encoding="utf-8")
