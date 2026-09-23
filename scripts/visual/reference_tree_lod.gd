extends RefCounted
## Runtime mesh LODs for the reconstructed trees on the game table (TableBiomePresenter tree pass).
##
## The tree GLBs arrive without LODs (~100k triangles each, the acacia 273k), and their UV charts cut the
## surface into many small islands, so the engine's generator (ImporterMesh.generate_lods) stops after 0-2
## levels. Here each surface is first welded by position (seams ignored), the LOD chain is generated on the
## welded copy, and every LOD index is mapped back to one original vertex at that position. LOD 0 stays the
## untouched original; a lower LOD may borrow a neighbouring chart's UV at a former seam, only at the small
## screen sizes the engine picks it for. Pure data work: safe on a worker thread.

## Weld tolerance, relative to the mesh's longest extent.
const WELD_STEP := 1.0e-5


## A copy of `mesh` whose triangle surfaces carry a welded LOD chain; materials and names are kept.
static func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var step := maxf(mesh.get_aabb().get_longest_axis_size(), 0.000001) * WELD_STEP
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var primitive := mesh.surface_get_primitive_type(s)
		var lods := _welded_lods(arrays, step) if primitive == Mesh.PRIMITIVE_TRIANGLES else {}
		out.add_surface_from_arrays(primitive, arrays, [], lods)
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	return out


## Number of LOD levels of surface 0 (0 = none), for logs and tests.
static func lod_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	return (surface.get("lods", []) as Array).size()


static func _welded_lods(arrays: Array, step: float) -> Dictionary:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(positions.size())
		for i in positions.size():
			indices[i] = i
	var inv := 1.0 / step
	var first := {}
	var welded := PackedVector3Array()
	var welded_normals := PackedVector3Array()
	var representative := PackedInt32Array()
	var remap := PackedInt32Array()
	remap.resize(positions.size())
	for i in positions.size():
		var p := positions[i]
		var key := Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv))
		var w: int = first.get(key, -1)
		if w < 0:
			w = welded.size()
			first[key] = w
			welded.append(p)
			if not normals.is_empty():
				welded_normals.append(normals[i])
			representative.append(i)
		remap[i] = w
	var welded_indices := PackedInt32Array()
	welded_indices.resize(indices.size())
	for i in indices.size():
		welded_indices[i] = remap[indices[i]]
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = welded
	if not welded_normals.is_empty():
		surface[Mesh.ARRAY_NORMAL] = welded_normals
	surface[Mesh.ARRAY_INDEX] = welded_indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, surface)
	importer.generate_lods(60.0, 25.0, [])
	# The generator may reorder or duplicate vertices: map each LOD corner back through its position.
	var result_positions: PackedVector3Array = importer.get_surface_arrays(0)[Mesh.ARRAY_VERTEX]
	var lods := {}
	for l in importer.get_surface_lod_count(0):
		var lod_indices := importer.get_surface_lod_indices(0, l)
		var mapped := PackedInt32Array()
		mapped.resize(lod_indices.size())
		for k in lod_indices.size():
			var p := result_positions[lod_indices[k]]
			mapped[k] = representative[first.get(Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv)), 0)]
		lods[importer.get_surface_lod_size(0, l)] = mapped
	return lods
