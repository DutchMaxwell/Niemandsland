class_name BoardgenDressMesh
extends RefCounted
## The merge of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): every placement {module, xf (metres, board space), cls} of the planners becomes geometry of ONE mesh with one surface per shared material
## (sorted by name, each surface named by its material), so the whole board is a handful of draw calls. The vertex data of the modules is kept as authored - tangents come with the GLBs, nothing is
## generated here (generate_tangents on a merged mesh costs over a second). `shadow` is the low-poly proxy that casts the shadows: one surface of boxes from the modules' hull lists.

const IN_M := 0.0254
const SHRINK_IN := 0.05   # a module without a hull list casts the shadow of its aabb shrunk by this much


## One mesh, one surface per material name (sorted); a placement whose module has no mesh is skipped.
static func merge(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var tools := {}
	for p: Dictionary in placements:
		var mesh := kit.mesh(p["module"])
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var key := mesh.surface_get_name(s)
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
			(tools[key] as SurfaceTool).append_from(mesh, s, p["xf"])
	var out := ArrayMesh.new()
	var names := tools.keys()
	names.sort()
	for key: String in names:
		(tools[key] as SurfaceTool).commit(out)
		out.surface_set_name(out.get_surface_count() - 1, key)
	return out


## The shadow proxy: one surface of boxes, the hulls (aabb_in pairs, inches, module space) of every placed module moved by its transform. A module with an EMPTY `shadow` list casts nothing (flat litter, soft
## vegetation); only a module without the key gets its aabb shrunk by SHRINK_IN.
static func shadow(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boxes := 0
	for p: Dictionary in placements:
		var m := kit.module(p["module"])
		if m.is_empty():
			continue
		for hull: Array in _hulls(m):
			var lo := Vector3(hull[0][0], hull[0][1], hull[0][2])
			var hi := Vector3(hull[1][0], hull[1][1], hull[1][2])
			st.append_from(unit, 0, (p["xf"] as Transform3D) * Transform3D(Basis.from_scale((hi - lo) * IN_M), (lo + hi) * 0.5 * IN_M))
			boxes += 1
	var out := ArrayMesh.new()
	if boxes > 0:
		st.commit(out)
	return out


static func _hulls(m: Dictionary) -> Array:
	if m.has("shadow"):
		return m["shadow"]
	var a: Array = m["aabb_in"]
	var lo := Vector3(a[0][0], a[0][1], a[0][2])
	var hi := Vector3(a[1][0], a[1][1], a[1][2])
	for k in 3:
		if hi[k] - lo[k] > 2.0 * SHRINK_IN:   # a flat piece keeps its thickness
			lo[k] += SHRINK_IN
			hi[k] -= SHRINK_IN
	return [[[lo.x, lo.y, lo.z], [hi.x, hi.y, hi.z]]]
