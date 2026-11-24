# kit_k5.py - batch K5 = refuse (18): six bulky junk props and four yard pieces (terrain cells and solid
# footprints only), eight FLAT litter clusters (anywhere walkable). Conventions as kit_build.py / kit_k4.py
# (Blender X, Y, Z up; inches; every module centred on its origin).
# The refuse is dirtier and gloomier, and NOT painted on - so every litter piece is a solid with real thickness
# (<= 0.06 in built, the flat limit is 0.08), bevelled or broken, and every heap FEATHERS to the ground (outer ring at
# z = 0) instead of floating as a card. No confetti: earthy values close to the toned ground, clustered (check TONE).
import math, os
from mathutils import Vector
from kit_build import Piece
from kit_k4 import M, faces, hexa, block, lathe, mound, stick, leaf, grim_shade, nz, TAU

LIT = 0.06   # the built litter height limit (the rule's FLAT is 0.08: room for a planner's lift / scale)
STRAW = ((0.15, 0.115, 0.055), (0.12, 0.09, 0.045), (0.17, 0.135, 0.07))
LEAF = ((0.13, 0.085, 0.04), (0.095, 0.065, 0.035), (0.15, 0.11, 0.045), (0.08, 0.06, 0.035))
RAG = ((0.12, 0.105, 0.088), (0.105, 0.08, 0.068), (0.085, 0.088, 0.09), (0.125, 0.108, 0.075))   # (the rust-red kept toned down)
MUCK = (0.05, 0.04, 0.028)
BURLAP = ((0.16, 0.13, 0.09), (0.13, 0.11, 0.08), (0.18, 0.15, 0.1))


def litter_shade(q, m):
    """Dirt on every bit: darker where it meets the ground, low-frequency blotches, a high grime mask."""
    k = 0.62 + 0.38 * min(1.0, max(0.0, q.z / 0.04))
    n = 1.0 - 0.28 * nz(q.x, q.y, 0.0, 3.1)
    b = {"ct_timber": (0.62, 0.58, 0.54), "ct_roof": (0.62, 0.62, 0.66), "ct_clay": (0.8, 0.74, 0.7)}.get(m, (1.0, 1.0, 1.0))
    return (b[0] * k * n, b[1] * k * n, b[2] * k * n, min(1.0, 0.6 + 0.4 * (1.0 - k)))


def ridge(p, a, b, w, h, mat, tint, z0=0.004):
    """A stalk / twig as a ridged strip lying on the ground (two faces meeting in a ridge: real height, no card)."""
    a = Vector((a[0], a[1], 0)); b = Vector((b[0], b[1], 0))
    d = (b - a).normalized(); s = Vector((-d.y, d.x, 0)) * (w * 0.5)
    up = Vector((0, 0, z0 + h)); g = Vector((0, 0, z0 * 0.3))
    return faces(p, [[a - s + g, b - s + g, b + up, a + up], [a + up, b + up, b + s + g, a + s + g]], mat, tuple(d), tint, up=True)


def tri_slab(p, c, size, h, yaw, mat, tint, xf=None, skew=0.3, bevel=0.2):
    """A three-cornered fragment (shard, broken slate, splinter): a bevelled solid, 7 triangles."""
    r = p.rng
    pts = []
    for k in range(3):
        a = yaw + TAU * k / 3 + r.uniform(-skew, skew)
        d = size * r.uniform(0.7, 1.15)
        pts.append((c[0] + d * math.cos(a), c[1] + d * math.sin(a)))
    cx, cy = sum(q[0] for q in pts) / 3, sum(q[1] for q in pts) / 3
    bot = [(x, y, 0.0) for x, y in pts]
    top = [(x + (cx - x) * bevel, y + (cy - y) * bevel, h) for x, y in pts]
    loops = [top] + [[bot[k], bot[(k + 1) % 3], top[(k + 1) % 3], top[k]] for k in range(3)]
    return faces(p, loops, mat, None, tint, inside=(cx, cy, h * 0.4), xf=xf)


def cloth(p, c, w, l, yaw, tint):
    """A rag dropped in a heap: a 4 x 3 net, its hem on the ground (ragged outline), two folds standing up. 12 triangles."""
    r = p.rng
    cy, sy = math.cos(yaw), math.sin(yaw)
    g = []
    for j in range(3):
        for i in range(4):
            edge = i in (0, 3) or j in (0, 2)
            x = (i / 3 - 0.5) * w + r.uniform(-0.12, 0.12) * w
            y = (j / 2 - 0.5) * l + r.uniform(-0.14, 0.14) * l
            z = 0.003 if edge else r.uniform(0.045, LIT)
            g.append((c[0] + x * cy - y * sy, c[1] + x * sy + y * cy, z))
    loops = []
    for j in range(2):
        for i in range(3):
            a, b, d, e = g[j * 4 + i], g[j * 4 + i + 1], g[(j + 1) * 4 + i + 1], g[(j + 1) * 4 + i]
            loops += [[a, b, d], [a, d, e]] if (i + j) % 2 else [[a, b, e], [b, d, e]]
    return faces(p, loops, "ct_matte", None, tint, up=True)


