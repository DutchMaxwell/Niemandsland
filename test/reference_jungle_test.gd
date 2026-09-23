extends GdUnitTestSuite
## Decorative leaf reach must stay outside units, hazards, walls and the board edge.

const Jungle = preload("res://scripts/visual/reference_jungle.gd")
const Motion = preload("res://scripts/visual/reference_jungle_motion.gd")


func test_full_leaf_footprint_respects_rule_object_clearings() -> void:
	var jungle: Node3D = auto_free(Jungle.new())
	jungle._board_size = Vector2(1.8,1.2)
	jungle._exclusions.append(Vector3(0,0,0.024))
	jungle._blockers.append(Vector3(0.3,0,0.035))
	jungle._walls = [[Vector2(-0.5,-0.3),Vector2(-0.5,0.3)]]
	assert_bool(jungle.clear_footprint(Vector2(0.038,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.349,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(-0.48,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.88,0),0.016)).is_false()
	assert_bool(jungle.clear_footprint(Vector2(0.09,0.10),0.016)).is_true()
	# A tiny fragment fits a clearing which a full fern must avoid.
	assert_bool(jungle.clear_footprint(Vector2(0.038,0),0.003)).is_true()


func test_leaf_meshes_fit_the_declared_placement_envelopes() -> void:
	var jungle: Node3D = auto_free(Jungle.new())
	for record: Array in [[jungle._fern_mesh(),0.016],[jungle._broadleaf_mesh(),0.013]]:
		var mesh: ArrayMesh = record[0]
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_int(vertices.size()).is_greater(100)
		for v in vertices:
			assert_float(Vector2(v.x,v.z).length()).is_less_equal(record[1])
			assert_float(v.y).is_greater_equal(-0.0001)
			assert_float(v.y).is_less_equal(0.020)


func test_hazard_motion_preserves_sources_and_uses_one_root_frame() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	root.position = Vector3(0.4,0.002,-0.2)
	root.rotation.y = 0.7
	var source := StandardMaterial3D.new()
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.DARK_GREEN)
	source.albedo_texture = ImageTexture.create_from_image(image)
	source.roughness = 0.73
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.01,0.02,0.01)
	mesh.material = source
	var parts: Array[MeshInstance3D] = []
	var transforms: Array[Transform3D] = []
	for i in 2:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.position = Vector3(0.0,0.01+float(i)*0.02,0)
		part.scale = Vector3.ONE*(1.0+float(i)*0.2)
		root.add_child(part)
		parts.append(part)
		transforms.append(part.transform)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	body.add_child(collider)
	root.add_child(body)
	var anchor_before := root.global_transform
	var shape_before := collider.shape
	var collision_before := collider.global_transform
	var motion: Node3D = auto_free(Motion.new())
	motion.shade_hazard(root,3)
	assert_int(motion._materials.size()).is_equal(2)
	for value in [0.0,2.0,8.0]:
		motion.set_time(value)
		for i in parts.size():
			var material := parts[i].get_active_material(0) as ShaderMaterial
			assert_bool(material.get_shader_parameter("jungle_sway")).is_true()
			assert_float(material.get_shader_parameter("wind_time")).is_equal(value)
			assert_float(material.get_shader_parameter("tree_bottom")).is_equal_approx(0.0,0.000001)
			assert_float(material.get_shader_parameter("tree_height")).is_equal_approx(0.042,0.000001)
			assert_bool(material.get_shader_parameter("wind_to_plant").is_equal_approx(transforms[i])).is_true()
			assert_float(material.get_shader_parameter("base_roughness")).is_equal_approx(0.73,0.000001)
			assert_bool(parts[i].transform == transforms[i]).is_true()
	assert_bool(root.global_transform == anchor_before).is_true()
	assert_bool(collider.global_transform == collision_before).is_true()
	assert_object(collider.shape).is_same(shape_before)
	assert_object(mesh.material).is_same(source)
	assert_object(parts[0].mesh).is_same(mesh)
