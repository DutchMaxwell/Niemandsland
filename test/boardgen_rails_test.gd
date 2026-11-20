extends GdUnitTestSuite
## The look pass's safety railings of a boardgen layout (BoardgenRails): one seed rails the same board every time and another seed
## another, every box stands on a tier top within REACH_IN of an edge that drops to a lower cell inside the board, a ladder top keeps its
## gap clear, the board perimeter has no rail, and the kit is ONE MultiMesh with nothing physical. Stands on the recorded seed 42 layout.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


## The 8 corners of a box's unit cube through its transform, in board inches off the centre.
func _corners(item: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			for sz in [-0.5, 0.5]:
				out.append(item["xf"] * Vector3(sx, sy, sz) / BoardgenRails.INCHES_TO_METERS)
	return out


func _cell(layout: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_IN + layout["nx"] * 0.5), floori(p.z / CELL_IN + layout["nz"] * 0.5))


func _level(layout: Dictionary, c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= layout["nx"] or c.y >= layout["nz"]:
		return 0
	return layout["cells"][c.y * layout["nx"] + c.x]["level"]


## True when `p` is on a tier top within REACH_IN of an edge that drops to a lower cell inside the board. The cells 0.05 in around
## `p` count too: a post shared by two cells stands on their common boundary.
func _near_drop(layout: Dictionary, p: Vector3) -> bool:
	for dx in [-0.05, 0.0, 0.05]:
		for dz in [-0.05, 0.0, 0.05]:
			var q := Vector3(p.x + dx, p.y, p.z + dz)
			var c := _cell(layout, q)
			var level := _level(layout, c)
			if level == 0 or p.y < float(layout["level_in"][level]) - 0.001:
				continue
			var f := Vector2(q.x / CELL_IN + layout["nx"] * 0.5 - c.x, q.z / CELL_IN + layout["nz"] * 0.5 - c.y) * CELL_IN
			for d in BoardgenProps.DIRS:
				var dist := CELL_IN - f.x if d.x > 0 else f.x if d.x < 0 else CELL_IN - f.y if d.y > 0 else f.y
				if BoardgenRails._drops(layout, c, d) and dist <= BoardgenRails.REACH_IN + 0.001:
					return true
	return false


func test_one_seed_rails_the_same_board_and_another_seed_another() -> void:
	var layout := _fixture()
	var first := BoardgenRails.plan(layout)
	assert_int(first.size()).is_greater(100)
	randomize()   # the global generator must not matter
	assert_array(BoardgenRails.plan(layout)).is_equal(first)
	assert_array(BoardgenRails.plan(_fixture())).is_equal(first)
	var other := _fixture()
	other["seed"] = int(layout["seed"]) + 1
	assert_bool(BoardgenRails.plan(other) == first).is_false()


func test_every_box_stands_on_a_tier_top_within_reach_of_a_drop_edge() -> void:
	var layout := _fixture()
	for item in BoardgenRails.plan(layout):
		for p in _corners(item):
			assert_bool(_near_drop(layout, p)).override_failure_message("a rail box reaches %s, away from a drop edge" % p).is_true()


func test_a_ladder_top_keeps_a_gap_and_the_rail_runs_up_to_it() -> void:
	var layout := _fixture()
	var origin := Vector2(layout["nx"], layout["nz"]) * CELL_IN * -0.5
	var items := BoardgenRails.plan(layout)
	var flanked := 0   # ladders with rail right beside the gap: the gap test is not satisfied by an empty board
	for c: Dictionary in layout["connectors"]:
		var at := Vector2(c["edge_in"][0], c["edge_in"][1]) + origin
		var top := float(layout["level_in"][layout["cells"][c["high"]]["level"]])
		var nearest := 99.0
		for item in items:
			for p in _corners(item):
				if p.y > top - 0.001:
					nearest = minf(nearest, Vector2(p.x, p.z).distance_to(at))
		assert_float(nearest).override_failure_message("a rail box comes within %s in of the ladder top at %s" % [nearest, at]).is_greater_equal(0.8)
		flanked += 1 if nearest < 1.2 else 0
	assert_int(flanked).is_greater(5)


func test_the_board_perimeter_has_no_rail() -> void:
	var layout := _fixture()
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var items := BoardgenRails.plan(layout)
	var perimeter := 0
	for z in nz:
		for x in nx:
			for d in BoardgenProps.DIRS:
				var c := Vector2i(x, z)
				if _level(layout, c) == 0 or _level(layout, c + d) != 0 or (c + d).x >= 0 and (c + d).y >= 0 and (c + d).x < nx and (c + d).y < nz:
					continue
				perimeter += 1   # a tier cell whose neighbour in d is off the board
				var line := (Vector2(c) + Vector2(0.5, 0.5) + Vector2(d) * 0.5) * CELL_IN - Vector2(nx, nz) * CELL_IN * 0.5
				for item in items:
					var o: Vector3 = item["xf"].origin / BoardgenRails.INCHES_TO_METERS
					var across := Vector2(o.x, o.z) - line
					var on_edge := absf(across.dot(Vector2(d))) < 0.15 and absf(across.dot(Vector2(-d.y, d.x))) < 1.2
					assert_bool(on_edge and o.y > float(layout["level_in"][_level(layout, c)])).override_failure_message("a rail box stands on the board perimeter at %s" % c).is_false()
	assert_int(perimeter).is_greater(0)


func test_the_kit_is_one_multimesh_with_taller_corner_posts_and_nothing_physical() -> void:
	var layout := _fixture()
	var node: BoardgenRails = auto_free(BoardgenRails.new())
	add_child(node)
	node.build(layout)
	var items := BoardgenRails.plan(layout)
	var meshes := node.find_children("*", "MultiMeshInstance3D", false, false)
	assert_int(meshes.size()).is_equal(1)
	assert_int((meshes[0] as MultiMeshInstance3D).multimesh.instance_count).is_equal(items.size())
	assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	var tall := items.filter(func(i: Dictionary) -> bool: return i["xf"].basis.get_scale().y / BoardgenRails.INCHES_TO_METERS > 1.0)
	assert_int(tall.size()).is_greater(0)   # the corner posts are 1.1 in, a plain post 0.84


## ---- the authored K1 kit (AAA step 15): the same railing as instances of rail_span / rail_post / rail_post_corner ----

const FIXTURE_DIR := "user://boardgen_rails_test"


## A kit whose three rail modules are stand-in GLBs (a sphere each) in FIXTURE_DIR; `with_modules` false = an empty folder.
func _kit(with_modules: bool) -> BoardgenKit:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	for module in BoardgenRails.KIT_MODULES:
		var path := "%s/%s.glb" % [FIXTURE_DIR, module]
		if with_modules and not FileAccess.file_exists(path):
			var holder := MeshInstance3D.new()
			holder.mesh = SphereMesh.new()
			var state := GLTFState.new()
			GLTFDocument.new().append_from_scene(holder, state)
			GLTFDocument.new().write_to_filesystem(state, path)
			holder.free()
		elif not with_modules and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var kit := BoardgenKit.new()
	add_child(kit)
	kit.local_dir = FIXTURE_DIR
	return auto_free(kit)


## True when a tier top of exactly height `p.y` is under `p` (or within 0.05 in of it: a shared post stands on a boundary).
func _on_a_tier_top(layout: Dictionary, p: Vector3) -> bool:
	for dx in [-0.05, 0.0, 0.05]:
		for dz in [-0.05, 0.0, 0.05]:
			var level := _level(layout, _cell(layout, Vector3(p.x + dx, p.y, p.z + dz)))
			if level > 0 and absf(float(layout["level_in"][level]) - p.y) < 0.001:
				return true
	return false


func test_the_kit_plan_is_the_same_railing_drawn_as_modules() -> void:
	var layout := _fixture()
	var kit := BoardgenRails.kit_plan(layout)
	var spans: int = kit["rail_span"].size()
	var corners: int = kit["rail_post_corner"].size()
	assert_int(spans).is_greater(20)
	assert_int(corners).is_greater(0)
	# a span is 3 boxes, a post 1, a corner post 2: the box plan is these very parts
	assert_int(BoardgenRails.plan(layout).size()).is_equal(spans * 3 + kit["rail_post"].size() + corners * 2)
	assert_dict(BoardgenRails.kit_plan(_fixture())).is_equal(kit)
	for module: String in kit:
		for item: Dictionary in kit[module]:   # every module origin stands on a tier top within reach of a drop edge
			var p: Vector3 = item["xf"].origin / BoardgenRails.INCHES_TO_METERS
			assert_bool(_near_drop(layout, p) and _on_a_tier_top(layout, p)).override_failure_message("%s at %s is not on a tier top at a drop edge" % [module, p]).is_true()


func test_a_kit_span_ends_at_least_the_gap_from_a_ladder_top() -> void:
	var layout := _fixture()
	var origin := Vector2(layout["nx"], layout["nz"]) * CELL_IN * -0.5
	var ends: Array[Vector3] = []
	for item: Dictionary in BoardgenRails.kit_plan(layout)["rail_span"]:
		var half: Vector3 = item["xf"].basis.x * (BoardgenRails.SPAN_MODULE_IN * 0.5) / BoardgenRails.INCHES_TO_METERS
		ends.append(item["xf"].origin / BoardgenRails.INCHES_TO_METERS + half)
		ends.append(item["xf"].origin / BoardgenRails.INCHES_TO_METERS - half)
	for c: Dictionary in layout["connectors"]:
		var at := Vector2(c["edge_in"][0], c["edge_in"][1]) + origin
		for e in ends:
			if absf(e.y - float(layout["level_in"][layout["cells"][c["high"]]["level"]])) < 0.001:
				assert_float(Vector2(e.x, e.z).distance_to(at)).override_failure_message("a rail span ends %s in from the ladder top at %s" % [Vector2(e.x, e.z).distance_to(at), at]).is_greater_equal(0.85)


func test_build_draws_the_modules_when_they_are_cached_and_the_boxes_otherwise() -> void:
	var layout := _fixture()
	var with_kit: BoardgenRails = auto_free(BoardgenRails.new())
	add_child(with_kit)
	with_kit.build(layout, _kit(true))
	var plan := BoardgenRails.kit_plan(layout)
	assert_int(with_kit.get_child_count()).is_equal(3)   # one MultiMesh per module: three draws
	for module: String in BoardgenRails.KIT_MODULES:
		assert_int((with_kit.get_node(module) as MultiMeshInstance3D).multimesh.instance_count).is_equal(plan[module].size())
	for module: String in BoardgenRails.KIT_MODULES:   # a mesh that casts a shadow is drawn again in every cascade: only the span does
		assert_bool((with_kit.get_node(module) as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON).is_equal(module == "rail_span")
	var without: BoardgenRails = auto_free(BoardgenRails.new())
	add_child(without)
	without.build(layout, _kit(false))   # a module missing = the procedural boxes, still ONE MultiMesh
	assert_int(without.get_child_count()).is_equal(1)
	assert_int((without.get_node("Rails") as MultiMeshInstance3D).multimesh.instance_count).is_equal(BoardgenRails.plan(layout).size())
