# kit_sheet.py - the review sheet of a kit batch (every module, labelled, a 25 mm base disc beside each, plus two
# houses assembled by the grammar's face convention). Rendered headless in Blender (Cycles CPU), composed with PIL.
# Preview shading only: the sets' 512 px JPEG copies (see TEX below), board-projected sets by object
# position / tile_in, mesh sets by UV (inches) / tile_in, albedo x tone x vertex colour x 2. The game's shader is the real one.
import bpy, os, math
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view
import kit_table

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.environ.get("NML_KIT_TEX512", os.path.join(REPO, "build", "kit_forge", "tex512"))
PREFIX = {"coursed_stone": "stone", "plaster": "plaster", "timber": "timber", "roof_tiles": "roof", "flags": "flags"}
DISC_R = 0.492   # 25 mm
STONE_1K = os.environ.get("NML_KIT_STONE_1K", os.path.join(REPO, "build", "kit_forge", "stone_1k"))


def preview_material(name):
    d = kit_table.MATERIALS[name]
    m = bpy.data.materials.new("pv_" + name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Color"
    x2 = nt.nodes.new("ShaderNodeMix"); x2.data_type = "RGBA"; x2.blend_type = "MULTIPLY"
    x2.inputs[0].default_value = 1.0
    nt.links.new(vc.outputs["Color"], x2.inputs[6])
    x2.inputs[7].default_value = (2.0, 2.0, 2.0, 1.0)
    if "set" in d:
        pre = PREFIX[d["set"]]
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        s = 1.0 / d["tile_in"]
        mp.inputs["Scale"].default_value = (s, s, s)
        imgs = []
        for suf, cs in (("Diffuse", "sRGB"), ("nor_gl", "Non-Color"), ("arm", "Non-Color")):
            t = nt.nodes.new("ShaderNodeTexImage")
            src1k = os.path.join(STONE_1K, suf + ".png")   # (the stone set is baked at 1k: preview it from the 1k source)
            t.image = bpy.data.images.load(src1k if (pre == "stone" and os.path.exists(src1k)) else os.path.join(TEX, f"{pre}_{suf}.jpg"), check_existing=True)
            t.image.colorspace_settings.name = cs
            if d["uv"] == "world":
                t.projection = "BOX"; t.projection_blend = 0.15
                nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
            else:
                nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
            nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
            imgs.append(t)
        tone = nt.nodes.new("ShaderNodeMix"); tone.data_type = "RGBA"; tone.blend_type = "MULTIPLY"; tone.inputs[0].default_value = 1.0
        nt.links.new(imgs[0].outputs["Color"], tone.inputs[6])
        tone.inputs[7].default_value = (*[c * 1.6 for c in d["tone"]], 1.0)   # (preview exposure: the scans are toned for dusk)
        mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
        nt.links.new(tone.outputs[2], mul.inputs[6]); nt.links.new(x2.outputs[2], mul.inputs[7])
        nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(imgs[1].outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(imgs[2].outputs["Color"], sep.inputs["Color"]); nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    else:
        mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
        mul.inputs[6].default_value = (*d["colour"], 1.0)
        nt.links.new(x2.outputs[2], mul.inputs[7])
        nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = d.get("roughness", 0.8)
        bsdf.inputs["Metallic"].default_value = d.get("metallic", 0.0)
        if "emission" in d:
            bsdf.inputs["Emission Color"].default_value = (*d["emission"], 1.0)
            bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


def frame(origin, along, out):
    a = Vector(along).normalized(); o = Vector(out).normalized(); up = Vector((0, 0, 1))
    y = -o
    return Matrix(((a.x, y.x, up.x, origin[0]), (a.y, y.y, up.y, origin[1]), (a.z, y.z, up.z, origin[2]), (0, 0, 0, 1)))


def place(objs, name, mw, coll):
    src = objs[name]
    o = bpy.data.objects.new(name + "_inst", src.data)
    o.matrix_world = mw
    coll.objects.link(o)
    return o


def disc(coll, x, y, r=DISC_R):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r, depth=0.12, location=(x, y, 0.06))
    o = bpy.context.active_object
    m = bpy.data.materials.get("pv_disc") or bpy.data.materials.new("pv_disc")
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"); b.inputs["Base Color"].default_value = (0.02, 0.02, 0.025, 1)
    o.data.materials.append(m)
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    return o


def houses(objs, coll, x_off):
    """Two lots dressed by hand with the grammar's face convention: a timber house 6 x 3 (ridge along the 6, span 3) and a
    stone house 6 x 6 (span 6). Faces start at the lot corners; panels on the collider face (no inset in this preview)."""
    B = 2.5
    def faces(x0, y0, x1, y1):
        return {"front": ((x0, y0), (1, 0), (0, -1)), "right": ((x1, y0), (0, 1), (1, 0)),
                "back": ((x1, y1), (-1, 0), (0, 1)), "left": ((x0, y1), (0, -1), (-1, 0))}
    # timber house, lot x 0..6, y 0..3
    x0 = x_off; f = faces(x0, 0, x0 + 6, 3)
    def run(face, mods, z=0.0):
        (sx, sy), a, o = f[face]
        for i, m in enumerate(mods):
            place(objs, m, frame((sx + a[0] * 3 * i, sy + a[1] * 3 * i, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    run("front", ["dr_house_tb_door", "dr_house_tb_window_lit"]); run("back", ["dr_house_tb_plain_a", "dr_house_tb_plain_b"])
    run("right", ["dr_house_tb_window"]); run("left", ["dr_house_tb_blank"])
    for c in ((x0, 0), (x0 + 6, 0), (x0 + 6, 3), (x0, 3)):
        place(objs, "dr_house_tb_post", Matrix.Translation((c[0], c[1], 0)), coll)
    place(objs, "dr_gable_tb_s3", frame((x0 + 6, 0, B), (0, 1, 0), (1, 0, 0)), coll)
    place(objs, "dr_gable_tb_s3_b", frame((x0, 3, B), (0, -1, 0), (-1, 0, 0)), coll)
    place(objs, "dr_roof_s3_mid_a", frame((x0, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s3_mid_b", frame((x0 + 3, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s3_verge", frame((x0 + 6, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s3_verge", frame((x0, 3, B), (-1, 0, 0), (0, 1, 0)), coll)
    place(objs, "dr_chimney_a", Matrix.Translation((x0 + 4.6, 1.5, B)), coll)
    disc(coll, x0 + 2.0, -1.3)
    # stone house, lot x 9..15, y 0..6
    x0 = x_off + 9; f = faces(x0, 0, x0 + 6, 6)
    run("front", ["dr_house_st_door", "dr_house_st_window"]); run("back", ["dr_house_st_plain_a", "dr_house_st_plain_b"])
    run("right", ["dr_house_st_plain_a", "dr_house_st_window"]); run("left", ["dr_house_st_plain_b", "dr_house_st_plain_a"])
    for face in ("front", "right", "back", "left"):
        (sx, sy), a, o = f[face]
        place(objs, "dr_house_st_quoin", frame((sx, sy, 0), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    place(objs, "dr_gable_st_s6", frame((x0 + 6, 0, B), (0, 1, 0), (1, 0, 0)), coll)
    place(objs, "dr_gable_st_s6", frame((x0, 6, B), (0, -1, 0), (-1, 0, 0)), coll)
    place(objs, "dr_roof_s6_mid_a", frame((x0, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s6_mid_b", frame((x0 + 3, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s6_verge", frame((x0 + 6, 0, B), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_roof_s6_verge", frame((x0, 6, B), (-1, 0, 0), (0, 1, 0)), coll)
    place(objs, "dr_chimney_a", Matrix.Translation((x0 + 1.4, 3.0, B)), coll)
    disc(coll, x0 + 2.0, -1.3); disc(coll, x0 + 3.4, -1.3, 0.63)
    # the second timber gable pair on a 6 x 6 timber lot would need s6: shown in the module rows


def setup_scene():
    sc = bpy.context.scene
    if bpy.data.objects.get("sun"):   # (several batches in one run: one light rig)
        return sc
    try:
        sc.render.engine = "CYCLES"
    except TypeError as e:
        print("ENGINE", e)
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.32, 0.34, 0.38, 1); bg.inputs["Strength"].default_value = 0.6
    sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.2; sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun); so.rotation_euler = (math.radians(50), 0, math.radians(-35)); sc.collection.objects.link(so)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, -0.005))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("pv_ground"); gm.use_nodes = True
    b = next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED"); b.inputs["Base Color"].default_value = (0.11, 0.1, 0.09, 1)
    g.data.materials.append(gm)
    return sc


def render_row(sc, coll, out, res, labels, title):
    """One ortho render of a collection; labels = [(text, world point)]."""
    for c in bpy.data.collections:
        c.hide_render = c is not coll
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(v) for o in coll.objects for v in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), 0)); hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (lo + hi) * 0.5
    cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"
    co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co); sc.camera = co
    el, az = math.radians(30), math.radians(-18)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    co.location = ctr + d * 80
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = res
    bpy.context.view_layer.update()
    # fit the ortho scale to the projected extents
    cam.ortho_scale = 10.0
    bpy.context.view_layer.update()
    vs = [world_to_camera_view(sc, co, p) for p in pts]
    span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs))   # (both fractions of the frame)
    cam.ortho_scale = 10.0 * span * 1.1
    print("FIT", coll.name, tuple(round(c, 2) for c in lo), tuple(round(c, 2) for c in hi), round(span, 3), len(pts))
    bpy.context.view_layer.update()
    vs = [world_to_camera_view(sc, co, p) for p in pts]
    cx = (max(v.x for v in vs) + min(v.x for v in vs)) * 0.5 - 0.5; cy = (max(v.y for v in vs) + min(v.y for v in vs)) * 0.5 - 0.5
    cam.shift_x = cx; cam.shift_y = cy * res[1] / res[0] - 0.03
    bpy.context.view_layer.update()
    sc.render.filepath = out
    sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    lab = []
    for t, p in labels:
        v = world_to_camera_view(sc, co, Vector(p))
        lab.append((t, v.x * res[0], (1 - v.y) * res[1]))
    bpy.data.objects.remove(co)
    return lab


ROWS = {
    "K1": [
        ("timber house panels 3.0 x 2.5 (the corner post at the end)", ["dr_house_tb_plain_a", "dr_house_tb_plain_b", "dr_house_tb_window", "dr_house_tb_window_lit", "dr_house_tb_door", "dr_house_tb_blank", "dr_house_tb_post"], 4.0, False),
        ("stone house panels 3.0 x 2.5 + quoin + chimney (25 mm and 32 mm discs; chimney from its eaves-line origin)", ["dr_house_st_plain_a", "dr_house_st_plain_b", "dr_house_st_window", "dr_house_st_door", "dr_house_st_quoin", "dr_chimney_a"], 4.0, True),
        ("gables (origin = the eaves line, 2.5 in up in a house; shown on the ground)", ["dr_gable_tb_s3", "dr_gable_tb_s3_b", "dr_gable_st_s3", "dr_gable_tb_s6", "dr_gable_tb_s6_b", "dr_gable_st_s6"], 1.2, False),
        ("roof segments (origin = the eaves line of the front wall; span 3 / 6, 3 in along the ridge; verge 0.32)", ["dr_roof_s3_mid_a", "dr_roof_s3_mid_b", "dr_roof_s3_verge", "dr_roof_s6_mid_a", "dr_roof_s6_mid_b", "dr_roof_s6_verge"], 2.0, False),
    ],
    "K2": [
        ("ruin tier faces 3 x 3 (foot = stands on walkable ground: plinth + damp; plain / window = upper bands, no damp)", ["dr_ruin_face_foot_a", "dr_ruin_face_foot_b", "dr_ruin_face_plain_a", "dr_ruin_face_plain_b", "dr_ruin_face_plain_c"], 3.0, True),
        ("window (bricked up), doorway (dark, closed by rubble), quoin, ladders (pale timber, 1.0 in)", ["dr_ruin_face_window", "dr_ruin_face_doorway", "dr_ruin_quoin", "dr_ladder_3in", "dr_ladder_top"], 3.0, True),
        ("top edges: parapet stubs (<= 0.7 high, inside the 0.4 strip), ruin gables (<= 0.3 thick, <= 2.6), deck edges (<= 0.2 out)", ["dr_parapet_stub_a", "dr_parapet_stub_b", "dr_parapet_stub_c", "dr_ruin_gable_s3", "dr_ruin_gable_s6", "dr_deck_edge_a", "dr_deck_edge_b"], 2.0, False),
    ],
    "K3": [
        ("town wall faces 3 x 3, ct_stone_big (foot = batter inside the cell; corbel = string course under a 6 / 9 in walk; ragged = beside a breach)", ["dr_twall_foot", "dr_twall_face_a", "dr_twall_face_b", "dr_twall_slit", "dr_twall_corbel", "dr_twall_ragged", "dr_twall_quoin"], 2.5, True),
        ("merlon runs (<= 0.7 high, inside the 0.4 strip, no regular rhythm) and tower faces", ["dr_merlon_run_a", "dr_merlon_run_b", "dr_merlon_run_broken", "dr_tower_foot", "dr_tower_face_a", "dr_tower_face_b", "dr_tower_slit", "dr_tower_quoin"], 2.0, True),
        ("tower tops: slate cap / burnt-out, inside the 12 in top band, apex exactly 12 in (shown from their 12 in origin)", ["dr_tower_cap_slate", "dr_tower_cap_burnt"], 3.0, False),
    ],
}


def faces_of(x0, y0, x1, y1):
    return {"front": ((x0, y0), (1, 0), (0, -1)), "right": ((x1, y0), (0, 1), (1, 0)),
            "back": ((x1, y1), (-1, 0), (0, 1)), "left": ((x0, y1), (0, -1), (-1, 0))}


def run(objs, coll, f, face, mods, z=0.0, start=0):
    (sx, sy), a, o = f[face]
    for i, m in enumerate(mods):
        if m:
            place(objs, m, frame((sx + a[0] * 3 * (i + start), sy + a[1] * 3 * (i + start), z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)


def top_plane(coll, x0, y0, x1, y1, z, mat):
    bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, z))
    o = bpy.context.active_object
    o.scale = (x1 - x0, y1 - y0, 1)
    o.data.materials.append(bpy.data.materials.get("pv_" + mat) or preview_material(mat))
    if not o.data.color_attributes:
        o.data.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
        for d in o.data.color_attributes["Color"].data:
            d.color = (0.5, 0.5, 0.5, 0.3)
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)


def tiers(objs, coll, x_off):
    """A ruin tier by the grammar: a Block lot 6 x 3 at 3 in, against a Deck lot 3 x 3 at 6 in; foot bands on walkable ground,
    upper bands above, quoins per band at convex corners, a ladder from the street (its face plain, no parapet near its top),
    a ladder from the 3 in tier to the 6 in deck, parapet stubs on the free top edge, a ruin gable on the Block's end face,
    deck edges round the deck. The tops are preview planes (in the game: generated quads)."""
    X = x_off
    f = faces_of(X, 0, X + 6, 3)
    run(objs, coll, f, "front", ["dr_ruin_face_foot_a", "dr_ruin_face_foot_b"])
    run(objs, coll, f, "back", ["dr_ruin_face_foot_b", "dr_ruin_face_doorway"])
    run(objs, coll, f, "left", ["dr_ruin_face_foot_a"])
    place(objs, "dr_ladder_top", frame((X + 1.5, 0, 0), (1, 0, 0), (0, -1, 0)), coll)
    run(objs, coll, f, "front", [None, "dr_parapet_stub_a"], z=3.0)
    place(objs, "dr_ruin_gable_s3", frame((X, 3, 3.0), (0, -1, 0), (-1, 0, 0)), coll)
    for face in ("front", "left"):
        (sx, sy), a, o = f[face]
        place(objs, "dr_ruin_quoin", frame((sx, sy, 0), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    top_plane(coll, X, 0, X + 6, 3, 3.0, "ct_flags")
    g = faces_of(X + 6, 0, X + 9, 3)
    run(objs, coll, g, "front", ["dr_ruin_face_window"], z=3.0)
    run(objs, coll, g, "front", ["dr_ruin_face_foot_a"], z=0.0)
    run(objs, coll, g, "right", ["dr_ruin_face_foot_b"], z=0.0)
    run(objs, coll, g, "right", ["dr_ruin_face_plain_c"], z=3.0)
    run(objs, coll, g, "back", ["dr_ruin_face_plain_a"], z=3.0)
    run(objs, coll, g, "back", ["dr_ruin_face_foot_a"], z=0.0)
    run(objs, coll, g, "left", ["dr_ruin_face_foot_b"], z=3.0)   # stands on the 3 in tier top: a foot band
    place(objs, "dr_ladder_top", frame((X + 6, 1.5, 3.0), (0, -1, 0), (-1, 0, 0)), coll)
    run(objs, coll, g, "front", ["dr_deck_edge_a"], z=6.0)
    run(objs, coll, g, "right", ["dr_deck_edge_b"], z=6.0)
    for face in ("front", "right"):
        (sx, sy), a, o = g[face]
        for z in (0.0, 3.0):
            place(objs, "dr_ruin_quoin", frame((sx, sy, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    top_plane(coll, X + 6, 0, X + 9, 3, 6.0, "ct_timber")
    disc(coll, X + 2.0, -1.3); disc(coll, X + 3.4, -1.3, 0.63); disc(coll, X + 4.5, 1.0, DISC_R)


def walls(objs, coll, x_off):
    """A town wall by the grammar: a breach cell (level 0, open), two wall cells at 6 in and one at 9 in, merlons on the field
    edge, the face beside the breach ragged; two tall towers 6 x 6 at 12 in, one capped, one burnt out."""
    X = x_off
    f = faces_of(X, 0, X + 6, 3)   # the 6 in wall, two cells
    run(objs, coll, f, "front", ["dr_twall_foot", "dr_twall_foot"])
    run(objs, coll, f, "front", ["dr_twall_corbel", "dr_twall_slit"], z=3.0)
    run(objs, coll, f, "back", ["dr_twall_foot", "dr_twall_foot"])
    run(objs, coll, f, "back", ["dr_twall_face_a", "dr_twall_face_b"], z=3.0)
    run(objs, coll, f, "left", ["dr_twall_ragged"]); run(objs, coll, f, "left", ["dr_twall_ragged"], z=3.0)
    run(objs, coll, f, "front", ["dr_merlon_run_a", "dr_merlon_run_broken"], z=6.0)
    for z in (0.0, 3.0):
        (sx, sy), a, o = f["left"]
        place(objs, "dr_twall_quoin", frame((sx, sy, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
        (sx, sy), a, o = f["front"]
        place(objs, "dr_twall_quoin", frame((sx, sy, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    top_plane(coll, X, 0, X + 6, 3, 6.0, "ct_flags")
    g = faces_of(X + 6, 0, X + 9, 3)   # the 9 in cell
    run(objs, coll, g, "front", ["dr_twall_foot"]); run(objs, coll, g, "front", ["dr_twall_face_a"], z=3.0)
    run(objs, coll, g, "front", ["dr_twall_corbel"], z=6.0)
    run(objs, coll, g, "right", ["dr_twall_foot"]); run(objs, coll, g, "right", ["dr_twall_face_b"], z=3.0)
    run(objs, coll, g, "right", ["dr_twall_slit"], z=6.0)
    run(objs, coll, g, "back", ["dr_twall_foot"]); run(objs, coll, g, "back", ["dr_twall_face_a"], z=3.0)
    run(objs, coll, g, "back", ["dr_twall_face_b"], z=6.0)
    run(objs, coll, g, "left", ["dr_twall_face_a"], z=6.0)
    for face in ("front", "back", "left"):
        run(objs, coll, g, face, ["dr_merlon_run_b"], z=9.0)
    run(objs, coll, g, "right", ["dr_merlon_run_a"], z=9.0)
    for face in ("front", "right"):
        (sx, sy), a, o = g[face]
        for z in (0.0, 3.0, 6.0):
            place(objs, "dr_twall_quoin", frame((sx, sy, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    top_plane(coll, X + 6, 0, X + 9, 3, 9.0, "ct_flags")
    for tx, cap in ((X + 12, "dr_tower_cap_slate"), (X + 21, "dr_tower_cap_burnt")):
        h = faces_of(tx, 0, tx + 6, 6)
        for face in ("front", "right", "back", "left"):
            run(objs, coll, h, face, ["dr_tower_foot", "dr_tower_foot"])
            run(objs, coll, h, face, ["dr_tower_face_a", "dr_tower_slit"], z=3.0)
            run(objs, coll, h, face, ["dr_tower_face_b", "dr_tower_face_a"], z=6.0)
            if cap != "dr_tower_cap_slate":   # (the slate cap module carries the whole top band itself)
                run(objs, coll, h, face, ["dr_tower_slit", "dr_tower_face_b"], z=9.0)
            (sx, sy), a, o = h[face]
            for z in ((0.0, 3.0, 6.0) if cap == "dr_tower_cap_slate" else (0.0, 3.0, 6.0, 9.0)):
                place(objs, "dr_tower_quoin", frame((sx, sy, z), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
        place(objs, cap, frame((tx, 0, 12.0), (1, 0, 0), (0, -1, 0)), coll)
    disc(coll, X - 1.5, -1.3); disc(coll, X - 1.5, 0.3, 0.63); disc(coll, X + 1.5, 1.5); disc(coll, X + 7.5, 1.5)


ASSEMBLY = {"K1": (houses, "two lots assembled by the grammar's face convention (preview: faces ON the collider, no inset; 25 mm discs)",
                   [("timber house 6 x 3 (span 3): door, lit window, s3 gables, verges, chimney", (3, -2.6, 0)),
                    ("stone house 6 x 6 (span 6): quoins, s6 gables, mid_a + mid_b", (12, -2.6, 0))]),
            "K3": (walls, "a town wall by the grammar (breach on the left, 6 in and 9 in walks, merlons) and two 12 in towers: slate cap / burnt out",
                   [("wall: ragged face at the breach, corbels, slits, merlons", (4, -2.6, 0)), ("tower 6 x 6, capped", (15, -2.6, 0)),
                    ("tower 6 x 6, burnt out", (24, -2.6, 0))]),
            "K2": (tiers, "a ruin tier by the grammar: Block 6 x 3 at 3 in + Deck 3 x 3 at 6 in, two ladders (preview tops; discs on the street and the tier)",
                   [("Block lot 3 in: foot bands, parapet, ruin gable, ladder", (3, -2.6, 0)), ("Deck lot 6 in: window band, deck edges, ladder from the tier", (8, -2.6, 0))])}


PV_OVERRIDE = {}   # module name -> a function returning its preview material (vegetation: the material the game still lacks)


def _late():
    """K4 / K5 rows and assemblies live in their batch files."""
    for mod in ("kit_k4_sheet", "kit_k5_sheet", "kit_k5b_sheet", "kit_house_rows_sheet", "kit_house_flush_sheet"):
        try:
            km = __import__(mod)
        except ImportError:
            continue
        ROWS.update(km.ROWS); ASSEMBLY.update(km.ASSEMBLY)
        PV_OVERRIDE.update(getattr(km, "PV_OVERRIDE", {}))


def render_batch(batch, objs, T, out_dir):
    _late()
    """Renders the rows of one batch + its assembly to PNGs and writes rows.json (composed by compose_sheet.py)."""
    import json
    sc = setup_scene()
    for name, o in objs.items():   # preview materials on the built meshes (the GLBs on disk keep their placeholders)
        me = o.data
        for i, m in enumerate(me.materials):
            if name in PV_OVERRIDE:
                me.materials[i] = PV_OVERRIDE[name]()
            elif not m.name.startswith("pv_"):
                me.materials[i] = bpy.data.materials.get("pv_" + m.name) or preview_material(m.name)
        o.hide_render = True
    meta = []
    for k, (title, names, gap, two_discs) in enumerate(ROWS[batch]):
        coll = bpy.data.collections.new(f"{batch}_row{k}"); bpy.context.scene.collection.children.link(coll)
        x = 0.0; labels = []
        for n in names:
            bb = objs[n].bound_box
            oy = -min(v[1] for v in bb) if batch in ("K4", "K5", "K5b") else 0.0   # (centred props: their front at y = 0, the discs before them)
            oz = max(0.0, -min(v[2] for v in bb)) if batch in ("K4", "K5", "K5b") else 0.0                            # (a wall bracket hangs below its origin: shown lifted)
            o = place(objs, n, Matrix.Translation((x - bb[0][0], oy, oz)), coll)
            w = max(v[0] for v in objs[n].bound_box) - min(v[0] for v in objs[n].bound_box)
            if two_discs:   # 25 mm and 32 mm discs (judge the stone size)
                disc(coll, x + w * 0.5 - 0.6, -1.6); disc(coll, x + w * 0.5 + 0.55, -1.6, 0.63)
            else:
                disc(coll, x + w * 0.5, -1.6)
            e = T[n]
            labels.append((f"{n}\n{e['tris']} tris, proud {e['proud_in']['low']}/{e['proud_in']['high']}", (x + w * 0.5, -2.4, 0)))
            x += w + gap
        png = os.path.join(out_dir, f"row{k}.png")
        lab = render_row(bpy.context.scene, coll, png, (2600, 900), labels, title)
        meta.append({"png": png, "title": title, "labels": lab})
    fn, title, labels = ASSEMBLY[batch]
    coll = bpy.data.collections.new(f"{batch}_assembly"); bpy.context.scene.collection.children.link(coll)
    fn(objs, coll, 0.0)
    png = os.path.join(out_dir, "row_assembly.png")
    lab = render_row(bpy.context.scene, coll, png, (2600, 1300), labels, title)
    meta.append({"png": png, "title": title, "labels": lab, "batch": batch})
    json.dump(meta, open(os.path.join(out_dir, "rows.json"), "w"), indent=1)