def straw_bundle(p, c, a, n, L, spread=0.12, fan=0.22, zmax=0.056):
    """Stalks lying together: n ridged stalks nearly parallel (a bundle that fell apart), a few crossing on top."""
    r = p.rng
    for k in range(n):
        aa = a + r.uniform(-fan, fan) + (r.uniform(0.6, 1.2) * r.choice((-1, 1)) if k % 5 == 4 else 0.0)
        o = r.uniform(-spread, spread)
        cx, cy = c[0] - math.sin(a) * o + r.uniform(-0.1, 0.1) * math.cos(a), c[1] + math.cos(a) * o + r.uniform(-0.1, 0.1) * math.sin(a)
        l = L * r.uniform(0.6, 1.0)
        ridge(p, (cx - math.cos(aa) * l, cy - math.sin(aa) * l), (cx + math.cos(aa) * l, cy + math.sin(aa) * l), r.uniform(0.022, 0.034),
              r.uniform(0.022, zmax if k % 5 == 4 else 0.04), "ct_matte", r.choice(STRAW))


def leaves(p, c, n, rx, ry):
    r = p.rng
    for k in range(n):
        a = r.uniform(0, TAU); d = r.random() ** 0.7
        leaf(p, (c[0] + rx * d * math.cos(a), c[1] + ry * d * math.sin(a)), r.uniform(0, TAU), r.uniform(0.17, 0.27), r.uniform(0.1, 0.15), r.uniform(0.025, 0.05),
             r.uniform(0.004, 0.02), r.choice(LEAF))


def shards(p, c, n, rad, mat="ct_clay", lo=0.36, hi=0.58, smin=0.09, smax=0.2, h=(0.026, 0.04)):
    r = p.rng
    for k in range(n):
        a = r.uniform(0, TAU); d = rad * r.random() ** 0.8
        t = lo + (hi - lo) * r.random()
        tri_slab(p, (0, 0), r.uniform(smin, smax), r.uniform(*h), r.uniform(0, TAU), mat, (t, t * 0.96, t * 0.92),
                 xf=M(c[0] + d * math.cos(a), c[1] + d * math.sin(a), 0.0, pitch=r.uniform(-5, 5) if k % 3 == 0 else 0.0))


def boards(p, spots, th=0.03):
    r = p.rng
    for (x, y, yw, L, w, pt) in spots:
        t = 0.68 + 0.25 * r.random()
        block(p, (-L, -w, 0.0), (L, w, th), "ct_timber", xf=M(x, y, 0.014 if pt else 0.0, yaw=yw, pitch=pt), bevel=0.012, jit=0.03, grain=(1, 0, 0), tint=(t, t, t))


def slates(p, spots):
    r = p.rng
    for (x, y, yw, pt) in spots:
        t = 0.72 + 0.25 * r.random()
        block(p, (-0.24, -0.17, 0.0), (0.24, 0.17, 0.024), "ct_roof", xf=M(x, y, 0.012 if pt else 0.0, yaw=yw, pitch=pt), bevel=0.012, jit=0.03, tint=(t, t, t))


def _flatten(p):
    for v in p.bm.verts:
        v.co.z = max(v.co.z, 0.0)
    top = max(v.co.z for v in p.bm.verts)
    if top > LIT:   # (a tilted bit: squeeze the cluster under the built limit)
        for v in p.bm.verts:
            v.co.z *= LIT / top
    p.openings = []
    p.shadow = []
    p.entry = {"height_in": round(max(v.co.z for v in p.bm.verts), 3)}
    return p


