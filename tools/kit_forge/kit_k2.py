# kit_k2.py - batch K2 = ruin tier faces, quoin, parapet stubs, ruin gables, deck edges, ladders (17).
# Same conventions as kit_build.py (Blender: X along, Y INTO the mass, -Y out, Z up; inches). A ruin tier is a PLATFORM,
# never a room: no open window, no open door (windows bricked up, the doorway closed by rubble), nothing above the parapet
# limit (0.7 in, inside the 0.4 in edge strip), ruin gables <= 0.3 thick and <= 2.6 high.
import math
from mathutils import Vector
import kit_table
from kit_build import Piece, house_shade, course, stone

CELL = 3.0
FACE_T = 0.4


def ruin_shade(damp=False, soot=0.0, moss=0.25):
    """Cool grey-brown ruin stone; damp + moss only on foot modules; soot (fire) as a value and a grime mask."""
    base = house_shade(damp=damp)
    def f(q, m):
        r, g, b, a = base(q, m)
        if m in ("ct_stone", "ct_stone_big", "ct_stone_fine"):
            k = soot * max(0.0, min(1.0, (q.z - 0.6) / 2.0))
            r, g, b = r * (0.92 - k), g * (0.92 - k), b * (0.95 - k * 0.9)
            a = min(1.0, a + moss * (1.0 - q.z / 3.0) + k)
        return (r, g, b, a)
    return f


def stone_face(p, mat, length, height, bands, holes=(), proud=3, pockets=1, putlogs=0, plinth=0, avoid_ends=0.35, pocket_d=0.07, grid_s=None,
               cluster=None):
    """A coursed face built in relief bands (course-aligned heights), cut round `holes` (x0, x1, z0, z1), with proud stones,
    lost-stone pockets and put-log holes on the stone grid of `mat` (course x stone); nothing within avoid_ends of the ends
    (the module tiles)."""
    r = p.rng
    C, S = course(mat), grid_s or stone(mat)
    NC, NS = int(round(height / C)), int(round(length / S))
    taken = set()
    pk = []
    for _ in range(pockets * 4):
        if len(pk) >= pockets:
            break
        if cluster:   # lost facing stones in one patch round (x, z)
            k = int(round(cluster[1] / C + r.uniform(-1.4, 1.4))); i = int(round(cluster[0] / S - 0.5 + r.uniform(-1.4, 1.4)))
            if not (1 <= k < NC - 1 and 1 <= i < NS - 1) or (k, i) in taken:
                continue
        else:
            k, i = r.randrange(3, NC - 1), r.randrange(1, NS - 1)
            if (k, i) in taken:
                continue   # (a pocket twice on one stone = coincident boxes = black in the K3 sheet)
        if i * S < avoid_ends or (i + 1) * S > length - avoid_ends:
            continue
        if any(h[0] - S < (i + 0.5) * S < h[1] + S and h[2] - C < (k + 0.5) * C < h[3] + C for h in holes):
            continue
        pk.append((k, i)); taken.add((k, i))
    z = 0.0
    for bi, bh in enumerate(bands):
        z0, z1 = z, z + bh
        if bi == len(bands) - 1:
            z1 = height - 0.01
        d = -0.04 if bi < plinth else -r.choice([0.0, 0.012, 0.024])
        t = 0.85 + r.random() * 0.2
        tint = (t, t * (0.98 + r.random() * 0.04), t * (0.96 + r.random() * 0.08))
        spans = [(0.0, length)]
        for h in holes:
            if z0 < h[3] - 1e-6 and z1 > h[2] + 1e-6:
                spans = [(a, b) for a, b in [(sp[0], min(sp[1], h[0])) for sp in spans] + [(max(sp[0], h[1]), sp[1]) for sp in spans] if b - a > 1e-3]
        for a, b in spans:
            cuts = [(a, b)]
            for (k, i) in pk:
                kz0, kz1 = k * C, (k + 1) * C
                gx0, gx1 = i * S, (i + 1) * S
                if z0 - 1e-6 <= kz0 and kz1 <= z1 + 1e-6 and a <= gx0 and gx1 <= b:
                    nc = []
                    for c0, c1 in cuts:
                        if c0 <= gx0 and gx1 <= c1:
                            nc += [(c0, gx0), (gx1, c1)]
                        else:
                            nc.append((c0, c1))
                    cuts = nc
                    # the lost stone: the band above / below it stays, its cell is a shallow pocket
                    p.box((gx0 + 0.004, pocket_d, kz0 + 0.004), (gx1 - 0.004, FACE_T - 0.01, kz1 - 0.004), mat, tint=(0.6, 0.58, 0.58), cull=False)
                    if kz0 > z0 + 1e-6:
                        p.box((gx0, d, z0), (gx1, FACE_T, kz0), mat, tint=tint)
                    if kz1 < z1 - 1e-6:
                        p.box((gx0, d, kz1), (gx1, FACE_T, z1), mat, tint=tint)
            for c0, c1 in cuts:
                if c1 - c0 > 1e-3:
                    p.box((c0, d, z0), (c1, FACE_T, z1), mat, tint=tint)
        z = z1
    for _ in range(proud):
        k, i = r.randrange(2 if plinth else 0, NC), r.randrange(0, NS)
        if (k, i) in taken or i * S < avoid_ends or (i + 1) * S > length - avoid_ends:
            continue
        if any(i * S - 0.05 < h[1] and (i + 2) * S + 0.05 > h[0] and k * C - 0.05 < h[3] and (k + 1) * C + 0.05 > h[2] for h in holes):
            continue   # (the whole stone, even a double one, keeps clear of an opening: the K3 slit check caught a centre-only test)
        taken.add((k, i))
        w = S * (2 if (r.random() < 0.3 and (k, i + 1) not in taken) else 1)
        if w > S:
            taken.add((k, i + 1))
        p.box((i * S + 0.015, -0.05, k * C + 0.015), (min(i * S + w, length - avoid_ends) - 0.015, 0.03, (k + 1) * C - 0.015), mat,
              tint=(0.95, 0.95, 0.98))
    return taken


