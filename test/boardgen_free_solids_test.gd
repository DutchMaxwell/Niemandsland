extends GdUnitTestSuite
## Organic plan K1: on a board with free solids (the layout's `solids`, the core's intact houses as turned boxes) the drawn house body and its
## collider ARE the core box - centre, size and yaw - and the house's cells are open ground. The layout is the recorded one with one 2 x 2 house
## lot whose core box is turned 15 deg (as the core would emit it), so this suite stands without the native library.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const YAW := 0.2617993878   # 15 deg
const TOL_IN := 0.1


func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["lots"] = [{"id": 1, "x": 2, "z": 2, "w": 2, "h": 2, "sector": [0, 0], "kind": "Roofed"}]
	for dz in 2:
		for dx in 2:
			var c: Dictionary = layout["cells"][(2 + dz) * int(layout["nx"]) + 2 + dx]
			c.merge({"lot_id": 1, "lot_kind": "Roofed", "level": 0, "street": false}, true)
	# the core's inscribed box of the 6 x 6 in lot at 15 deg (centre = the lot's centre, -24 + 6 + 3 = -15 in)
	var side := (6.0 * cos(YAW) - 6.0 * sin(YAW)) / cos(2.0 * YAW)
	layout["solids"] = [{"c_in": [-15.0, -15.0], "he_in": [side * 0.5, side * 0.5], "yaw": YAW, "lot": 1}]
	return layout


## Corners of a box: centre + half extents turned the core's way (local +X -> (cos, -sin), Basis(UP, yaw) in Godot).
func _corners(c: Vector2, size: Vector2, yaw: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(c + (s * size * 0.5).rotated(-yaw))
	return out


func _worst(a: Array[Vector2], b: Array[Vector2]) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


func _core_corners(layout: Dictionary) -> Array[Vector2]:
	var s: Dictionary = layout["solids"][0]
	return _corners(Vector2(s["c_in"][0], s["c_in"][1]), Vector2(s["he_in"][0], s["he_in"][1]) * 2.0, float(s["yaw"]))


func test_a_drawn_house_is_its_core_box() -> void:
	var layout := _town()
	var bodies := BoardgenTownDressing.house_bodies(layout)
	assert_int(bodies.size()).is_equal(1)
	var b: Dictionary = bodies[0]
	assert_float(_worst(_corners(b["centre"], b["size"], b["yaw"]), _core_corners(layout))).is_less_equal(TOL_IN)
	# planted fault: the drawn body with its yaw ignored is caught by the same measure
	assert_float(_worst(_corners(b["centre"], b["size"], 0.0), _core_corners(layout))).is_greater(TOL_IN)
	# the roof follows the box's own axis
	for r: Dictionary in BoardgenTownDressing.roofs(layout):
		assert_float(absf(float(r["yaw"]) - YAW)).is_less_equal(deg_to_rad(2.0) + 1e-6)


func test_the_collider_is_the_core_box() -> void:
	var layout := _town()
	var solid := BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b["solid"] and b["kind"] == "roofed")
	assert_int(solid.size()).is_equal(1)   # the house's cells are no collider of their own: only its box
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	var hit := 0
	for col: CollisionShape3D in node.find_child("Colliders", false, false).get_children():
		var box := col.shape as BoxShape3D
		if not is_equal_approx(col.rotation.y, YAW):
			continue
		var c := Vector2(col.position.x, col.position.z) / BoardgenGreybox.INCHES_TO_METERS
		var size := Vector2(box.size.x, box.size.z) / BoardgenGreybox.INCHES_TO_METERS
		assert_float(_worst(_corners(c, size, col.rotation.y), _core_corners(layout))).is_less_equal(0.001)
		hit += 1
	assert_int(hit).is_equal(1)


func test_a_free_house_cell_is_open_ground_in_the_plan_and_the_ground_map() -> void:
	var layout := _town()
	var cell: Dictionary = layout["cells"][2 * int(layout["nx"]) + 2]
	assert_str(BoardgenGreybox._cell_kind(cell, true, true)).is_equal("ground")
	assert_str(BoardgenGreybox._cell_kind(cell, true, false)).is_equal("roofed")   # a cell board keeps its painted house


## K2 (lite): the ground map paints no house texel at all on a free board - the house is its drawn body, the ground under a turned box's leftover corners
## is open ground like the core's NONE. Planted: the same map on the cell board paints the lot's four cells as house.
func test_no_house_texel_outside_its_box() -> void:
	var layout := _town()
	var kinds: Array = BoardgenTheme.TOWN_KINDS
	var roofed := kinds.find("roofed")
	var count := func(bytes: PackedByteArray) -> int:
		var n := 0
		for i in range(0, bytes.size(), 4):
			n += int(bytes[i] == roofed)
		return n
	assert_int(count.call(BoardgenGreybox.ground_map(layout, kinds))).is_equal(0)
	layout.erase("solids")
	assert_int(count.call(BoardgenGreybox.ground_map(layout, kinds))).is_equal(4)