def litter(name, seed, kind):
    """One kind per cluster, <= 100 triangles (the cap allows bundles, not single bits)."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = litter_shade
    if kind == "straw":   # a trodden drift: a matted heap, two bundles of stalks across it, strays trailing off
        mound(p, (0, 0), 0.5, 0.3, 0.045, 6, "ct_matte", tint=(0.1, 0.075, 0.04), inner=0.55, yaw=0.5, rough=0.4)
        straw_bundle(p, (-0.12, 0.02), 0.45, 10, 0.5); straw_bundle(p, (0.25, -0.1), -0.25, 7, 0.42)
        straw_bundle(p, (0.1, 0.3), 1.4, 3, 0.3, spread=0.3, fan=0.8)
    elif kind == "leaves":   # wet leaf mould with leaves heaped on it and blown off one side
        mound(p, (0.05, 0), 0.42, 0.3, 0.036, 5, "ct_matte", tint=(0.055, 0.042, 0.03), inner=0, yaw=1.0, rough=0.3)
        mound(p, (-0.4, 0.25), 0.22, 0.16, 0.026, 5, "ct_matte", tint=(0.06, 0.045, 0.03), inner=0, rough=0.3)
        leaves(p, (0.05, 0.0), 13, 0.5, 0.36); leaves(p, (-0.45, 0.3), 7, 0.3, 0.22); leaves(p, (0.75, -0.3), 2, 0.12, 0.1)
    elif kind == "shards":   # a smashed pot: thick bevelled shards in a spray, the big ones where it hit, dust under them
        mound(p, (0, 0), 0.3, 0.24, 0.016, 6, "ct_matte", tint=(0.085, 0.06, 0.045), inner=0, rough=0.4)
        shards(p, (0, 0), 5, 0.2, smin=0.14, smax=0.22); shards(p, (0.15, 0.1), 7, 0.6, smin=0.06, smax=0.12, h=(0.02, 0.03))
    elif kind == "rags":   # dull, dirty cloth (no bright red): three heaps and torn strips
        cloth(p, (-0.3, 0.05), 0.75, 0.5, 0.3, RAG[0]); cloth(p, (0.35, -0.2), 0.6, 0.42, 1.2, RAG[1]); cloth(p, (0.25, 0.4), 0.45, 0.35, 2.2, RAG[3])
        cloth(p, (-0.55, -0.4), 0.35, 0.22, 0.9, RAG[2])
        for k in range(6):
            a = r.uniform(0, TAU); cx, cy = r.uniform(-0.6, 0.6), r.uniform(-0.45, 0.45); l = r.uniform(0.1, 0.22)
            ridge(p, (cx - math.cos(a) * l, cy - math.sin(a) * l), (cx + math.cos(a) * l, cy + math.sin(a) * l), 0.05, 0.02, "ct_matte", r.choice(RAG))
    elif kind == "mud":   # clots of muck with crumbs of fallen mortar pressed into them
        mound(p, (-0.15, 0), 0.45, 0.3, 0.056, 6, "ct_matte", tint=MUCK, inner=0.5, yaw=0.4, rough=0.35)
        mound(p, (0.42, 0.2), 0.3, 0.22, 0.04, 6, "ct_matte", tint=(0.06, 0.047, 0.032), inner=0.5, yaw=2.0, rough=0.35)
        mound(p, (0.1, -0.42), 0.2, 0.13, 0.03, 5, "ct_matte", tint=(0.055, 0.045, 0.03), inner=0, yaw=1.0, rough=0.35)
        for k in range(12):
            a = r.uniform(0, TAU); d = r.uniform(0.1, 0.7)
            mound(p, (d * math.cos(a), d * 0.7 * math.sin(a)), r.uniform(0.03, 0.065), r.uniform(0.025, 0.05), r.uniform(0.02, 0.04), 3, "ct_matte",
                  tint=(0.11, 0.105, 0.095) if k % 3 else (0.085, 0.08, 0.075), inner=0, rough=0.2)
    elif kind == "planks_flat":   # broken boards trodden into the street, crossing, with splinters
        boards(p, ((-0.1, -0.2, 8, 0.62, 0.11, 0.0), (0.05, 0.22, -14, 0.5, 0.095, 0.0), (0.1, 0.0, 62, 0.42, 0.1, -3.0), (-0.45, 0.4, 35, 0.25, 0.08, 0.0),
                   (0.55, -0.42, -40, 0.2, 0.07, 0.0), (0.6, 0.35, 80, 0.16, 0.06, 0.0)))
        for (x, y) in ((-0.62, 0.1), (0.4, 0.5), (-0.3, -0.5), (0.75, 0.0)):
            tri_slab(p, (x, y), r.uniform(0.07, 0.13), 0.022, r.uniform(0, 6), "ct_timber", (0.8, 0.8, 0.8))
    elif kind == "staves_flat":   # a barrel fallen apart: staves fanned out belly up, pieces of a hoop
        for k in range(6):
            yw = -50 + 20 * k + r.uniform(-7, 7)
            L, w = r.uniform(0.4, 0.52), 0.07
            xf = M(-0.15 + 0.06 * k + r.uniform(-0.06, 0.06), -0.3 + 0.12 * k + r.uniform(-0.04, 0.04), 0.0, yaw=yw)
            t = 0.6 + 0.25 * r.random()
            hexa(p, [(-L, -w, 0), (L, -w, 0), (L, w, 0), (-L, w, 0), (-L * 0.55, -w * 0.6, 0.04), (L * 0.55, -w * 0.6, 0.04),
                     (L * 0.55, w * 0.6, 0.04), (-L * 0.55, w * 0.6, 0.04)], "ct_timber", grain=(1, 0, 0), tint=(t, t * 0.97, t * 0.93), xf=xf)
        for k in range(3):   # a rusted hoop, broken: three bent lengths of flat iron
            a = 0.5 + 0.55 * k
            block(p, (-0.11, -0.016, 0.0), (0.11, 0.016, 0.022), "ct_iron", xf=M(0.5 + 0.24 * math.cos(a), 0.2 + 0.24 * math.sin(a), 0.0, yaw=math.degrees(a) + 90), jit=0.006)
    elif kind == "slates_fallen":   # slates off the roof: whole ones, halves, chips; lying on one another
        slates(p, ((-0.3, -0.1, 12, 0.0), (0.12, 0.05, 50, -4.0), (0.5, 0.42, -20, 0.0), (-0.55, 0.4, 70, 0.0), (0.3, -0.45, 5, 3.0)))
        for (x, y) in ((0.62, -0.25), (-0.15, 0.5), (-0.7, -0.35), (0.05, -0.62), (0.8, 0.15)):
            tri_slab(p, (x, y), r.uniform(0.1, 0.19), 0.024, r.uniform(0, 6), "ct_roof", (0.85, 0.85, 0.87))
        for k in range(3):
            mound(p, (r.uniform(-0.7, 0.7), r.uniform(-0.6, 0.6)), 0.06, 0.045, 0.028, 3, "ct_roof", tint=(0.7, 0.7, 0.72), inner=0, rough=0.2)
    return _flatten(p)


def drift(name, seed, variant):
    """A LARGER cluster (3 x 1.3 in, <= 300 triangles): several kinds laid in one drift along a bent line - the heavy bits
    where they fell, the light ones blown to one end - so a street needs a few drifts, not dozens of stamps.
    a = stable sweepings (straw, muck, a board); b = under a broken eave / at a wall foot (slates, mortar, leaves);
    c = household refuse (rags, potsherds, staves, straw)."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = litter_shade
    sp = lambda t: (-1.35 + 2.7 * t, 0.28 * math.sin(2.4 * t + seed) - 0.05)   # the drift's bent line
    for k in range(4):   # the stain / muck bed under everything: feathered heaps along the line
        x, y = sp((k + 0.5) / 4)
        mound(p, (x, y), r.uniform(0.38, 0.52), r.uniform(0.22, 0.32), r.uniform(0.022, 0.04), 6, "ct_matte", tint=r.choice((MUCK, (0.06, 0.047, 0.032), (0.07, 0.055, 0.035))),
              inner=0.5, yaw=r.uniform(-0.4, 0.4), rough=0.35)
    if variant == "a":
        straw_bundle(p, sp(0.2), 0.3, 11, 0.5); straw_bundle(p, sp(0.5), -0.15, 9, 0.45); straw_bundle(p, sp(0.8), 0.5, 6, 0.36, spread=0.2, fan=0.5)
        boards(p, ((sp(0.62)[0], sp(0.62)[1] + 0.3, 15, 0.4, 0.09, 0.0),))
        leaves(p, sp(0.95), 5, 0.25, 0.2)
    elif variant == "b":
        x, y = sp(0.3)
        slates(p, ((x, y, 20, 0.0), (x + 0.3, y + 0.12, 65, -4.0), (x - 0.35, y - 0.1, -10, 0.0)))
        for k in range(4):
            tri_slab(p, (x + r.uniform(-0.6, 0.7), y + r.uniform(-0.35, 0.35)), r.uniform(0.09, 0.17), 0.024, r.uniform(0, 6), "ct_roof", (0.85, 0.85, 0.87))
        for k in range(14):   # mortar crumbs and chips of the wall's stone
            xx, yy = sp(r.uniform(0.1, 0.75))
            mound(p, (xx + r.uniform(-0.2, 0.2), yy + r.uniform(-0.3, 0.3)), r.uniform(0.03, 0.06), r.uniform(0.025, 0.045), r.uniform(0.02, 0.04), 3, "ct_matte",
                  tint=(0.11, 0.105, 0.095) if k % 3 else (0.08, 0.08, 0.085), inner=0, rough=0.2)
        leaves(p, sp(0.82), 12, 0.42, 0.3)
    else:
        x, y = sp(0.25)
        cloth(p, (x, y), 0.7, 0.45, 0.4, RAG[0]); cloth(p, (x + 0.45, y + 0.2), 0.5, 0.36, 1.5, RAG[1])
        shards(p, sp(0.55), 9, 0.4, smin=0.07, smax=0.17)
        xx, yy = sp(0.8)
        for k in range(3):
            xf = M(xx + 0.07 * k, yy - 0.15 + 0.14 * k, 0.0, yaw=-20 + 22 * k)
            hexa(p, [(-0.45, -0.07, 0), (0.45, -0.07, 0), (0.45, 0.07, 0), (-0.45, 0.07, 0), (-0.25, -0.04, 0.04), (0.25, -0.04, 0.04), (0.25, 0.04, 0.04), (-0.25, 0.04, 0.04)],
                 "ct_timber", grain=(1, 0, 0), tint=(0.68, 0.66, 0.62), xf=xf)
        straw_bundle(p, sp(0.42), 0.2, 8, 0.4)
    return _flatten(p)


