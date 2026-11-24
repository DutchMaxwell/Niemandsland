# kit_build.py - the Blender builders of the ruin-town dressing kit (the house set, 25 modules).
# The kit conventions: inches UV (TEXCOORD_0 in inches, origins on course lines), no images, COLOR_0 = tint x 0.5
# (+ grime / moss mask in alpha), measured proud / aabb / shadow, declared openings, honest heights.
# Blender axes while building: X along the face, Y INTO the mass (-Y = out = glTF / Godot +Z), Z up; 1 unit = 1 inch.
import bpy, bmesh, os, sys, math, random, json, struct
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_table, check_kit

IN = 0.0254
MATS = kit_table.MATERIALS
BODY = kit_table.BODY          # 2.5: the house body = the collider height
RIDGE_MAX = 2.0                # local top of every roof / gable / chimney: 2.5 + 2.0 = 4.5 (the core's HOUSE_TOP_IN)
PLINTH = 0.5                   # one stone course (ct_stone course_in 0.5)
PANEL_T = 0.3


def course(mat):
    return MATS.get(mat, {}).get("course_in") or 0.0


def stone(mat):
    return MATS.get(mat, {}).get("stone_in") or 0.0


class Piece:
    """One module: a bmesh with named material slots, inches UV, a vertex colour per corner, and a record of its solid
    parts (material, AABB, fill flag) for the openings check."""

    def __init__(self, name, seed, cull_back=None):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Color")
        self.mats = []
        self.rng = random.Random(seed)
        self.uv_off = {}
        self.shade = None
        self.parts = []
        self.cull_back = cull_back   # y of the back plane: faces looking +Y at or behind it are dropped (inside the mass)
        self.cull_ends = None        # (0, len): end faces of a face module are dropped - a neighbour, a quoin or the other mass
                                     # covers them, and left in they are coplanar with the perpendicular face at a corner (dark slits)
        self.cull_top = None         # z of the module top: faces looking up there are dropped (the generated top quad covers them)

    def mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
            c, s = course(name), stone(name)   # the UV origin sits on a course line / stone joint: whole courses only
            self.uv_off[name] = ((self.rng.randrange(8) * s) if s else 0.0, (self.rng.randrange(8) * c) if c else 0.0)
        return self.mats.index(name)

    def _record(self, vs, mat, fill):
        xs = [v[0] for v in vs]; ys = [v[1] for v in vs]; zs = [v[2] for v in vs]
        self.parts.append({"mat": mat, "lo": (min(xs), min(ys), min(zs)), "hi": (max(xs), max(ys), max(zs)), "fill": fill})

    def poly(self, vs, mat, grain=None, tint=(1, 1, 1), fill=False, cull=True, uvo=None, keep_bottom=False):
        """A convex solid from 8 corners: v0..v3 bottom ring, v4..v7 top ring (same order)."""
        self._record(vs, mat, fill)
        bv = [self.bm.verts.new(v) for v in vs]
        quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        faces = []
        for q in quads:
            try:
                faces.append(self.bm.faces.new([bv[i] for i in q]))
            except ValueError:
                continue
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        if cull:
            keep = []
            for f in faces:
                f.normal_update()
                c = f.calc_center_median()
                back = self.cull_back is not None and f.normal.y > 0.99 and c.y >= self.cull_back - 1e-3
                floor = (not keep_bottom) and f.normal.z < -0.99 and abs(c.z) < 1e-3
                top = self.cull_top is not None and f.normal.z > 0.99 and c.z >= self.cull_top - 1e-3
                ends = self.cull_ends is not None and abs(f.normal.x) > 0.99 and min(abs(c.x - e) for e in self.cull_ends) < 1e-3
                if back or floor or top or ends:
                    self.bm.faces.remove(f)
                else:
                    keep.append(f)
            faces = keep
        self._finish(faces, mat, grain, tint, uvo)
        return faces

    def box(self, lo, hi, mat, grain=None, tint=(1, 1, 1), fill=False, cull=True):
        x0, y0, z0 = lo; x1, y1, z1 = hi
        return self.poly([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                          (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], mat, grain, tint, fill, cull)

    def beam(self, a, b, w, d, mat, out=Vector((0, -1, 0)), tint=(1, 1, 1), fill=False):
        a = Vector(a); b = Vector(b)
        ax = (b - a).normalized()
        side = ax.cross(out).normalized() * (w * 0.5)
        o = out.normalized() * d
        vs = [a - side, a + side, a + side + o, a - side + o, b - side, b + side, b + side + o, b - side + o]
        faces = self.poly([tuple(v) for v in vs], mat, grain=ax, tint=tint, fill=fill)
        self.parts[-1]["seg"] = ((a.x, a.z), (b.x, b.z), w)   # the openings check tests the real (diagonal) member
        return faces

    def flat(self, pts, mat, tint=(1, 1, 1), normal=Vector((0, -1, 0)), fill=False):
        """One flat convex face (a plaster patch, a pane, a daub field); wound to face `normal`."""
        self._record(pts, mat, fill)
        bv = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(bv)
        f.normal_update()
        if f.normal.dot(normal) < 0:
            f.normal_flip()
        self._finish([f], mat, None, tint, None)
        return [f]

    def prism(self, pts2d, y0, y1, mat, tint=(1, 1, 1), back=False):
        """A convex polygon in the XZ plane, extruded from y0 (front) to y1; the back face only when back=True."""
        self._record([(x, y0, z) for x, z in pts2d] + [(x, y1, z) for x, z in pts2d], mat, False)
        a = [self.bm.verts.new((x, y0, z)) for x, z in pts2d]
        b = [self.bm.verts.new((x, y1, z)) for x, z in pts2d]
        faces = [self.bm.faces.new(a)]
        if back:
            faces.append(self.bm.faces.new(list(reversed(b))))
        n = len(pts2d)
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new([a[i], b[i], b[j], a[j]]))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        if not back:   # recalc can fail on an open shell: force the front to look -Y and the rims outward
            for f in faces:
                f.normal_update()
            if faces[0].normal.y > 0:
                for f in faces:
                    f.normal_flip()
        self._finish(faces, mat, None, tint, None)
        return faces

    def _finish(self, faces, mat, grain, tint, uvo):
        mi = self.mat(mat)
        ou, ov = self.uv_off[mat]
        up = Vector((0, 0, 1))
        o = Vector(uvo) if uvo is not None else Vector((0, 0, 0))
        for f in faces:
            f.material_index = mi
            f.normal_update()
            n = f.normal
            if grain is not None:
                g = Vector(grain)
                vdir = g - n * g.dot(n)
                if vdir.length < 1e-4:
                    vdir = up - n * up.dot(n)
                    if vdir.length < 1e-4:
                        vdir = Vector((1, 0, 0))
                vdir.normalize()
                udir = vdir.cross(n).normalized()
            elif abs(n.z) > 0.95:
                udir = Vector((1, 0, 0)); vdir = Vector((0, 1, 0))
            else:
                udir = up.cross(n).normalized()
                vdir = n.cross(udir).normalized()
            for loop in f.loops:
                p = loop.vert.co
                loop[self.uv].uv = ((p - o).dot(udir) + ou, (p - o).dot(vdir) + ov)   # INCHES (the shader divides by tile_in)
                s = self.shade(p, mat) if self.shade else (1, 1, 1, 0.3)
                a = s[3] if len(s) > 3 else 0.3
                # COLOR_0 = tint x 0.5 (the shader multiplies by 2), alpha = grime / moss mask
                loop[self.col] = tuple(max(0.0, min(1.0, 0.5 * tint[i] * s[i])) for i in range(3)) + (max(0.0, min(1.0, a)),)

    def sag_apply(self, length, depth):
        for v in self.bm.verts:
            if length > 0:
                v.co.z -= depth * math.sin(math.pi * max(0.0, min(1.0, v.co.x / length))) * max(0.0, min(1.0, (v.co.z + 0.3) / 2.3))

    # ------------------------------------------------------------------ measuring (Godot axes: gx = x, gy = z, gz = -y)
    def measure(self, mount):
        vs = [(v.co.x, v.co.z, -v.co.y) for v in self.bm.verts]
        lo = [min(v[i] for v in vs) for i in range(3)]
        hi = [max(v[i] for v in vs) for i in range(3)]
        bands = {"flat": 0.0, "low": 0.0, "high": 0.0}
        for x, y, z in vs:
            wy = mount + y
            b = "flat" if wy <= kit_table.FLAT + 1e-4 else "low" if wy < kit_table.CLEAR else "high"
            bands[b] = max(bands[b], z)
        tris = sum(len(f.verts) - 2 for f in self.bm.faces)
        return {"aabb_in": [[round(c, 3) for c in lo], [round(c, 3) for c in hi]],
                "proud_in": {k: round(v, 3) for k, v in bands.items()}, "tris": tris}