def bands_for(height, plinth):
    """Relief bands on course lines (0.5 in): a 0.5 in plinth for foot modules, else four 0.75 in bands."""
    return [0.5, 1.0, 1.0, 0.5] if plinth else [1.0, 1.0, 1.0]


FACE_T_CULL = FACE_T


def ruin_face(name, seed, role="plain", variant="a"):
    p = Piece(name, seed, cull_back=FACE_T_CULL)
    p.cull_ends = (0.0, CELL)
    # (the top face stays, 0.01 in under the module top: no open notch, no z-fight with the generated top quad)
    foot = role in ("foot", "doorway")
    soot = {"a": 0.0, "b": 0.12, "c": 0.35}.get(variant, 0.0) if role == "plain" else 0.08
    p.shade = ruin_shade(damp=foot, soot=soot, moss=0.35 if foot else 0.15)
    r = p.rng
    holes = []
    if role == "window":
        holes = [(1.05, 1.95, 1.0, 2.0)]
    if role == "doorway":
        holes = [(1.0, 2.0, 0.0, 2.0)]
    bands = bands_for(CELL, 2 if foot else 0)
    if role == "window" or role == "doorway":   # bands on course lines that also meet the opening edges
        bands = [0.5, 0.5, 1.0, 1.0] if role == "doorway" else [0.5, 0.5, 1.0, 1.0]
    if role == "plain" and variant == "a":   # a blocked round arch: voussoirs proud 0.04, infill recessed 0.05
        holes = [(0.85, 2.15, 0.5, 2.0)]
        bands = [0.5, 0.5, 0.5, 0.5, 1.0]
    if role == "plain" and variant == "c":   # a patch of lost facing stones: the core shows 0.12 in deep
        stone_face(p, "ct_stone", CELL, CELL, bands, (), proud=2, pockets=7, plinth=0, pocket_d=0.12, cluster=(1.6, 1.8))
        bands = None
    if bands is not None:
      stone_face(p, "ct_stone", CELL, CELL, bands, holes, proud=3 if role != "plain" else 4,
               pockets=1 if role in ("plain", "foot") else 0, plinth=1 if foot else 0)
    if role == "plain" and variant == "a":
        x0, x1, z0, z1 = holes[0]
        cx, cz, ri, ro = 1.5, 1.35, 0.65, 0.92
        p.box((x0, 0.05, z0), (x1, FACE_T - 0.01, z1), "ct_stone", tint=(0.72, 0.7, 0.66), fill=True)   # the infill
        n = 7
        for k in range(n):   # the voussoirs of the blocked arch (half ring above the springing line)
            a0, a1 = math.pi * k / n, math.pi * (k + 1) / n
            pts = [(cx + ri * math.cos(a0), cz + ri * math.sin(a0)), (cx + ro * math.cos(a0), cz + ro * math.sin(a0)),
                   (cx + ro * math.cos(a1), cz + ro * math.sin(a1)), (cx + ri * math.cos(a1), cz + ri * math.sin(a1))]
            pts = [(u, min(v, CELL - 0.02)) for u, v in pts]
            p.poly([(u, -0.04, v) for u, v in pts] + [(u, 0.06, v) for u, v in pts], "ct_stone", tint=(1.1, 1.08, 1.02), fill=True)
        for xj in (x0, x1 - 0.25):   # the jambs up to the springing line
            p.box((xj, -0.03, 0.5), (xj + 0.25, 0.05, cz), "ct_stone", tint=(1.05, 1.04, 1.0), fill=True)
        p.openings = []
        return p
    if role == "plain" and variant == "b":   # a shallow buttress (0.2 proud, all of it in the high band) with a weathered top
        bx = 1.95
        p.box((bx, -0.2, 0.0), (bx + 0.6, 0.02, 2.2), "ct_stone", tint=(0.95, 0.95, 0.97))
        p.poly([(bx, -0.2, 2.2), (bx + 0.6, -0.2, 2.2), (bx + 0.6, 0.02, 2.2), (bx, 0.02, 2.2),
                (bx, -0.02, 2.55), (bx + 0.6, -0.02, 2.55), (bx + 0.6, 0.02, 2.55), (bx, 0.02, 2.55)], "ct_stone", tint=(1.0, 1.0, 1.0))
    if role == "window":   # BRICKED UP: lintel, sill, a recessed infill of smaller, paler stones (fill: it closes the opening)
        x0, x1, z0, z1 = holes[0]
        p.box((x0 - 0.12, -0.035, z1), (x1 + 0.12, 0.02, z1 + 0.5), "ct_stone", tint=(1.12, 1.1, 1.04))
        p.box((x0 - 0.06, -0.06, z0 - 0.1), (x1 + 0.06, 0.02, z0), "ct_stone", tint=(1.05, 1.05, 1.05))
        zz = z0
        k = 0
        while zz < z1 - 1e-6:
            hh = min(0.25, z1 - zz)   # (the infill: half-course stones, smaller than the wall's: reads as a later repair)
            off = 0.15 if k % 2 else 0.0
            p.box((x0, 0.07, zz), (x1, FACE_T - 0.01, zz + hh), "ct_stone", tint=(0.78 + 0.1 * (k % 2), 0.76, 0.72), fill=True)
            zz += hh; k += 1
        p.openings = [list(holes[0])]
    elif role == "doorway":   # DARK, CLOSED BY RUBBLE: jambs + lintel, a rubble heap filling the opening to near the head
        x0, x1, z0, z1 = holes[0]
        p.box((x0 - 0.15, -0.04, z1), (x1 + 0.15, 0.02, z1 + 0.5), "ct_stone", tint=(1.1, 1.08, 1.02))   # lintel (2 courses)
        p.flat([(x0, 0.35, 0.0), (x1, 0.35, 0.0), (x1, 0.35, z1), (x0, 0.35, z1)], "ct_glass_dark", fill=True)   # the dark behind
        for k in range(9):   # the rubble: blocks piled inside the reveal, the top row below the head (a dark gap stays)
            row = k // 3
            bw = (x1 - x0) / 3.0
            bx = x0 + (k % 3) * bw + r.uniform(-0.03, 0.03)
            bz = row * 0.5 + r.uniform(0.0, 0.05)
            hh = r.uniform(0.38, 0.5) - (0.12 if row == 2 else 0.0)
            yy = 0.06 + r.uniform(0.0, 0.08) + row * 0.04
            a = math.radians(r.uniform(-12, 12))
            cx, cz = bx + bw * 0.5, bz + hh * 0.5
            hw, hz = bw * 0.48, hh * 0.5
            rot = lambda dx, dz: (cx + dx * math.cos(a) - dz * math.sin(a), cz + dx * math.sin(a) + dz * math.cos(a))
            pts = [rot(-hw, -hz), rot(hw, -hz), rot(hw, hz), rot(-hw, hz)]
            p.poly([(u, yy, max(0.0, v)) for u, v in pts] + [(u, 0.34, max(0.0, v)) for u, v in pts], "ct_stone",
                   tint=(0.7 + r.random() * 0.2,) * 3, fill=True)
        p.openings = [list(holes[0])]
    else:
        p.openings = []
    return p


