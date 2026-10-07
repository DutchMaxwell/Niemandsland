"""Blender probe for idle_pet_floor_test.py: a tilted owner armature, a synthetic pet rat part (an elongated blob that touches the floor), the real
pet rig and loop. Prints the pet's lowest vertex relative to the intended floor, at placement and over the whole sway.
blender -b --factory-startup -P test/idle_pet_floor_probe.py -- <repo tools/idle dir> <out.json>"""
import bpy, json, math, sys, tempfile
from mathutils import Euler, Vector

tools, out = sys.argv[sys.argv.index("--") + 1:][:2]
sys.path.insert(0, tools)
from pet_rig import add_pet, make_pose

bpy.ops.wm.read_factory_settings(use_empty=True)
# owner armature with one bone, tilted like the keep_rig armatures (rig alignment of about 15 degrees)
data = bpy.data.armatures.new("owner")
arm = bpy.data.objects.new("owner", data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
arm.rotation_euler = Euler((math.radians(14), math.radians(-3), math.radians(5)))
bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="EDIT")
b = data.edit_bones.new("Hips")
b.head, b.tail = Vector((0, 0, 1)), Vector((0, 0, 1.2))
bpy.ops.object.mode_set(mode="OBJECT")

# pet part glb: a blob 0.35 x 0.94 x 0.5 (nose at -Y), bottom exactly on z = -0.25, with fine tessellation so the reduction really moves vertices
bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=64, radius=0.5, location=(0, 0, 0))
blob = bpy.context.object
blob.scale = (0.35, 0.94, 0.5)
bpy.ops.object.transform_apply(scale=True)
for v in blob.data.vertices:
    v.co.z = max(v.co.z, -0.25) if v.co.z > -0.25 else -0.25   # flat feet at the floor
path = tempfile.mkdtemp() + "/pet.glb"
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)
bpy.data.objects.remove(blob, do_unlink=True)

feet_z = -0.8
pet, bones = add_pet(arm, path, [1.0, -0.1, 0.35], [0, 0, 0], 1.4, feet_z, tris=4000)
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()


def lowest():
    ev = pet.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    low = min((pet.matrix_world @ v.co).z for v in m.vertices)
    ev.to_mesh_clear()
    return low - feet_z


placed = lowest()
pose = make_pose(arm, bpy.context.view_layer)
lows = []
for k in range(24):
    pose(k / 24)
    bpy.context.view_layer.update()
    lows.append(lowest())
result = {"placed": placed, "min": min(lows), "max": max(lows), "bones": bones}
json.dump(result, open(out, "w"))
print("PET_FLOOR", json.dumps(result))