def peel_patches(p, rect, holes, cover, rng, y, tint, xs=None, zs=None, clip=None):
    """Plaster laid in irregular sheets over a dark daub: the rect is cut into cells (cuts at xs / zs plus the hole edges),
    each cell is a jittered convex hexagon inset by a crack; `cover` = the share of cells still plastered. Cells inside a
    hole (an opening) are skipped. clip = an optional convex polygon (x, z) the cells are clipped to (a gable triangle)."""
    x0, x1, z0, z1 = rect
    xs = sorted(set([x0, x1] + (xs or []) + [h[0] for h in holes] + [h[1] for h in holes]))
    zs = sorted(set([z0, z1] + (zs or []) + [h[2] for h in holes] + [h[3] for h in holes]))
    xs = [x for x in xs if x0 - 1e-6 <= x <= x1 + 1e-6]
    zs = [z for z in zs if z0 - 1e-6 <= z <= z1 + 1e-6]
    peeled = []
    for i in range(len(xs) - 1):
        for k in range(len(zs) - 1):
            a, b, c, d = xs[i], xs[i + 1], zs[k], zs[k + 1]
            if b - a < 0.06 or d - c < 0.06:
                continue
            mx, mz = (a + b) / 2, (c + d) / 2
            if any(h[0] - 1e-6 <= mx <= h[1] + 1e-6 and h[2] - 1e-6 <= mz <= h[3] + 1e-6 for h in holes):
                continue
            if rng.random() > cover:
                peeled.append((a, b, c, d))
                continue
            g = 0.012 + rng.random() * 0.02   # the crack
            pts = [(a + g + rng.uniform(0, 0.04), c + g), (b - g - rng.uniform(0, 0.04), c + g),
                   (b - g, mz + rng.uniform(-0.08, 0.08)), (b - g - rng.uniform(0, 0.05), d - g),
                   (a + g + rng.uniform(0, 0.05), d - g), (a + g, mz + rng.uniform(-0.08, 0.08))]
            if clip:
                pts = clip_poly(pts, clip)
                if len(pts) < 3:
                    continue
            t = 0.72 + rng.random() * 0.3                      # sheet by sheet: some stained grey-brown, some damp-dark
            st = rng.choice(((1.0, 1.0, 1.0), (0.92, 0.9, 0.86), (0.85, 0.82, 0.74), (0.95, 0.88, 0.78)))
            p.flat([(u, y, v) for u, v in pts], "ct_plaster", tint=(tint[0] * t * st[0], tint[1] * t * st[1], tint[2] * t * st[2]))
    return peeled


def clip_poly(pts, clip):
    """Sutherland-Hodgman: a polygon clipped by a convex counter-clockwise polygon (both (x, z))."""
    out = pts
    n = len(clip)
    for i in range(n):
        ax, az = clip[i]; bx, bz = clip[(i + 1) % n]
        inside = lambda q: (bx - ax) * (q[1] - az) - (bz - az) * (q[0] - ax) >= 0
        src, out = out, []
        for j in range(len(src)):
            c, d = src[j], src[(j + 1) % len(src)]
            ic, id_ = inside(c), inside(d)
            if ic:
                out.append(c)
            if ic != id_:
                dx, dz = d[0] - c[0], d[1] - c[1]
                den = (bx - ax) * dz - (bz - az) * dx
                if abs(den) > 1e-9:
                    t = ((ax - c[0]) * (bz - az) - (az - c[1]) * (bx - ax)) / -den
                    out.append((c[0] + dx * t, c[1] + dz * t))
        if not out:
            return []
    return out


# ------------------------------------------------------------------ shading (vertex colour): gloomy and dirty by default
def house_shade(soot=None, damp=True):
    def f(q, m):
        if m in ("ct_stone", "ct_stone_big", "ct_stone_fine"):
            r, g, b = 0.6, 0.63, 0.7
        elif m == "ct_plaster":   # not cream-clean: grey-ochre, a grime streak under the plate, a dirty splash foot to 1.2 in
            streak = 0.55 + 0.45 * min(1.0, max(0.0, (2.4 - q.z) / 0.6))
            foot = 0.6 + 0.4 * min(1.0, max(0.0, (q.z - 0.5) / 0.7))
            r, g, b = 0.74 * streak * foot, 0.68 * streak * foot, 0.57 * streak * foot
        elif m == "ct_timber":
            r, g, b = 0.72, 0.68, 0.64
        else:
            r, g, b = 1.0, 1.0, 1.0
        dmp = (0.55 + 0.45 * min(1.0, max(0.0, q.z / 0.9))) if damp else 1.0   # the wet foot (single-band modules only)
        moss = max(0.0, 1.0 - q.z / 0.9) * 0.85 if damp else 0.0
        grime = 0.3 + moss + (0.25 * max(0.0, 1.0 - (q.z - 0.5) / 0.7) + 0.15 if m == "ct_plaster" else 0.0)
        if soot is not None:
            x0, x1, z1 = soot
            if x0 - 0.2 <= q.x <= x1 + 0.2 and q.z >= z1 - 0.01:
                k = 0.5 * max(0.0, 1.0 - (q.z - z1) / 0.8)
                r, g, b = r * (1 - k), g * (1 - k), b * (1 - k * 0.9)
                grime = max(grime, 0.3 + k)
        return (r * dmp, g * dmp, b * dmp, min(1.0, grime))
    return f


