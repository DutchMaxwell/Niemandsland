# kit_k4_sheet.py - the K4 rows and assembly of the review sheet (preview only; used by kit_sheet.render_batch).
import bpy, os
from mathutils import Matrix
import kit_table, kit_sheet
from kit_sheet import place, frame, disc, faces_of, run, top_plane, DISC_R

GPRE = {"cobbles": "cobbles", "earth": "earth", "plot": "earth", "yard_flags": "flags"}


def ground(coll, x0, y0, x1, y1, kind, z=0.002):
    """A preview ground patch: the set of the manifest's ground class x its tone x 1.6 (as the kit's preview materials)."""
    name = "pv_ground_" + kind
    m = bpy.data.materials.get(name)
    if not m:
        d = kit_table.GROUND[kind]
        m = bpy.data.materials.new(name); m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
        s = 1.0 / d["tile_in"]; mp.inputs["Scale"].default_value = (s, s, s)
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(os.path.join(kit_sheet.TEX, GPRE[kind] + "_Diffuse.jpg"), check_existing=True)
        nt.links.new(mp.outputs["Vector"], t.inputs["Vector"])
        mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
        nt.links.new(t.outputs["Color"], mul.inputs[6]); mul.inputs[7].default_value = (*[c * 1.6 for c in d["tone"]], 1.0)
        nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(os.path.join(kit_sheet.TEX, GPRE[kind] + "_nor_gl.jpg"), check_existing=True)
        n.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(n.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = 0.85
    bpy.ops.mesh.primitive_plane_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, z))
    o = bpy.context.active_object
    o.scale = (x1 - x0, y1 - y0, 1)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    o.data.materials.append(m)
    for c in o.users_collection:
        c.objects.unlink(o)
    coll.objects.link(o)
    return o


def water(coll, x0, y0, x1, y1, z=0.07):
    top_plane(coll, x0, y0, x1, y1, z, "ct_glass_dark")


def scene(objs, coll, X):
    """K4 by the grammar: a street with a lamp post at a cell corner and a wall lantern on a stone house (2.6 in up), the
    fountain on its 6 x 6 footprint, the statue cell, a pool cell with kerbs on its four edges, two plot cells."""
    ground(coll, X - 2, -4, X + 34, 9, "cobbles", 0.0)
    f = faces_of(X, 3, X + 6, 6)   # a stone house front (two panels) carrying the bracket
    run(objs, coll, f, "front", ["dr_house_st_plain_a", "dr_house_st_door"])
    (sx, sy), a, o = f["front"]
    place(objs, "dr_house_st_quoin", frame((sx, sy, 0), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    place(objs, "dr_lamp_bracket", frame((X + 2.2, 3, 2.6), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_lamp_post", Matrix.Translation((X + 7.5, 0.0, 0)), coll)
    disc(coll, X + 6.6, -0.4); disc(coll, X + 8.6, -0.3, 0.63)
    place(objs, "dr_fountain", Matrix.Translation((X + 12.5, 3.0, 0)), coll)
    ground(coll, X + 9.5, 0, X + 15.5, 6, "yard_flags", 0.004)
    disc(coll, X + 10.2, -0.8); disc(coll, X + 15.9, -0.7, 0.63)
    place(objs, "dr_statue_plinth", Matrix.Translation((X + 19.0, 1.5, 0)), coll)
    disc(coll, X + 17.0, 0.3); disc(coll, X + 20.9, -0.3, 0.63)
    px, py = X + 22.5, 3.5   # the pool cell
    water(coll, px, py, px + 3, py + 3)
    for face, (st, al, ou) in {"front": ((px, py), (1, 0), (0, -1)), "right": ((px + 3, py), (0, 1), (1, 0)),
                               "back": ((px + 3, py + 3), (-1, 0), (0, 1)), "left": ((px, py + 3), (0, -1), (-1, 0))}.items():
        place(objs, "dr_pool_kerb", frame((st[0], st[1], 0), (al[0], al[1], 0), (ou[0], ou[1], 0)), coll)
    disc(coll, px + 1.0, py - 0.8)
    for k, mods in enumerate((["dr_plot_weeds_a", "dr_plot_fence_run"], ["dr_plot_weeds_b", "dr_plot_deadbush", "dr_plot_fence_run"])):
        gx = X + 27 + 3 * k
        ground(coll, gx, 0, gx + 3, 3, "plot", 0.004)
        for m in mods:
            place(objs, m, frame((gx, 0, 0), (1, 0, 0), (0, -1, 0)), coll)
    place(objs, "dr_plot_fence_run", frame((X + 33, 0, 0), (0, 1, 0), (1, 0, 0)), coll)
    disc(coll, X + 28.0, -0.9); disc(coll, X + 31.0, -0.95, 0.63)


ROWS = {"K4": [
    ("lamp post (<= 0.2 in thick, glass centre 2.55 in), wall lantern (shown lifted: its origin is 2.6 in up a wall), statue plinth, pool kerb (flat), fence run, dead bush - 25 mm and 32 mm discs",
     ["dr_lamp_post", "dr_lamp_bracket", "dr_statue_plinth", "dr_pool_kerb", "dr_plot_fence_run", "dr_plot_deadbush"], 2.6, True),
    ("fountain (inside 5.6 in of its 6 x 6 in solid footprint, top 2.5 in) and the two weed covers of a 3 x 3 in plot cell",
     ["dr_fountain", "dr_plot_weeds_a", "dr_plot_weeds_b"], 2.0, True)]}
ASSEMBLY = {"K4": (scene, "K4 by the grammar on cobbles: wall lantern at 2.6 in + lamp post at a cell corner, fountain on its footprint, statue cell, pool cell with four kerbs, two plot cells",
                   [("stone house + bracket, lamp post", (4, -2.2, 0)), ("fountain 6 x 6", (12.5, -2.2, 0)), ("statue cell", (19, -2.2, 0)),
                    ("pool cell + kerbs", (24, -2.2, 0)), ("plot cells: weeds a / b, fence, dead bush", (30, -2.2, 0))])}
