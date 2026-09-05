extends GdUnitTestSuite
## The gate and the table read the same Stage A base data and numeric pin.

func test_pinned_base_shapes_fixture_uses_real_footprint() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/position_parity/cases.json"))
	var pin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/position_parity/base_shapes.json"))
	var fixture: Dictionary
	for candidate in fixtures["cases"]:
		if candidate["id"] == pin["source_case"]:
			fixture = candidate
	var shapes: Array = []
	for spec in fixture["units"]:
		var unit := GameUnit.new()
		unit.unit_properties = {"base_is_oval":spec["base_shape"] == "oval",
			"base_width_mm":int(spec["base_w_mm"]),"base_depth_mm":int(spec["base_d_mm"]),
			"base_size_round":int(spec["base_w_mm"])}
		var model := ModelInstance.new()
		model.unit = unit
		model.properties = {"tough":int(spec["tough"])}
		var node: Node3D = auto_free(Node3D.new())
		add_child(node)
		var p: Array = spec["positions"][0]
		node.global_position = Vector3(p[0],p[1],p[2])
		model.node = node
		var shape := SeparationChecker.shape_for_model(model)
		assert_float(shape.bounding_radius()).is_equal_approx(float(spec["radii"][0]),0.00000001)
		shapes.append(shape)
		model.unit = null
		model.node = null
	assert_float(SeparationChecker.edge_distance(shapes[0],shapes[1])).is_equal_approx(
		float(pin["edge_in"]),float(pin["tolerance_in"]))

	# The same axes/contact probes exercise the production overlap resolver.
	for probe in pin["probes"]:
		for swap in [false,true]:
			var moving: SeparationChecker.BaseShape = shapes[1] if swap else shapes[0]
			var other: SeparationChecker.BaseShape = shapes[0] if swap else shapes[1]
			moving.center = Vector2.ZERO
			other.center = Vector2(probe["obstacle_offset_m"][0],probe["obstacle_offset_m"][1])
			var push := SeparationResolver.resolve_overlaps([moving],[other])
			var expected := Vector2(probe["expected_push_m"][0],probe["expected_push_m"][1])
			assert_float(push.distance_to(expected) / 0.0254).is_less(float(pin["tolerance_in"]))