# ------------------------------------------------------------------ timber-framed house panels (3.0 x 2.5)
def tb_panel(name, seed, kind="plain_a", width=3.0, sill_across=False):
    """A half-timber panel: a stone plinth course, a dark daub field, plaster laid on it in cracked / peeling sheets, oak
    frame proud of the plaster. kind = plain_a | plain_b (fallen plaster, lath) | window | window_lit | door | blank.
    sill_across=True rebuilds the first door panel (sill beam across the door): the openings check's red proof."""
    p = Piece(name, seed, cull_back=PANEL_T)
    p.cull_ends = (0.0, width)
    r = p.rng
    out = Vector((0, -1, 0))
    bt = 0.11
    door = (1.1, 1.85, 0.0, 1.72) if kind == "door" else None
    win = (0.95, 2.05, 1.12, 1.88) if kind.startswith("window") else None
    hole = door or win
    p.shade = house_shade(soot=(hole[0], hole[1], hole[3]) if hole else None)
    # the plinth (one stone course; broken by a door), the door step is FLAT (<= 0.07 high)
    if door:
        p.box((0, -0.04, 0), (door[0], PANEL_T, PLINTH), "ct_stone")
        p.box((door[1], -0.04, 0), (width, PANEL_T, PLINTH), "ct_stone")
        p.box((door[0] - 0.05, -0.2, 0), (door[1] + 0.05, 0.17, 0.07), "ct_stone", tint=(0.8, 0.8, 0.8), fill=True)
    else:
        p.box((0, -0.04, 0), (width, PANEL_T, PLINTH), "ct_stone")
    # the daub field behind the plaster (dark brown mud), cut round the opening
    dk = (0.55, 0.44, 0.33)
    fields = [(0, width, PLINTH, BODY)] if not hole else [
        (0, hole[0], PLINTH, BODY), (hole[1], width, PLINTH, BODY), (hole[0], hole[1], hole[3], BODY)] + (
        [(hole[0], hole[1], PLINTH, hole[2])] if hole[2] > PLINTH else [])
    for a, b, c, d in fields:
        p.flat([(a, 0.03, c), (b, 0.03, c), (b, 0.03, d), (a, 0.03, d)], "ct_plaster", tint=dk)
    cover = {"plain_a": 0.78, "plain_b": 0.5, "window": 0.8, "window_lit": 0.8, "door": 0.78, "blank": 0.72}[kind]
    holes = [(hole[0] - 0.02, hole[1] + 0.02, hole[2], hole[3])] if hole else []
    pt = (1.0 + r.uniform(-0.05, 0.02), 0.96 + r.uniform(-0.05, 0.03), 0.86 + r.uniform(-0.05, 0.04))
    peeled = peel_patches(p, (0, width, PLINTH + 0.1, BODY - 0.1), holes, cover, r, 0.02, pt,
                          xs=[0.75, 1.5, 2.25], zs=[1.0, 1.47, 2.0])
    if kind in ("plain_b", "plain_a", "blank"):   # where the plaster fell: the lath shows on the biggest bare cells
        peeled.sort(key=lambda c: -(c[1] - c[0]) * (c[3] - c[2]))
        for a, b, c, d in peeled[:2 if kind == "plain_b" else 1]:
            zz = c + 0.06
            while zz < d - 0.06:
                p.box((a + 0.03, 0.0, zz), (b - 0.03, 0.03, zz + 0.04), "ct_timber", grain=(1, 0, 0), tint=(1.1, 1.0, 0.9))
                zz += 0.11
    if door:
        p.box((door[0], 0.17, 0.07), (door[1], PANEL_T, 1.72), "ct_timber", grain=(0, 0, 1), tint=(0.9, 0.82, 0.72), fill=True)  # the leaf
        p.box((door[0] + 0.05, 0.14, 0.55), (door[1] - 0.05, 0.17, 0.65), "ct_timber", grain=(1, 0, 0), fill=True)   # ledges
        p.box((door[0] + 0.05, 0.14, 1.25), (door[1] - 0.05, 0.17, 1.35), "ct_timber", grain=(1, 0, 0), fill=True)
        p.box((door[0] - 0.06, 0.0, 0.07), (door[0], PANEL_T, 1.72), "ct_stone")   # the reveals (outside the opening)
        p.box((door[1], 0.0, 0.07), (door[1] + 0.06, PANEL_T, 1.72), "ct_stone")
        p.box((door[0], 0.0, 1.72), (door[1], 0.17, 1.76), "ct_timber", grain=(1, 0, 0))   # the head lining (on the opening edge)
        p.beam((door[0] - 0.12, 0, 1.79), (door[1] + 0.12, 0, 1.79), 0.13, 0.06, "ct_timber", out)   # the lintel
        p.beam((door[0] - 0.05, 0, PLINTH), (door[0] - 0.05, 0, 1.72), bt, 0.05, "ct_timber", out)
        p.beam((door[1] + 0.05, 0, PLINTH), (door[1] + 0.05, 0, 1.72), bt, 0.05, "ct_timber", out)
    elif win:
        x0, x1, z0, z1 = win
        lit = kind == "window_lit"
        p.flat([(x0, 0.2, z0), (x1, 0.2, z0), (x1, 0.2, z1), (x0, 0.2, z1)], "ct_glass_lit" if lit else "ct_glass_dark", fill=True)
        xm, zm = (x0 + x1) * 0.5, (z0 + z1) * 0.5
        p.box((xm - 0.025, 0.12, z0), (xm + 0.025, 0.2, z1), "ct_timber", grain=(0, 0, 1), fill=True)   # mullion (glazing bar)
        p.box((x0, 0.12, zm - 0.02), (x1, 0.2, zm + 0.02), "ct_timber", grain=(1, 0, 0), fill=True)     # transom (glazing bar)
        p.box((x0 - 0.08, -0.1, z0 - 0.07), (x1 + 0.08, 0.1, z0), "ct_timber", grain=(1, 0, 0))   # the sill board (below the opening)
        p.box((x0, 0.03, z0), (x0 + 0.03, 0.2, z1), "ct_timber"); p.box((x1 - 0.03, 0.03, z0), (x1, 0.2, z1), "ct_timber")
        p.box((x0, 0.03, z1 - 0.03), (x1, 0.2, z1), "ct_timber")   # the linings (on the opening edges, 0.03 in)
        sw = (x1 - x0) * 0.5   # shutters swung open against the wall (one hangs crooked), never in front of the opening
        p.box((x0 - sw - 0.04, -0.1, z0 + 0.02), (x0 - 0.04, -0.06, z1 - 0.02), "ct_timber", grain=(0, 0, 1), tint=(0.95, 0.85, 0.75))
        a = math.radians(r.uniform(-7, 7))
        cx, cz = x1 + 0.04 + sw * 0.5 + 0.02, zm
        hw, hh = sw * 0.5, (z1 - z0) * 0.5 - 0.04
        rot = lambda dx, dz: (cx + dx * math.cos(a) - dz * math.sin(a), cz + dx * math.sin(a) + dz * math.cos(a))
        pts = [rot(-hw, -hh), rot(hw, -hh), rot(hw, hh), rot(-hw, hh)]
        p.poly([(u, -0.1, v) for u, v in pts] + [(u, -0.06, v) for u, v in pts], "ct_timber", grain=(0, 0, 1), tint=(0.95, 0.85, 0.75))
        p.beam((x0 - 0.055, 0, PLINTH), (x0 - 0.055, 0, BODY), bt, 0.05, "ct_timber", out)
        p.beam((x1 + 0.055, 0, PLINTH), (x1 + 0.055, 0, BODY), bt, 0.05, "ct_timber", out)
    elif kind != "blank":
        p.beam((1.5, 0, PLINTH), (1.5, 0, BODY), bt, 0.05, "ct_timber", out)
        if kind == "plain_a":   # a St Andrew's cross under the rail and a down-brace in the upper right bay
            p.beam((0.12, 0, PLINTH + 0.08), (1.44, 0, 1.42), 0.1, 0.045, "ct_timber", out)
            p.beam((1.44, 0, PLINTH + 0.08), (0.12, 0, 1.42), 0.1, 0.045, "ct_timber", out)
            p.beam((1.56, 0, 1.52), (2.88, 0, BODY - 0.1), 0.1, 0.045, "ct_timber", out)
        else:                   # plain_b: two plain down-braces, the bays left open for the fallen plaster
            p.beam((0.12, 0, 1.52), (1.44, 0, BODY - 0.1), 0.1, 0.045, "ct_timber", out)
            p.beam((2.88, 0, PLINTH + 0.08), (1.56, 0, 1.42), 0.1, 0.045, "ct_timber", out)
    # the frame: sill beam, rail, top plate (a slight sag), the half posts at both ends (two panels form one post)
    sag = 0.0   # (a sag would break the tiling of the rails / top plate between neighbours; leaning is the planner's)
    if door and not sill_across:   # the sill beam stops at the door posts
        p.beam((0, 0, PLINTH + 0.07), (door[0] - 0.11, 0, PLINTH + 0.07), 0.13, 0.06, "ct_timber", out)
        p.beam((door[1] + 0.11, 0, PLINTH + 0.07), (width, 0, PLINTH + 0.07), 0.13, 0.06, "ct_timber", out)
    else:
        p.beam((0, 0, PLINTH + 0.07), (width, 0, PLINTH + 0.07), 0.13, 0.06, "ct_timber", out)
    # (the end faces of sill, posts and plate do not overlap at x = 0 / width: no coplanar flicker; the rails start inside the posts)
    if hole:
        p.beam((0.12, 0, 1.47), (hole[0] - 0.11, 0, 1.47), 0.09, 0.05, "ct_timber", out)
        p.beam((hole[1] + 0.11, 0, 1.47 - sag), (width - 0.12, 0, 1.47 - sag), 0.09, 0.05, "ct_timber", out)
    else:
        p.beam((0.12, 0, 1.47), (width - 0.12, 0, 1.47 - sag), 0.09, 0.05, "ct_timber", out)
    p.beam((0, 0, BODY - 0.07), (width, 0, BODY - 0.07 - sag), 0.14, 0.07, "ct_timber", out)
    p.beam((0.06, 0, PLINTH + 0.135), (0.06, 0, BODY - 0.14), 0.12, 0.06, "ct_timber", out)
    p.beam((width - 0.06, 0, PLINTH + 0.135), (width - 0.06, 0, BODY - 0.14), 0.12, 0.06, "ct_timber", out)
    p.openings = [[hole[0], hole[1], hole[2], hole[3]]] if hole else []
    return p