# ------------------------------------------------------------------ bulky junk (terrain cells / solid footprints only)
JUNK = {"ct_timber": (0.66, 0.6, 0.54), "ct_stone": (0.58, 0.6, 0.64), "ct_iron": (1.5, 1.0, 0.75), "ct_roof": (0.6, 0.6, 0.64), "ct_clay": (0.7, 0.65, 0.6)}


def barrel(p, xf, n, rad, h, open_top=False, tint=1.0):
    """A coopered barrel (n staves as facets), iron hoops as bands, a sunk head inside the chime; open_top = the head is
    knocked in (a dark inside). Local: axis z, standing on z = 0."""
    T, I = "ct_timber", "ct_iron"
    w = (tint, tint * 0.97, tint * 0.93); ir = (1.0, 1.0, 1.0); dk = (tint * 0.4,) * 3
    s = rad / 0.25; q = h / 0.7
    prof = [(0.0, 0.03 * q), (0.185 * s, 0.03 * q, T, dk), (0.2 * s, 0.0, T, w), (0.214 * s, 0.07 * q, T, w), (0.224 * s, 0.125 * q, I, ir),
            (0.25 * s, 0.33 * q, T, w), (0.25 * s, 0.385 * q, I, ir), (0.226 * s, 0.6 * q, T, w), (0.216 * s, 0.655 * q, I, ir), (0.208 * s, 0.7 * q, T, w),
            (0.186 * s, 0.7 * q, T, w)]
    if open_top:
        prof += [(0.18 * s, 0.14 * q, T, dk), (0.0, 0.14 * q, T, (tint * 0.25,) * 3)]
    else:
        prof += [(0.186 * s, 0.655 * q, T, dk), (0.0, 0.655 * q, T, (tint * 0.75, tint * 0.72, tint * 0.68))]
    lathe(p, (0, 0), prof, n, T, xf=xf, tint=w, ph=0.2)


def junk_barrels(name, seed):
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.3, foot_k=0.5, blotch=0.3, grime=0.6)
    barrel(p, M(-0.32, 0.14, 0.0, yaw=10), 9, 0.25, 0.68, tint=0.9)
    barrel(p, M(0.36, -0.2, 0.2, yaw=-28, pitch=90), 8, 0.2, 0.62, open_top=True, tint=0.75)   # fallen, its head knocked in
    for (x, y, yw) in ((0.1, 0.5, 35), (0.42, 0.28, -70)):   # two sprung staves on the ground
        hexa(p, [(-0.26, -0.035, 0), (0.26, -0.035, 0), (0.26, 0.035, 0), (-0.26, 0.035, 0), (-0.15, -0.02, 0.035), (0.15, -0.02, 0.035),
                 (0.15, 0.02, 0.035), (-0.15, 0.02, 0.035)], "ct_timber", grain=(1, 0, 0), tint=(0.7, 0.68, 0.64), xf=M(x, y, 0, yaw=yw))
    p.openings = []
    return p


