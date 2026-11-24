# kit_k5b.py - batch K5b = the VEGETATION as kit modules (dr_veg_*): ribbon grass, moss, nettles, dead stalks,
# plus alpha-card tufts (three crossed quads on a billboard of Poly Haven grass_medium_01).
# The modelled generators come from an external source file (see VEG_SOURCE below), loaded as source with its main() not run.
# WHAT THE GAME STILL LACKS: vegetation needs its own material (two-sided, bent normals, wrapped diffuse + backlight, no shadow;
# for cards an alpha-scissor atlas). Until then every dr_veg_* GLB carries the placeholder name ct_matte, the key
# `needs_material`, and stays `stub: true` (not usable).
# Vertex data (differs from the kit contract, declared per module in `veg`):
#   COLOR_0.rgb = linear albedo / ALBEDO_SCALE x 0.5 (the dusk albedos 0.007-0.066 do not survive u8 at scale 1), a = AO
#   NORMAL = bent (0.6 up + 0.45 out of the clump + 0.3 blade face), smooth;  TEXCOORD_0 = u across / v along the blade, or
#   the card's atlas rectangle (0..1, grass_medium_01 1k layout);  TEXCOORD_1 = (random per blade, thinness)
import bpy, bmesh, os, math, random
from mathutils import Vector, Matrix
from kit_build import Piece

# The vegetation generator source is external (not part of this repository). Point NML_KIT_VEG_SOURCE at it; the default
# is veg_kit.py next to this file.
VEG_SOURCE = os.environ.get("NML_KIT_VEG_SOURCE", os.path.join(os.path.dirname(os.path.abspath(__file__)), "veg_kit.py"))
ALBEDO_SCALE = 0.14
CARD_RECTS = [(190, 765, 322, 140), (590, 770, 250, 115), (25, 890, 175, 122), (250, 900, 260, 112), (585, 885, 200, 127)]
_ns = {}


def gen():
    """The external generators (VPiece, grass, moss, nettle, dead_stalks), read from their source without running main()."""
    if not _ns:
        src = open(VEG_SOURCE).read()
        src = src[:src.rindex("\nmain()")]
        _ns["__name__"] = "veg_kit_src"
        exec(compile(src, VEG_SOURCE, "exec"), _ns)
    return _ns


class VegPiece:
    """A kit module assembled from the external VPieces (their contact-halo faces dropped: ct_halo is no kit material)."""
    def __init__(self, name, card=False):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("UV2")
        self.col = self.bm.loops.layers.float_color.new("Color")
        self.mats = ["ct_veg"]
        self.parts, self.openings, self.normals = [], [], []
        self.shadow = []
        self.card = card
        self.count = 0
        # ct_veg is in the game: usable; the card modules name the material's `card` variant (a `variant` per module,
        # no `veg.card`).
        self.entry_after = {"stub": False, **({"variant": "card"} if card else {}),
                            "veg": {"albedo_scale": 1.0 if card else ALBEDO_SCALE, "uv": "atlas 0..1" if card else "u across, v along the blade",
                                    "uv2": "x = random per blade, y = thinness", "normals": "bent, smooth", "color_a": "ambient occlusion"}}

    def add(self, V, N, UV, UV2, C, F, xf=None, s=1.0):
        used = sorted({i for f in F for i in f})
        rot = xf.to_3x3() if xf is not None else None
        bv = {}
        for i in used:
            co = Vector(V[i]) * s
            n = Vector(N[i])
            if xf is not None:
                co = xf @ co; n = rot @ n
            bv[i] = self.bm.verts.new(co)
            self.normals.append(tuple(n.normalized()))
        for f in F:
            try:
                bf = self.bm.faces.new([bv[i] for i in f])
            except ValueError:
                continue
            for loop, i in zip(bf.loops, f):
                loop[self.uv].uv = UV[i]; loop[self.uv2].uv = UV2[i]
                c = C[i]
                k = 0.5 if self.card else 0.5 / ALBEDO_SCALE
                loop[self.col] = (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k), c[3])
        self.count += 1

    def put(self, P, x=0.0, y=0.0, yaw=0.0, s=1.0, z=0.0):
        F = [f for f, m in zip(P.F, P.FM) if m == 0]
        self.add(P.V, P.N, P.UV, P.UV2, P.C, F, Matrix.Translation((x, y, z)) @ Matrix.Rotation(yaw, 4, "Z"), s)

    def measure(self, mount):
        return Piece.measure(self, mount)

    def done(self):
        top = max(v.co.z for v in self.bm.verts)
        if top > 0.39:
            raise SystemExit(f"{self.name}: vegetation {top:.3f} in high (> 0.39)")
        self.entry = {"height_in": 0.4}
        return self