# ------------------------------------------------------------------ stone house panels (3.0 x 2.5), coursed 0.5 in
ST_T = 0.4


def st_panel(name, seed, kind="plain_a", width=3.0):
    """A coursed-stone house wall: five 0.5 in courses (each at its own small depth: the bond reads in relief), a few
    proud, missing and odd stones in GEOMETRY (the texture is sampled once), openings on course lines.
    plain_b = a peeling lime render over the stone."""
    p = Piece(name, seed, cull_back=ST_T)
    p.cull_ends = (0.0, width)
    r = p.rng
    win = (1.0, 2.0, 0.75, 1.875) if kind == "window" else None     # (on the 0.375 in course lines: 2..5 / 0..5 courses)
    door = (1.1, 1.9, 0.0, 1.875) if kind == "door" else None
    hole = win or door
    p.shade = house_shade(soot=(hole[0], hole[1], hole[3]) if hole else None)
    # Fine stone: NO course steps, proud / missing / odd stones on ct_stone_fine - the board-projected
    # rubble photo carries the stones; a geometry grid drew straight shadow lines through them. Flush wall, carved by the opening.
    if kind == "plain_b":   # weathered: a damp streak (vertex colour) below the eaves
        i0 = r.randrange(0, 4)
        base_shade = p.shade
        def streak(q, m, i0=i0):
            c = base_shade(q, m)
            k = max(0.0, 1.0 - abs(q.x - (i0 + 1.5) * 0.45) / 0.9) * 0.45
            return (c[0] * (1 - k), c[1] * (1 - k * 0.8), c[2] * (1 - k * 0.9), min(1.0, c[3] + k))
        p.shade = streak
    tint = (0.95, 0.95, 0.95)
    if hole:
        x0, x1, z0, z1 = hole
        if z0 > 1e-6:
            p.box((0.0, 0.0, 0.0), (width, ST_T, z0), "ct_stone_fine", tint=tint)
        p.box((0.0, 0.0, z0), (x0, ST_T, z1), "ct_stone_fine", tint=tint)
        p.box((x1, 0.0, z0), (width, ST_T, z1), "ct_stone_fine", tint=tint)
        p.box((0.0, 0.0, z1), (width, ST_T, BODY), "ct_stone_fine", tint=tint)
    else:
        p.box((0.0, 0.0, 0.0), (width, ST_T, BODY), "ct_stone_fine", tint=tint)
    C = course("ct_stone_fine")   # 0.375: the lintel stones stay one course high
    if kind == "plain_b":   # remnants of a lime render, peeling in sheets
        pass   # (the lime-render variant was dropped after review K1b: it read as cards / tiles; plain_b = weathered stone)
    if win:
        x0, x1, z0, z1 = win
        p.flat([(x0, 0.25, z0), (x1, 0.25, z0), (x1, 0.25, z1), (x0, 0.25, z1)], "ct_glass_dark", fill=True)
        xm = (x0 + x1) * 0.5
        p.box((xm - 0.03, 0.18, z0), (xm + 0.03, 0.25, z1), "ct_timber", grain=(0, 0, 1), fill=True)   # glazing bars
        p.box((x0, 0.18, (z0 + z1) * 0.5 - 0.025), (x1, 0.25, (z0 + z1) * 0.5 + 0.025), "ct_timber", grain=(1, 0, 0), fill=True)
        p.box((x0 - 0.06, -0.08, z0 - 0.08), (x1 + 0.06, 0.1, z0), "ct_stone_fine", tint=(1.05, 1.05, 1.05))   # the sill
        p.box((x0 - 0.1, -0.035, z1), (x1 + 0.1, 0.0, z1 + C), "ct_stone_fine", tint=(1.1, 1.08, 1.02))  # the lintel stone
    if door:
        x0, x1, z0, z1 = door
        p.box((x0, 0.22, 0.06), (x1, ST_T, z1), "ct_timber", grain=(0, 0, 1), tint=(0.85, 0.78, 0.7), fill=True)   # the leaf
        for zz in (0.5, 1.4):
            p.box((x0 + 0.04, 0.18, zz), (x1 - 0.04, 0.22, zz + 0.1), "ct_timber", grain=(1, 0, 0), fill=True)
        p.box((x0 - 0.05, -0.2, 0.0), (x1 + 0.05, 0.22, 0.06), "ct_stone_fine", tint=(0.8, 0.8, 0.8), fill=True)   # the step (flat)
        p.box((x0 - 0.12, -0.035, z1), (x1 + 0.12, 0.0, z1 + C), "ct_stone_fine", tint=(1.1, 1.08, 1.02))       # the lintel stone
    p.openings = [[hole[0], hole[1], hole[2], hole[3]]] if hole else []
    return p


