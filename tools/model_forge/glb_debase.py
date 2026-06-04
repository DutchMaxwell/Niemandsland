"""Strip the baked-on base disc from a TRELLIS GLB — headless Blender.

TRELLIS grounds standing figures on a flat disc base regardless of the input image. Niemandsland
never wants a modelled base (the game generates it from base_size at spawn), so this removes it.

The disc is detected geometrically: binning the mesh over height, the base shows as the bottom run
of slices that are much wider than the slice just above (a figure's boots are far narrower than the
disc). Everything below the disc top is cut off; PBR textures (4K WebP) are preserved by Blender's
glTF I/O.

Run headless:
    blender -b -P glb_debase.py -- <in.glb> <out.glb> [z_ratio_threshold]

Exit code 0 on success (or clean no-op if no disc detected), 1 on error.
"""

import sys
import bpy
import bmesh

# --- args after "--" ---------------------------------------------------------
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("usage: blender -b -P glb_debase.py -- <in.glb> <out.glb> [threshold]")
    sys.exit(1)
IN_GLB, OUT_GLB = argv[0], argv[1]
WIDTH_RATIO = float(argv[2]) if len(argv) > 2 else 1.25  # bin wider than this x the bin above = disc
N_BINS = 40
MAX_DISC_FRACTION = 0.15  # safety: never cut more than the bottom 15% of height


def main() -> int:
    # Clean slate, import.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=IN_GLB)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("ERROR: no mesh in", IN_GLB)
        return 1

    # Join into one object so a single cut handles the whole model.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    me = obj.data

    # Width-over-height profile in the object's local frame (glTF import is Z-up; base at min Z).
    co = [v.co for v in me.vertices]
    zmin = min(c.z for c in co)
    zmax = max(c.z for c in co)
    height = zmax - zmin
    if height <= 0:
        print("ERROR: degenerate height")
        return 1

    binw = [0.0] * N_BINS
    for i in range(N_BINS):
        lo = zmin + i * height / N_BINS
        hi = lo + height / N_BINS
        pts = [c for c in co if (lo <= c.z < hi) or (i == N_BINS - 1 and c.z >= lo)]
        if pts:
            wx = max(c.x for c in pts) - min(c.x for c in pts)
            wy = max(c.y for c in pts) - min(c.y for c in pts)
            binw[i] = max(wx, wy)

    # Disc = maximal bottom run where each bin flares out vs the one above.
    disc_top_bin = 0
    i = 0
    while i < N_BINS - 1 and binw[i + 1] > 0 and binw[i] > WIDTH_RATIO * binw[i + 1]:
        disc_top_bin = i + 1
        i += 1

    if disc_top_bin == 0:
        print("No base disc detected (no flaring bottom) — exporting unchanged.")
    elif disc_top_bin / N_BINS > MAX_DISC_FRACTION:
        print(f"SAFETY: detected 'disc' spans {disc_top_bin}/{N_BINS} bins "
              f"(> {MAX_DISC_FRACTION:.0%}) — too much, refusing to cut. Exporting unchanged.")
        disc_top_bin = 0
    else:
        z_cut = zmin + disc_top_bin * height / N_BINS
        print(f"Disc spans bins 0..{disc_top_bin - 1}; cutting at z={z_cut:.4f} "
              f"({(z_cut - zmin) / height * 100:.1f}% up). bottom_width={binw[0]:.3f} "
              f"figure_width≈{binw[disc_top_bin]:.3f}")
        bm = bmesh.new()
        bm.from_mesh(me)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5,
                               plane_co=(0, 0, z_cut), plane_no=(0, 0, 1), clear_inner=True)
        bm.to_mesh(me)
        bm.free()
        me.update()
        print(f"after cut: verts={len(me.vertices)} polys={len(me.polygons)}")

    # Export GLB, preserving WebP PBR textures (Godot 4.6 loads EXT_texture_webp).
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format="GLB", use_selection=True,
        export_image_format="WEBP", export_image_quality=92,
        export_yup=True,
    )
    print("wrote", OUT_GLB)
    return 0


if __name__ == "__main__":
    sys.exit(main())
