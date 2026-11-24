# kit_k3.py - batch K3 = town wall + tall towers (17), all in ct_stone_big (tile 3.6, course 0.6 in;
# geometry on a 0.6 x 0.75 in stone grid, 4 stones per 3 in face). Honesty: the town wall's batter stays INSIDE the cell (the
# foot's face steps back 0.2 in over its 3 in), the breach face is RAGGED (stones missing <= 0.2 in deep, never a bitten top),
# merlon runs <= 0.7 high inside the 0.4 in strip with no regular rhythm, tower tops: a pitched slate cap or a
# burnt-out top of bare rafters, INSIDE the 12 in top band (apex exactly at 12 in, never above), never a flat platform.
import math
from mathutils import Vector
from kit_build import Piece, course, stone
from kit_k2 import ruin_shade, stone_face

CELL = 3.0
T = 0.4
MAT = "ct_stone_big"
GS = 0.75   # the geometry stone length on the big-stone faces (4 per 3 in face)


def wall_face(name, seed, role="plain", variant="a", tower=False):
    p = Piece(name, seed, cull_back=T)
    p.cull_ends = (0.0, CELL)
    r = p.rng
    C = course(MAT)   # 0.6
    foot = role == "foot"
    p.shade = ruin_shade(damp=foot, soot=0.1 if variant == "b" else 0.03, moss=0.3 if foot else 0.12)
    holes = []
    if role == "slit":
        holes = [(1.35, 1.65, 0.6, 2.4)]
    if foot:   # the batter: five courses, each stepped back 0.04 in (0 at the foot, 0.2 at 3 in): inside the cell, never proud
        for k in range(5):
            z0, z1 = k * C, (k + 1) * C - (0.01 if k == 4 else 0.0)
            y0 = 0.04 * k + r.choice((0.0, 0.0, 0.008))
            x = 0.0
            while x < CELL - 1e-3:   # stones of one course, a few with their own small set-back (rough big blocks)
                w = min(CELL - x, GS * r.choice((1, 2, 2)))
                p.box((x, y0 + r.choice((0.0, 0.006, 0.012)), z0), (x + w, T, z1), MAT, tint=(0.9 + 0.15 * r.random(),) * 3)
                x += w
        p.openings = []
        return p
    if role == "ragged":   # beside a breach: many stones missing (<= 0.2 deep), full height kept
        stone_face(p, MAT, CELL, CELL, [1.2, 1.2, 0.6], (), proud=1, pockets=7, pocket_d=0.18, grid_s=GS, cluster=(1.6, 1.4))
        p.openings = []
        return p
    bands = [1.2, 1.2, 0.6] if role != "slit" else [0.6, 0.6, 1.2, 0.6]
    stone_face(p, MAT, CELL, CELL, bands, holes, proud=3 if variant == "a" else 5, pockets=1 if variant == "a" else 2, grid_s=GS)
    if role == "slit":   # an arrow slit: splayed dark recess, sill and head stones; nothing crosses it
        x0, x1, z0, z1 = holes[0]
        p.flat([(x0, 0.3, z0), (x1, 0.3, z0), (x1, 0.3, z1), (x0, 0.3, z1)], "ct_glass_dark", fill=True)
        p.box((x0 - 0.3, -0.03, z1), (x1 + 0.3, 0.02, z1 + 0.3), MAT, tint=(1.08, 1.06, 1.0))
        p.box((x0 - 0.2, -0.05, z0 - 0.12), (x1 + 0.2, 0.02, z0), MAT, tint=(1.05, 1.05, 1.02))
        p.openings = [list(holes[0])]
        return p
    if role == "corbel":   # the string course on corbels under a 6 / 9 in walk, above CLEAR (<= 0.35 out), weathered slope on top
        zc = CELL - 0.55
        for k in range(4):
            xc = 0.375 + 0.75 * k
            p.poly([(xc - 0.13, 0.0, zc - 0.45), (xc + 0.13, 0.0, zc - 0.45), (xc + 0.13, 0.02, zc - 0.45), (xc - 0.13, 0.02, zc - 0.45),
                    (xc - 0.13, -0.25, zc), (xc + 0.13, -0.25, zc), (xc + 0.13, 0.02, zc), (xc - 0.13, 0.02, zc)], MAT, tint=(1.0, 1.0, 1.0))
        p.poly([(0.0, -0.3, zc), (CELL, -0.3, zc), (CELL, 0.02, zc), (0.0, 0.02, zc),
                (0.0, -0.3, zc + 0.3), (CELL, -0.3, zc + 0.3), (CELL, 0.02, zc + 0.42), (0.0, 0.02, zc + 0.42)], MAT, tint=(1.08, 1.06, 1.0))
    p.openings = []
    return p


