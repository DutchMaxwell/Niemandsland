class_name BoardgenDressMesh
extends RefCounted
## The merge of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): every placement
## {module, xf (metres, board space), cls} of the planners becomes geometry of ONE mesh with one
## surface per shared material (sorted by name, each surface named by its material), so the whole
## board is a handful of draw calls. The vertex data of the modules is kept as authored - tangents
## come with the GLBs, nothing is generated here (generate_tangents on a merged mesh costs over a
## second). `shadow` is the low-poly proxy that casts the shadows: one surface of boxes from the
## modules' hull lists.

# a module without a hull list casts the shadow of its aabb shrunk by this much
const SHRINK_IN := 0.05


## One mesh, one surface per material name (sorted); a placement whose module has no mesh is
## skipped.
static func merge(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var tools := {}  # material name -> SurfaceTool
	for placement: Dictionary in placements:
		var mesh := kit.mesh(placement["module"])
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var key := mesh.surface_get_name(surface)
			if not tools.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = tool
			(tools[key] as SurfaceTool).append_from(mesh, surface, placement["xf"])
	var out := ArrayMesh.new()
	var names := tools.keys()
	names.sort()
	for key: String in names:
		(tools[key] as SurfaceTool).commit(out)
		out.surface_set_name(out.get_surface_count() - 1, key)
	return out


## The shadow proxy: one surface of boxes, the hulls (aabb_in pairs, inches, module space) of every
## placed module moved by its transform. A module with an EMPTY `shadow` list casts nothing (flat
## litter, soft vegetation); only a module without the key gets its aabb shrunk by SHRINK_IN.
static func shadow(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boxes := 0
	for placement: Dictionary in placements:
		var module := kit.module(placement["module"])
		if module.is_empty():
			continue
		for hull: Array in _hulls(module):
			var lo := Vector3(hull[0][0], hull[0][1], hull[0][2])
			var hi := Vector3(hull[1][0], hull[1][1], hull[1][2])
			var box := Transform3D(
				Basis.from_scale((hi - lo) * Units.INCHES_TO_METERS),
				(lo + hi) * 0.5 * Units.INCHES_TO_METERS
			)
			tool.append_from(unit, 0, (placement["xf"] as Transform3D) * box)
			boxes += 1
	var out := ArrayMesh.new()
	if boxes > 0:
		tool.commit(out)
	return out


## The shadow hulls of a module: its `shadow` list, or else its aabb shrunk by SHRINK_IN on every
## axis thicker than twice that.
static func _hulls(module: Dictionary) -> Array:
	if module.has("shadow"):
		return module["shadow"]
	var aabb: Array = module["aabb_in"]
	var lo := Vector3(aabb[0][0], aabb[0][1], aabb[0][2])
	var hi := Vector3(aabb[1][0], aabb[1][1], aabb[1][2])
	for axis in 3:
		if hi[axis] - lo[axis] > 2.0 * SHRINK_IN:  # a flat piece keeps its thickness
			lo[axis] += SHRINK_IN
			hi[axis] -= SHRINK_IN
	return [[[lo.x, lo.y, lo.z], [hi.x, hi.y, hi.z]]]
