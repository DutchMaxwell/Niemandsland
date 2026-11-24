# kit_house_flush_sheet.py - the stone-house sheet after the relief on ct_stone_fine was removed (tile 2.25 kept).
# Same rows / assembly / head-on 248 px / in strip as the house rows sheet, plus one PLAY-CAMERA view: perspective, vertical FOV 60
# (scenes/main.tscn), ~27 in from the house, 55 deg down, 1920 x 1080 = the game's pixels at 1080p.
import bpy, os, math
from mathutils import Vector
import kit_house_rows_sheet
from kit_house_rows_sheet import street_crop

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROWS_DIR = os.path.join(REPO, "build", "sheets", "rows_flush")
PLAY = {"dist": 27.0, "pitch": 55.0, "fov": 60.0, "res": (1920, 1080)}


def play_view(coll, target, out_png):
    sc = bpy.context.scene
    for c in bpy.data.collections:
        c.hide_render = c is not coll
    cam = bpy.data.cameras.new("cam_play"); cam.type = "PERSP"; cam.sensor_fit = "VERTICAL"; cam.lens_unit = "FOV"
    cam.angle = math.radians(PLAY["fov"])
    co = bpy.data.objects.new("cam_play", cam); sc.collection.objects.link(co); sc.camera = co
    el, az = math.radians(PLAY["pitch"]), math.radians(-18)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    co.location = Vector(target) + d * PLAY["dist"]
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = PLAY["res"]
    sc.render.filepath = out_png; sc.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(co)


def scene(objs, coll, X):
    os.makedirs(ROWS_DIR, exist_ok=True)
    street_crop(objs, os.path.join(ROWS_DIR, "row_street2x.png"))   # (same framing as the house rows sheet)
    # build the house rows assembly WITHOUT its own street crop, then the play view of it
    orig = kit_house_rows_sheet.street_crop
    kit_house_rows_sheet.street_crop = lambda *a, **k: None
    try:
        kit_house_rows_sheet.scene(objs, coll, X)
    finally:
        kit_house_rows_sheet.street_crop = orig
    play_view(coll, (X + 6.0, 3.0, 1.5), os.path.join(ROWS_DIR, "row_play.png"))


ROWS = {"house_flush": [(t.replace("ct_stone_fine", "ct_stone_fine, NO relief", 1), n, g, two) for t, n, g, two in kit_house_rows_sheet.ROWS["house_rows"]]}
ASSEMBLY = {"house_flush": (scene, kit_house_rows_sheet.ASSEMBLY["house_rows"][1].replace("(tile 2.25)", "(tile 2.25, flush: no course steps / proud stones)", 1),
                            kit_house_rows_sheet.ASSEMBLY["house_rows"][2])}
