# kit_k4.py - batch K4 = lamps, landmarks, plots (9). Same conventions as kit_build.py (Blender: X
# along, Y INTO the mass, -Y out, Z up; inches). Honesty: the lamp post is <= 0.2 in thick over its WHOLE height (foot and
# lantern included: the thickness exception), both lanterns carry their glass centre at 2.55 in (the game's light), the bracket has
# nothing below CLEAR (2.0 in), the fountain stays inside 5.6 in of its 6 x 6 in solid footprint and under 2.5 in, the plinth
# carries a broken column (no figure), the pool kerb is FLAT (<= 0.08 in), the plot pieces stay inside their 3 x 3 in cell.
# Shared helpers for the prop batches live here: faces / hexa / block / lathe / mound / stick / blade and the dirt shades.
import math
from mathutils import Vector, Matrix
import kit_table
from kit_build import Piece

FLAT = kit_table.FLAT
LANTERN_IN = 2.55   # the height of the game's lantern light (BoardgenTownDressing._add_lights)
TAU = 2.0 * math.pi


# ------------------------------------------------------------------ geometry helpers (free polygons on a Piece)
def M(x=0.0, y=0.0, z=0.0, yaw=0.0, pitch=0.0, roll=0.0):
    return (Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "Y")
            @ Matrix.Rotation(math.radians(roll), 4, "X"))


def faces(p, loops, mat, grain=None, tint=(1, 1, 1), inside=None, up=False, fill=False, xf=None):
    """Free polygons (lists of points). inside = a point the normals must look away from; up = normals must look up;
    neither = the winding as given. xf = a matrix applied to the points (and to inside / grain)."""
    fs, pts = [], []
    for loop in loops:
        vs = [tuple(xf @ Vector(v)) if xf is not None else tuple(v) for v in loop]
        pts += vs
        fs.append(p.bm.faces.new([p.bm.verts.new(v) for v in vs]))
    ins = (xf @ Vector(inside)) if (xf is not None and inside is not None) else (Vector(inside) if inside is not None else None)
    for f in fs:
        f.normal_update()
        if up:
            if f.normal.z < 0:
                f.normal_flip()
        elif ins is not None and f.normal.dot(f.calc_center_median() - ins) < 0:
            f.normal_flip()
    p._record(pts, mat, fill)
    g = (xf.to_3x3() @ Vector(grain)) if (xf is not None and grain is not None) else grain
    p._finish(fs, mat, g, tint, None)
    return fs


def hexa(p, vs, mat, grain=None, tint=(1, 1, 1), bottom=False, top=True, fill=False, xf=None, skip=()):
    """A solid from 8 corners (v0..v3 bottom ring, v4..v7 top ring, same order). Sides: 0 = v0-v1, 1 = v1-v2, 2 = v2-v3, 3 = v3-v0."""
    c = Vector((0, 0, 0))
    for v in vs:
        c += Vector(v)
    c /= 8.0
    quads = ([(4, 5, 6, 7)] if top else []) + [q for i, q in enumerate(((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))) if i not in skip]
    if bottom:
        quads.append((0, 3, 2, 1))
    return faces(p, [[vs[i] for i in q] for q in quads], mat, grain, tint, inside=tuple(c), fill=fill, xf=xf)


def block(p, lo, hi, mat, xf=None, bevel=0.0, jit=0.0, grain=None, tint=(1, 1, 1), bottom=False, top=True, fill=False, skip=(), zj=0.0):
    """A box lo..hi; bevel = the top ring set in (a chamfered / worn stone, a slab); jit = corner jitter (broken, irregular);
    zj = jitter of the top corners' height (downwards only)."""
    r = p.rng
    x0, y0, z0 = lo; x1, y1, z1 = hi
    j = (lambda: r.uniform(-jit, jit)) if jit else (lambda: 0.0)
    d = (lambda: r.uniform(0.0, zj)) if zj else (lambda: 0.0)
    b = bevel
    vs = [(x0 + j(), y0 + j(), z0), (x1 + j(), y0 + j(), z0), (x1 + j(), y1 + j(), z0), (x0 + j(), y1 + j(), z0),
          (x0 + b + j(), y0 + b + j(), z1 - d()), (x1 - b + j(), y0 + b + j(), z1 - d()), (x1 - b + j(), y1 - b + j(), z1 - d()),
          (x0 + b + j(), y1 - b + j(), z1 - d())]
    return hexa(p, vs, mat, grain, tint, bottom, top, fill, xf, skip)


def ngon(c, r, z, n, ph=0.0):
    return [(c[0] + r * math.cos(ph + TAU * k / n), c[1] + r * math.sin(ph + TAU * k / n), z) for k in range(n)]


def lathe(p, c, prof, n, mat, xf=None, ph=0.0, grain=(0, 0, 1), tint=(1, 1, 1), cap=False, wob=None):
    """A turned shape: prof = [(r, z) | (r, z, mat, tint)] traced from the bottom outside, up, then inward / down inside
    (the winding gives outward normals for that order). Band i joins prof[i] and prof[i + 1] and takes prof[i + 1]'s
    mat / tint when given. cap = an n-gon closing the last ring, looking up. wob(k, i) = a radius factor per corner."""
    rings = []
    for i, e in enumerate(prof):
        rr = e[0]
        rings.append([(c[0] + rr * (wob(k, i) if wob else 1.0) * math.cos(ph + TAU * k / n),
                       c[1] + rr * (wob(k, i) if wob else 1.0) * math.sin(ph + TAU * k / n), e[1]) for k in range(n)])
    out = []
    for i in range(len(prof) - 1):
        a, b = rings[i], rings[i + 1]
        e = prof[i + 1]
        m, t = (e[2], e[3]) if len(e) > 3 else (mat, tint)
        loops = []
        for k in range(n):
            k1 = (k + 1) % n
            if prof[i + 1][0] < 1e-6:
                loops.append([a[k], a[k1], b[k]])
            elif prof[i][0] < 1e-6:
                loops.append([a[k], b[k1], b[k]])
            else:
                loops.append([a[k], a[k1], b[k1], b[k]])
        out += faces(p, loops, m, grain, t, xf=xf)
    if cap:
        out += faces(p, [rings[-1]], mat if len(prof[-1]) < 4 else prof[-1][2], grain, tint if len(prof[-1]) < 4 else prof[-1][3], xf=xf)
    return out


