extends GdUnitTestSuite
## The look pass's urban debris of a boardgen layout (BoardgenDebris): one seed scatters the same board every time and another seed
## another, nothing loose stands outside the wall strip (only flat paper lies in the open), the foot of every connector and the
## sump cells stay bare, and the kit is two MultiMeshes with nothing physical. Stands on the recorded seed 42 layout.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## The 8 corners of an item's unit box through its transform, in board inches off the centre.
func _corners(item: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				out.append(item["xf"] * Vector3(sx, sy, sz) / BoardgenDebris.INCHES_TO_METERS)
	return out


func _cell(layout: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_IN + layout["nx"] * 0.5), floori(p.z / CELL_IN + layout["nz"] * 0.5))


func _level(layout: Dictionary, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= layout["nx"] or c.y >= layout["nz"]:
		return 0
	return layout["cells"][c.y * layout["nx"] + c.x]["level"]


## A point is in the wall strip when it is inside a tier block (below its top) or within STRIP_IN of a tier wall of its floor cell.
func _in_strip(layout: Dictionary, p: Vector3) -> bool:
	var c := _cell(layout, p)
	if _level(layout, c) > 0:
		return p.y <= float(layout["level_in"][_level(layout, c)]) + 0.001
	var f := Vector2(p.x / CELL_IN + layout["nx"] * 0.5 - c.x, p.z / CELL_IN + layout["nz"] * 0.5 - c.y) * CELL_IN
	for d in BoardgenProps.DIRS:
		if _level(layout, c + d) > 0:
			var dist := CELL_IN - f.x if d.x > 0 else f.x if d.x < 0 else CELL_IN - f.y if d.y > 0 else f.y
			if dist <= BoardgenDebris.STRIP_IN + 0.001:
				return true
	return false


func _is_flat(layout: Dictionary, item: Dictionary) -> bool:
	var level := _level(layout, _cell(layout, item["xf"].origin / BoardgenDebris.INCHES_TO_METERS))
	var floor_y: float = float(layout["level_in"][level]) if level > 0 else BoardgenDebris.SKIN_IN
	return _corners(item).all(func(p: Vector3) -> bool: return p.y - floor_y <= BoardgenDebris.FLAT_IN + 0.001)


func test_one_seed_scatters_the_same_board_and_another_seed_another() -> void:
	var layout := _fixture()
	var first := BoardgenDebris.plan(layout)
	assert_int(first.size()).is_greater(60)
	randomize()   # the global generator must not matter
	assert_array(BoardgenDebris.plan(layout)).is_equal(first)
	assert_array(BoardgenDebris.plan(_fixture())).is_equal(first)
	var other := _fixture()
	other["seed"] = int(layout["seed"]) + 1
	assert_bool(BoardgenDebris.plan(other) == first).is_false()


func test_nothing_loose_stands_outside_the_wall_strip_only_flat_paper_lies_in_the_open() -> void:
	var layout := _fixture()
	var flat := 0
	var loose := 0
	for item in BoardgenDebris.plan(layout):
		if _is_flat(layout, item):
			flat += 1
			continue
		loose += 1
		for p in _corners(item):
			assert_bool(_in_strip(layout, p)).override_failure_message("a %s item reaches %s, outside the wall strip" % [item["shape"], p]).is_true()
	assert_int(flat).is_greater(10)
	assert_int(loose).is_greater(15)


func test_loose_debris_keeps_off_the_cells_that_carry_a_prop_of_the_kit() -> void:
	var layout := _fixture()
	var busy := {}
	for prop in BoardgenProps.plan(layout):
		if prop["shape"] != "light" and prop["xf"].origin.y > BoardgenDebris.FLAT_IN * BoardgenDebris.INCHES_TO_METERS:
			busy[_cell(layout, prop["xf"].origin / BoardgenDebris.INCHES_TO_METERS)] = true
	assert_int(busy.size()).is_greater(5)
	var loose := 0
	for item in BoardgenDebris.plan(layout):
		if not _is_flat(layout, item):
			loose += 1
			assert_bool(busy.has(_cell(layout, item["xf"].origin / BoardgenDebris.INCHES_TO_METERS))).override_failure_message("loose debris in the prop cell %s" % _cell(layout, item["xf"].origin / BoardgenDebris.INCHES_TO_METERS)).is_false()
	assert_int(loose).is_greater(10)


## A corner inside a tier block (below its top) is hidden in the concrete: only what shows counts.
func _shows_in(layout: Dictionary, p: Vector3) -> Vector2i:
	var c := _cell(layout, p)
	var level := _level(layout, c)
	return Vector2i(-99, -99) if level > 0 and p.y <= float(layout["level_in"][level]) + 0.001 else c


func test_the_foot_of_a_connector_and_the_sump_cells_stay_bare() -> void:
	var layout := _fixture()
	var feet: Array = layout["connectors"].map(func(c: Dictionary) -> Vector2i: return Vector2i(c["low_xz"][0], c["low_xz"][1]))
	assert_int(feet.size()).is_greater(10)
	for item in BoardgenDebris.plan(layout):
		for p in _corners(item):
			assert_bool(feet.has(_shows_in(layout, p))).override_failure_message("a %s item shows in the foot cell %s" % [item["shape"], _cell(layout, p)]).is_false()
	# This fixture has no sump, so mark every third column of it as one (the plan reads lot_kind) and the items must keep out of those.
	for i in layout["cells"].size():
		if i % layout["nx"] % 3 == 0:
			layout["cells"][i]["lot_kind"] = "Hazard"
	var planned := BoardgenDebris.plan(layout)
	assert_int(planned.size()).is_greater(30)
	for item in planned:
		for p in _corners(item):
			var c := _shows_in(layout, p)
			if c.x >= 0:
				assert_bool(layout["cells"][c.y * layout["nx"] + c.x]["lot_kind"] == "Hazard").override_failure_message("a %s item shows in the sump cell %s" % [item["shape"], c]).is_false()


func test_the_kit_is_two_multimeshes_and_nothing_physical() -> void:
	var layout := _fixture()
	var node: BoardgenDebris = auto_free(BoardgenDebris.new())
	add_child(node)
	node.build(layout)
	var items := BoardgenDebris.plan(layout)
	var meshes := node.find_children("*", "MultiMeshInstance3D", false, false)
	assert_int(meshes.size()).is_equal(2)
	for m: MultiMeshInstance3D in meshes:
		assert_int(m.multimesh.instance_count).is_equal(items.filter(func(p: Dictionary) -> bool: return p["shape"] == m.name).size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	assert_int(node.find_children("*", "Light3D", true, false).size()).is_equal(0)
