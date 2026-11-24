# check_kit.py - the forge checks of the ruin-town dressing kit.
# Export is refused on any failure. Pure Python (struct + json), used by kit_build.py inside Blender and standalone:
#   python3 tools/kit_forge/check_kit.py <kit dir>   -> re-checks every built GLB against the manifest (4, 5 and the tri count)
# (1) OPENINGS: no ct_timber / ct_stone part crosses a declared opening except declared fill (glazing bars, door leaf, step)
# (2) triangle cap   (3) proud limits (flat <= 0.25, low <= 0.12, high <= 0.35)   (H) honest heights per family
# (4) no image / texture, all material names known, COLOR_0 (normalised u8, not constant white), TEXCOORD_0, NORMAL present
# (5) every module tagged `tiles` matches at its two ends (x = 0 and x = len_in): profile extents within 0.06 in
import json, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_table

IN = 0.0254
SHRINK = 0.05   # a lining on the opening edge (<= 0.05 in) is not a crossing
FRAME_MATS = ("ct_timber", "ct_stone", "ct_stone_big", "ct_stone_fine")
# The highest local y (inches above the module origin) per family: the house body is 2.5 (the collider), roofs / gables
# end at the core's HOUSE_TOP_IN 4.5 (= 2.5 + 2.0), a chimney at 4.8 (tolerance 4.5 + 0.3).
TOP_MAX = {"gable": 2.0, "roof": 2.0, "chimney": 2.9, "deck_edge": kit_table.FLAT, "ruin_gable": 2.6, "parapet": 0.7,
           "merlon_run": 0.7, "tower_cap": 0.0, "litter": kit_table.FLAT}   # (tower caps: apex exactly at 12 in)   # every other family: its nominal height_in


def openings(parts, ops):
    errs = []
    for o in ops:
        x0, x1, z0, z1 = o[0] + SHRINK, o[1] - SHRINK, o[2] + SHRINK, o[3] - SHRINK
        for pt in parts:
            if pt["mat"] not in FRAME_MATS or pt["fill"]:
                continue
            (a, _, c), (b, _, d) = pt["lo"], pt["hi"]
            if "seg" in pt:   # a beam: sample its centre line, widened by half its width
                (sa, sb), (ea, eb), w = pt["seg"]
                hw = w * 0.5
                hit = any(x0 - hw < sa + (ea - sa) * k / 200 < x1 + hw and z0 - hw < sb + (eb - sb) * k / 200 < z1 + hw
                          for k in range(201))
                if hit:
                    errs.append(f"OPENINGS: {pt['mat']} member ({sa:.2f},{sb:.2f})-({ea:.2f},{eb:.2f}) crosses opening {o}")
                continue
            if a < x1 and b > x0 and c < z1 and d > z0:
                errs.append(f"OPENINGS: {pt['mat']} part x {a:.2f}..{b:.2f} z {c:.2f}..{d:.2f} crosses opening {o}")
    return errs