def big_quoin(name, seed, height=CELL):
    p = Piece(name, seed, cull_back=0.36)
    p.shade = ruin_shade(soot=0.03)
    r = p.rng
    C = course(MAT)
    p.flat([(0.02, 0.02, 0.0), (0.7, 0.02, 0.0), (0.7, 0.02, height - 0.01), (0.02, 0.02, height - 0.01)], MAT, tint=(0.7, 0.7, 0.7))
    p.flat([(0.02, 0.02, 0.0), (0.02, 0.7, 0.0), (0.02, 0.7, height - 0.01), (0.02, 0.02, height - 0.01)], MAT, tint=(0.7, 0.7, 0.7),
           normal=Vector((-1, 0, 0)))
    for k in range(int(round(height / C))):
        z0, z1 = k * C + 0.01, (k + 1) * C - 0.01
        t = 1.02 + r.random() * 0.12
        ln = r.uniform(0.55, 0.62)
        fs = p.box((-0.05, -0.05, z0), (ln, 0.36, z1) if k % 2 == 0 else (0.36, ln, z1), MAT, tint=(t, t, t * 0.97))
        if k > 0:
            for f in fs:
                if f.normal.z < -0.99:
                    p.bm.faces.remove(f)
    p.openings = []
    return p


def merlon_run(name, seed, variant="a"):
    """Battlements of one 3 in edge: a low breastwork (0.3) with merlons up to 0.7, inside the 0.4 strip (y 0.03..0.38),
    widths and gaps NOT regular (variant a: two wide + one narrow; b: one long + one short; broken: stumps and a fallen gap)."""
    p = Piece(name, seed)
    p.shade = ruin_shade(soot=0.05, moss=0.35)
    r = p.rng
    if variant == "a":
        merl = [(0.1, 0.95), (1.4, 2.05), (2.5, 2.9)]
    elif variant == "b":
        merl = [(0.25, 1.45), (2.1, 2.7)]
    else:
        merl = [(0.3, 0.8), (2.2, 2.75)]
    base_h = 0.3 if variant != "broken" else 0.2
    x = 0.0
    gap = (1.0, 1.7) if variant == "broken" else None
    while x < CELL - 1e-3:   # the breastwork (gone in the broken gap)
        w = min(CELL - x, 0.75)
        if not (gap and gap[0] <= x + w * 0.5 <= gap[1]):
            p.box((x + 0.005, 0.03, 0.0), (x + w - 0.005, 0.38, base_h - (r.uniform(0, 0.08) if variant == "broken" else 0.0)), MAT,
                  tint=(0.95 + 0.1 * r.random(),) * 3)
        x += w
    for a, b in merl:
        h = 0.7 if variant != "broken" else r.uniform(0.4, 0.55)
        h -= r.choice((0.0, 0.0, 0.06))
        p.box((a, 0.04, base_h), (b, 0.37, h), MAT, tint=(1.0 + 0.1 * r.random(),) * 3)
    p.openings = []
    return p


