"""Render every GLB in a session glb dir to a thumbnail (one Blender session, EEVEE).
   blender -b -P _ah_overview.py -- <glb_dir> <out_dir>
"""
import sys, glob, os
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GLB_DIR, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)

sc = bpy.context.scene
try: sc.render.engine = "BLENDER_EEVEE_NEXT"
except Exception: sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "AgX"
sc.render.resolution_x = 300; sc.render.resolution_y = 340
sc.render.image_settings.file_format = "PNG"

# world + lights + camera target (rebuilt per model for correct framing)
def setup_world():
    if sc.world is None: sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = next(n for n in sc.world.node_tree.nodes if n.bl_idname == "ShaderNodeBackground")
    bg.inputs[0].default_value = (0.85, 0.86, 0.89, 1.0)
setup_world()

for path in sorted(glob.glob(os.path.join(GLB_DIR, "*.glb"))):
    name = os.path.splitext(os.path.basename(path))[0]
    # clear previous objects
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:
        print("FAIL import", name, e); continue
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes: continue
    for o in meshes[1:]: o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    m = bpy.context.view_layer.objects.active
    bb = [m.matrix_world @ Vector(c) for c in m.bound_box]
    ctr = sum(bb, Vector()) / 8.0
    size = max((max(v[i] for v in bb) - min(v[i] for v in bb)) for i in range(3))
    tgt = bpy.data.objects.new("t", None); sc.collection.objects.link(tgt); tgt.location = ctr
    cam_d = bpy.data.cameras.new("c"); cam = bpy.data.objects.new("c", cam_d); sc.collection.objects.link(cam)
    cam.location = ctr + Vector((0.7, -2.0, 0.5)) * (size * 1.25); cam_d.lens = 80
    c = cam.constraints.new("TRACK_TO"); c.target = tgt; c.track_axis = "TRACK_NEGATIVE_Z"; c.up_axis = "UP_Y"
    sc.camera = cam
    for nm, loc, en in [("k", (2, -2.5, 3), 280), ("f", (-2, -1, 1.5), 110), ("r", (0.5, 2.5, 2.5), 200)]:
        ld = bpy.data.lights.new(nm, "AREA"); ld.energy = en * (size**2 + 0.2); ld.size = size * 2
        lo = bpy.data.objects.new(nm, ld); sc.collection.objects.link(lo); lo.location = ctr + Vector(loc) * size
        cc = lo.constraints.new("TRACK_TO"); cc.target = tgt; cc.track_axis = "TRACK_NEGATIVE_Z"; cc.up_axis = "UP_Y"
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name, flush=True)
print("OVERVIEW DONE")