def stone_render(p, r, taken, C, sw, NC, NS):
    """Remnants of an old lime render that FOLLOW THE STONES: two soft blobs on the stone grid (course x stone), a cell is
    rendered when it lies inside a blob with a jittered rim; runs of rendered cells per course become one patch whose ends
    stop at a stone joint +- a little (broken edges), dirty and uneven. Cells of proud / missing stones stay bare."""
    blobs = [(r.uniform(0.6, 1.4), r.uniform(1.4, 2.1), r.uniform(0.6, 0.9), r.uniform(0.35, 0.6)),
             (r.uniform(1.8, 2.5), r.uniform(0.9, 1.6), r.uniform(0.4, 0.7), r.uniform(0.3, 0.45))]
    for k in range(2, NC):
        for i in range(NS):
            if (k, i) in taken:
                continue
            cx, cz = (i + 0.5) * sw, (k + 0.5) * C
            if not any(((cx - bx) / rx) ** 2 + ((cz - bz) / rz) ** 2 < 1.0 + r.uniform(-0.5, 0.3) for bx, bz, rx, rz in blobs):
                continue
            j = lambda: r.uniform(-0.035, 0.035)   # the render breaks along the joints, never along a straight line
            x0, x1, z0, z1 = i * sw, (i + 1) * sw, k * C, (k + 1) * C
            t = 0.45 + r.random() * 0.2
            p.flat([(x0 + 0.01 + abs(j()), -0.058, z0 + abs(j())), (x1 - 0.01 - abs(j()), -0.058, z0 + abs(j())),
                    (x1 - abs(j()), -0.058, z1 - abs(j())), (x0 + abs(j()), -0.058, z1 - abs(j()))], "ct_plaster", tint=(t * 1.05, t, t * 0.86))


def tb_post(name, seed):
    """The corner post of a timber house, centred on the lot corner, on a stone pad."""
    p = Piece(name, seed)
    p.shade = house_shade()
    p.box((-0.08, -0.08, PLINTH), (0.08, 0.08, BODY), "ct_timber", grain=(0, 0, 1), tint=(0.9, 0.85, 0.8))
    p.box((-0.11, -0.11, 0), (0.11, 0.11, PLINTH), "ct_stone", tint=(0.7, 0.72, 0.78))
    p.openings = []
    return p


def st_quoin(name, seed):
    """Dressed corner stones, long and short by course, at the start corner of a face (mass along +x and +y)."""
    p = Piece(name, seed)
    p.shade = house_shade()
    r = p.rng
    C2 = 2 * course("ct_stone_fine")   # dressed corner stones two courses high (0.75 in), the last one the part course
    for k in range(4):
        z0, z1 = k * C2 + 0.01, min((k + 1) * C2, BODY) - 0.01
        t = 1.05 + r.random() * 0.1
        if k % 2 == 0:
            p.box((-0.05, -0.05, z0), (0.5, 0.3, z1), "ct_stone_fine", tint=(t, t, t * 0.97))
        else:
            p.box((-0.05, -0.05, z0), (0.3, 0.5, z1), "ct_stone_fine", tint=(t, t, t * 0.97))
    p.openings = []
    return p


# ------------------------------------------------------------------ gables (on the end face, origin at the eaves line)
def roof_rise_u(span):
    """The underside line of the roof slab at the ridge (local), so the gable top sits under the slates."""
    return RIDGE_MAX - 0.28


def tb_gable(name, seed, span=6.0, variant="a"):
    """A jettied (0.12 in proud) half-timber gable triangle under the roof underside: bressumer on joist ends, king post,
    raking beams, braces clear of the attic window; variant b: no window, more fallen plaster, a louvred vent."""
    p = Piece(name, seed, cull_back=None)
    r = p.rng
    j = -0.12
    h = span * 0.5
    ru = roof_rise_u(span) - 0.02
    out = Vector((0, -1, 0))
    win = None
    if variant == "a":
        ww = 0.5 if span > 4 else 0.4
        win = (h + 0.18, h + 0.18 + ww, 0.35, 0.35 + ww) if span > 4 else (h - ww / 2, h + ww / 2, 0.3, 0.3 + ww * 0.9)
    p.shade = house_shade(soot=None, damp=False)
    tri = [(0.0, 0.0), (span, 0.0), (h, ru)]
    p.prism(tri, j + 0.03, 0.0, "ct_plaster", tint=(0.55, 0.44, 0.33))   # the daub field + its rims (the jetty step)
    holes = [(win[0] - 0.02, win[1] + 0.02, win[2], win[3])] if win else []
    pt = (0.95 + r.uniform(-0.04, 0.02), 0.9 + r.uniform(-0.04, 0.03), 0.8 + r.uniform(-0.04, 0.04))
    clip = [(0.0, 0.0), (span, 0.0), (h, ru)]
    peel_patches(p, (0.0, span, 0.12, ru), holes, 0.88 if variant == "a" else 0.55, r, j + 0.02, pt,
                 xs=[h - 1.5, h - 0.75, h, h + 0.75, h + 1.5], zs=[0.6, 1.1], clip=clip)
    p.beam((-0.12, j, 0.05), (span + 0.12, j, 0.05), 0.14, 0.08, "ct_timber", out)   # the bressumer
    n_j = 4 if span > 4 else 3
    for d in range(n_j):   # the joist ends under the jetty
        xx = 0.4 + d * (span - 0.8) / (n_j - 1)
        p.box((xx - 0.06, j, -0.12), (xx + 0.06, 0.0, -0.0), "ct_timber", grain=(0, 1, 0))
    if not win:   # the king post, broken round the vent (it crossed the vent in the first build: the check caught it)
        vz = ru * 0.45
        p.beam((h, j, 0.12), (h, j, vz - 0.03), 0.12, 0.06, "ct_timber", out)
        p.beam((h, j, vz + 0.33), (h, j, ru - 0.08), 0.12, 0.06, "ct_timber", out)
    p.beam((0.05, j, 0.1), (h, j, ru), 0.12, 0.06, "ct_timber", out)
    p.beam((span - 0.05, j, 0.1), (h, j, ru), 0.12, 0.06, "ct_timber", out)
    if span > 4:   # the braces stop short of the window
        p.beam((0.6, j, 0.12), (1.7, j, 0.72), 0.09, 0.05, "ct_timber", out)
        p.beam((span - 0.6, j, 0.12), (span - 1.7, j, 0.72), 0.09, 0.05, "ct_timber", out)
    if win:
        x0, x1, z0, z1 = win
        p.flat([(x0, j + 0.2, z0), (x1, j + 0.2, z0), (x1, j + 0.2, z1), (x0, j + 0.2, z1)], "ct_glass_dark", fill=True)
        p.box((x0, j + 0.03, z0), (x1, j + 0.2, z0 + 0.03), "ct_timber"); p.box((x0, j + 0.03, z1 - 0.03), (x1, j + 0.2, z1), "ct_timber")
        p.box((x0 - 0.05, j - 0.06, z0 - 0.06), (x1 + 0.05, j + 0.1, z0), "ct_timber", grain=(1, 0, 0))   # sill
        p.beam((x0 - 0.05, j, 0.12), (x0 - 0.05, j, z1 + 0.05), 0.09, 0.05, "ct_timber", out)
        p.beam((x1 + 0.05, j, 0.12), (x1 + 0.05, j, min(z1 + 0.05, ru * (1 - (x1 + 0.05 - h) / h) - 0.05)), 0.09, 0.05, "ct_timber", out)
    else:   # a louvred vent below the apex (dark, slats in front)
        vz = ru * 0.45
        p.flat([(h - 0.18, j + 0.15, vz), (h + 0.18, j + 0.15, vz), (h + 0.18, j + 0.15, vz + 0.3), (h - 0.18, j + 0.15, vz + 0.3)],
               "ct_glass_dark", fill=True)
        for s in range(3):
            zz = vz + 0.05 + s * 0.09
            p.box((h - 0.17, j + 0.05, zz), (h + 0.17, j + 0.13, zz + 0.04), "ct_timber", grain=(1, 0, 0), fill=True)
        p.openings_extra = [[h - 0.18, h + 0.18, vz, vz + 0.3]]
    p.openings = [[win[0], win[1], win[2], win[3]]] if win else getattr(p, "openings_extra", [])
    return p