def tower_cap(name, seed, burnt=False):
    """The top of a 2 x 2 cell tall tower (6 x 6 in), INSIDE the top band: a ragged coping ring on the wall head (0.4 in, its
    stones at 11.85-12.0 in, some lower) and a hipped cap inside it from eaves at 10.6 in to the apex at exactly 12.0 in
    (pitch ~28 deg); burnt: bare charred rafters over a dark void and a few slates left. Never a flat deck, never above 12 in."""
    p = Piece(name, seed)
    r = p.rng
    S = 6.0
    p.shade = (lambda q, m: (0.4, 0.38, 0.36, 0.7) if m == "ct_timber" else (0.55, 0.55, 0.57, 0.4)) if burnt else \
        (lambda q, m: (0.62, 0.62, 0.65, 0.45) if m == "ct_roof" else (0.85, 0.85, 0.88, 0.35))
    # the coping ring (stones of 0.75 along each side, heights 11.8-12.0 local -0.2..0)
    for side in range(4):
        for k in range(6):
            t0, t1 = k * 1.0, (k + 1) * 1.0
            h = -r.choice((0.0, 0.0, 0.05, 0.12))
            if side == 0:
                lo, hi = (t0, 0.0, -0.2), (t1, 0.4, h)
            elif side == 1:
                lo, hi = (S - 0.4, t0, -0.2), (S, t1, h)
            elif side == 2:
                lo, hi = (t0, S - 0.4, -0.2), (t1, S, h)
            else:
                lo, hi = (0.0, t0, -0.2), (0.4, t1, h)
            if side in (1, 3) and (k == 0 or k == 5):
                continue   # (the corners belong to sides 0 / 2)
            fs = p.box((lo[0] + 0.005, lo[1] + 0.005, lo[2]), (hi[0] - 0.005, hi[1] - 0.005, hi[2]), MAT, tint=(1.0 + 0.1 * r.random(),) * 3)
            for f in fs:   # (undersides sit on the wall head)
                if f.normal.z < -0.99:
                    p.bm.faces.remove(f)
    c = Vector((S / 2, S / 2, 0.0))
    e = 0.4   # eaves line inset (inside the ring)
    ez = -1.4
    corners = [Vector((e, e, ez)), Vector((S - e, e, ez)), Vector((S - e, S - e, ez)), Vector((e, S - e, ez))]
    apex = Vector((S / 2, S / 2, 0.0))
    if not burnt:
        n_c = 4
        for side in range(4):
            a, b = corners[side], corners[(side + 1) % 4]
            mid = (a + b) * 0.5
            nrm = (mid - c); nrm.z = 0; nrm.normalize()
            up_n = Vector((nrm.x * math.sin(math.radians(28)), nrm.y * math.sin(math.radians(28)), math.cos(math.radians(28))))
            for k in range(n_c):   # courses of slabs, each split in 2 groups, lifted lower edges (stepped rows)
                f0, f1 = k / n_c, min(1.0, (k + 1) / n_c + 0.06)
                a0, b0 = a.lerp(apex, f0), b.lerp(apex, f0)
                a1, b1 = a.lerp(apex, f1), b.lerp(apex, f1)
                ng = 2 if k < 2 else 1
                for g in range(ng):
                    u0, u1 = g / ng, (g + 1) / ng
                    q = [a0.lerp(b0, u0), a0.lerp(b0, u1), a1.lerp(b1, u1), a1.lerp(b1, u0)]
                    if (q[2] - q[3]).length < 0.02 and (q[0] - q[1]).length < 0.02:
                        continue
                    lift = 0.05 if k < n_c - 1 else 0.0
                    top = [v + up_n * (0.05 + (lift if i < 2 else 0.0)) for i, v in enumerate(q)]
                    top = [Vector((v.x, v.y, min(v.z, 0.0))) for v in top]
                    tt = 0.85 + 0.25 * r.random()
                    p.poly([tuple(v) for v in q] + [tuple(v) for v in top], "ct_roof", tint=(tt, tt, tt), cull=False)
        p.box((S / 2 - 0.12, S / 2 - 0.12, -0.25), (S / 2 + 0.12, S / 2 + 0.12, 0.0), "ct_roof", tint=(0.6, 0.6, 0.62))   # the cap stone
    else:
        # the dark void inside the walls, the burnt hip and common rafters (charred), a few slabs left on one side
        p.flat([(e, e, ez - 0.3), (S - e, e, ez - 0.3), (S - e, S - e, ez - 0.3), (e, S - e, ez - 0.3)], "ct_glass_dark", normal=Vector((0, 0, 1)))
        for side in range(4):
            if side == 2 and r.random() < 0.7:
                continue   # one hip rafter has fallen
            a = corners[side]
            p.beam(tuple(a), tuple(apex - (apex - a).normalized() * 0.45), 0.12, 0.1, "ct_timber", out=Vector((0, 0, 1)), tint=(0.5, 0.45, 0.4))
        for side in range(4):
            a, b = corners[side], corners[(side + 1) % 4]
            for k in (1, 2, 3):
                if r.random() < 0.35:
                    continue   # burnt through
                st = a.lerp(b, k / 4)
                en = st.lerp(apex, r.uniform(0.45, 0.85))   # snapped short
                p.beam(tuple(st), tuple(en), 0.08, 0.08, "ct_timber", out=Vector((0, 0, 1)), tint=(0.45, 0.4, 0.36))
        a, b = corners[0], corners[1]
        for k in range(2):   # a few slabs still hanging on near the eaves of one side
            q = [a.lerp(b, 0.2 + 0.3 * k), a.lerp(b, 0.45 + 0.3 * k)]
            q += [q[1].lerp(apex, 0.3), q[0].lerp(apex, 0.3)]
            top = [v + Vector((0, -0.03, 0.05)) for v in q]
            p.poly([tuple(v) for v in q] + [tuple(v) for v in top], "ct_roof", tint=(0.8, 0.8, 0.8), cull=False)
    p.openings = []
    return p