def card(seed, variant, hgt):
    """The card mesh: three quads crossed through the root + two smaller ones set off it, each leaning
    out at the top. Returns VPiece-like lists (Blender axes: Z up)."""
    r = random.Random(900 + seed)
    rx, ry, rw, rh = CARD_RECTS[variant % 5]
    wid = min(hgt * rw / rh * 0.8, 0.42)
    V, N, UV, UV2, C, F = [], [], [], [], [], []
    for k in range(5):
        a = math.pi * k / 3.0 + r.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), 0.0)); nr = Vector((-d.y, d.x, 0.0))
        sc = 1.0 if k < 3 else r.uniform(0.5, 0.7)
        off = Vector((0, 0, 0)) if k < 3 else nr * wid * 0.22 * (1.0 if k == 3 else -1.0)
        tilt = r.uniform(0.15, 0.4) * (1.0 if k % 2 == 0 else -1.0)
        base = len(V)
        for cu, cv in ((-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)):
            V.append(tuple(off + d * (wid * sc * cu) + Vector((0, 0, -0.012 + hgt * sc * cv)) + nr * (hgt * tilt * cv)))
            N.append(tuple((Vector((0, 0, 0.7)) + d * (cu * 0.9) + nr * tilt).normalized()))
            UV.append(((rx + rw * (cu + 0.5)) / 1024.0, 1.0 - (ry + rh * (1.0 - cv)) / 1024.0))   # (glTF flips v on export)
            UV2.append((0.5, 0.0)); C.append((1.0, 1.0, 1.0, 0.3 + 0.7 * cv))
        F.append((base, base + 1, base + 2, base + 3))
    return V, N, UV, UV2, C, F


W = (0.008, 0.015)
GRASS = {"tuft": (101, 22, 0.05, (0.15, 0.3), (0.1, 0.55), (0.3, 1.0), W, dict(long_share=0.55)),
         "tussock": (107, 28, 0.085, (0.14, 0.29), (0.15, 0.9), (0.3, 1.1), W, dict(long_share=0.3, flat_n=3, broken_n=3)),
         "stubble": (106, 14, 0.05, (0.05, 0.11), (0.1, 0.7), (0.2, 0.8), (0.009, 0.015), dict(long_share=0.0, flat_n=1, broken_n=0)),
         "trodden": (105, 17, 0.07, (0.11, 0.22), (1.1, 1.45), (0.0, 0.3), W, dict(long_share=0.3, flat_n=6, broken_n=3)),
         "wisp": (103, 12, 0.04, (0.2, 0.3), (0.05, 0.4), (0.4, 1.2), (0.007, 0.012), dict(long_share=0.9, seed_stalks=2, flat_n=1))}
MOSS = {"cushion": (111, [(0.0, 0.0, 0.12, 0.1, 0.3, 0.016)]),
        "strip": (112, [(0.0, 0.0, 0.2, 0.055, 0.0, 0.012), (0.17, 0.05, 0.06, 0.05, 0.5, 0.01)]),
        "cluster": (113, [(-0.08, 0.02, 0.07, 0.06, 0.2, 0.012), (0.06, -0.05, 0.085, 0.06, 1.1, 0.014), (0.07, 0.09, 0.05, 0.05, 0.0, 0.01)]),
        "mat": (114, [(0.0, 0.0, 0.3, 0.26, 0.4, 0.0)])}


def src(kind, seed_off=0):
    g = gen()
    if kind in GRASS:
        sd, n, rad, ln, le, be, w, kw = GRASS[kind]
        return g["grass"]("x", sd + seed_off, n, rad, ln, le, be, w, **kw)
    if kind in MOSS:
        return g["moss"]("x", MOSS[kind][0] + seed_off, MOSS[kind][1])
    if kind == "nettle":
        return g["nettle"]("x", 122 + seed_off)
    return g["dead_stalks"]("x", 123 + seed_off)


def single(name, kind):
    p = VegPiece(name)
    p.put(src(kind))
    return p.done()


def card_tuft(name, seed, variant, hgt):
    p = VegPiece(name, card=True)
    p.add(*card(seed, variant, hgt))
    return p.done()


def scatter(p, r, kinds, spots, smin=0.85, smax=1.2, satellites=("stubble", "cushion")):
    """Grown: every parent brings 0-3 smaller satellites within 0.25 in (short stubble, or moss)."""
    for k, (x, y) in enumerate(spots):
        kind = r.choice(kinds)
        p.put(src(kind, k), x, y, r.uniform(0, 6.28), r.uniform(smin, smax))
        for j in range(r.choice((0, 1, 1, 2, 3))):
            a = r.uniform(0, 6.28); d = r.uniform(0.12, 0.25)
            p.put(src(r.choice(satellites), 10 * k + j), x + d * math.cos(a), y + d * math.sin(a), r.uniform(0, 6.28), r.uniform(0.6, 0.9))