def mound(p, c, rx, ry, h, n, mat, tint=(1, 1, 1), inner=0.5, yaw=0.0, z0=0.0, rough=0.25, xf=None, grain=None):
    """A low heap that FEATHERS to the ground: the outer ring lies at z0 (jittered radius = a ragged outline), an inner ring
    and an off-centre top carry the height. inner = 0: a plain fan (n triangles); else 3 n triangles."""
    r = p.rng
    cy, sy = math.cos(yaw), math.sin(yaw)
    def pt(a, k, z):
        x, y = rx * k * math.cos(a), ry * k * math.sin(a)
        return (c[0] + x * cy - y * sy, c[1] + x * sy + y * cy, z)
    ph = r.uniform(0, TAU)
    ang = [ph + TAU * (k + r.uniform(-0.25, 0.25)) / n for k in range(n)]
    outer = [pt(a, 1.0 + r.uniform(-rough, rough), z0) for a in ang]
    top = pt(r.uniform(0, TAU), 0.12, z0 + h)
    loops = []
    if inner > 0:
        ring = [pt(a + r.uniform(-0.15, 0.15), inner * (1.0 + r.uniform(-0.2, 0.2)), z0 + h * r.uniform(0.62, 0.95)) for a in ang]
        for k in range(n):
            k1 = (k + 1) % n
            loops.append([outer[k], outer[k1], ring[k1]])
            loops.append([outer[k], ring[k1], ring[k]])
            loops.append([ring[k], ring[k1], top])
    else:
        loops = [[outer[k], outer[(k + 1) % n], top] for k in range(n)]
    return faces(p, loops, mat, grain, tint, up=True, xf=xf)


def stick(p, a, b, ra, rb, mat, tint=(1, 1, 1), grain=None):
    """A three-sided tapered twig / stalk from a to b (rb = 0: a point). Closed all round: visible from every side."""
    a = Vector(a); b = Vector(b)
    d = (b - a).normalized()
    u = d.orthogonal().normalized(); v = d.cross(u)
    A = [a + (u * math.cos(t) + v * math.sin(t)) * ra for t in (0.3, 0.3 + TAU / 3, 0.3 + 2 * TAU / 3)]
    if rb <= 1e-5:
        loops = [[A[k], A[(k + 1) % 3], b] for k in range(3)]
    else:
        B = [b + (u * math.cos(t) + v * math.sin(t)) * rb for t in (0.3, 0.3 + TAU / 3, 0.3 + 2 * TAU / 3)]
        loops = [[A[k], A[(k + 1) % 3], B[(k + 1) % 3], B[k]] for k in range(3)]
    return faces(p, loops, mat, grain, tint, inside=tuple((a + b) * 0.5))


def blade(p, base, yaw, lean, L, w, bend=0.0, tint=(1, 1, 1), mat="ct_matte", hmax=None):
    """A grass blade / stalk as a closed three-sided sliver (flat back, a ridge on its upper side) leaning `lean` rad from the
    vertical towards `yaw`; bend > 0 adds a second segment that leans further (a curved blade). 3 or 9 triangles."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    dv = lambda l: Vector((cy * math.sin(l), sy * math.sin(l), math.cos(l)))
    nv = lambda l: Vector((-cy * math.cos(l), -sy * math.cos(l), math.sin(l)))
    side = Vector((-sy, cy, 0.0)) * (w * 0.5)
    P0 = Vector(base)
    if hmax is not None:   # never above the module's honest height
        top = P0.z + (L * math.cos(lean) if bend <= 0 else L * 0.55 * math.cos(lean) + L * 0.45 * math.cos(min(1.5, lean + bend)))
        if top > hmax:
            L *= hmax / top
    A0, B0, C0 = P0 - side, P0 + side, P0 + nv(lean) * (w * 0.4)
    if bend <= 0:
        tip = P0 + dv(lean) * L
        return faces(p, [[A0, B0, tip], [B0, C0, tip], [C0, A0, tip]], mat, None, tint, inside=tuple((P0 + tip) * 0.5))
    P1 = P0 + dv(lean) * (L * 0.55)
    l1 = min(1.5, lean + bend)
    A1, B1, C1 = P1 - side * 0.7, P1 + side * 0.7, P1 + nv((lean + l1) * 0.5) * (w * 0.3)
    tip = P1 + dv(l1) * (L * 0.45)
    fs = faces(p, [[A0, B0, B1, A1], [B0, C0, C1, B1], [C0, A0, A1, C1]], mat, None, tint, inside=tuple((P0 + P1) * 0.5))
    fs += faces(p, [[A1, B1, tip], [B1, C1, tip], [C1, A1, tip]], mat, None, tint, inside=tuple((P1 + tip) * 0.5))
    return fs


def leaf(p, c, yaw, ln, wd, z_mid, z_tip, tint, mat="ct_matte", z0=0.004):
    """A broad leaf lying low: a rhombus folded along a raised midrib (4 triangles), every edge near the ground."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    u = Vector((cy, sy, 0)); s = Vector((-sy, cy, 0))
    A = Vector((c[0], c[1], c[2] if len(c) > 2 else z0))
    Mi = A + u * (ln * 0.5) + Vector((0, 0, z_mid))
    T = A + u * ln + Vector((0, 0, z_tip))
    Lf = A + u * (ln * 0.45) + s * (wd * 0.5) + Vector((0, 0, z_mid * 0.45))
    R = A + u * (ln * 0.45) - s * (wd * 0.5) + Vector((0, 0, z_mid * 0.45))
    return faces(p, [[A, R, Mi], [A, Mi, Lf], [Mi, R, T], [Lf, Mi, T]], mat, None, tint, up=True)


