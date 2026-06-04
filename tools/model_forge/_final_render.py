"""Headless EEVEE render of a GLB for a clean presentation shot.
   blender -b -P _final_render.py -- <in.glb> <out.png>
"""
import sys, math
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
IN_GLB, OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN_GLB)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes[1:]:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
model = bpy.context.view_layer.objects.active

# World: soft light grey.
sc = bpy.context.scene
if sc.world is None:
    sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
bg = next((n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground"), None)
bg.inputs[0].default_value = (0.85, 0.86, 0.89, 1.0)
bg.inputs[1].default_value = 0.9

# Bounding box centre + size (world space).
bb = [model.matrix_world @ Vector(c) for c in model.bound_box]
ctr = sum(bb, Vector()) / 8.0
size = max((max(v[i] for v in bb) - min(v[i] for v in bb)) for i in range(3))

# Camera, front-right-up 3/4 angle, aimed at centre via Track-To.
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
sc.collection.objects.link(cam)
cam.location = ctr + Vector((0.75, -2.0, 0.45)) * (size * 1.2)
tgt = bpy.data.objects.new("tgt", None); sc.collection.objects.link(tgt)
tgt.location = ctr + Vector((0, 0, size * 0.04))
con = cam.constraints.new("TRACK_TO"); con.target = tgt
con.track_axis = "TRACK_NEGATIVE_Z"; con.up_axis = "UP_Y"
cam_data.lens = 75
sc.camera = cam

# Filmic tonemap so the dark slate + copper read properly (not washed out).
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Medium High Contrast"

# Key + fill + rim lights (softer, so colours stay saturated).
for name, loc, energy in [("key", (2, -2.5, 3), 280), ("fill", (-2.5, -1, 1.5), 110),
                          ("rim", (0.5, 2.5, 2.5), 220)]:
    ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy * (size ** 2 + 0.2); ld.size = size * 2
    lo = bpy.data.objects.new(name, ld); sc.collection.objects.link(lo)
    lo.location = ctr + Vector(loc) * size
    c = lo.constraints.new("TRACK_TO"); c.target = tgt; c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"

try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except Exception:
    sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = 1100
sc.render.resolution_y = 1300
sc.render.film_transparent = False
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("wrote", OUT)