def check_piece(rec):
    e = rec["entry"]
    errs = openings(rec["parts"], rec["openings"])
    if rec["tris"] > e["tri_cap"]:
        errs.append(f"TRI_CAP: {rec['tris']} > {e['tri_cap']}")
    pr = rec["proud_in"]
    for band, lim in (() if ("centred" in e["tags"] or "ladder" in e["tags"] or "veg" in e["tags"]) else (("flat", 0.25), ("low", 0.12), ("high", 0.35))):
        if pr[band] > lim + 1e-4:
            errs.append(f"PROUD: {band} {pr[band]} > {lim}")
    lo, hi = rec["aabb_in"]
    top = TOP_MAX.get(e["family"], e["height_in"])
    if hi[1] > top + 1e-3:
        errs.append(f"HEIGHT: top {hi[1]:.3f} > {top} (local; world {e['mount_in'] + hi[1]:.2f})")
    if "R4_strip" in e["tags"] and (lo[2] < -0.4 - 1e-3 or hi[2] > 1e-3):
        errs.append(f"R4 STRIP: z {lo[2]:.3f}..{hi[2]:.3f} outside the 0.4 in edge strip")
    if "R4_gable" in e["tags"] and (lo[2] < -0.3 - 1e-3 or hi[2] > 1e-3):
        errs.append(f"R4 GABLE: thickness z {lo[2]:.3f}..{hi[2]:.3f} (<= 0.3, never proud)")
    if ("single_band" in e["tags"] or "upper_band" in e["tags"] or "foot" in e["tags"]) and (lo[0] < -0.02 or hi[0] > e["len_in"] + 0.02):
        errs.append(f"FOOTPRINT: x {lo[0]:.3f}..{hi[0]:.3f} outside 0..{e['len_in']}")
    for m in rec["materials"]:
        if m not in kit_table.MATERIALS:
            errs.append(f"MATERIAL: unknown {m}")
    # ---- K4 / K5 (props, landmarks, plots, refuse)
    tags = e["tags"]
    if "flat" in tags and (hi[1] > kit_table.FLAT + 1e-3 or lo[1] < -1e-3):
        errs.append(f"FLAT: y {lo[1]:.3f}..{hi[1]:.3f} outside 0..{kit_table.FLAT} (a flat piece)")
    if "cell_corner" in tags and max(hi[0] - lo[0], hi[2] - lo[2]) > 0.2 + 1e-3:
        errs.append(f"LAMP POST: {hi[0] - lo[0]:.3f} x {hi[2] - lo[2]:.3f} in thick > 0.2 (the lamp-post thickness exception)")
    if e["role"] == "lamp":
        gl = [pt for pt in rec["parts"] if pt["mat"] == "ct_glass_lit"]
        c = (min(pt["lo"][2] for pt in gl) + max(pt["hi"][2] for pt in gl)) * 0.5 + e["mount_in"] if gl else -1.0
        if abs(c - 2.55) > 0.02:
            errs.append(f"LANTERN: glass centre at {c:.3f} in, not 2.55 (the light)")
    if "above_clear" in tags and e["mount_in"] + lo[1] < kit_table.CLEAR - 1e-3:
        errs.append(f"ABOVE CLEAR: lowest point at {e['mount_in'] + lo[1]:.3f} in < {kit_table.CLEAR}")
    if "inside_solid_footprint" in tags:
        half = 2.8 if e["role"] == "fountain" else 1.4   # 6 x 6 / 3 x 3 in footprint less the 0.2 in inset
        if max(-lo[0], hi[0], -lo[2], hi[2]) > half + 1e-3:
            errs.append(f"FOOTPRINT: reaches {max(-lo[0], hi[0], -lo[2], hi[2]):.3f} in from the centre > {half}")
    if "terrain_cell" in tags and (lo[0] < 0.05 or hi[0] > 2.95 or lo[2] < -2.95 or hi[2] > -0.05):
        errs.append(f"PLOT CELL: x {lo[0]:.3f}..{hi[0]:.3f} z {lo[2]:.3f}..{hi[2]:.3f} leaves the 3 x 3 in cell (0.05 in margin)")
    if e["family"] in ("junk", "yard") and max(-lo[0], hi[0], -lo[2], hi[2]) > 1.45:
        errs.append(f"JUNK CELL: reaches {max(-lo[0], hi[0], -lo[2], hi[2]):.3f} in from its centre (> 1.45: it must fit one terrain cell)")
    return errs


# ------------------------------------------------------------------ GLB access
def read_glb(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    rest = b[20 + jl:]
    binc = b""
    if len(rest) >= 8:
        bl = struct.unpack("<I", rest[0:4])[0]
        binc = rest[8:8 + bl]
    return j, binc


def write_glb(path, j, binc):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binc += b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binc)
    out = b"glTF" + struct.pack("<II", 2, total) + struct.pack("<I", len(js)) + b"JSON" + js
    out += struct.pack("<I", len(binc)) + b"BIN\0" + binc
    open(path, "wb").write(out)