def ruin_quoin(name, seed):
    p = Piece(name, seed, cull_back=0.3)
    p.shade = ruin_shade(soot=0.05)
    r = p.rng
    C2 = course("ct_stone")
    # a backing core behind both faces: closes any gap where the two faces' modules meet the quoin (dark slits)
    p.flat([(0.02, 0.02, 0.0), (0.6, 0.02, 0.0), (0.6, 0.02, CELL - 0.01), (0.02, 0.02, CELL - 0.01)], "ct_stone", tint=(0.7, 0.7, 0.7))
    p.flat([(0.02, 0.02, 0.0), (0.02, 0.6, 0.0), (0.02, 0.6, CELL - 0.01), (0.02, 0.02, CELL - 0.01)], "ct_stone", tint=(0.7, 0.7, 0.7),
           normal=Vector((-1, 0, 0)))
    for k in range(int(round(CELL / C2))):
        z0, z1 = k * C2 + 0.01, (k + 1) * C2 - 0.01
        t = 1.0 + r.random() * 0.12
        ln = r.uniform(0.42, 0.5)
        if k % 2 == 0:
            fs = p.box((-0.05, -0.05, z0), (ln, 0.3, z1), "ct_stone", tint=(t, t, t * 0.97))
        else:
            fs = p.box((-0.05, -0.05, z0), (0.3, ln, z1), "ct_stone", tint=(t, t, t * 0.97))
        if k > 0:   # (the underside sits on the block below: dropped, tri cap)
            for f in fs:
                if f.normal.z < -0.99:
                    p.bm.faces.remove(f)
    p.openings = []
    return p