def plot(name, seed, variant):
    """A garden-plot cell overgrown (replaces dr_plot_weeds_a / _b once the vegetation material exists): parents drawn to the
    edges, a trodden bare patch, satellites round each. a = rank grass; b = nettles and dead stalks with grass under them."""
    from kit_k4 import _spots
    r = random.Random(seed)
    p = VegPiece(name, card=(variant == "a"))
    bare = (r.uniform(1.1, 1.9), r.uniform(1.1, 1.9), 0.6)
    if variant == "a":   # CARDS only (one material per module): 14 parents, each with 0-3 smaller tufts beside it
        for k, (x, y) in enumerate(_spots(r, 14, 0.4, 2.6, 0.38, 0.7, [bare])):
            fam = [(x, y, r.uniform(0.14, 0.22))] + [(x + r.uniform(-0.22, 0.22), y + r.uniform(-0.22, 0.22), r.uniform(0.07, 0.12)) for _ in range(r.choice((0, 1, 2, 3)))]
            for j, (cx, cy, h) in enumerate(fam):
                V, N, UV, UV2, C, F = card(seed * 100 + k * 7 + j, r.randrange(5), h)
                p.add(V, N, UV, UV2, C, F, Matrix.Translation((cx, cy, 0.0)) @ Matrix.Rotation(r.uniform(0, 6.28), 4, "Z"))
    else:
        scatter(p, r, ("nettle", "nettle", "dead", "nettle"), _spots(r, 4, 0.5, 2.5, 0.55, 0.6, [bare]), satellites=("stubble",))
    return p.done()


def foot_run(name, seed, variant):
    """Growth along 3 in of a wall foot (origin = the face's left foot, growth in FRONT of the wall: 0.03-0.45 in out).
    a = FLAT (moss strips and cushions in the angle, <= 0.02 in): legal on any walkable ground. b = soft growth to 0.3 in
    (stubble, a tuft, dead stalks, nettles) - above FLAT: needs the rules' word that soft vegetation is no obstacle."""
    r = random.Random(seed)
    p = VegPiece(name)
    x = 0.2
    while x < 2.85:
        if variant == "a":
            kind = r.choice(("strip", "strip", "cushion", "cluster"))
            p.put(src(kind, int(x * 10)), x, -r.uniform(0.07, 0.2), r.uniform(-0.3, 0.3) if kind == "strip" else r.uniform(0, 6.28), r.uniform(0.8, 1.2))
            x += r.uniform(0.3, 0.6)
        else:
            kind = r.choice(("stubble", "stubble", "dead", "tuft", "nettle", "strip"))
            p.put(src(kind, int(x * 10)), x + 0.15, -r.uniform(0.22, 0.36), r.uniform(0, 6.28), r.uniform(0.8, 1.05))
            x += r.uniform(0.45, 0.8)
            if x > 2.55:
                break
    if variant == "a":
        p.entry_tags = True
    return p.done()


def rim(name, seed):
    """Growth round a puddle: an arc (200 deg of a 0.6 in ring) of short stubble, moss and one wisp; centred on the puddle."""
    r = random.Random(seed)
    p = VegPiece(name)
    a = 0.4
    while a < 3.9:
        rad = r.uniform(0.5, 0.68)
        kind = r.choice(("stubble", "stubble", "cushion", "cluster", "wisp"))
        p.put(src(kind, int(a * 10)), rad * math.cos(a), rad * math.sin(a), r.uniform(0, 6.28), r.uniform(0.7, 1.0))
        a += r.uniform(0.4, 0.7)
    return p.done()


def builders():
    B = [("dr_veg_grass_" + k, lambda k=k: single("dr_veg_grass_" + k, k)) for k in ("tuft", "tussock", "stubble", "trodden")]
    B += [("dr_veg_card_" + v, lambda v=v, i=i, h=h: card_tuft("dr_veg_card_" + v, i, i, h)) for i, (v, h) in enumerate((("a", 0.22), ("b", 0.16), ("c", 0.12)))]
    B += [("dr_veg_moss_" + k, lambda k=k: single("dr_veg_moss_" + k, k)) for k in ("cushion", "strip", "cluster", "mat")]
    B += [("dr_veg_nettle", lambda: single("dr_veg_nettle", "nettle")), ("dr_veg_dead_stalks", lambda: single("dr_veg_dead_stalks", "dead")),
          ("dr_veg_plot_a", lambda: plot("dr_veg_plot_a", 611, "a")), ("dr_veg_plot_b", lambda: plot("dr_veg_plot_b", 612, "b")),
          ("dr_veg_foot_run_a", lambda: foot_run("dr_veg_foot_run_a", 621, "a")), ("dr_veg_foot_run_b", lambda: foot_run("dr_veg_foot_run_b", 622, "b")),
          ("dr_veg_rim_a", lambda: rim("dr_veg_rim_a", 631))]
    return B


def red_proofs(check_kit, T):
    rc = {"entry": T["dr_veg_nettle"], "parts": [], "openings": [], "materials": [], "tris": 1, "aabb_in": [[-0.2, 0.0, -0.2], [0.2, 0.51, 0.2]],
          "proud_in": {"flat": 0.0, "low": 0.0, "high": 0.0}}
    errs = [e for e in check_kit.check_piece(rc) if e.startswith("HEIGHT")]
    if not errs:
        raise SystemExit("RED_PROOF_BROKEN: the HEIGHT check passed vegetation 0.51 in high")
    print("RED_PROOF HEIGHT check fails as required (vegetation 0.51 in, an earlier fault):", errs[0])
