extends GdUnitTestSuite
## The look pass's dressing of a boardgen layout (BoardgenProps): one seed dresses the same board every time and another seed
## another, every prop stands on level-0 floor against a wall (or lies flat on a street), the foot of a ladder stays bare,
## at most 8 lights, and the kit is three MultiMeshes with nothing physical. Stands on the recorded seed 42 layout.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## The cell (x, z) a prop's centre is in, from its board-metre transform.
func _cell_of(layout: Dictionary, prop: Dictionary) -> Vector2i:
	var p: Vector3 = prop["xf"].origin / BoardgenProps.INCHES_TO_METERS
	return Vector2i(floori(p.x / CELL_IN + layout["nx"] * 0.5), floori(p.z / CELL_IN + layout["nz"] * 0.5))


func _level(layout: Dictionary, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= layout["nx"] or c.y >= layout["nz"]:
		return 0
	return layout["cells"][c.y * layout["nx"] + c.x]["level"]


func test_one_seed_dresses_the_same_board_and_another_seed_another() -> void:
	var layout := _fixture()
	var first := BoardgenProps.plan(layout)
	assert_int(first.size()).is_greater(40)
	randomize()   # the global generator must not matter
	assert_array(BoardgenProps.plan(layout)).is_equal(first)
	assert_array(BoardgenProps.plan(_fixture())).is_equal(first)
	var other := _fixture()
	other["seed"] = int(layout["seed"]) + 1
	assert_bool(BoardgenProps.plan(other) == first).is_false()


func test_every_prop_stands_on_level_0_floor_against_a_wall_or_lies_flat_on_a_street() -> void:
	var layout := _fixture()
	var shapes := {}
	for prop in BoardgenProps.plan(layout):
		shapes[prop["shape"]] = true
		var c := _cell_of(layout, prop)
		assert_int(_level(layout, c)).override_failure_message("%s in cell %s is not on level 0" % [prop["shape"], c]).is_equal(0)
		var flat: bool = prop["xf"].origin.y < 0.1 * BoardgenProps.INCHES_TO_METERS
		var by_wall := BoardgenProps.DIRS.any(func(d: Vector2i) -> bool: return _level(layout, c + d) > 0)
		assert_bool(by_wall or (flat and layout["cells"][c.y * layout["nx"] + c.x]["street"])).override_failure_message("%s in cell %s stands in the open" % [prop["shape"], c]).is_true()
	assert_array(shapes.keys()).contains_exactly_in_any_order(["box", "cyl", "bulb", "light"])


func test_the_foot_of_a_ladder_stays_bare() -> void:
	var layout := _fixture()
	var feet: Array = layout["connectors"].map(func(c: Dictionary) -> Vector2i: return Vector2i(c["low_xz"][0], c["low_xz"][1]))
	assert_int(feet.size()).is_greater(10)
	for prop in BoardgenProps.plan(layout):
		assert_bool(feet.has(_cell_of(layout, prop))).is_false()


func test_at_most_eight_lights_and_no_two_lamps_cluster() -> void:
	var lights := BoardgenProps.plan(_fixture()).filter(func(p: Dictionary) -> bool: return p["shape"] == "light")
	assert_int(lights.size()).is_between(1, BoardgenProps.MAX_LIGHTS)
	for i in lights.size():
		for j in range(i + 1, lights.size()):
			var gap: float = lights[i]["xf"].origin.distance_to(lights[j]["xf"].origin) / BoardgenProps.INCHES_TO_METERS
			assert_float(gap).is_greater(BoardgenProps.LAMP_GAP_IN - 2.0)


func test_build_makes_three_multimeshes_and_the_lights_and_nothing_physical() -> void:
	var layout := _fixture()
	var node: BoardgenProps = auto_free(BoardgenProps.new())
	add_child(node)
	node.build(layout)
	var props := BoardgenProps.plan(layout)
	var meshes := node.find_children("*", "MultiMeshInstance3D", false, false)
	assert_int(meshes.size()).is_equal(3)
	for m: MultiMeshInstance3D in meshes:
		assert_int(m.multimesh.instance_count).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == m.name).size())
	assert_int(node.find_children("*", "OmniLight3D", false, false).size()).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == "light").size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
