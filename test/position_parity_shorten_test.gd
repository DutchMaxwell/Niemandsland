extends GdUnitTestSuite
## Pin the production table's shortening call and the Rust port to one capture.
const Replay := preload("res://tools/node_recheck.gd")

func test_pinned_whole_unit_shorten_reaches_the_table_placement() -> void:
	var pin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://test/fixtures/position_parity/whole_unit_shorten.json"))
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.terrain_type_at = Replay.terrain_at_from_plain(pin["terrain"])
	var walls: Array = []
	for wall in pin["terrain"]["walls"]:
		walls.append([Vector2(wall[0][0],wall[0][1]),Vector2(wall[1][0],wall[1][1])])
	solo.walls_provider = func() -> Array: return walls
	var models: Array = []
	for spec in pin["moving"]:
		var unit := GameUnit.new()
		unit.unit_properties = {"base_is_oval":bool(spec["oval"]),
			"base_width_mm":int(round(float(spec["semi_x"]) * 2000.0)),
			"base_depth_mm":int(round(float(spec["semi_z"]) * 2000.0)),
			"base_size_round":int(round(float(spec["radius"]) * 2000.0))}
		var model := ModelInstance.new()
		model.unit = unit
		model.properties = {"tough":1}
		var node: Node3D = auto_free(Node3D.new())
		add_child(node)
		node.rotation.y = float(spec["yaw"])
		model.node = node
		models.append(model)
	var obstacles: Array = []
	for spec in pin["external"]:
		var c := Vector2(spec["center"][0],spec["center"][1])
		obstacles.append(SeparationChecker.BaseShape.make_oval(c,float(spec["yaw"]),
			float(spec["semi_x"]),float(spec["semi_z"])) if spec["oval"] else
			SeparationChecker.BaseShape.make_round(c,float(spec["radius"])))
	var start: Array = []
	var planned: Array = []
	for p in pin["start_world"]: start.append(Vector3(p[0],p[1],p[2]))
	for p in pin["planned_world"]: planned.append(Vector3(p[0],p[1],p[2]))
	var got := solo._shorten_world_to_legal(start,planned,models,obstacles,float(pin["max_chain"]))
	for i in got.size():
		var p: Array = pin["expected_world"][i]
		assert_float((got[i] as Vector3).distance_to(Vector3(p[0],p[1],p[2])) / 0.0254).is_less_equal(
			float(pin["tolerance_in"]))
	var next := solo._blend_world(start,planned,float(pin["blend_factor"]) + 1.0 / 65536.0)
	assert_bool(solo._config_coherent_world(models,next,float(pin["max_chain"]))).is_false()
	for model in models:
		model.unit = null
		model.node = null
