"""Reduce a real idle GLB before skinning, preserving weights and bone-bound gear.

blender -b -P tools/idle/decimate_weighted.py -- source.glb output.glb budgets.json
Budgets are measured from the shipped body/parts meshes, not a class estimate.
"""
import bpy
from mathutils import Vector
import json
import sys
from pathlib import Path

source, output, budget_file = sys.argv[sys.argv.index('--') + 1:]
budgets = json.loads(Path(budget_file).read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
for obj in list(bpy.context.scene.objects):
    if obj.type == 'MESH' and obj.name.lower().startswith('icosphere'):
        bpy.data.objects.remove(obj, do_unlink=True)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
skinned = [o for o in meshes if any(m.type == 'ARMATURE' for m in o.modifiers)]
body = max(skinned, key=lambda o: len(o.data.polygons))   # a rigged pet is a second skinned mesh: the owner body is the larger one
parts = [o for o in meshes if o != body]
parts_faces = sum(len(o.data.polygons) for o in parts)
minimum = {o: min(5000, len(o.data.polygons)) for o in parts}
remaining = budgets['parts']['triangles'] - sum(minimum.values())
assert remaining >= 0
report = []
for obj in meshes:
    target = budgets['body']['triangles'] if obj == body else minimum[obj] + int(remaining * len(obj.data.polygons) / parts_faces)
    # Leave room for UV/normal seam splits in the serialized vertex budget.
    target = int(target * 0.95)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Weld in the bind mesh, never in an evaluated animated pose.
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode='OBJECT')
    before = len(obj.data.polygons)
    floor_before = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    for attempt in range(2):
        faces = len(obj.data.polygons)
        if faces <= target:
            break
        modifier = obj.modifiers.new('IdleBudget', 'DECIMATE')
        modifier.ratio = target / faces * (0.98 if attempt else 1.0)
        modifier.use_collapse_triangulate = True
        while obj.modifiers.find(modifier.name) > 0:
            bpy.ops.object.modifier_move_up(modifier=modifier.name)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    if obj in skinned and obj != body:
        # a rigged pet rests on the floor: the collapse must not push its feet through it
        lift = floor_before - min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
        shift = obj.matrix_world.to_3x3().inverted() @ Vector((0, 0, lift))
        for v in obj.data.vertices:
            v.co += shift
    if obj in skinned:
        # Collapse interpolates deform groups. Keep the GPU contract's strongest four.
        for vertex in obj.data.vertices:
            weights = sorted(((g.group, g.weight) for g in vertex.groups if g.weight > 0), key=lambda x: -x[1])
            assert weights, ('Unweighted vertex', vertex.index)
            total = sum(w for _, w in weights[:4])
            for group, weight in weights:
                obj.vertex_groups[group].remove([vertex.index])
            for group, weight in weights[:4]:
                obj.vertex_groups[group].add([vertex.index], weight / total, 'REPLACE')
    obj.data.validate(clean_customdata=False)
    report.append({'mesh': obj.name, 'before_triangles': before, 'triangles': len(obj.data.polygons), 'target': target})
# Shares are soft: disconnected gear may stop slightly above its allocation.
assert sum(len(o.data.polygons) for o in meshes) <= sum(b['triangles'] for b in budgets.values())
# Do not join rigid attachments: each weapon keeps its own hand-bone transform.
bpy.ops.export_scene.gltf(filepath=output, export_format='GLB', export_skins=True,
                          export_animations=True, export_force_sampling=True,
                          export_image_format='WEBP', export_image_quality=90)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from preserve_pose import preserve
preserve(source, output)
Path(output).with_suffix('.budget.json').write_text(json.dumps(report, indent=2) + '\n')
print('IDLE_DECIMATED', json.dumps(report), flush=True)