def slate_cap(name, seed):
    """The capped tower: this module IS the whole top band (local y -3..0 = 9..12 in): the four upper walls to the
    eaves at 10.55 in (coursed big stone, quoins, two dark slits), and a hipped slate cap from the eaves (0.25 in overhang) to the
    apex at exactly 12.0 in, pitch 26 deg. The tower planner places face bands 0-2 only under it."""
    p = Piece(name, seed)
    r = p.rng
    S, C = 6.0, course(MAT)
    p.shade = lambda q, m: (0.62, 0.62, 0.65, 0.45) if m == "ct_roof" else (0.85, 0.85, 0.88, 0.3)
    ez = -1.45
    bands = [(-3.0, -2.4), (-2.4, -1.8), (-1.8, ez)]
    for (z0, z1) in bands:   # the four upper walls: one box per side and course band, each at its own small depth
        d = r.choice((0.0, 0.012, 0.024))
        for lo, hi in (((0.0, d, z0), (S, 0.4, z1)), ((S - 0.4, 0.4, z0), (S - d, S - 0.4, z1)),
                       ((0.0, S - 0.4, z0), (S, S - d, z1)), ((d, 0.4, z0), (0.4, S - 0.4, z1))):
            fs = p.box(lo, hi, MAT, tint=(0.9 + 0.15 * r.random(),) * 3)
            for f in fs:
                if f.normal.z < -0.99 and z0 > -2.99:
                    p.bm.faces.remove(f)
    for (x, y) in ((0.0, 0.0), (S, 0.0), (S, S), (0.0, S)):   # quoin blocks at the corners, alternating
        for k, (z0, z1) in enumerate(bands):
            sx = 0.55 if (k % 2 == 0) else 0.3
            sy = 0.3 if (k % 2 == 0) else 0.55
            ax = x - 0.04 if x == 0.0 else x - sx
            ay = y - 0.04 if y == 0.0 else y - sy
            p.box((ax, ay, z0 + 0.01), (ax + sx + 0.04, ay + sy + 0.04, z1 - 0.01), MAT, tint=(1.08, 1.06, 1.02))
    for side in (0, 2):   # two slits (dark, recessed)
        xs = 2.85 if side == 0 else 3.15
        y = -0.002 if side == 0 else S + 0.002
        p.flat([(xs - 0.12, y, -2.85), (xs + 0.12, y, -2.85), (xs + 0.12, y, -1.95), (xs - 0.12, y, -1.95)], "ct_glass_dark",
               normal=Vector((0, -1 if side == 0 else 1, 0)))
    ov = 0.25
    c = Vector((S / 2, S / 2, 0.0))
    corners = [Vector((-ov, -ov, ez - 0.12)), Vector((S + ov, -ov, ez - 0.12)), Vector((S + ov, S + ov, ez - 0.12)), Vector((-ov, S + ov, ez - 0.12))]
    apex = Vector((S / 2, S / 2, -0.06))
    pitch = math.atan2(-0.06 - (ez - 0.12), S / 2 + ov)
    n_c = 4
    for side in range(4):
        a, b = corners[side], corners[(side + 1) % 4]
        mid = (a + b) * 0.5
        nrm = mid - c; nrm.z = 0; nrm.normalize()
        up_n = Vector((nrm.x * math.sin(pitch), nrm.y * math.sin(pitch), math.cos(pitch)))
        for k in range(n_c):   # slab courses, stepped lower edges; groups split on the lower courses
            f0, f1 = k / n_c, min(1.0, (k + 1) / n_c + 0.05)
            a0, b0 = a.lerp(apex, f0), b.lerp(apex, f0)
            a1, b1 = a.lerp(apex, f1), b.lerp(apex, f1)
            ng = 2 if k < 2 else 1
            for g in range(ng):
                u0, u1 = g / ng, (g + 1) / ng
                q = [a0.lerp(b0, u0), a0.lerp(b0, u1), a1.lerp(b1, u1), a1.lerp(b1, u0)]
                lift = 0.04 + 0.03 * r.random()
                top = [v + up_n * (0.05 + (lift if i < 2 else 0.0)) for i, v in enumerate(q)]
                top = [Vector((v.x, v.y, min(v.z, 0.0))) for v in top]
                tt = 0.85 + 0.25 * r.random()
                p.poly([tuple(v) for v in q] + [tuple(v) for v in top], "ct_roof", tint=(tt, tt, tt), cull=False)
    p.box((S / 2 - 0.1, S / 2 - 0.1, -0.2), (S / 2 + 0.1, S / 2 + 0.1, 0.0), "ct_roof", tint=(0.6, 0.6, 0.62))   # the cap stone, top = 12.0
    p.openings = []
    return p