def crate(p, xf, w, l, h, rows=3, lid=True, t=0.85):
    r = p.rng
    block(p, (-w, -l, 0.0), (w, l, h - 0.004), "ct_timber", xf=xf, tint=(0.3, 0.28, 0.26))   # the dark core seen through the gaps
    ph = h / rows
    for k in range(rows):
        z0, z1 = k * ph + 0.006, (k + 1) * ph - 0.006
        for side in range(4):
            tt = t * r.uniform(0.8, 1.05); d = 0.014 + r.choice((0.0, 0.006, 0.012))
            if side == 0:
                lo, hi, sk = (-w - 0.004, -l - d, z0), (w + 0.004, -l, z1), 2
            elif side == 1:
                lo, hi, sk = (w, -l, z0), (w + d, l, z1), 3
            elif side == 2:
                lo, hi, sk = (-w - 0.004, l, z0), (w + 0.004, l + d, z1), 0
            else:
                lo, hi, sk = (-w - d, -l, z0), (-w, l, z1), 1
            block(p, lo, hi, "ct_timber", xf=xf, grain=(1, 0, 0) if side in (0, 2) else (0, 1, 0), tint=(tt, tt * 0.97, tt * 0.92), skip=(sk,), bottom=True)
    if lid:
        n = 3
        for k in range(n):
            y0, y1 = -l + 2 * l * k / n + 0.008, -l + 2 * l * (k + 1) / n - 0.008
            tt = t * r.uniform(0.85, 1.08)
            block(p, (-w - 0.02, y0, h), (w + 0.02, y1, h + 0.022), "ct_timber", xf=xf, grain=(1, 0, 0), tint=(tt, tt * 0.97, tt * 0.92), jit=0.006)


def junk_crates(name, seed):
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.3, foot_k=0.5, blotch=0.3, grime=0.6)
    crate(p, M(-0.2, 0.1, 0.0, yaw=8), 0.36, 0.3, 0.55)
    crate(p, M(-0.12, 0.05, 0.575, yaw=-24), 0.22, 0.19, 0.28, rows=2, t=0.75)          # a small one askew on top
    for k, (x, y, yw, pt) in enumerate(((0.5, -0.3, 20, 0), (0.55, -0.05, -15, 0), (0.42, 0.25, 70, 0), (0.6, -0.42, 95, -6), (0.3, -0.52, -40, 0))):
        tt = r.uniform(0.6, 0.85)   # a third crate, smashed: its boards splayed on the ground
        block(p, (-0.24, -0.045, 0.0), (0.24, 0.045, 0.024), "ct_timber", xf=M(x, y, 0.02 if pt else 0.0, yaw=yw, pitch=pt), grain=(1, 0, 0),
              tint=(tt, tt * 0.97, tt * 0.92), jit=0.02, bevel=0.006)
    mound(p, (0.48, -0.15), 0.3, 0.22, 0.06, 6, "ct_matte", tint=STRAW[1], inner=0.5, yaw=0.6)   # rotten packing straw
    p.openings = []
    return p


def junk_cart_wheel(name, seed):
    """A cart wheel propped against the stump of a post: ten spokes (two broken), two felloes gone, a heap at its foot."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.3, foot_k=0.5, blotch=0.3, grime=0.6)
    R, ri, hw = 0.45, 0.375, 0.04
    xf = M(0.0, -0.06, 0.445, yaw=12, roll=72)
    N = 12
    for k in range(N):
        if k in (2, 3):
            continue   # two felloes are gone
        a0, a1 = TAU * k / N + 0.01, TAU * (k + 1) / N - 0.01
        pt = lambda rr, a, z: (rr * math.cos(a), rr * math.sin(a), z)
        t = 0.75 + 0.2 * r.random()
        hexa(p, [pt(R, a0, -hw), pt(R, a1, -hw), pt(ri, a1, -hw), pt(ri, a0, -hw), pt(R, a0, hw), pt(R, a1, hw), pt(ri, a1, hw), pt(ri, a0, hw)],
             "ct_timber", grain=(-math.sin((a0 + a1) / 2), math.cos((a0 + a1) / 2), 0), tint=(t, t * 0.97, t * 0.93), bottom=True, xf=xf)
    lathe(p, (0, 0), [(0.0, -0.11), (0.085, -0.11), (0.115, -0.04), (0.115, 0.04), (0.085, 0.11), (0.0, 0.11)], 8, "ct_timber", xf=xf, tint=(0.7, 0.67, 0.63))
    for k in range(10):
        a = TAU * (k + 0.5) / 10
        gone = k in (1, 2)
        L = r.uniform(0.2, 0.26) if gone else ri + 0.01
        fs_a = xf @ Vector((0.1 * math.cos(a), 0.1 * math.sin(a), 0)); fs_b = xf @ Vector((L * math.cos(a), L * math.sin(a), 0))
        stick(p, fs_a, fs_b, 0.03, 0.0 if gone else 0.024, "ct_timber", tint=(0.8, 0.77, 0.72))
    block(p, (-0.14, 0.1, 0.0), (0.14, 0.36, 0.66), "ct_timber", grain=(0, 0, 1), tint=(0.62, 0.6, 0.56), jit=0.02, zj=0.1)     # the post stump
    mound(p, (0.05, -0.2), 0.42, 0.2, 0.08, 6, "ct_matte", tint=MUCK, inner=0.5)                                                # muck at the foot
    block(p, (-0.2, -0.03, 0.0), (0.2, 0.03, 0.03), "ct_timber", xf=M(0.32, -0.36, 0.0, yaw=30), grain=(1, 0, 0), tint=(0.75, 0.72, 0.68), jit=0.01)   # a fallen felloe
    for v in p.bm.verts:
        v.co.z = max(v.co.z, 0.0)
    p.openings = []
    return p


def junk_planks(name, seed):
    """A heap of old boards: a rough stack in three layers, ends broken, two slid off."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.15, foot_k=0.5, blotch=0.3, grime=0.6)
    def board(x, y, z, yw, L, w, pt=0.0, th=0.055):
        t = r.uniform(0.6, 0.92)
        block(p, (-L, -w, 0.0), (L, w, th), "ct_timber", xf=M(x, y, z, yaw=yw, pitch=pt), grain=(1, 0, 0), tint=(t, t * 0.97, t * 0.92), jit=0.025, bevel=0.008,
              bottom=z > 0.01)
    for k in range(4):
        board(r.uniform(-0.06, 0.06), -0.3 + 0.2 * k, 0.0, r.uniform(-7, 7), r.uniform(0.5, 0.62), 0.085)
    for k in range(3):
        board(-0.3 + 0.3 * k, r.uniform(-0.05, 0.05), 0.06, 90 + r.uniform(-12, 12), r.uniform(0.36, 0.46), 0.08)
    board(0.05, -0.1, 0.12, r.uniform(15, 30), 0.52, 0.09); board(-0.1, 0.18, 0.12, r.uniform(-25, -10), 0.4, 0.08)
    board(0.46, 0.34, 0.06, 55, 0.3, 0.075, pt=-11); board(-0.5, -0.4, 0.0, -50, 0.22, 0.07)
    p.openings = []
    return p


