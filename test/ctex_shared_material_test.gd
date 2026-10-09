extends GdUnitTestSuite


func _figure(tint: Color = Color.WHITE) -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var mesh := MeshInstance3D.new()
	mesh.name = "body"
	mesh.mesh = BoxMesh.new()
	var base := StandardMaterial3D.new()
	base.albedo_color = tint
	mesh.mesh.surface_set_material(0, base)
	root.add_child(mesh)
	return root


func test_shared_material_survives_death_hover_and_revive_of_one_model() -> void:
	var first := _figure()
	var second := _figure()
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.DARK_GREEN)
	var texture := ImageTexture.create_from_image(image)
	for figure in [first, second]:
		var mesh := figure.get_node("body") as MeshInstance3D
		(mesh.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture = texture
	CtexLoader.apply_to_mesh(first, "")
	CtexLoader.apply_to_mesh(second, "")
	var a := first.get_node("body") as MeshInstance3D
	var b := second.get_node("body") as MeshInstance3D
	var shared := a.get_active_material(0) as StandardMaterial3D
	assert_bool(shared == b.get_active_material(0)).is_true()
	var mgr: OPRArmyManager = auto_free(OPRArmyManager.new())
	mgr._brighten_ctex_materials(first)
	var properties := {}
	for prop in shared.get_property_list():
		if int(prop.usage) & PROPERTY_USAGE_STORAGE:
			properties[prop.name] = shared.get(prop.name)
	var glow := HoverGlow.new()
	glow.set_target(first)
	mgr._desaturate_model(first)
	assert_bool((a.get_active_material(0) as ShaderMaterial).get_shader_parameter("albedo_tex") == texture).is_true()
	assert_bool(a.get_active_material(0) != shared).is_true()
	assert_bool(b.get_active_material(0) == shared).is_true()
	assert_object(b.material_overlay).is_null()
	for key in properties:
		assert_bool(shared.get(key) == properties[key]).override_failure_message(str(key)).is_true()
	glow.clear()
	mgr._restore_model_material(first)
	assert_bool(a.get_active_material(0) == shared).is_true()
	assert_object(a.material_overlay).is_null()


func test_multi_surface_path_shares_but_distinct_source_tints_do_not() -> void:
	var first := _figure()
	var second := _figure()
	var red := _figure(Color.RED)
	for figure in [first, second, red]:
		CtexLoader.apply_materials_to_mesh(figure, [{"surface": 0, "albedo": ""}])
	var shared := (first.get_node("body") as MeshInstance3D).get_active_material(0)
	assert_bool(shared == (second.get_node("body") as MeshInstance3D).get_active_material(0)).is_true()
	assert_bool(shared != (red.get_node("body") as MeshInstance3D).get_active_material(0)).is_true()
