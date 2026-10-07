"""Rig the Ratmen pet rat once and animate it inside the owner's armature: breathing, sniffing, tail sway.

The composed pet forms are the base form plus the static pet part (placement = translation, euler, scale of compose_static.py, in the
grounded frame; the keep_rig frame sits feet_z lower). The pet mesh is reduced, weighted along its head-to-tail axis (body / head / three tail
bones) and its bones are added to the same armature, so one skeleton and one clip drive the whole form. Breathing is a scale about the floor
(feet stay put), the sniff pitches the head, the tail yaws: nothing here can push the pet through the ground.
"""
import bpy, math
from mathutils import Euler, Matrix, Vector

NAMES = ["PetRoot", "PetBody", "PetHead", "PetTail0", "PetTail1", "PetTail2"]


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a))) if a != b else float(x >= a)
    return t * t * (3 - 2 * t)


def add_pet(arm, glb, pos, rot, scale, feet_z, tris=8000):
    """Import the pet part, place it, reduce and weight it, add its bones to `arm`. Returns (pet object, bone names)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    imported = [o for o in bpy.data.objects if o not in before]
    pet = next(o for o in imported if o.type == "MESH")
    for o in imported:
        if o is not pet:
            bpy.data.objects.remove(o, do_unlink=True)
    pet.parent = None
    placement = (Matrix.Translation(Vector(pos) + Vector((0, 0, feet_z))) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
                 @ Matrix.Scale(scale, 4))
    pet.matrix_world = placement @ pet.matrix_world
    for o in bpy.context.view_layer.objects:
        o.select_set(o is pet)
    bpy.context.view_layer.objects.active = pet
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    floor0 = min(v.co.z for v in pet.data.vertices)
    if len(pet.data.polygons) > tris:
        mod = pet.modifiers.new("PetReduce", "DECIMATE")
        mod.ratio = tris / len(pet.data.polygons)
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in pet.data.polygons:
        poly.use_smooth = True
    lift = floor0 - min(v.co.z for v in pet.data.vertices)   # the collapse can push the feet below the accepted floor: put it back
    for v in pet.data.vertices:
        v.co.z += lift
    verts = [v.co.copy() for v in pet.data.vertices]
    head_dir = (placement.to_3x3() @ Vector((0, -1, 0))).normalized()   # the pet's local -Y is its nose
    centre = sum(verts, Vector()) / len(verts)
    ax = [(v - centre).dot(head_dir) for v in verts]
    length = max(ax) - min(ax)
    f = [a / length for a in ax]            # +0.5 nose ... -0.5 tail tip
    floor = min(v.z for v in verts)

    def slab(lo, hi):
        pts = [v for v, x in zip(verts, f) if lo <= x < hi] or [min(verts, key=lambda v: abs(((v - centre).dot(head_dir) / length) - (lo + hi) / 2))]
        return sum(pts, Vector()) / len(pts)

    def at(x):
        return slab(x - 0.03, x + 0.03)

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    to_local = arm.matrix_world.inverted()
    eb = arm.data.edit_bones
    ground = Vector((centre.x, centre.y, floor))
    root = eb.new("PetRoot")
    root.head, root.tail = to_local @ ground, to_local @ (ground + Vector((0, 0, 0.05)))
    body = eb.new("PetBody")
    body.head, body.tail, body.parent = to_local @ ground, to_local @ (ground + Vector((0, 0, 0.3))), root
    neck, nose = at(0.25), at(0.46)
    head = eb.new("PetHead")
    head.head, head.tail, head.parent = to_local @ neck, to_local @ nose, body
    joints = [at(-0.36), at(-0.41), at(-0.45), at(-0.49)]
    parent = body
    for i in range(3):
        b = eb.new(f"PetTail{i}")
        b.head, b.tail, b.parent = to_local @ joints[i], to_local @ joints[i + 1], parent
        parent = b
    bpy.ops.object.mode_set(mode="OBJECT")

    groups = {n: pet.vertex_groups.new(name=n) for n in NAMES}
    for i, x in enumerate(f):
        wh = _smooth(0.21, 0.32, x)
        wt = _smooth(-0.34, -0.38, x)
        s = min(2.999, max(0.0, (-x - 0.36) / 0.13 * 3))
        tail = [max(0.0, 1.0 - abs(s - (b + 0.5))) for b in range(3)]
        norm = sum(tail) or 1.0
        wb = max(0.0, 1.0 - wh - wt)
        groups["PetBody"].add([i], wb, "REPLACE")
        if wh > 0:
            groups["PetHead"].add([i], wh, "REPLACE")
        for b in range(3):
            if wt * tail[b] / norm > 0:
                groups[f"PetTail{b}"].add([i], wt * tail[b] / norm, "REPLACE")
    mod = pet.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    pet.parent = arm
    pet.matrix_parent_inverse = arm.matrix_world.inverted()
    pet.name = "PetRat"
    return pet, list(NAMES)


def make_pose(arm, view):
    """pose(t) for t in [0, 1): resets the pet bones, then breath (scale about the floor), sniff bursts and tail yaw."""
    pb = arm.pose.bones
    awi = arm.matrix_world.to_3x3().normalized().inverted()   # world axes expressed in armature space
    up, side = (awi @ Vector((0, 0, 1))).normalized(), (awi @ Vector((1, 0, 0))).normalized()
    for n in NAMES:
        pb[n].rotation_mode = "QUATERNION"

    def turn(name, axis, deg):
        p = pb[name]
        h = p.head.copy()
        p.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ p.matrix
        view.update()

    def burst(t, c):
        return math.exp(-(((t - c) / 0.035) ** 2))

    def pose(t):
        for n in NAMES:
            pb[n].rotation_quaternion, pb[n].location, pb[n].scale = (1, 0, 0, 0), (0, 0, 0), (1, 1, 1)
        view.update()
        s = math.sin(2 * math.pi * 5 * t)
        pb["PetBody"].scale = (1 + 0.004 * s, 1 + 0.012 * s, 1 + 0.004 * s)   # local Y is up: grows from the floor
        view.update()
        sniff = sum(burst(t, c) * math.sin(2 * math.pi * 14 * (t - c)) for c in (0.2, 0.55, 0.8))
        turn("PetHead", side, 5.0 * sniff + 2.5 * math.sin(2 * math.pi * t + 0.4))
        turn("PetHead", up, 7.0 * math.sin(2 * math.pi * t + 1.3))
        for b in range(3):
            turn(f"PetTail{b}", up, (6.0 + 5.0 * b) * math.sin(2 * math.pi * t - 0.5 - 0.45 * b) + 2.0 * math.sin(2 * math.pi * 3 * t - 0.6 * b))

    return pose