# ------------------------------------------------------------------ shades (vertex colour): damp feet, dirt blotches, grime
def nz(x, y, z=0.0, f=1.0):
    """A cheap smooth blotch value in 0..1 (no pure noise: clustered, low frequency)."""
    return 0.5 + 0.25 * math.sin(x * 2.1 * f + 1.3) * math.sin(y * 1.7 * f + 0.4) + 0.25 * math.sin((x + y) * 3.3 * f + z * 2.0 * f)


def grim_shade(base, foot=0.25, foot_k=0.55, blotch=0.25, grime=0.55):
    """Gloomy props: base = {material: (r, g, b)} multipliers; a dark damp foot (x foot_k at z = 0, gone at `foot`),
    low-frequency dirt blotches, a grime mask in alpha (strongest at the foot)."""
    def f(q, m):
        r, g, b = base.get(m, (1.0, 1.0, 1.0))
        d = (foot_k + (1.0 - foot_k) * min(1.0, max(0.0, q.z / foot))) if foot > 0 else 1.0
        n = 1.0 - blotch * nz(q.x, q.y, q.z, 2.3)
        k = d * n
        return (r * k, g * k, b * k * 0.97, min(1.0, grime + (1.0 - d) * 0.8 + (1.0 - n) * 0.5))
    return f


def iron_shade(q, m):
    if m == "ct_iron":   # rust in blotches, soot towards the lantern
        n = nz(q.x * 9, q.y * 9, q.z * 2.2, 1.0)
        return (1.0 + 0.85 * n, 1.0 + 0.1 * n, 1.0 - 0.3 * n, 0.5 + 0.4 * n)
    if m in ("ct_stone", "ct_stone_big"):
        k = 0.55 + 0.45 * min(1.0, max(0.0, q.z / 0.2))
        return (0.6 * k, 0.63 * k, 0.7 * k, 0.8)
    return (1.0, 1.0, 1.0, 0.3)


def lantern(p, cx, cy, z0, z1, gb, gt, roof=0.095):
    """A four-pane lantern: glass from z0 to z1 (its centre = the light), widening upwards (gb -> gt half widths), iron
    corner bars, a floor plate and a pyramid roof. Returns the apex height."""
    block(p, (cx - gb - 0.012, cy - gb - 0.012, z0 - 0.025), (cx + gb + 0.012, cy + gb + 0.012, z0), "ct_iron", bottom=True)
    b = [(cx - gb, cy - gb, z0), (cx + gb, cy - gb, z0), (cx + gb, cy + gb, z0), (cx - gb, cy + gb, z0)]
    t = [(cx - gt, cy - gt, z1), (cx + gt, cy - gt, z1), (cx + gt, cy + gt, z1), (cx - gt, cy + gt, z1)]
    faces(p, [[b[k], b[(k + 1) % 4], t[(k + 1) % 4], t[k]] for k in range(4)], "ct_glass_lit", inside=(cx, cy, (z0 + z1) * 0.5), fill=True)
    s = 0.012
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        bx, by, tx, ty = cx + sx * gb, cy + sy * gb, cx + sx * gt, cy + sy * gt
        hexa(p, [(bx - s, by - s, z0), (bx + s, by - s, z0), (bx + s, by + s, z0), (bx - s, by + s, z0),
                 (tx - s, ty - s, z1), (tx + s, ty - s, z1), (tx + s, ty + s, z1), (tx - s, ty + s, z1)], "ct_iron", top=False)
    e = gt + 0.015
    block(p, (cx - e, cy - e, z1), (cx + e, cy + e, z1 + 0.02), "ct_iron", bottom=True)
    block(p, (cx - e, cy - e, z1 + 0.02), (cx + e, cy + e, z1 + 0.02 + roof), "ct_iron", bevel=e - 0.02)
    return z1 + 0.02 + roof


# ------------------------------------------------------------------ lamps
def lamp_post(name, seed):
    """A street lamp at a cell corner: <= 0.2 in thick over its whole height (stone foot 0.2, shaft 0.09, lantern 0.196),
    glass 2.40-2.70 in (centre 2.55), top 2.89. The one thickness exception."""
    p = Piece(name, seed)
    p.shade = iron_shade
    block(p, (-0.1, -0.1, 0.0), (0.1, 0.1, 0.1), "ct_stone", jit=0.0, top=False)
    block(p, (-0.1, -0.1, 0.1), (0.1, 0.1, 0.16), "ct_stone", bevel=0.035)
    block(p, (-0.06, -0.06, 0.16), (0.06, 0.06, 0.21), "ct_iron")
    lathe(p, (0, 0), [(0.045, 0.21), (0.04, 1.1), (0.052, 1.12), (0.052, 1.17), (0.036, 1.19), (0.03, 2.27), (0.066, 2.375)], 6, "ct_iron")
    top = lantern(p, 0.0, 0.0, LANTERN_IN - 0.15, LANTERN_IN + 0.15, 0.058, 0.083)
    block(p, (-0.012, -0.012, top - 0.01), (0.012, 0.012, 2.89), "ct_iron")
    p.openings = []
    return p


def lamp_bracket(name, seed):
    """A wall lantern on an iron bracket, origin on the wall plane at 2.6 in: wall plate, arm, brace, a hanging lantern with
    its glass centre at local -0.05 (= 2.55 in). Nothing below local -0.45 (2.15 in: above CLEAR), <= 0.31 in out (R2)."""
    p = Piece(name, seed)
    p.shade = iron_shade
    block(p, (-0.05, -0.022, -0.45), (0.05, 0.0, 0.195), "ct_iron", bottom=True, skip=(2,))   # the wall plate (its back is the wall)
    block(p, (-0.018, -0.30, 0.155), (0.018, -0.02, 0.195), "ct_iron", bottom=True)             # the arm
    hexa(p, [(-0.015, -0.022, -0.40), (0.015, -0.022, -0.40), (0.015, -0.022, -0.355), (-0.015, -0.022, -0.355),
             (-0.015, -0.255, 0.155), (0.015, -0.255, 0.155), (0.015, -0.215, 0.155), (-0.015, -0.215, 0.155)], "ct_iron", top=False)   # the brace
    cy = -0.21
    c0 = LANTERN_IN - 2.6   # the glass centre, local
    apex = lantern(p, 0.0, cy, c0 - 0.12, c0 + 0.12, 0.05, 0.072, roof=0.06)
    block(p, (-0.01, cy - 0.01, apex - 0.012), (0.01, cy + 0.01, 0.156), "ct_iron", top=False)   # the link under the arm
    block(p, (-0.012, cy - 0.012, c0 - 0.19), (0.012, cy + 0.012, c0 - 0.145), "ct_iron", top=False, bottom=True)   # the drop finial
    p.openings = []
    return p


