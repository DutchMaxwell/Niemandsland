extends GdUnitTestSuite
## reference_tree_lod.gd: the welded LOD chain the table tree pass gives the reconstructed trees.

const LodBuilder := preload("res://scripts/visual/reference_tree_lod.gd")


## A sphere whose every triangle has its own three vertices: the worst case of a reconstructed tree GLB,
## whose UV charts split the surface into many islands.
func _split_sphere() -> Array:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	var arrays := sphere.get_mesh_arrays()
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var split_positions := PackedVector3Array()
	var split_normals := PackedVector3Array()
	var split_uvs := PackedVector2Array()
	for i: int in arrays[Mesh.ARRAY_INDEX]:
		split_positions.append(positions[i])
		split_normals.append(normals[i])
		split_uvs.append(uvs[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = split_positions
	out[Mesh.ARRAY_NORMAL] = split_normals
	out[Mesh.ARRAY_TEX_UV] = split_uvs
	return out


func test_a_split_surface_gets_a_welded_lod_chain() -> void:
	var arrays := _split_sphere()
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var lods := LodBuilder._welded_lods(arrays, 0.00001)
	assert_int(lods.size()).override_failure_message("only %d LOD levels" % lods.size()).is_greater_equal(3)
	var sizes: Array = lods.keys()
	sizes.sort()
	var previous := vertex_count + 1
	for size in sizes:
		var indices: PackedInt32Array = lods[size]
		assert_int(indices.size() % 3).is_equal(0)
		assert_int(indices.size()).override_failure_message("a coarser LOD is not smaller").is_less(previous)
		previous = indices.size()
		for index in indices:
			if index < 0 or index >= vertex_count:
				fail("LOD index %d outside the %d original vertices" % [index, vertex_count])
				return
	# The reason for the weld: the engine's generator alone stops early on such a split surface.
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(60.0, 25.0, [])
	assert_int(lods.size()).is_greater(importer.get_surface_lod_count(0))


func test_lod_zero_and_materials_stay_untouched() -> void:
	var arrays := _split_sphere()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	mesh.surface_set_material(0, material)
	mesh.surface_set_name(0, "bark")
	var out := LodBuilder.with_lods(mesh)
	assert_int(out.get_surface_count()).is_equal(1)
	assert_object(out.surface_get_material(0)).is_same(material)
	assert_str(out.surface_get_name(0)).is_equal("bark")
	assert_bool(out.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == arrays[Mesh.ARRAY_VERTEX]).is_true()