def st_gable(name, seed, span=6.0):
    """A coursed stone gable triangle (flush with the wall below), under the roof underside; a dark slit vent."""
    p = Piece(name, seed, cull_back=None)
    r = p.rng
    h = span * 0.5
    ru = roof_rise_u(span) - 0.02
    p.shade = house_shade(damp=False)
    p.prism([(0.0, 0.0), (span, 0.0), (h, ru)], 0.0, ST_T, "ct_stone_fine", tint=(0.9, 0.9, 0.92))
    # (no proud stones on ct_stone_fine - they cut through the photographed rubble)
    vz = 0.6 if span > 4 else 0.45
    p.flat([(h - 0.06, 0.2, vz), (h + 0.06, 0.2, vz), (h + 0.06, 0.2, vz + 0.45), (h - 0.06, 0.2, vz + 0.45)], "ct_glass_dark", fill=True)
    p.box((h - 0.14, -0.03, vz + 0.45), (h + 0.14, 0.0, vz + 0.55), "ct_stone_fine", tint=(1.1, 1.1, 1.05))
    p.openings = []
    return p


# ------------------------------------------------------------------ slate roof segments
def roof(name, seed, span=6.0, length=3.0, verge=False, variant="a"):
    """A slate gable roof segment, `length` along the ridge (X), spanning `span` (Y from 0 = the front wall plane to span),
    eaves at z = 0, ridge capping top at RIDGE_MAX exactly. Slab courses of 0.614 in (2 texture rows) with stepped lower
    edges, slate groups in whole slates (0.1875 in), sag 0 at both ends (segments tile). variant b: slipped and missing
    groups (battens and a dark void show), more moss. verge: the 0.3 in overhang past the gable + a barge board."""
    p = Piece(name, seed)
    r = p.rng
    h = span * 0.5
    ru = roof_rise_u(span)
    pitch = math.atan2(ru, h)
    ov = 0.22 if span > 4 else 0.15   # eave overhang (horizontal, at the underside); proud stays <= 0.35 measured
    L = (h + ov / 1.0) / math.cos(pitch)
    t = 0.06
    crs = 2 * course("ct_roof")
    slate = stone("ct_roof")
    def roof_shade(q, m):
        if m != "ct_roof":
            return (0.75, 0.7, 0.66, 0.4)
        low = max(0.0, min(1.0, 1.0 - (q.z + 0.3) / 1.4))   # moss and wet at the eaves, dry grey up at the ridge
        k = 0.6 if variant == "a" else 0.52
        return (k * (1 - 0.35 * low), k * (1 - 0.18 * low), k * (1 - 0.4 * low), min(1.0, 0.3 + 0.7 * low + (0.15 if variant == "b" else 0.0)))
    p.shade = roof_shade
    x_end = length
    hole = (r.uniform(1.1, 1.4), L * 0.45, 0.6, 0.5 if span < 4 else 0.65, -1) if (variant == "b" and not verge) else None
    for side in (-1, 1):
        up = Vector((0, -side * math.cos(pitch), math.sin(pitch)))
        e = Vector((0, h + side * (h + ov), -ov * math.tan(pitch)))
        n = Vector((0, side * math.sin(pitch), math.cos(pitch)))
        n_out = Vector((0, side, 0))   # (unused: the slope's outward normal is n)
        def at(x, s, d):
            return e + Vector((x, 0, 0)) + up * s + n * d
        # rafter tails under the eaves (short: the body hides the rest)
        k = 0
        xx = 0.15
        while xx < x_end - 0.1 and not verge:
            p.beam(at(xx, 0.02, -0.12), at(xx, 0.55, -0.12), 0.08, 0.1, "ct_timber", out=n, tint=(0.7, 0.65, 0.6))
            xx += 0.75
        s = 0.0
        ci = 0
        while s < L - 0.02:
            s1 = min(L, s + crs)
            x = 0.0
            while x < x_end - 1e-6:
                w = min(x_end - x, slate * r.randint(3, 5))
                if x_end - x - w < slate * 2:
                    w = x_end - x
                ds = r.uniform(-0.03, 0.02) if s > 0 else 0.0   # the ragged lower edge of a course (the eave stays clean: proud cap)
                slip = 0.0
                if 0 < ci and s1 < L - 0.4 and r.random() < (0.08 if variant == "b" else 0.025):
                    slip = r.uniform(0.04, 0.12)
                runs = [(x, x + w, False)]
                if hole and side == hole[4]:   # a ragged hole: slates dropped one by one round an ellipse with a jittered rim
                    n_sl = max(1, int(round(w / slate)))
                    cs = (s + s1) * 0.5
                    def inside(px, ps):   # two overlapping ellipses (an irregular tear), each slate with its own jitter
                        a_ = ((px - hole[0]) / hole[2]) ** 2 + ((ps - hole[1]) / hole[3]) ** 2
                        b_ = ((px - hole[0] - hole[2] * 0.7) / (hole[2] * 0.6)) ** 2 + ((ps - hole[1] - hole[3] * 0.8) / (hole[3] * 0.7)) ** 2
                        return min(a_, b_) < 1.0 + r.uniform(-0.6, 0.6)
                    keep = [not inside(x + (j + 0.5) * w / n_sl, cs) for j in range(n_sl)]
                    if not all(keep):
                        runs = []
                        for j in range(n_sl):   # each slate next to the hole on its own: broken, shorter, darker
                            if keep[j]:
                                near = (j > 0 and not keep[j - 1]) or (j < n_sl - 1 and not keep[j + 1])
                                xa, xb = x + j * w / n_sl, x + (j + 1) * w / n_sl
                                if near or not runs or runs[-1][2] or abs(runs[-1][1] - xa) > 1e-6:
                                    runs.append((xa, xb, near))
                                else:
                                    runs[-1] = (runs[-1][0], xb, False)
                for (rx0, rx1, broken) in runs:
                    lift = 0.04 + slip * 0.3 + (r.uniform(0.0, 0.05) if broken else 0.0)
                    tint = (0.85 + r.random() * 0.25) * (0.8 if broken else 1.0)
                    tt = (tint, tint, tint * (0.98 + r.random() * 0.05))
                    a0 = s + ds - slip; a1 = min(L + 0.02, s1 + 0.1 - slip)
                    if broken:   # a snapped slate: its top edge is gone
                        a1 = max(a0 + 0.12, a1 - r.uniform(0.1, 0.35))
                    vs = [at(rx0, a0, 0.0), at(rx1, a0, 0.0), at(rx1, a0, t + lift), at(rx0, a0, t + lift),
                          at(rx0, a1, 0.0), at(rx1, a1, 0.0), at(rx1, a1, t), at(rx0, a1, t)]
                    vs = [vs[0], vs[1], vs[5], vs[4], vs[3], vs[2], vs[6], vs[7]]
                    faces = p.poly([tuple(v) for v in vs], "ct_roof", tint=tt, uvo=tuple(e), cull=False)
                    if ci > 0 and not verge and not broken:   # the slab underside is hidden by the course below (except at the eave)
                        for f in list(faces):
                            if f.normal.dot(n) < -0.9:
                                p.bm.faces.remove(f)
                x += w
            s = s1
            ci += 1
        if hole and side == hole[4]:   # under the hole: two rafters, battens (some broken), a dark void deep below
            hx, hs, hrx, hrs = hole[:4]
            for xx in (0.4, 1.15, 1.9, 2.65):   # the rafters on their 0.75 in rhythm (not a frame round the hole)
                if abs(xx - hx) < hrx * 1.7:
                    p.beam(at(xx, hs - hrs - 0.3, -0.16), at(xx, hs + hrs * 1.6 + 0.2, -0.16), 0.09, 0.12, "ct_timber", out=n, tint=(0.55, 0.5, 0.45))
            bs = hs - hrs + 0.05
            while bs < hs + hrs * 1.5:   # battens on every row, a third gone, some snapped and sagging
                if r.random() > 0.33:
                    x0b = hx - hrx * 1.3 + (r.uniform(0.1, 0.6) if r.random() < 0.45 else 0.0)
                    x1b = hx + hrx * 1.5 - (r.uniform(0.1, 0.6) if r.random() < 0.45 else 0.0)
                    sag_b = r.uniform(0.0, 0.1) if r.random() < 0.4 else 0.0
                    p.beam(at(x0b, bs, -0.035), at(x1b, bs - sag_b, -0.035 - sag_b * 0.5), 0.055, 0.03, "ct_timber", out=n, tint=(0.7, 0.64, 0.56))
                bs += course("ct_roof")
            q = [(hx - hrx * 1.4, hs - hrs - 0.1), (hx + hrx * 1.6, hs - hrs - 0.1), (hx + hrx * 1.6, hs + hrs * 1.7), (hx - hrx * 1.4, hs + hrs * 1.7)]
            p.poly([tuple(at(u, v, -0.5)) for u, v in q] + [tuple(at(u, v, -0.49)) for u, v in q], "ct_timber", tint=(0.22, 0.2, 0.18))   # the dim loft below
        if verge:   # the barge board under the verge edge
            a = at(x_end - 0.04, -0.02, -0.05); b = at(x_end - 0.04, L - 0.05, -0.05)
            p.beam(a, b, 0.22, 0.06, "ct_timber", out=Vector((1, 0, 0)), tint=(0.7, 0.65, 0.6))
    # the ridge capping: rolls whose top is exactly RIDGE_MAX
    x = 0.0
    rz = RIDGE_MAX
    while x < x_end - 1e-6:
        w = min(x_end - x, r.uniform(0.45, 0.6))
        if x_end - x - w < 0.2:
            w = x_end - x
        drop = r.uniform(0.0, 0.02)
        p.poly([(x, h - 0.2, rz - 0.36), (x + w, h - 0.2, rz - 0.36), (x + w, h + 0.2, rz - 0.36), (x, h + 0.2, rz - 0.36),
                (x, h - 0.08, rz - drop), (x + w, h - 0.08, rz - drop), (x + w, h + 0.08, rz - drop), (x, h + 0.08, rz - drop)],
               "ct_roof", tint=(0.55, 0.55, 0.57))
        x += w
    if not verge:
        p.sag_apply(length, r.uniform(0.04, 0.08) if variant == "a" else r.uniform(0.08, 0.12))
    # to the module frame: origin = the left foot of the FRONT wall plane (y = 0 there already), the back plane at y = span
    p.openings = []
    return p