# ------------------------------------------------------------------ landmarks
def fountain(name, seed):
    """The town fountain, dry-rotten: two worn octagonal steps (across 5.45 in: inside 5.6), an octagonal basin wall with a
    coping (one bay broken down), black stagnant water with scum, a turned pier and bowl, a snapped spout. Top 2.49 in
    (the landmark's collider is 2.5). No figure, no mask, no lettering. The 6 x 6 footprint's corners stay free (junk)."""
    p = Piece(name, seed)
    r = p.rng
    N, ph = 8, math.pi / 8   # flats to the axes

    def shade(q, m):
        rad = math.hypot(q.x, q.y)
        if m == "ct_stone":
            k = 0.58 + 0.42 * min(1.0, max(0.0, q.z / 0.6))                     # the damp foot
            inside = rad < 1.99 and q.z < 1.02
            if inside:
                k *= 0.5 + 0.5 * min(1.0, max(0.0, (q.z - 0.78) / 0.24))        # the black tide mark inside the basin
            if rad < 0.7 and q.z > 0.7:
                k *= 0.62 + 0.38 * min(1.0, abs(q.z - 1.95) / 0.5)              # drip stains down the pier from the bowl
            n = 1.0 - 0.22 * nz(q.x, q.y, q.z, 1.6)
            moss = 0.85 * max(0.0, 1.0 - q.z / 0.7) + (0.5 if inside else 0.0)
            return (0.6 * k * n, 0.64 * k * n, 0.66 * k * n, min(1.0, 0.35 + moss))
        if m == "ct_matte":
            return (1.0, 1.0, 1.0, 0.7)
        return (1.0, 1.0, 1.0, 0.3)
    p.shade = shade

    def seg(R0, R1, z0, z1, k, bevel=0.0, tint=(1, 1, 1), dz=(0.0, 0.0), dr=0.0):
        g = 0.006
        a0 = ph + TAU * k / N + g / R1; a1 = ph + TAU * (k + 1) / N - g / R1
        pt = lambda R, a, z: (R * math.cos(a), R * math.sin(a), z)
        hexa(p, [pt(R1 + dr, a0, z0), pt(R1 + dr, a1, z0), pt(R0, a1, z0), pt(R0, a0, z0),
                 pt(R1 + dr - bevel, a0, z1 + dz[0]), pt(R1 + dr - bevel, a1, z1 + dz[1]), pt(R0 + bevel, a1, z1 + dz[1]), pt(R0 + bevel, a0, z1 + dz[0])],
             "ct_stone", tint=tint)

    broken = 5
    for k in range(N):
        t = lambda: (0.9 + 0.16 * r.random(),) * 3
        seg(2.5, 2.95, 0.0, 0.17, k, bevel=0.02, tint=t(), dz=((-0.05, -0.015) if k == 2 else (-r.uniform(0, 0.012),) * 2))   # step 1 (k 2: sunk)
        seg(2.2, 2.62, 0.17, 0.34, k, bevel=0.02, tint=t(), dz=(-r.uniform(0, 0.012),) * 2, dr=-r.uniform(0, 0.02))
        if k == broken:   # the broken bay: a ragged stump of the wall, no coping
            seg(1.95, 2.3, 0.34, 0.88, k, tint=(0.85, 0.85, 0.85), dz=(-0.06, 0.09))   # (stays above the water line: no way to see under the water)
            continue
        seg(1.95, 2.3, 0.34, 1.0, k, tint=t(), dr=-r.uniform(0, 0.015))
        seg(1.9, 2.38, 1.0, 1.13, k, bevel=0.03, tint=(1.04, 1.03, 1.0), dz=(-r.uniform(0, 0.015),) * 2)
    # the fallen stones of the broken bay (on the steps and in the water, all inside the footprint)
    am = ph + TAU * (broken + 0.5) / N
    for d, s, zz, yw in ((2.42, 0.2, 0.34, 20), (2.52, 0.16, 0.34, 65), (2.5, 0.17, 0.34, -30), (2.2, 0.17, 0.34 + 0.2, 40), (1.6, 0.2, 0.74, 15), (1.35, 0.15, 0.74, 70)):
        a = am + r.uniform(-0.28, 0.28)
        block(p, (-s, -s * 0.7, 0.0), (s, s * 0.7, s * 0.9), "ct_stone", xf=M(d * math.cos(a), d * math.sin(a), zz, yaw=yw + math.degrees(a), roll=r.uniform(-14, 14)),
              jit=0.02, tint=(0.82, 0.82, 0.82))
    # stagnant water (black, glossy) and scum mats on it
    faces(p, [ngon((0, 0), 1.965, 0.78, N, ph)], "ct_glass_dark", up=True)
    for cx, cy, rx in ((0.9, -0.7, 0.55), (-1.1, 0.5, 0.45), (0.2, 1.35, 0.4), (-0.6, -1.25, 0.3)):
        mound(p, (cx, cy), rx, rx * 0.55, 0.01, 9, "ct_matte", tint=(0.04, 0.046, 0.03), inner=0.6, yaw=r.uniform(0, 3), z0=0.782, rough=0.45)
    # the pier, the bowl (dry sludge inside) and the snapped spout
    dark = (0.5, 0.5, 0.47)
    lathe(p, (0, 0), [(0.5, 0.6), (0.5, 1.35), (0.62, 1.42), (0.62, 1.5), (0.36, 1.58), (0.3, 1.9), (0.46, 2.0), (0.96, 2.19), (0.99, 2.27),
                      (0.86, 2.27), (0.6, 2.15, "ct_stone", dark), (0.16, 2.11, "ct_stone", dark), (0.13, 2.4), (0.0, 2.43)], 10, "ct_stone", ph=0.2)
    block(p, (-0.02, -0.1, 2.38), (0.09, 0.02, 2.49), "ct_stone", bevel=0.03, jit=0.012, tint=(0.8, 0.8, 0.8))   # the jagged stub of the spout
    p.openings = []
    p.entry = {"len_in": 5.45, "height_in": 2.5}
    p.shadow = [[[-2.2, 0.0, -2.2], [2.2, 1.1, 2.2]], [[-0.75, 1.1, -0.75], [0.75, 2.25, 0.75]]]
    return p