def sack(p, xf, w, l, h, tint):
    """A slumped sack: a lumpy pillow on the ground with a tied neck at one end."""
    r = p.rng
    def ring(k, z, n=8, zj=0.0):
        out = []
        for i in range(n):
            a = TAU * i / n
            sq = 1.0 / max(abs(math.cos(a)), abs(math.sin(a))) ** 0.6   # rounded rectangle
            out.append((w * k * sq * math.cos(a) * r.uniform(0.92, 1.06), l * k * sq * math.sin(a) * r.uniform(0.92, 1.06), z + r.uniform(-zj, zj)))
        return out
    a, b, c = ring(0.86, 0.0), ring(1.0, h * 0.45, zj=h * 0.05), ring(0.6, h * 0.92, zj=h * 0.07)
    loops = []
    for i in range(8):
        j = (i + 1) % 8
        loops += [[a[i], a[j], b[j], b[i]], [b[i], b[j], c[j], c[i]], [c[i], c[j], (r.uniform(-0.03, 0.03), 0.0, h)]]
    faces(p, loops, "ct_matte", None, tint, inside=(0, 0, h * 0.3), xf=xf)
    block(p, (w * 0.9, -0.04, h * 0.3), (w * 1.22, 0.04, h * 0.62), "ct_matte", xf=xf, tint=tuple(c_ * 0.8 for c_ in tint), bevel=0.012, jit=0.01, bottom=True)   # the neck


def junk_sacks(name, seed):
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade({}, foot=0.2, foot_k=0.45, blotch=0.35, grime=0.65)
    sack(p, M(-0.18, 0.12, 0.0, yaw=15), 0.3, 0.2, 0.2, BURLAP[0])
    sack(p, M(0.14, -0.2, 0.0, yaw=-35), 0.28, 0.19, 0.18, BURLAP[1])
    sack(p, M(-0.02, -0.02, 0.17, yaw=70, roll=6), 0.27, 0.18, 0.19, BURLAP[2])
    mound(p, (0.32, 0.26), 0.2, 0.15, 0.05, 6, "ct_matte", tint=(0.11, 0.085, 0.045), inner=0.5)   # spilt, rotting grain from a split sack
    mound(p, (0.18, 0.36), 0.1, 0.08, 0.025, 5, "ct_matte", tint=(0.09, 0.07, 0.04), inner=0)
    p.openings = []
    return p


def heap(p, rx, ry, h, nblocks, smin, smax, mat="ct_stone", core_tint=(0.7, 0.68, 0.66)):
    """A rubble heap: a ragged core that feathers to the ground and tumbled ashlar blocks half sunk in it."""
    r = p.rng
    mound(p, (0, 0), rx, ry, h * 0.7, 9, mat, tint=core_tint, inner=0.55, rough=0.2)
    for k in range(nblocks):
        a = r.uniform(0, TAU); d = r.random() ** 0.7
        x, y = rx * 0.95 * d * math.cos(a), ry * 0.95 * d * math.sin(a)
        s = r.uniform(smin, smax)
        z = max(0.0, h * 0.62 * (1.0 - d) - s * 0.25)
        t = r.uniform(0.85, 1.15)
        block(p, (-s, -s * 0.62, -s * 0.2), (s, s * 0.62, s * 0.75), mat, xf=M(x, y, z, yaw=r.uniform(0, 180), pitch=r.uniform(-22, 22), roll=r.uniform(-18, 18)),
              jit=s * 0.12, bevel=s * 0.06, tint=(t, t, t * 0.98))


