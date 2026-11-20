extends GdUnitTestSuite
## The look pass's dressing of a boardgen layout (BoardgenProps): one seed dresses the same board every time and another seed
## another, no prop takes standing room (only the wall strip, or flat), the foot of a ladder stays bare,
## at most 8 lights, and the kit is five MultiMeshes with nothing physical. Stands on the recorded seed 42 layout.

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


func test_a_landmark_footprint_stays_bare() -> void:
	var layout := _fixture()
	assert_int(BoardgenProps.plan(layout).size()).is_greater(40)
	layout["landmarks"] = [{"kind": "TankCluster", "x": 0, "z": 0, "w": 16, "h": 16, "turn": 0}]   # every cell is some landmark's
	assert_int(BoardgenProps.plan(layout).size()).is_equal(0)


## True when `corner` (inches off the board centre) is not standing room: inside a tier block, within STRIP_IN of a tier wall in its level-0 cell.
func _outside_standing_room(layout: Dictionary, corner: Vector3) -> bool:
	var half := Vector2(layout["nx"], layout["nz"]) * CELL_IN * 0.5
	var g := (Vector2(corner.x, corner.z) + half) / CELL_IN
	var c := Vector2i(floori(g.x), floori(g.y))
	var level := _level(layout, c)
	if level > 0:
		return corner.y <= float(layout["level_in"][level]) + 0.01
	var f := (g - Vector2(c)) * CELL_IN
	for d in BoardgenProps.DIRS:
		var dist := CELL_IN - f.x if d.x > 0 else f.x if d.x < 0 else CELL_IN - f.y if d.y > 0 else f.y
		if _level(layout, c + d) > 0 and dist <= BoardgenProps.STRIP_IN + 0.01:
			return true
	return false


