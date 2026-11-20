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
