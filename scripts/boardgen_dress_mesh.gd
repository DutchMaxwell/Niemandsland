class_name BoardgenDressMesh
extends RefCounted
## The merge of the ruin-town dressing (docs/adr/0003-generated-board-dressing.md): every
## DressPlacement of the planners becomes geometry of ONE mesh with one surface per shared material
## (sorted by name, each surface named by its material), so the whole board is a handful of draw
## calls. The vertex data of the modules is kept as authored - tangents come with the GLBs, nothing
## is generated here (generate_tangents on a merged mesh costs over a second). `shadow` is the
## low-poly proxy that casts the shadows: one surface of boxes from the modules' resolved hull
## lists.


## One mesh, one surface per material name (sorted); a placement whose module has no mesh is
## skipped.
static func merge(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var tools := {}  # material name -> SurfaceTool
	for placement: DressPlacement in placements:
		var mesh := kit.mesh(placement.module)
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var key := mesh.surface_get_name(surface)
			if not tools.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = tool
			(tools[key] as SurfaceTool).append_from(mesh, surface, placement.transform)
	var out := ArrayMesh.new()
	var names := tools.keys()
	names.sort()
	for key: String in names:
		(tools[key] as SurfaceTool).commit(out)
		out.surface_set_name(out.get_surface_count() - 1, key)
	return out


## The shadow proxy: one surface of boxes, the resolved hulls (lo / hi pairs, inches, module space)
## of every placed module moved by its transform. A module with an EMPTY hull list casts nothing
## (flat litter, soft vegetation).
static func shadow(placements: Array, kit: BoardgenDressKit) -> ArrayMesh:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boxes := 0
	for placement: DressPlacement in placements:
		var spec := kit.spec(placement.module)
		if spec == null:
			continue
		for hull: Array in spec.shadow_hulls:
			var lo: Vector3 = hull[0]
			var hi: Vector3 = hull[1]
			var box := Transform3D(
				Basis.from_scale((hi - lo) * Units.INCHES_TO_METERS),
				(lo + hi) * 0.5 * Units.INCHES_TO_METERS
			)
			tool.append_from(unit, 0, placement.transform * box)
			boxes += 1
	var out := ArrayMesh.new()
	if boxes > 0:
		tool.commit(out)
	return out