def parapet(name, seed, variant="a"):
    """Broken parapet stubs on a dropping top edge: <= 0.7 high, inside the 0.4 in strip (y 0..0.4), never proud."""
    p = Piece(name, seed)
    p.shade = ruin_shade(soot=0.1, moss=0.3)
    r = p.rng
    C = course("ct_stone")
    if variant == "a":     # two stubs with a gap
        runs = [(0.15, r.uniform(1.0, 1.3), 0.7), (r.uniform(1.7, 2.0), 2.85, 0.5)]
    elif variant == "b":   # one long stub, stepping down where it broke
        runs = [(0.1, 1.6, 0.7), (1.6, 2.3, 0.45), (2.3, 2.8, 0.25)]
    else:                  # c: a low rubble course with one block left standing
        b0 = 0.2 + stone("ct_stone") * r.randrange(1, 3)   # one block left standing, the low course either side (no overlap)
        runs = [(0.2, b0, 0.25), (b0, b0 + 0.6, 0.5), (b0 + 0.6, 2.8, 0.25)]
    for a, b, h in runs:
        x = a
        while x < b - 1e-3:   # blocks of one stone length, each with its own height (a ragged top), courses on C
            w = min(b - x, stone("ct_stone") * r.choice((1, 2)))
            hh = max(0.2, min(0.7, h - r.choice((0.0, 0.0, 0.15))))
            t = 0.85 + r.random() * 0.2
            p.box((x, 0.04, 0.0), (x + w, 0.38, hh), "ct_stone", tint=(t, t, t * 0.97))
            x += w
    p.openings = []
    return p


def ruin_gable(name, seed, span=3.0):
    """A ruin gable end on an end face: a jagged stepped triangle, <= 0.3 thick (y 0..0.3), peak <= 2.6, broken off on one
    side; nothing proud."""
    p = Piece(name, seed, cull_back=0.3)
    p.shade = ruin_shade(soot=0.3, moss=0.15)
    r = p.rng
    C = course("ct_stone")
    S = stone("ct_stone")
    NS = int(round(span / S))
    peak = 2.5 if span > 4 else 2.0
    broken_side = r.choice((0, 1))
    S = S * 0.5   # half-stone columns: a finer stepped outline
    NS = NS * 2
    for i in range(NS):
        cx = (i + 0.5) * S
        tri = peak * (1.0 - abs(cx - span * 0.5) / (span * 0.5))
        if (cx > span * 0.5) == bool(broken_side):
            tri *= r.uniform(0.45, 0.8)   # the broken half
        h = min(2.6, max(0.0, tri + r.uniform(-0.45, 0.25)))
        h = round(h / (C * 0.5)) * C * 0.5   # half-course steps, each column its own break
        if h < C * 0.5:
            continue
        t = 0.82 + r.random() * 0.2
        p.box((i * S, 0.0 + r.choice((0.0, 0.0, 0.015)), 0.0), ((i + 1) * S, 0.3, h), "ct_stone", tint=(t, t, t * 0.97))
    p.openings = []
    return p