def junk_rubble(name, seed):
    """A small heap of building rubble and refuse: stones, a broken board, potsherds, a slate."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.25, foot_k=0.5, blotch=0.3, grime=0.6)
    heap(p, 0.68, 0.55, 0.36, 13, 0.07, 0.15)
    block(p, (-0.36, -0.05, 0.0), (0.36, 0.05, 0.04), "ct_timber", xf=M(0.15, -0.2, 0.16, yaw=25, pitch=-14), grain=(1, 0, 0), tint=(0.7, 0.67, 0.62), jit=0.02, bottom=True)
    block(p, (-0.2, -0.13, 0.0), (0.2, 0.13, 0.024), "ct_roof", xf=M(-0.35, 0.3, 0.07, yaw=60, pitch=12), jit=0.02, bottom=True, tint=(0.85, 0.85, 0.87))
    for k in range(3):
        tri_slab(p, (0, 0), 0.1, 0.03, r.uniform(0, 6), "ct_clay", (0.7, 0.66, 0.62), xf=M(0.45 + 0.1 * k, 0.25 - 0.22 * k, 0.0))
    for v in p.bm.verts:
        v.co.z = max(v.co.z, 0.0)
    p.openings = []
    return p


# ------------------------------------------------------------------ yard pieces (ruin yards)
def wallstub(name, seed, variant="a"):
    """The stump of a yard wall, 0.4 in thick, on 0.5 in courses: stepped, ragged ends, loose stones on top and at its foot.
    a = 2.8 in long, 1.2 in at its high end; b = 0.8 in, broken through in the middle, with the start of a return wall."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade({"ct_stone": (0.6, 0.63, 0.68)}, foot=0.5, foot_k=0.5, blotch=0.28, grime=0.55)
    def course(x0, x1, z0, z1, y0=-0.2, y1=0.2, loose=False):
        x = x0
        while x < x1 - 0.12:
            w = min(x1 - x, r.choice((0.45, 0.6, 0.6, 0.75)))
            if x1 - (x + w) < 0.2:
                w = x1 - x
            d = r.choice((0.0, 0.012, 0.024)); t = r.uniform(0.86, 1.1)
            zt = z1 - (r.uniform(0.0, 0.12) if loose else 0.0)
            block(p, (x + 0.006, y0 + d, z0), (x + w - 0.006, y1 - r.choice((0.0, 0.012, 0.024)), zt), "ct_stone", jit=0.012, bevel=0.012 if loose else 0.0,
                  tint=(t, t, t * 0.98), bottom=z0 > 0.01)
            x += w
    def fallen(spots):
        for (x, y, s, yw) in spots:
            block(p, (-s, -s * 0.65, 0.0), (s, s * 0.65, s * 0.8), "ct_stone", xf=M(x, y, 0.0, yaw=yw, roll=r.uniform(-12, 12)), jit=0.02, bevel=0.012,
                  tint=(0.9, 0.9, 0.9))
    if variant == "a":
        course(-1.4, 1.4, 0.0, 0.5); course(-1.4, 0.55, 0.5, 1.0); course(-1.4, -0.45, 1.0, 1.2, loose=True)
        block(p, (0.6, -0.17, 0.5), (1.0, 0.16, 0.72), "ct_stone", jit=0.03, bevel=0.02, tint=(0.95, 0.95, 0.95), bottom=True)
        fallen(((0.9, -0.42, 0.13, 20), (1.2, 0.45, 0.11, 70), (0.3, 0.46, 0.14, -15), (1.32, -0.36, 0.09, 40), (-0.2, -0.44, 0.1, 55)))
    else:
        course(-1.4, -0.35, 0.0, 0.5); course(0.45, 1.4, 0.0, 0.5)
        course(-1.4, -0.9, 0.5, 0.8, loose=True); course(0.9, 1.4, 0.5, 0.74, loose=True)
        x = 0.2
        for k in range(2):   # the start of a return wall at the left end (y 0.2..1.0)
            block(p, (-1.4 + 0.012 * k, x, 0.0), (-1.0, x + 0.4, 0.5 - 0.14 * k), "ct_stone", jit=0.012, tint=(0.95, 0.95, 0.95))
            x += 0.4
        fallen(((-0.1, -0.1, 0.14, 30), (0.2, 0.12, 0.12, 75), (0.05, -0.42, 0.1, 10), (-0.3, 0.4, 0.11, 50), (0.7, 0.45, 0.09, 20), (-0.6, -0.4, 0.09, 65)))
    p.openings = []
    return p


def yard_rubble(name, seed):
    """A fallen wall in a ruin yard: big ashlar blocks on a spread heap, a slab of masonry still bonded, a charred beam through it."""
    p = Piece(name, seed)
    r = p.rng
    p.shade = grim_shade(JUNK, foot=0.3, foot_k=0.5, blotch=0.3, grime=0.6)
    heap(p, 0.95, 0.8, 0.42, 15, 0.12, 0.22, core_tint=(0.66, 0.64, 0.62))
    block(p, (-0.5, -0.2, 0.0), (0.5, 0.2, 0.3), "ct_stone", xf=M(-0.3, 0.25, 0.2, yaw=35, pitch=-16, roll=20), jit=0.03, tint=(0.95, 0.95, 0.95), bottom=True)
    block(p, (-0.7, -0.07, 0.0), (0.7, 0.07, 0.13), "ct_timber", xf=M(0.2, -0.3, 0.22, yaw=-20, pitch=-13), grain=(1, 0, 0), tint=(0.4, 0.37, 0.35), jit=0.02, bottom=True)
    for v in p.bm.verts:
        v.co.z = min(max(v.co.z, 0.0), 0.59)
    p.openings = []
    return p