def chimney(name, seed):
    """A stone stack 0.62 in square, centred, from the eaves line; corbelled cap and two clay pots, top = RIDGE_MAX + 0.9
    (5.4 in = today's chimney box top: the collider is the truth; for a roof height h the planner scales Y by (h + 0.9) / 2.9)."""
    p = Piece(name, seed)
    q = 0.31
    top = RIDGE_MAX + 0.9   # exactly the chimney box top (2.5 + 2.0 + 0.9 = 5.4 in); the smoke emitter stays
    p.shade = lambda v, m: tuple(c * (1.0 - 0.6 * max(0.0, min(1.0, (v.z - 1.6) / 0.7))) for c in ((0.6, 0.63, 0.7) if m == "ct_stone_fine" else (0.8, 0.8, 0.8))) + (0.5,)
    p.box((-q, -q, 0), (q, q, top - 0.33), "ct_stone_fine")
    p.box((-q - 0.06, -q - 0.06, top - 0.33), (q + 0.06, q + 0.06, top - 0.22), "ct_stone_fine", tint=(0.9, 0.9, 0.9))
    p.box((-q - 0.03, -q - 0.03, top - 0.22), (q + 0.03, q + 0.03, top - 0.16), "ct_stone_fine", tint=(0.8, 0.8, 0.8))
    for cx, hh in ((-0.12, 0.16), (0.13, 0.12)):
        pts = [(cx + 0.09 * math.cos(a * math.pi / 3), 0.09 * math.sin(a * math.pi / 3)) for a in range(6)]
        z0 = top - 0.16
        bot = [p.bm.verts.new((x, y, z0)) for x, y in pts]
        tp = [p.bm.verts.new((cx + (x - cx) * 0.85, y * 0.85, z0 + hh)) for x, y in pts]
        inner = [p.bm.verts.new((cx + (x - cx) * 0.55, y * 0.55, z0 + hh - 0.03)) for x, y in pts]
        faces = [p.bm.faces.new([bot[i], bot[(i + 1) % 6], tp[(i + 1) % 6], tp[i]]) for i in range(6)]
        faces += [p.bm.faces.new([tp[i], tp[(i + 1) % 6], inner[(i + 1) % 6], inner[i]]) for i in range(6)]
        faces.append(p.bm.faces.new(list(reversed(inner))))
        for f in faces:
            f.normal_update()
        p._record([(x, y, z0) for x, y in pts] + [(cx, 0, z0 + hh)], "ct_clay", False)
        p._finish(faces, "ct_clay", None, (0.6, 0.55, 0.5), None)
    p.openings = []
    return p


