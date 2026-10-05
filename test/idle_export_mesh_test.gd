extends GdUnitTestSuite

const Packer := preload("res://tools/idle/export_mesh.gd")

func _pack(skinned: bool) -> Dictionary:
	var figure: MeshInstance3D = auto_free(MeshInstance3D.new())
	var arrays := BoxMesh.new().get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if skinned:
		figure.skin = Skin.new()
		var joints := PackedInt32Array()
		var weights := PackedFloat32Array()
		for vertex in vertices:
			joints.append_array(PackedInt32Array([0, 1, 0, 0]))
			weights.append_array(PackedFloat32Array([0.25, 0.75, 0, 0]))
		arrays[Mesh.ARRAY_BONES] = joints
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	figure.mesh = ArrayMesh.new()
	figure.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.2, 0.3, 0.4)
	figure.mesh.surface_set_material(0, source)
	var packed := Packer.pack([{"mi": figure, "frame": Transform3D(Basis(), Vector3(0, 2, 0)), "offset": 5}], {})
	assert_bool(packed.mesh.surface_get_material(0) != source).is_true()
	assert_bool(packed.mesh.surface_get_material(0).albedo_color == source.albedo_color).is_true()
	assert_bool(figure.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices).is_true()
	return packed

func test_rigid_gear_keeps_its_own_palette_entry_and_grounded_frame() -> void:
	var packed := _pack(false)
	var arrays: Array = packed.mesh.surface_get_arrays(0)
	var ids: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var weights: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1]
	for v in arrays[Mesh.ARRAY_VERTEX].size():
		assert_int(ids[v * 4]).is_equal(5)
		assert_int(weights[v * 4]).is_equal(255)
		assert_int(weights[v * 4 + 1]).is_equal(0)
	assert_float(packed.mesh.get_aabb().position.y).is_equal_approx(1.5, 0.001)
	assert_bool(arrays[Mesh.ARRAY_BONES] == null).is_true()

func test_real_skin_weights_preserve_influences_after_palette_offset() -> void:
	var packed := _pack(true)
	var arrays: Array = packed.mesh.surface_get_arrays(0)
	var ids: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var weights: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM1]
	for v in arrays[Mesh.ARRAY_VERTEX].size():
		assert_int(ids[v * 4]).is_equal(5)
		assert_int(ids[v * 4 + 1]).is_equal(6)
		assert_int(weights[v * 4]).is_equal(64)
		assert_int(weights[v * 4 + 1]).is_equal(191)
	assert_int(packed.points[0].used.size()).is_equal(2)
