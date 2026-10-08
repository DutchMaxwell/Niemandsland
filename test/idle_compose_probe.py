"""Blender probe for idle_compose_test.py: two synthetic rigid composed parts (a throne-like box at scale 4, a rotated bearer-like box) placed by the
real pet_rig.add_statics. Prints the world bounds of every placed part.
blender -b --factory-startup -P test/idle_compose_probe.py -- <repo tools/idle dir> <out.json>"""
import bpy, json, sys, tempfile

tools, out = sys.argv[sys.argv.index("--") + 1:][:2]
sys.path.insert(0, tools)
from pet_rig import add_statics

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))   # 1 x 1 x 1, bottom on z = 0
box = bpy.context.object
box.scale = (1.0, 2.0, 1.0)
bpy.ops.object.transform_apply(scale=True)
path = tempfile.mkdtemp() + "/box.glb"
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True)
bpy.data.objects.remove(box, do_unlink=True)

placed = add_statics([{"glb": path, "pos": [0, 0, 2.0], "scale": 4.0}, {"glb": path, "pos": [1.0, 1.0, 0.5], "rot": [0, 0, 90]}])
rows = []
for o in placed:
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    rows.append({"name": o.name, "parent": o.parent is not None, "lo": [min(p[i] for p in pts) for i in range(3)], "hi": [max(p[i] for p in pts) for i in range(3)]})
json.dump({"rows": rows, "meshes": sum(1 for o in bpy.data.objects if o.type == "MESH")}, open(out, "w"))
print("COMPOSE", json.dumps(rows))
