"""Blender probe for idle_tail_floor_test.py: synthetic mixamorig rig whose tail rests on the floor, posed through the real idle loop.
blender -b --factory-startup -P test/idle_tail_floor_probe.py -- <repo tools/idle dir> <out.json>"""
import bpy, json, sys
from mathutils import Vector

_a = sys.argv[sys.argv.index("--") + 1:]
tools, out = _a[:2]
MERGED = len(_a) > 2 and _a[2] == "merged"   # tail geometry merged into the body mesh, no Tail bones in the rig
sys.path.insert(0, tools)
from warrior_pose import create_pose
from warrior_tail import add_tail

P = "mixamorig:"
bpy.ops.wm.read_factory_settings(use_empty=True)
arm_data = bpy.data.armatures.new("rig")
arm = bpy.data.objects.new("rig", arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
JOINTS = {  # name: (head, tail, parent)
    "Hips": ((0, 0, 1.0), (0, 0, 1.1), None), "Spine": ((0, 0, 1.1), (0, 0, 1.25), "Hips"), "Spine1": ((0, 0, 1.25), (0, 0, 1.4), "Spine"),
    "Spine2": ((0, 0, 1.4), (0, 0, 1.5), "Spine1"), "Neck": ((0, 0, 1.5), (0, 0, 1.6), "Spine2"), "Head": ((0, 0, 1.6), (0, 0, 1.8), "Neck"),
}
for side, x in (("Left", 0.1), ("Right", -0.1)):
    JOINTS[side + "UpLeg"] = ((x, 0, 0.95), (x, 0.05, 0.5), "Hips")
    JOINTS[side + "Leg"] = ((x, 0.05, 0.5), (x, 0, 0.1), side + "UpLeg")
    JOINTS[side + "Foot"] = ((x, 0, 0.1), (x, -0.1, 0.0), side + "Leg")
for n, (h, t, parent) in JOINTS.items():
    b = arm_data.edit_bones.new(P + n)
    b.head, b.tail = Vector(h), Vector(t)
    if parent:
        b.parent = arm_data.edit_bones[P + parent]
TAIL = [(0, 0.1, 0.9), (0, 0.4, 0.4), (0, 0.7, 0.08), (0, 1.0, 0.05), (0, 1.3, 0.05), (0, 1.6, 0.05)]
for i in range(0 if MERGED else 5):
    b = arm_data.edit_bones.new(f"Tail{i}")
    b.head, b.tail = Vector(TAIL[i]), Vector(TAIL[i + 1])
    b.parent = arm_data.edit_bones[P + "Hips"] if i == 0 else arm_data.edit_bones[f"Tail{i - 1}"]
bpy.ops.object.mode_set(mode="OBJECT")

# body mesh: a hips block plus a tube along the tail that touches z = 0 (ring radius 0.05 around z = 0.05)
verts, weights = [], []
for sx in (-0.15, 0.15):
    for sy in (-0.1, 0.1):
        for sz in (0.9, 1.1):
            verts.append((sx, sy, sz))
            weights.append((P + "Hips", 1.0))
for i in range(5):
    for k in range(8):
        a = (TAIL[i][0], TAIL[i][1], TAIL[i][2]) if k < 4 else TAIL[i + 1]
        dx, dz = [(0.05, 0), (-0.05, 0), (0, 0.05), (0, -0.05)][k % 4]
        verts.append((a[0] + dx, a[1], a[2] + dz))
        weights.append((P + "Hips" if MERGED else f"Tail{i}", 1.0))
mesh = bpy.data.meshes.new("body")
mesh.from_pydata(verts, [], [])
body = bpy.data.objects.new("body", mesh)
bpy.context.collection.objects.link(body)
for n in {w[0] for w in weights}:
    body.vertex_groups.new(name=n)
for i, (n, w) in enumerate(weights):
    body.vertex_groups[n].add([i], w, "REPLACE")
body.parent = arm
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
bpy.context.view_layer.update()


def tail_low():
    deps = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(deps)
    m = ev.to_mesh()
    tail = [v for v in body.data.vertices if any(body.vertex_groups[g.group].name.startswith("Tail") for g in v.groups)]
    low = min((body.matrix_world @ m.vertices[v.index].co).z for v in tail)
    ev.to_mesh_clear()
    return low


result = {}
if MERGED:
    bpy.context.view_layer.update()
    names, count = add_tail(arm, body, P, {"cut_y": 0.3, "max_z": 1.0})
    result["region"] = {"bones": names, "verts": count}
for label, kw in (("rigid_sway", {}), ("floor_follow", {"body": body})):
    for p in arm.pose.bones:  # create_pose takes the current pose as the calibrated base: start every variant from rest
        p.rotation_mode = "QUATERNION"
        p.rotation_quaternion, p.location = (1, 0, 0, 0), (0, 0, 0)
    bpy.context.view_layer.update()
    tail_names = [f"Tail{i}" for i in range(5)]
    ANIM, pose_at = create_pose(arm, tail_names, True, **kw)
    lows = []
    for k in range(12):
        pose_at(k / 12)
        bpy.context.view_layer.update()
        lows.append(tail_low())
    result[label] = {"min": min(lows), "max": max(lows)}
json.dump(result, open(out, "w"))
print("TAIL_FLOOR", json.dumps(result))
