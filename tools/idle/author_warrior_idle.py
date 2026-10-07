"""Preserved from the approved 2026-09-24 real-idle prototype: REAL rig + REAL idle -> animated GLB for the game.

blender -b -P tools/idle/author_warrior_idle.py -- <keep_rig.glb> <out.glb> <out.json> <twohand 0|1>

Same idle as idle_real.py ("## Real idle"): weapons on their bones (W_<bone>_<i>), a 5-bone tail chain along the
generated 'Joined rat tail' (skipped if the body has none), 9 s additive loop at 24 fps on the calibrated pose,
feet re-solved onto their calibrated ankles. Two-handed forms (recipe weapon_hold) get no arm/shoulder tracks so the
support hand stays on the shaft. Exports armature + skin + bone-parented weapons + the 'idle' animation, textures
embedded, no Draco. The sidecar JSON carries the calibrated body's lowest point (the static bake grounds it at 0).
"""
import bpy, sys, json

a = sys.argv[sys.argv.index("--") + 1:]
IN, OUT, SIDE, TWOHAND = a[0], a[1], a[2], a[3] == "1"
L, FPS, P = 216, 24, "mixamorig:"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN)
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.lower().startswith("icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers))
weapons = [o for o in bpy.data.objects if o.name.startswith("W_")]
view = bpy.context.view_layer
info = {"weapons": [], "twohand": TWOHAND}

# calibrated pose: the body's lowest point (game_optimize grounds the static bake's body at exactly this height)
deps = bpy.context.evaluated_depsgraph_get()
ev = body.evaluated_get(deps).to_mesh()
info["feet_z"] = min((body.matrix_world @ v.co).z for v in ev.vertices)
body.evaluated_get(deps).to_mesh_clear()

for w in weapons:
    bone = P + w.name.split("_")[1]
    world = w.matrix_world.copy()
    w.parent, w.parent_type, w.parent_bone = arm, "BONE", bone
    view.update()
    w.matrix_world = world
    info["weapons"].append([w.name, bone])
view.update()

# Blender does not add the -P script directory to sys.path.
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from warrior_tail import add_tail
from warrior_pose import create_pose

tail_bones, info["tail_verts"] = add_tail(arm, body, P)
info["tail_bones"] = len(tail_bones)
ANIM, pose_at = create_pose(arm, tail_bones, TWOHAND, body)
pb = arm.pose.bones

mod = next(m for m in body.modifiers if m.type == "ARMATURE")
mod.show_viewport = False
for f in range(L + 1):
    pose_at((f % L) / L)
    for n in ANIM:
        pb[n].keyframe_insert("rotation_quaternion", frame=f)
        pb[n].keyframe_insert("location", frame=f)
mod.show_viewport = True
arm.animation_data.action.name = "idle"
scene = bpy.context.scene
scene.render.fps = FPS
scene.frame_start, scene.frame_end = 0, L
scene.frame_set(0)
info["tracks"] = len(ANIM)
bpy.ops.object.select_all(action="DESELECT")
for o in [arm, body, *weapons]:
    o.select_set(True)
view.objects.active = arm
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_skins=True, export_animations=True, export_force_sampling=True,
                          export_frame_range=True, export_rest_position_armature=False,
                          export_image_format="WEBP", export_image_quality=90)
json.dump(info, open(SIDE, "w"), indent=1)
print("IDLE_EXPORT", json.dumps(info), flush=True)