# ------------------------------------------------------------------ export
def make_material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    d = MATS[name]
    col = d.get("colour") or d.get("tone")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = d.get("roughness", 0.85)
    bsdf.inputs["Metallic"].default_value = d.get("metallic", 0.0)
    return m


def to_object(p):
    me = bpy.data.meshes.new(p.name)
    p.bm.normal_update()
    p.bm.to_mesh(me)
    nrm = getattr(p, "normals", None)   # (vegetation: bent normals per vertex)
    for f in me.polygons:
        f.use_smooth = nrm is not None
    if nrm is not None:
        me.normals_split_custom_set_from_vertices(nrm)
    ob = bpy.data.objects.new(p.name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in p.mats:
        me.materials.append(make_material(m))
    me.color_attributes.active_color = me.color_attributes["Color"]
    return ob


def export(ob, path):
    """Export one module in metres (a scaled copy), no images, COLOR_0 fixed (Blender 5.1 writes the real colour as COLOR_1)."""
    cp = ob.copy(); cp.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(cp)
    cp.scale = (IN, IN, IN)
    for o in bpy.context.scene.objects:
        o.select_set(o == cp)
    bpy.context.view_layer.objects.active = cp
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_vertex_color="ACTIVE",
                              export_all_vertex_colors=True, export_image_format="NONE", export_apply=True, export_yup=True,
                              export_texcoords=True, export_normals=True, export_tangents=False)
    me = cp.data
    bpy.data.objects.remove(cp)
    bpy.data.meshes.remove(me)
    check_kit.fix_colors(path)


def forge(out, argv):
    os.makedirs(out, exist_ok=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    T = kit_table.table()
    # RED PROOF first: the first door panel (sill beam across the door) must fail the openings check
    red = tb_panel("red_proof_door", 14, "door", sill_across=True)
    errs = check_kit.openings(red.parts, red.openings)
    if not errs:
        raise SystemExit("RED_PROOF_BROKEN: the openings check passed the door panel with the sill beam across")
    print("RED_PROOF openings check FAILS the first door panel as required:", errs[0])
    red.bm.free()
    builders = []
    for k, role in enumerate(("plain_a", "plain_b", "window", "window_lit", "door", "blank")):
        builders.append(("dr_house_tb_" + role, lambda role=role, k=k: tb_panel("dr_house_tb_" + role, 101 + k, role)))
    builders.append(("dr_house_tb_post", lambda: tb_post("dr_house_tb_post", 111)))
    for sp in (3, 6):
        builders.append((f"dr_gable_tb_s{sp}", lambda sp=sp: tb_gable(f"dr_gable_tb_s{sp}", 120 + sp, float(sp), "a")))
        builders.append((f"dr_gable_tb_s{sp}_b", lambda sp=sp: tb_gable(f"dr_gable_tb_s{sp}_b", 130 + sp, float(sp), "b")))
    for k, role in enumerate(("plain_a", "plain_b", "window", "door")):
        builders.append(("dr_house_st_" + role, lambda role=role, k=k: st_panel("dr_house_st_" + role, 141 + k, role)))
    builders.append(("dr_house_st_quoin", lambda: st_quoin("dr_house_st_quoin", 151)))
    for sp in (3, 6):
        builders.append((f"dr_gable_st_s{sp}", lambda sp=sp: st_gable(f"dr_gable_st_s{sp}", 160 + sp, float(sp))))
        builders.append((f"dr_roof_s{sp}_mid_a", lambda sp=sp: roof(f"dr_roof_s{sp}_mid_a", 170 + sp, float(sp), 3.0, False, "a")))
        builders.append((f"dr_roof_s{sp}_mid_b", lambda sp=sp: roof(f"dr_roof_s{sp}_mid_b", 180 + sp, float(sp), 3.0, False, "b")))
        builders.append((f"dr_roof_s{sp}_verge", lambda sp=sp: roof(f"dr_roof_s{sp}_verge", 190 + sp, float(sp), 0.3, True, "a")))
    builders.append(("dr_chimney_a", lambda: chimney("dr_chimney_a", 199)))
    import kit_k2
    builders += kit_k2.builders()
    try:
        import kit_k3
        builders += kit_k3.builders()
    except ImportError:
        pass
    for mod in ("kit_k4", "kit_k5", "kit_k5b"):
        try:
            km = __import__(mod)
        except ImportError:
            continue
        builders += km.builders()
        km.red_proofs(check_kit, T)
    failures = []
    built = {}
    for name, fn in builders:
        p = fn()
        e = T[name]
        e.update(getattr(p, "entry", {}))   # (honest len / height / tags where the nominal stub was off)
        meas = p.measure(e["mount_in"])
        rec = {"name": name, "entry": e, "parts": p.parts, "openings": p.openings, "materials": list(p.mats), "shadow": getattr(p, "shadow", None), "entry_after": getattr(p, "entry_after", {}), **meas}
        errs = check_kit.check_piece(rec)
        if errs:
            failures += [f"{name}: {m}" for m in errs]
        ob = to_object(p)
        p.bm.free()
        path = os.path.join(out, name + ".glb")
        export(ob, path)
        errs = check_kit.check_glb(path, rec)
        if errs:
            failures += [f"{name}: {m}" for m in errs]
        built[name] = (ob, rec)
        print(f"MODULE {name} tris={meas['tris']} aabb={meas['aabb_in']} proud={meas['proud_in']} mats={p.mats}")
    if failures:
        for f in failures:
            print("CHECK_FAIL", f)
        for name in built:
            try:
                os.remove(os.path.join(out, name + ".glb"))
            except OSError:
                pass
        raise SystemExit(f"EXPORT REFUSED: {len(failures)} check failures")
    for name, (ob, rec) in built.items():
        e = T[name]
        e.update({"tris": rec["tris"], "aabb_in": rec["aabb_in"], "proud_in": rec["proud_in"], "openings": rec["openings"],
                  "materials": rec["materials"], "stub": False, "bytes": os.path.getsize(os.path.join(out, name + ".glb")),
                  "shadow": check_kit.shadow_boxes(name, e, rec)})
        e.update(rec["entry_after"])   # (modules that wait for a material decision stay `stub: true` = not usable)
    sheets = [a.split("=", 1)[1] for a in argv if a.startswith("--sheet=")]
    if "--sheet" in argv:
        sheets.append("K1")
    for b in sheets:
        import kit_sheet
        rows = os.path.join(out, "..", "sheets", "rows_" + b.lower())
        os.makedirs(rows, exist_ok=True)
        kit_sheet.render_batch(b, {n: ob for n, (ob, _) in built.items()}, T, rows)
    kit_table.write(os.path.join(out, "ruintown_dress.json"), T)   # LAST: the watched artefact
    print("KIT_DONE", len(built), sum(r["tris"] for _, r in built.values()))