def statue_plinth(name, seed):
    """The statue cell: a stepped plinth with a moulded cap and, where a statue stood, the stump of a broken column
    (ragged break at 2.15-2.47 in) and its fragments on the ledges. No figure. Inside 2.76 in of the 3 x 3 in solid cell."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade({"ct_stone": (0.6, 0.63, 0.68)}, foot=0.6, foot_k=0.55, blotch=0.25, grime=0.45)
    block(p, (-1.38, -1.38, 0.0), (1.38, 1.38, 0.2), "ct_stone", bevel=0.02, jit=0.012)
    block(p, (-1.12, -1.12, 0.2), (1.12, 1.12, 0.4), "ct_stone", bevel=0.02, jit=0.012, tint=(0.94, 0.94, 0.94))
    block(p, (-0.8, -0.8, 0.4), (0.8, 0.8, 1.22), "ct_stone", jit=0.008)                                   # the die
    block(p, (-0.92, -0.92, 1.22), (0.92, 0.92, 1.32), "ct_stone", bottom=True, tint=(1.05, 1.04, 1.0))     # the cap moulding
    block(p, (-0.86, -0.86, 1.32), (0.86, 0.86, 1.4), "ct_stone", bevel=0.05, tint=(1.0, 1.0, 0.98))
    n = 10
    lathe(p, (0, 0), [(0.5, 1.4), (0.57, 1.44), (0.57, 1.5), (0.45, 1.56), (0.42, 2.05)], n, "ct_stone", ph=0.1, tint=(1.05, 1.04, 1.02))
    base = ngon((0, 0), 0.42, 2.05, n, 0.1)   # the break: a slanted, ragged plane
    brk = [(x, y, min(2.47, 2.28 + 0.2 * (x * 0.8 + y * 0.6) / 0.42 + r.uniform(-0.05, 0.05))) for x, y, _ in base]
    faces(p, [[base[k], base[(k + 1) % n], brk[(k + 1) % n], brk[k]] for k in range(n)], "ct_stone", tint=(1.05, 1.04, 1.02))
    cz = sum(v[2] for v in brk) / n - 0.06
    faces(p, [[brk[k], brk[(k + 1) % n], (0.03, -0.02, cz)] for k in range(n)], "ct_stone", tint=(1.25, 1.22, 1.16), up=True)   # the fresh break
    # fragments on the ledges and against the die (inside the footprint)
    for (x, y, zz, s, yw) in ((0.98, -0.5, 0.4, 0.13, 25), (0.96, 0.62, 0.4, 0.1, 70), (-0.3, -0.99, 0.4, 0.12, 10), (-1.24, 0.9, 0.2, 0.11, 40),
                              (0.66, 0.6, 1.4, 0.1, 30), (-0.62, -0.58, 1.4, 0.08, 55), (-1.0, -0.2, 0.4, 0.09, 80)):
        block(p, (-s, -s * 0.75, 0.0), (s, s * 0.75, s * 1.1), "ct_stone", xf=M(x, y, zz, yaw=yw, roll=r.uniform(-12, 12)), jit=0.02, bevel=0.01,
              tint=(1.1, 1.08, 1.04))
    # a drum of the column fallen across the base step's corner (lying, inside the footprint)
    lathe(p, (0, 0), [(0.0, -0.2), (0.3, -0.2), (0.3, 0.2), (0.0, 0.2)], 8, "ct_stone", xf=M(-0.82, 0.86, 0.4 + 0.3, yaw=35, pitch=90), tint=(1.05, 1.04, 1.02))
    p.openings = []
    p.entry = {"len_in": 2.8}
    p.shadow = [[[-1.3, 0.0, -1.3], [1.3, 0.4, 1.3]], [[-0.8, 0.4, -0.8], [0.8, 1.4, 0.8]], [[-0.38, 1.4, -0.38], [0.38, 2.2, 0.38]]]
    return p


def pool_kerb(name, seed):
    """Flat kerb stones along one 3 in edge of a pool cell, inside the cell (z -0.3..-0.02), <= 0.075 in high: worn, bevelled,
    one cracked, one sunk; damp and green towards the water. The run tiles (the end stones share one profile)."""
    p = Piece(name, seed)
    r = p.rng
    def shade(q, m):
        k = 0.62 + 0.38 * min(1.0, max(0.0, (0.3 - q.y) / 0.3))     # darker (wet) towards the water
        n = 1.0 - 0.2 * nz(q.x, q.y, 0.0, 2.6)
        return (0.6 * k * n, 0.64 * k * n, 0.66 * k * n, min(1.0, 0.5 + 0.5 * (q.y / 0.3)))
    p.shade = shade
    ws = [0.52, 0.44, 0.31, 0.3, 0.5, 0.46, 0.47]   # (stones 3 + 4 = one cracked stone)
    x = 0.0
    for i, w in enumerate(ws):
        end = i in (0, len(ws) - 1)
        h = 0.066 if end else 0.058 + r.uniform(0.0, 0.016)
        y0 = 0.02 if end else 0.015 + r.uniform(0, 0.02)
        y1 = 0.28 if end else 0.3 - r.uniform(0, 0.035)
        a = x + (0.0 if i == 0 else 0.008)
        b = x + w - (0.0 if i == len(ws) - 1 else 0.008)
        t = 0.88 + 0.2 * r.random()
        if i == 4:   # sunk and tipped towards the water
            hexa(p, [(a, y0, 0), (b, y0, 0), (b, y1, 0), (a, y1, 0), (a + 0.03, y0 + 0.03, 0.05), (b - 0.03, y0 + 0.03, 0.058),
                     (b - 0.03, y1 - 0.03, 0.022), (a + 0.03, y1 - 0.03, 0.016)], "ct_stone", tint=(t * 0.85,) * 3)
        else:
            block(p, (a, y0, 0.0), (b, y1, h), "ct_stone", bevel=0.03, tint=(t, t, t), zj=0.0 if end else 0.01)
        x += w
    p.openings = []
    p.entry = {"tags": ["flat", "class_edge", "tiles"]}
    p.shadow = []
    return p


# ------------------------------------------------------------------ plots (a 3 x 3 in garden-plot cell: x 0..3, y 0..3 INTO the cell)
def plot_shade(q, m):
    if m == "ct_timber":   # grey weathered fence wood, dark and green at the foot
        k = 0.5 + 0.5 * min(1.0, max(0.0, q.z / 0.35))
        n = 1.0 - 0.2 * nz(q.x, q.y, q.z, 3.0)
        return (0.72 * k * n, 0.7 * k * n, 0.68 * k * n, min(1.0, 0.45 + (1.0 - k)))
    t = min(1.0, max(0.0, q.z / 0.24))       # weeds: dark wet base, dry pale tips
    k = 0.42 + 0.58 * t
    return (k * (1.0 + 0.3 * t), k * (1.0 + 0.08 * t), k * (1.0 - 0.25 * t), 0.4 + 0.4 * (1.0 - t))


LIVE = ((0.105, 0.125, 0.06), (0.12, 0.13, 0.065), (0.09, 0.115, 0.06))    # dull olive (never a fresh green)
DEAD = ((0.2, 0.17, 0.095), (0.17, 0.14, 0.08), (0.23, 0.2, 0.12))         # dry straw / brown
DOCK = ((0.075, 0.1, 0.05), (0.1, 0.105, 0.05), (0.13, 0.09, 0.05))


def _spots(r, n, lo, hi, dmin, edge_bias=0.0, avoid=()):
    """Grown, not scattered: n centres in [lo, hi]^2, at least dmin apart, drawn towards the cell edges when edge_bias > 0."""
    out = []
    for _ in range(n * 60):
        if len(out) >= n:
            break
        x, y = r.uniform(lo, hi), r.uniform(lo, hi)
        d_edge = min(x - lo, hi - x, y - lo, hi - y) / ((hi - lo) * 0.5)
        if r.random() < edge_bias * d_edge:
            continue
        if any(math.hypot(x - a, y - b) < dmin for a, b in out) or any(math.hypot(x - a, y - b) < d for a, b, d in avoid):
            continue
        out.append((x, y))
    return out


def tuft(p, c, n, hmax, dead=0.3, w=0.05, lmin=0.2, lmax=0.42, spread=0.07):
    """A clump of grass: n blades from a tight root, the outer ones leaning out and curved, a third of them short; a share dead."""
    r = p.rng
    mound(p, c, spread * 1.5, spread * 1.2, 0.025, 5, "ct_matte", tint=(0.06, 0.05, 0.035), inner=0, yaw=r.uniform(0, 3))   # the root mat
    for k in range(n):
        yaw = TAU * (k + r.uniform(-0.35, 0.35)) / n
        out = r.random()
        lean = math.radians(6 + 46 * out)
        L = r.uniform(lmin, lmax) * (0.6 if r.random() < 0.3 else 1.0)
        base = (c[0] + math.cos(yaw) * spread * out * 0.6, c[1] + math.sin(yaw) * spread * out * 0.6, 0.0)
        col = r.choice(DEAD) if r.random() < dead else r.choice(LIVE)
        blade(p, base, yaw, lean, L, w * r.uniform(0.75, 1.2), bend=(math.radians(r.uniform(22, 48)) if out > 0.55 else 0.0), tint=col, hmax=hmax)


def plot_weeds(name, seed, variant="a"):
    """Weeds over a garden-plot cell. a = rank grass clumps and dock rosettes; b = nettle / thistle stands and dead seed
    stalks. Clumps are GROWN (drawn to the cell's edges and to each other, a bare trodden patch left), each on a dark root
    mat, dark at the base and dry at the tips, a share dead. Inside the cell (>= 0.1 in from its outline), <= 0.4 in high."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = plot_shade
    H = 0.39
    bare = (r.uniform(1.1, 1.9), r.uniform(1.1, 1.9), 0.55)
    if variant == "a":
        for c in _spots(r, 7, 0.45, 2.55, 0.5, 0.7, [bare]):
            tuft(p, c, r.choice((6, 7, 7, 8)), H, dead=0.3)
        for c in _spots(r, 3, 0.5, 2.5, 0.8, 0.3, [bare]):   # dock: broad low leaves in a rosette, the outer ones brown
            for k in range(5):
                yaw = TAU * (k + r.uniform(-0.3, 0.3)) / 5
                leaf(p, c, yaw, r.uniform(0.26, 0.38), r.uniform(0.13, 0.18), r.uniform(0.05, 0.1), r.uniform(0.015, 0.05), r.choice(DOCK))
    else:
        for c in _spots(r, 9, 0.5, 2.5, 0.42, 0.6, [bare]):   # a stand of nettles: stiff stalks, leaf pairs up the stalk
            yaw = r.uniform(0, TAU); lean = math.radians(r.uniform(3, 14)); L = r.uniform(0.28, 0.4)
            col = r.choice(DEAD) if r.random() < 0.35 else r.choice(LIVE)
            blade(p, (c[0], c[1], 0.0), yaw, lean, L, 0.04, bend=math.radians(r.uniform(8, 20)), tint=col, hmax=H)
            for k in range(4):
                zz = L * (0.3 + 0.17 * k) * math.cos(lean)
                ly = yaw + 1.57 * k + r.uniform(-0.3, 0.3)
                ox, oy = math.sin(lean) * math.cos(yaw) * zz, math.sin(lean) * math.sin(yaw) * zz
                leaf(p, (c[0] + ox, c[1] + oy, zz), ly, r.uniform(0.13, 0.19), r.uniform(0.07, 0.1), 0.012, -r.uniform(0.02, 0.05), col)
            mound(p, c, 0.08, 0.07, 0.02, 5, "ct_matte", tint=(0.06, 0.05, 0.035), inner=0)
        for c in _spots(r, 4, 0.5, 2.5, 0.6, 0.5, [bare]):    # dead seed stalks in loose sprays
            for k in range(4):
                yaw = r.uniform(0, TAU)
                blade(p, (c[0] + r.uniform(-0.05, 0.05), c[1] + r.uniform(-0.05, 0.05), 0.0), yaw, math.radians(r.uniform(4, 30)), r.uniform(0.25, 0.4),
                      0.02, tint=r.choice(DEAD), hmax=H)
        for c in _spots(r, 2, 0.5, 2.5, 0.9, 0.6, [bare]):
            tuft(p, c, 5, H, dead=0.5, lmax=0.3)
    p.openings = []
    p.shadow = []
    return p


def fence_run(name, seed):
    """A paling fence along the front edge of a plot cell, 0.05-0.2 in INSIDE the cell: four posts out of true, two rails
    (the upper one snapped and hanging at one end), pointed pales with gaps, snapped tops, one hanging by a nail, one
    fallen into the plot. <= 0.97 in high."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = plot_shade
    yF = 0.125
    posts = [0.22, 1.12, 1.98, 2.78]
    for x in posts:
        h = r.uniform(0.84, 0.97); lx, ly = r.uniform(-0.035, 0.035), r.uniform(-0.015, 0.03)
        s = 0.055
        hexa(p, [(x - s, yF, 0), (x + s, yF, 0), (x + s, yF + 2 * s, 0), (x - s, yF + 2 * s, 0),
                 (x - s + lx + 0.012, yF + ly + 0.012, h - r.uniform(0, 0.05)), (x + s + lx - 0.012, yF + ly + 0.012, h - r.uniform(0, 0.05)),
                 (x + s + lx - 0.012, yF + 2 * s + ly - 0.012, h), (x - s + lx + 0.012, yF + 2 * s + ly - 0.012, h - r.uniform(0, 0.03))],
             "ct_timber", grain=(0, 0, 1), tint=(0.78, 0.76, 0.74))

    def rail(xa, za, xb, zb, t=(0.85, 0.83, 0.8)):
        hh = 0.035
        hexa(p, [(xa, yF - 0.035, za - hh), (xa, yF, za - hh), (xa, yF, za + hh), (xa, yF - 0.035, za + hh),
                 (xb, yF - 0.035, zb - hh), (xb, yF, zb - hh), (xb, yF, zb + hh), (xb, yF - 0.035, zb + hh)], "ct_timber", grain=(1, 0, 0), tint=t, bottom=True)
    rail(0.08, 0.3, 1.5, 0.27); rail(1.5, 0.27, 2.92, 0.31)
    rail(0.08, 0.68, 1.12, 0.66); rail(1.12, 0.66, 2.02, 0.64)
    rail(2.02, 0.6, 2.6, 0.07, t=(0.7, 0.68, 0.66))   # the snapped upper rail hangs to the ground

    def pale(x, w, h, snapped=False, lean=0.0, z0=0.03):
        y0, y1 = yF - 0.07, yF - 0.036
        if snapped:
            top = [(x + lean, y0, h - r.uniform(0, 0.09)), (x + w + lean, y0, h - r.uniform(0, 0.09)), (x + w + lean, y1, h), (x + lean, y1, h - r.uniform(0, 0.06))]
        else:
            top = [(x + w * 0.3 + lean, y0, h), (x + w * 0.7 + lean, y0, h), (x + w * 0.7 + lean, y1, h), (x + w * 0.3 + lean, y1, h)]
            # the pointed head sits on a shoulder: one body box below it
            sh = h - 0.09
            hexa(p, [(x, y0, z0), (x + w, y0, z0), (x + w, y1, z0), (x, y1, z0),
                     (x + lean * 0.9, y0, sh), (x + w + lean * 0.9, y0, sh), (x + w + lean * 0.9, y1, sh), (x + lean * 0.9, y1, sh)],
                 "ct_timber", grain=(0, 0, 1), tint=(tt,) * 3, top=False)
            hexa(p, [(x + lean * 0.9, y0, sh), (x + w + lean * 0.9, y0, sh), (x + w + lean * 0.9, y1, sh), (x + lean * 0.9, y1, sh)] + top,
                 "ct_timber", grain=(0, 0, 1), tint=(tt,) * 3)
            return
        hexa(p, [(x, y0, z0), (x + w, y0, z0), (x + w, y1, z0), (x, y1, z0)] + top, "ct_timber", grain=(0, 0, 1), tint=(tt,) * 3)
    x = 0.1
    while x < 1.95:
        w = r.uniform(0.1, 0.135)
        tt = 0.72 + 0.25 * r.random()
        if r.random() < 0.18:
            x += w + 0.03
            continue   # a missing pale
        if r.random() < 0.25:
            pale(x, w, r.uniform(0.42, 0.62), snapped=True)
        else:
            pale(x, w, r.uniform(0.78, 0.93), lean=r.uniform(-0.012, 0.012))
        x += w + r.uniform(0.02, 0.045)
    tt = 0.7
    pale(2.2, 0.12, 0.74, lean=0.16)      # hanging by one nail on the lower rail
    pale(2.62, 0.115, 0.55, snapped=True)
    block(p, (-0.4, -0.06, 0.0), (0.4, 0.06, 0.035), "ct_timber", xf=M(2.35, 0.52, 0.0, yaw=-24), grain=(1, 0, 0), tint=(0.66, 0.64, 0.6), bevel=0.008)   # fallen into the plot
    p.openings = []
    return p


def deadbush(name, seed):
    """A dead shrub in a plot cell: six bare stems from one root, forking twice into twigs (three-sided, closed), a few
    broken twigs on the ground. Grey-brown, dark at the root. <= 1.45 in high, inside the cell."""
    p = Piece(name, seed)
    r = p.rng
    def shade(q, m):
        k = 0.6 + 0.55 * min(1.0, max(0.0, q.z / 1.1))
        return (k, k * 0.97, k * 0.94, 0.5)
    p.shade = shade
    c = Vector((1.35, 1.65, 0.0))
    col = (0.14, 0.12, 0.1)

    def grow(a, d, L, rad, depth):
        b = a + d * L
        if depth == 2:
            stick(p, a, b, rad, 0.0, "ct_matte", tint=col)
            return
        stick(p, a, b, rad, rad * 0.62, "ct_matte", tint=col)
        for k in range(2 if depth == 0 else r.choice((2, 2, 3))):
            ax = Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-0.3, 0.3))).normalized()
            nd = (Matrix.Rotation(math.radians(r.uniform(20, 46)), 3, ax) @ d).normalized()
            nd.z = max(nd.z, -0.05 if depth == 1 else 0.2)
            grow(b, nd.normalized(), L * r.uniform(0.6, 0.82), rad * 0.62, depth + 1)
        if depth == 1 and r.random() < 0.5:   # a side shoot from the middle
            ax = Vector((r.uniform(-1, 1), r.uniform(-1, 1), 0.2)).normalized()
            nd = (Matrix.Rotation(math.radians(r.uniform(35, 60)), 3, ax) @ d).normalized()
            stick(p, a + d * (L * 0.5), a + d * (L * 0.5) + nd * (L * 0.6), rad * 0.5, 0.0, "ct_matte", tint=col)
    for k in range(6):
        yaw = TAU * (k + r.uniform(-0.3, 0.3)) / 6
        lean = math.radians(r.uniform(12, 48))
        d = Vector((math.cos(yaw) * math.sin(lean), math.sin(yaw) * math.sin(lean), math.cos(lean)))
        grow(c + Vector((math.cos(yaw), math.sin(yaw), 0)) * 0.05, d, r.uniform(0.5, 0.68), 0.045, 0)
    mound(p, (c.x, c.y), 0.2, 0.17, 0.07, 6, "ct_matte", tint=(0.07, 0.06, 0.045), inner=0.45)   # the root stock
    for k in range(5):   # fallen twigs
        a = r.uniform(0, TAU); d0 = r.uniform(0.3, 0.75)
        s = c + Vector((math.cos(a) * d0, math.sin(a) * d0, 0.012))
        yw = r.uniform(0, TAU)
        stick(p, s, s + Vector((math.cos(yw) * 0.3, math.sin(yw) * 0.3, 0.006)), 0.014, 0.0, "ct_matte", tint=(0.12, 0.1, 0.085))
    for v in p.bm.verts:
        v.co.z = max(v.co.z, 0.004)
    top = max(v.co.z for v in p.bm.verts)
    if top > 1.45:
        for v in p.bm.verts:
            v.co.z *= 1.45 / top
    p.openings = []
    p.shadow = [[[1.05, 0.0, -1.95], [1.65, 0.5, -1.35]]]
    return p


def builders():
    return [("dr_lamp_post", lambda: lamp_post("dr_lamp_post", 401)),
            ("dr_lamp_bracket", lambda: lamp_bracket("dr_lamp_bracket", 402)),
            ("dr_fountain", lambda: fountain("dr_fountain", 403)),
            ("dr_statue_plinth", lambda: statue_plinth("dr_statue_plinth", 404)),
            ("dr_pool_kerb", lambda: pool_kerb("dr_pool_kerb", 405)),
            ("dr_plot_weeds_a", lambda: plot_weeds("dr_plot_weeds_a", 411, "a")),
            ("dr_plot_weeds_b", lambda: plot_weeds("dr_plot_weeds_b", 412, "b")),
            ("dr_plot_fence_run", lambda: fence_run("dr_plot_fence_run", 413)),
            ("dr_plot_deadbush", lambda: deadbush("dr_plot_deadbush", 414))]


def red_proofs(check_kit, T):
    """Prove that the K4 checks can fail (printed every run): the 0.32 in lamp post, a lantern 0.2 in too low, a
    bracket reaching below CLEAR, a kerb 0.1 in high, a fountain 5.8 in across."""
    def rec(name, lo, hi, parts=()):
        return {"entry": T[name], "parts": list(parts), "openings": [], "materials": [], "tris": 1, "aabb_in": [lo, hi],
                "proud_in": {"flat": 0.0, "low": 0.0, "high": 0.0}}
    glass = lambda z0, z1: [{"mat": "ct_glass_lit", "lo": (-0.05, -0.05, z0), "hi": (0.05, 0.05, z1), "fill": True}]
    cases = [("LAMP POST", rec("dr_lamp_post", [-0.16, 0.0, -0.16], [0.16, 2.9, 0.16], glass(2.4, 2.7))),
             ("LANTERN", rec("dr_lamp_post", [-0.1, 0.0, -0.1], [0.1, 2.9, 0.1], glass(2.2, 2.5))),
             ("ABOVE CLEAR", rec("dr_lamp_bracket", [-0.1, -0.75, 0.0], [0.1, 0.2, 0.3], glass(-0.17, 0.07))),
             ("FLAT", rec("dr_pool_kerb", [0.0, 0.0, -0.3], [3.0, 0.1, 0.0])),
             ("FOOTPRINT", rec("dr_fountain", [-2.9, 0.0, -2.9], [2.9, 2.4, 2.9]))]
    for key, rc in cases:
        errs = [e for e in check_kit.check_piece(rc) if e.startswith(key)]
        if not errs:
            raise SystemExit(f"RED_PROOF_BROKEN: the {key} check passed a piece that must fail")
        print(f"RED_PROOF {key} check fails as required:", errs[0])