def yard_beam(name, seed):
    """Fallen roof timbers: a long charred beam snapped in two, one end on a stone, a rafter lying across it, charcoal."""
    p = Piece(name, seed)
    r = p.rng
    base = grim_shade(JUNK, foot=0.12, foot_k=0.55, blotch=0.35, grime=0.7)
    p.shade = base
    ch = (0.36, 0.33, 0.31)   # charred (dark brown-grey, never black)
    block(p, (-0.62, -0.08, 0.0), (0.62, 0.08, 0.15), "ct_timber", xf=M(-0.52, 0.05, 0.0, yaw=6), grain=(1, 0, 0), tint=ch, jit=0.02, bevel=0.022)
    block(p, (-0.52, -0.08, 0.0), (0.52, 0.08, 0.15), "ct_timber", xf=M(0.6, -0.08, 0.05, yaw=-9, pitch=-4.5), grain=(1, 0, 0), tint=(0.46, 0.42, 0.38), jit=0.025,
          bevel=0.022, bottom=True)
    block(p, (-0.13, -0.1, 0.0), (0.13, 0.1, 0.12), "ct_stone", xf=M(1.0, -0.14, 0.0, yaw=20), jit=0.02, bevel=0.012)                    # the stone under its end
    block(p, (-0.5, -0.05, 0.0), (0.5, 0.05, 0.09), "ct_timber", xf=M(-0.35, 0.02, 0.105, yaw=68, pitch=-6), grain=(1, 0, 0), tint=(0.5, 0.46, 0.42), jit=0.02,
          bevel=0.012, bottom=True)                                                                                                    # a rafter across it
    block(p, (-0.012, -0.09, 0.0), (0.012, 0.09, 0.16), "ct_iron", xf=M(-0.9, 0.01, 0.0, yaw=6), bottom=False)                           # an iron strap
    for (x, y, s) in ((0.0, -0.3, 0.07), (0.15, 0.32, 0.06), (-0.75, 0.3, 0.05), (0.3, -0.38, 0.045)):
        mound(p, (x, y), s, s * 0.7, s * 0.6, 4, "ct_matte", tint=(0.045, 0.04, 0.038), inner=0, rough=0.3)                            # charcoal
    for v in p.bm.verts:
        v.co.z = min(max(v.co.z, 0.0), 0.295)
    p.openings = []
    return p


def _grounded(fn):
    def f():
        p = fn()
        for v in p.bm.verts:   # nothing below the ground (a tipped block's corner)
            v.co.z = max(v.co.z, 0.0)
        return p
    return f


def builders():
    return [(n, _grounded(fn)) for n, fn in _builders()]


def _builders():
    B = [("dr_junk_barrels", lambda: junk_barrels("dr_junk_barrels", 501)), ("dr_junk_crates", lambda: junk_crates("dr_junk_crates", 502)),
         ("dr_junk_cart_wheel", lambda: junk_cart_wheel("dr_junk_cart_wheel", 503)), ("dr_junk_planks", lambda: junk_planks("dr_junk_planks", 504)),
         ("dr_junk_sacks", lambda: junk_sacks("dr_junk_sacks", 505)), ("dr_junk_rubble", lambda: junk_rubble("dr_junk_rubble", 506))]
    for k, v in enumerate(("straw", "leaves", "shards", "rags", "mud", "planks_flat", "staves_flat", "slates_fallen")):
        B.append(("dr_litter_" + v, lambda v=v, k=k: litter("dr_litter_" + v, 511 + k, v)))
    for v in ("a", "b", "c"):
        B.append(("dr_litter_drift_" + v, lambda v=v: drift("dr_litter_drift_" + v, 531 + ord(v), v)))
    B += [("dr_yard_wallstub_a", lambda: wallstub("dr_yard_wallstub_a", 521, "a")), ("dr_yard_wallstub_b", lambda: wallstub("dr_yard_wallstub_b", 522, "b")),
          ("dr_yard_rubble_a", lambda: yard_rubble("dr_yard_rubble_a", 523)), ("dr_yard_beam", lambda: yard_beam("dr_yard_beam", 524))]
    return B


def red_proofs(check_kit, T):
    """Prove the K5 checks can fail: a litter piece 0.1 in high, one of 101 triangles, a junk prop wider than a cell, and
    (through a real GLB) a near-white matte litter bit = confetti."""
    def rec(name, lo, hi, tris=1):
        return {"entry": T[name], "parts": [], "openings": [], "materials": [], "tris": tris, "aabb_in": [lo, hi],
                "proud_in": {"flat": 0.0, "low": 0.0, "high": 0.0}}
    for key, rc in (("FLAT", rec("dr_litter_straw", [-1, 0.0, -1], [1, 0.1, 1])), ("TRI_CAP", rec("dr_litter_straw", [-1, 0.0, -1], [1, 0.05, 1], 101)),
                    ("JUNK CELL", rec("dr_junk_planks", [-1.6, 0.0, -1], [1.6, 0.3, 1]))):
        errs = [e for e in check_kit.check_piece(rc) if e.startswith(key)]
        if not errs:
            raise SystemExit(f"RED_PROOF_BROKEN: the {key} check passed a piece that must fail")
        print(f"RED_PROOF {key} check fails as required:", errs[0])
    import bpy, tempfile, kit_build
    p = Piece("red_confetti", 1)
    p.shade = lambda q, m: (1.0, 1.0, 1.0, 0.3)
    mound(p, (0, 0), 0.2, 0.2, 0.03, 5, "ct_matte", tint=(0.8, 0.8, 0.78), inner=0)
    ob = kit_build.to_object(p)
    tris = sum(len(f.verts) - 2 for f in p.bm.faces)
    p.bm.free()
    path = os.path.join(tempfile.mkdtemp(), "red_confetti.glb")
    kit_build.export(ob, path)
    errs = [e for e in check_kit.check_glb(path, {"entry": T["dr_litter_straw"], "tris": tris}) if e.startswith("TONE")]
    me = ob.data
    bpy.data.objects.remove(ob); bpy.data.meshes.remove(me); os.remove(path)
    if not errs:
        raise SystemExit("RED_PROOF_BROKEN: the TONE check passed a near-white litter bit")
    print("RED_PROOF TONE check fails as required:", errs[0])