def deck_edge(name, seed, variant="a"):
    """The edge of a timber deck: a fascia board under the top and joist ends <= 0.2 out; all below the deck top (y <= 0)."""
    p = Piece(name, seed, cull_back=0.3)
    p.shade = lambda q, m: (0.62, 0.58, 0.54, 0.45)
    r = p.rng
    p.box((0.0, -0.06, -0.3), (CELL, 0.3, -0.05), "ct_timber", grain=(1, 0, 0), tint=(0.85, 0.8, 0.75))   # the edge beam
    xs = [0.375 + 0.75 * k for k in range(4)]
    for k, x in enumerate(xs):   # joist ends
        if variant == "b" and k == 2:
            continue   # one rotted away
        out = 0.18 if variant == "a" else r.uniform(0.08, 0.18)
        p.box((x - 0.07, -out, -0.28), (x + 0.07, -0.06, -0.08), "ct_timber", grain=(0, 1, 0), tint=(0.75, 0.7, 0.65))
    # the board ends of the deck under the generated top quad's edge (top at -0.012: no z-fight with the quad)
    x = 0.0
    while x < CELL - 1e-3:
        w = min(CELL - x, 2 * course("ct_timber"))   # (two boards per box: the tri cap)
        dz = 0.0 if variant == "a" else r.choice((0.0, 0.0, -0.03))
        p.box((x + 0.01, -0.04 + r.uniform(0, 0.03), -0.06 + dz), (x + w - 0.01, 0.02, -0.012 + dz), "ct_timber", grain=(0, 1, 0),
              tint=(0.9, 0.85, 0.8))
        x += w
    p.openings = []
    return p


def ladder(name, seed, top=False):
    """A pale new-timber ladder segment, 1.0 in wide, centred on x = 0, against the wall face (y -0.06 .. -0.22), 3 in;
    the top segment's stiles stand 0.5 in above the top edge (a hand-hold, outside the deck: still over the lower cell)."""
    p = Piece(name, seed)
    p.shade = lambda q, m: (1.25, 1.18, 1.05, 0.1)   # the lightest material on a wall
    h = CELL + (0.5 if top else 0.0)
    for sx in (-0.42, 0.42):
        p.box((sx - 0.05, -0.22, 0.0), (sx + 0.05, -0.12, h), "ct_timber", grain=(0, 0, 1))
    for k in range(6):
        z = 0.25 + k * 0.5
        p.box((-0.37, -0.2, z - 0.03), (0.37, -0.15, z + 0.03), "ct_timber", grain=(1, 0, 0), tint=(1.05, 1.0, 0.95))
    p.openings = []
    return p


def builders():
    B = []
    B.append(("dr_ruin_face_foot_a", lambda: ruin_face("dr_ruin_face_foot_a", 201, "foot", "a")))
    B.append(("dr_ruin_face_foot_b", lambda: ruin_face("dr_ruin_face_foot_b", 202, "foot", "b")))
    for k, v in enumerate("abc"):
        B.append((f"dr_ruin_face_plain_{v}", lambda v=v, k=k: ruin_face(f"dr_ruin_face_plain_{v}", 203 + k, "plain", v)))
    B.append(("dr_ruin_face_window", lambda: ruin_face("dr_ruin_face_window", 206, "window")))
    B.append(("dr_ruin_face_doorway", lambda: ruin_face("dr_ruin_face_doorway", 207, "doorway")))
    B.append(("dr_ruin_quoin", lambda: ruin_quoin("dr_ruin_quoin", 208)))
    for k, v in enumerate("abc"):
        B.append((f"dr_parapet_stub_{v}", lambda v=v, k=k: parapet(f"dr_parapet_stub_{v}", 210 + k, v)))
    for sp in (3, 6):
        B.append((f"dr_ruin_gable_s{sp}", lambda sp=sp: ruin_gable(f"dr_ruin_gable_s{sp}", 220 + sp, float(sp))))
    for v in "ab":
        B.append((f"dr_deck_edge_{v}", lambda v=v: deck_edge(f"dr_deck_edge_{v}", 230 + ord(v), v)))
    B.append(("dr_ladder_3in", lambda: ladder("dr_ladder_3in", 240, False)))
    B.append(("dr_ladder_top", lambda: ladder("dr_ladder_top", 241, True)))
    return B