func test_no_prop_takes_standing_room_it_stays_in_the_wall_strip_or_lies_flat() -> void:
	var layout := _fixture()
	var shapes := {}
	for prop in BoardgenProps.plan(layout):
		shapes[prop["shape"]] = true
		if prop["shape"] == "light":
			continue
		var top := -INF
		var corners: Array[Vector3] = []
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					corners.append(prop["xf"] * Vector3(sx, sy, sz) / BoardgenProps.INCHES_TO_METERS)
					top = maxf(top, corners[-1].y)
		if top <= BoardgenProps.FLAT_IN:
			continue   # paper-thin: a base can stand on it
		for corner in corners:
			assert_bool(_outside_standing_room(layout, corner)).override_failure_message("%s (scale %s, origin %s) reaches into standing room at %s" % [prop["shape"], prop["xf"].basis.get_scale() / BoardgenProps.INCHES_TO_METERS, prop["xf"].origin / BoardgenProps.INCHES_TO_METERS, corner]).is_true()
	assert_array(shapes.keys()).contains_exactly_in_any_order(["box", "cyl", "bulb", "ball", "ring", "light"])


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
	assert_int(meshes.size()).is_equal(5)
	for m: MultiMeshInstance3D in meshes:
		assert_int(m.multimesh.instance_count).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == m.name).size())
	assert_int(node.find_children("*", "OmniLight3D", false, false).size()).is_equal(props.filter(func(p: Dictionary) -> bool: return p["shape"] == "light").size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


## ---- the authored K2 pipes (AAA step 17): runs as modules, and no pipe ends in the air ----

const FIXTURE_DIR := "user://boardgen_props_test"


## The pipe runs of the kit plan: items of one module.
func _of(items: Array[Dictionary], module: String) -> Array[Dictionary]:
	return items.filter(func(p: Dictionary) -> bool: return p["shape"] == module)


func _inches(item: Dictionary) -> Vector3:
	return item["xf"].origin / BoardgenProps.INCHES_TO_METERS


## A pipe's two end points on the board (inches): the 3 in module is 1.5 in either side of its origin along its (stretched) x.
func _ends(pipe: Dictionary) -> Array[Vector3]:
	var half: Vector3 = pipe["xf"].basis.x * 1.5
	return [_inches(pipe) + half, _inches(pipe) - half]


func test_no_pipe_end_is_in_the_air_it_is_joined_or_turns_into_the_wall() -> void:
	var items := BoardgenProps.plan(_fixture(), true)
	var pipes := _of(items, "pipe")
	var elbows := _of(items, "elbow")
	var flanges := _of(items, "flange")
	assert_int(pipes.size()).is_greater(10)
	assert_int(elbows.size()).is_greater(0)
	for pipe in pipes:
		for end in _ends(pipe):
			var ok := flanges.any(func(f: Dictionary) -> bool: return _inches(f).distance_to(end) < 0.02)   # joined to the next run
			# an elbow's inlet (its -x end, one wall-offset from its corner) meets the pipe's end
			ok = ok or elbows.any(func(e: Dictionary) -> bool: return (_inches(e) - e["xf"].basis.x.normalized() * BoardgenProps.KIT_WALL_IN * e["xf"].basis.get_scale().x).distance_to(end) < 0.02)
			assert_bool(ok).override_failure_message("a pipe ends in the air at %s" % end).is_true()


func _on_grid(v: float) -> bool:
	return absf(v + 24.0 - roundf((v + 24.0) / CELL_IN) * CELL_IN) < 0.01


func test_an_elbow_outlet_lands_on_a_wall_plane() -> void:
	var items := BoardgenProps.plan(_fixture(), true)
	for e in _of(items, "elbow"):
		var out: Vector3 = _inches(e) + (e["xf"].basis * Vector3.BACK).normalized() * BoardgenProps.KIT_WALL_IN * e["xf"].basis.get_scale().x
		var on_plane := _on_grid(out.x) or _on_grid(out.z)   # walls stand on the 3 in cell grid, the board is 48 in wide
		assert_bool(on_plane).override_failure_message("an elbow outlet at %s is not on a wall plane" % out).is_true()


func test_the_kit_runs_keep_the_wall_strip_and_the_foot_of_a_ladder_bare() -> void:
	var layout := _fixture()
	var feet: Array = layout["connectors"].map(func(c: Dictionary) -> Vector2i: return Vector2i(c["low_xz"][0], c["low_xz"][1]))
	for item in BoardgenProps.plan(layout, true):
		if not BoardgenProps.KIT_MODULES.has(item["shape"]):
			continue
		assert_bool(feet.has(_cell_of(layout, item))).is_false()
		var box: AABB = BoardgenProps.KIT_BOUNDS[item["shape"]]
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var corner: Vector3 = item["xf"] * ((box.position + box.size * Vector3(sx, sy, sz)) * BoardgenProps.INCHES_TO_METERS) / BoardgenProps.INCHES_TO_METERS
					assert_bool(_outside_standing_room(layout, corner)).override_failure_message("%s reaches into standing room at %s" % [item["shape"], corner]).is_true()


func test_the_kit_does_not_change_what_the_board_is_dressed_with_otherwise() -> void:
	var layout := _fixture()
	var rest := func(items: Array[Dictionary]) -> Array: return items.filter(func(p: Dictionary) -> bool: return p["shape"] in ["light"]).map(func(p: Dictionary) -> Vector3: return p["xf"].origin)
	assert_array(rest.call(BoardgenProps.plan(layout, true))).is_equal(rest.call(BoardgenProps.plan(layout)))   # the same seeded draws: the same lamps


func test_build_draws_the_pipe_modules_when_cached_and_the_primitives_otherwise() -> void:
	var layout := _fixture()
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	for module in BoardgenProps.KIT_MODULES:
		var holder := MeshInstance3D.new()
		holder.mesh = SphereMesh.new()
		var state := GLTFState.new()
		GLTFDocument.new().append_from_scene(holder, state)
		GLTFDocument.new().write_to_filesystem(state, "%s/%s.glb" % [FIXTURE_DIR, module])
		holder.free()
	var kit: BoardgenKit = auto_free(BoardgenKit.new())
	add_child(kit)
	kit.local_dir = FIXTURE_DIR
	var node: BoardgenProps = auto_free(BoardgenProps.new())
	add_child(node)
	node.build(layout, kit)
	var items := BoardgenProps.plan(layout, true)
	for module: String in BoardgenProps.KIT_MODULES:
		assert_int((node.get_node(module) as MultiMeshInstance3D).multimesh.instance_count).is_equal(_of(items, module).size())
	assert_int(node.find_children("*", "MultiMeshInstance3D", false, false).size()).is_equal(10)   # five primitive shapes + five modules