FMT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(j, binc, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = NCOMP[a["type"]]
    f = FMT[a["componentType"]]
    size = struct.calcsize(f)
    stride = bv.get("byteStride", size * n)
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        out.append(struct.unpack_from("<" + f * n, binc, off + k * stride))
    return a, out


def fix_colors(path):
    """Blender 5.1 writes a white COLOR_0 and the real colour as COLOR_1: move COLOR_1 to COLOR_0, and store it as
    normalised unsigned bytes (the contract) when the exporter wrote floats or shorts."""
    j, binc = read_glb(path)
    binc = bytearray(binc)
    for m in j["meshes"]:
        for pr in m["primitives"]:
            at = pr["attributes"]
            if "COLOR_1" in at:
                at["COLOR_0"] = at.pop("COLOR_1")
            ci = at.get("COLOR_0")
            if ci is None:
                continue
            a, data = accessor(j, bytes(binc), ci)
            if a["componentType"] == 5121:
                continue
            scale = {5126: 1.0, 5123: 65535.0, 5121: 255.0}[a["componentType"]]
            n = NCOMP[a["type"]]
            raw = bytearray()
            for v in data:
                q = [max(0, min(255, int(round(c / scale * 255.0)))) for c in v]
                raw += bytes(q) + b"\0" * ((4 - n) % 4)   # 4-byte aligned elements
            while len(binc) % 4:
                binc.append(0)
            j["bufferViews"].append({"buffer": 0, "byteOffset": len(binc), "byteLength": len(raw),
                                     **({"byteStride": 4} if n == 3 else {}), "target": 34962})
            binc += raw
            j["accessors"].append({"bufferView": len(j["bufferViews"]) - 1, "componentType": 5121, "normalized": True,
                                   "count": a["count"], "type": a["type"]})
            at["COLOR_0"] = len(j["accessors"]) - 1
    j["buffers"][0]["byteLength"] = len(binc) + ((4 - len(binc) % 4) % 4)
    write_glb(path, j, bytes(binc))


def check_glb(path, rec):
    e = rec["entry"]
    j, binc = read_glb(path)
    errs = []
    if j.get("images") or j.get("textures") or j.get("samplers"):
        errs.append("GLB: carries an image / texture")
    names = [m.get("name") for m in j.get("materials", [])]
    for n in names:
        if n not in kit_table.MATERIALS:
            errs.append(f"GLB: unknown material {n}")
    tris = 0
    xs = []
    for m in j["meshes"]:
        for pr in m["primitives"]:
            at = pr["attributes"]
            for k in ("POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0"):
                if k not in at:
                    errs.append(f"GLB: primitive without {k}")
            if "COLOR_1" in at:
                errs.append("GLB: COLOR_1 still present")
            if "COLOR_0" in at:
                a, cols = accessor(j, binc, at["COLOR_0"])
                if a["componentType"] != 5121 or not a.get("normalized"):
                    errs.append("GLB: COLOR_0 is not normalised u8")
                if all(c[0] >= 250 and c[1] >= 250 and c[2] >= 250 for c in cols):
                    errs.append("GLB: COLOR_0 is constant white")
                if e["family"] in ("litter", "junk", "yard"):   # no confetti: earthy, clustered values (albedo = colour x COLOR_0 x 2)
                    mn = j["materials"][pr["material"]]["name"]
                    d = kit_table.MATERIALS.get(mn, {})
                    base = d.get("colour") or [0.4 * t for t in d.get("tone", [1, 1, 1])]   # (a set's albedo ~0.4 x its tone)
                    lum = [sum(w * base[i] * c[i] / 255.0 * 2.0 for i, w in enumerate((0.2126, 0.7152, 0.0722))) for c in cols]
                    if max(lum) > 0.3 or (mn == "ct_matte" and min(lum) < 0.012):
                        errs.append(f"TONE: {mn} albedo luma {min(lum):.3f}..{max(lum):.3f} outside 0.012..0.3 (confetti)")
            if "indices" in pr:
                tris += j["accessors"][pr["indices"]]["count"] // 3
            _, pos = accessor(j, binc, at["POSITION"])
            xs += [(p[0] / IN, p[1] / IN, p[2] / IN) for p in pos]
    if tris != rec["tris"]:
        errs.append(f"GLB: {tris} triangles in the file, {rec['tris']} built")
    if "tiles" in e["tags"]:
        L = e["len_in"]
        def prof(sel):
            v = [p for p in xs if sel(p[0])]
            if not v:
                return None
            return (min(p[1] for p in v), max(p[1] for p in v), max(p[2] for p in v), min(p[2] for p in v))
        a, b = prof(lambda x: x < 0.02), prof(lambda x: x > L - 0.02)
        if a is None or b is None or max(abs(a[i] - b[i]) for i in range(4)) > 0.06:
            errs.append(f"TILING: end profiles differ x=0 {a} vs x={L} {b}")
    return errs


def shadow_boxes(name, e, rec):
    """1-3 hull boxes (Godot axes, inches) for the shadow proxy, inside the module's mass."""
    lo, hi = rec["aabb_in"]
    f = e["family"]
    r3 = lambda v: [round(c, 3) for c in v]
    if rec.get("shadow") is not None:
        return rec["shadow"]
    if f == "litter" or "flat" in e["tags"]:
        return []
    if f == "house_panel":
        return [[r3([0.05, 0.0, lo[2] + 0.05]), r3([e["len_in"] - 0.05, kit_table.BODY - 0.05, 0.0])]]
    if f == "roof":
        sp = 6.0 if "span_6" in e["tags"] else 3.0
        L = hi[0]
        return [[r3([0.0, 0.0, -sp + 0.05]), r3([L, 0.95, -0.05])],
                [r3([0.0, 0.95, -sp * 0.75]), r3([L, 1.6, -sp * 0.25])]]
    if f == "gable":
        sp = e["len_in"]
        return [[r3([0.1, 0.0, -0.3]), r3([sp - 0.1, 0.8, 0.0])], [r3([sp * 0.3, 0.8, -0.3]), r3([sp * 0.7, 1.5, 0.0])]]
    return [[r3([lo[0] + 0.02, lo[1], lo[2] + 0.02]), r3([hi[0] - 0.02, hi[1] - 0.05, hi[2] - 0.02])]]


if __name__ == "__main__":
    kit = sys.argv[1]
    man = json.load(open(os.path.join(kit, "ruintown_dress.json")))
    bad = 0
    for name, e in man["modules"].items():
        if e["stub"]:
            continue
        rec = {"entry": e, "tris": e["tris"]}
        errs = check_glb(os.path.join(kit, name + ".glb"), rec)
        for m in errs:
            print("CHECK_FAIL", name, m); bad += 1
    print("CHECK_DONE", bad)