def builders():
    B = [("dr_twall_foot", lambda: wall_face("dr_twall_foot", 301, "foot")),
         ("dr_twall_face_a", lambda: wall_face("dr_twall_face_a", 302, "plain", "a")),
         ("dr_twall_face_b", lambda: wall_face("dr_twall_face_b", 303, "plain", "b")),
         ("dr_twall_slit", lambda: wall_face("dr_twall_slit", 304, "slit")),
         ("dr_twall_corbel", lambda: wall_face("dr_twall_corbel", 305, "corbel")),
         ("dr_twall_ragged", lambda: wall_face("dr_twall_ragged", 306, "ragged")),
         ("dr_twall_quoin", lambda: big_quoin("dr_twall_quoin", 307)),
         ("dr_merlon_run_a", lambda: merlon_run("dr_merlon_run_a", 311, "a")),
         ("dr_merlon_run_b", lambda: merlon_run("dr_merlon_run_b", 312, "b")),
         ("dr_merlon_run_broken", lambda: merlon_run("dr_merlon_run_broken", 313, "broken")),
         ("dr_tower_foot", lambda: wall_face("dr_tower_foot", 321, "foot", tower=True)),
         ("dr_tower_face_a", lambda: wall_face("dr_tower_face_a", 322, "plain", "a", tower=True)),
         ("dr_tower_face_b", lambda: wall_face("dr_tower_face_b", 323, "plain", "b", tower=True)),
         ("dr_tower_slit", lambda: wall_face("dr_tower_slit", 324, "slit", tower=True)),
         ("dr_tower_quoin", lambda: big_quoin("dr_tower_quoin", 325)),
         ("dr_tower_cap_slate", lambda: slate_cap("dr_tower_cap_slate", 331)),
         ("dr_tower_cap_burnt", lambda: tower_cap("dr_tower_cap_burnt", 332, True))]
    return B
