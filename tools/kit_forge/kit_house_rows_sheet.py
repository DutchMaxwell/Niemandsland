# kit_house_rows_sheet.py - the stone-house rows of the review sheet on ct_stone_fine (tile 2.25, 1k set),
# an assembled stone house beside a ruin tier (ct_stone, tile 3.0) for comparison, and a head-on crop at 2 x the street still's
# 124 px / in (written as row_street2x.png; compose_sheet.py adds it through rows.json).
import bpy, os, math
from mathutils import Matrix, Vector
import kit_sheet
from kit_sheet import place, frame, disc, faces_of, run, top_plane, DISC_R

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PX_IN = 248.0   # 2 x the 124 px / in street still


def street_crop(objs, out_png):
    sc = bpy.context.scene
    coll = bpy.data.collections.new("house_street"); sc.collection.children.link(coll)
    x = 0.15
    for n in ("dr_house_st_plain_a", "dr_house_st_window", "dr_house_st_door"):
        place(objs, n, Matrix.Translation((x, 0, 0)), coll); x += 3.0
    place(objs, "dr_ruin_face_foot_a", Matrix.Translation((x + 0.25, 0, 0)), coll)   # the ruin stone at tile 3.0, same bench
    for cx, r in ((1.2, DISC_R), (5.2, 0.63)):   # 25 / 32 mm bases standing against the wall
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=r, depth=0.04, location=(cx, -0.12, r), rotation=(math.radians(90), 0, 0))
        o = bpy.context.active_object
        o.data.materials.append(bpy.data.materials.get("pv_disc"))
        for c in o.users_collection:
            c.objects.unlink(o)
        coll.objects.link(o)
    for c in bpy.data.collections:
        c.hide_render = c is not coll
    res = (3100, 700)
    cam = bpy.data.cameras.new("cam2x"); cam.type = "ORTHO"; cam.ortho_scale = res[0] / PX_IN
    co = bpy.data.objects.new("cam2x", cam); sc.collection.objects.link(co); sc.camera = co
    co.location = (res[0] / PX_IN / 2, -40, res[1] / PX_IN / 2 - 0.1); co.rotation_euler = (math.radians(90), 0, 0)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = out_png; sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(co)
    coll.hide_render = True


def scene(objs, coll, X):
    out = os.path.join(REPO, "build", "sheets", "rows_house", "row_street2x.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    street_crop(objs, out)
    B = 2.5
    x0 = X; f = faces_of(x0, 0, x0 + 6, 6)
    fr = lambda face, mods: run(objs, coll, f, face, mods)
    fr("front", ["dr_house_st_door", "dr_house_st_window"]); fr("back", ["dr_house_st_plain_a", "dr_house_st_plain_b"])
    fr("right", ["dr_house_st_plain_a", "dr_house_st_window"]); fr("left", ["dr_house_st_plain_b", "dr_house_st_plain_a"])
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
    g = faces_of(X + 9, 0, X + 15, 3)   # a ruin tier (ct_stone, tile 3.0: unchanged) beside it
    run(objs, coll, g, "front", ["dr_ruin_face_foot_a", "dr_ruin_face_foot_b"]); run(objs, coll, g, "right", ["dr_ruin_face_foot_a"])
    run(objs, coll, g, "left", ["dr_ruin_face_foot_b"])
    for face in ("front", "right"):
        (sx, sy), a, o = g[face]
        place(objs, "dr_ruin_quoin", frame((sx, sy, 0), (a[0], a[1], 0), (o[0], o[1], 0)), coll)
    top_plane(coll, X + 9, 0, X + 15, 3, 3.0, "ct_flags")
    disc(coll, X + 11.0, -1.3); disc(coll, X + 12.4, -1.3, 0.63)


ROWS = {"house_rows": [
    ("stone HOUSE panels 3.0 x 2.5 on ct_stone_fine (tile 2.25, course 0.375, 1k set) + quoin + chimney - 25 mm and 32 mm discs",
     ["dr_house_st_plain_a", "dr_house_st_plain_b", "dr_house_st_window", "dr_house_st_door", "dr_house_st_quoin", "dr_chimney_a"], 4.0, True),
    ("stone gables s3 / s6 on ct_stone_fine (origin = the eaves line; shown on the ground)", ["dr_gable_st_s3", "dr_gable_st_s6"], 2.0, True)]}
ASSEMBLY = {"house_rows": (scene, "stone house 6 x 6 on ct_stone_fine (tile 2.25) beside a ruin tier on ct_stone (tile 3.0, unchanged) - preview from the 1k source",
                    [("stone house: fine stone", (3, -2.6, 0)), ("ruin tier: tile 3.0", (12, -2.6, 0))])}
