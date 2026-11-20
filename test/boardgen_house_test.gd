extends GdUnitTestSuite
## Intact houses stop being boxes (plan O3): the drawn body is inset (inward only) and yawed a little, its eaves and plinth vary per house and half of the board; the
## collider, the class and every ruined (walkable) tier stay exactly as the core gave them.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## The recorded layout as a town with intact lots: two houses side by side (a 2 x 2 and a 3 x 2, a party wall between them), one far away in the south half, and one ruined Block.
func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["lots"] = []
	var specs := [[1, 2, 2, 2, "Roofed"], [3, 2, 3, 2, "Roofed"], [10, 11, 2, 2, "Roofed"], [8, 4, 2, 2, "Block"]]
	for i in specs.size():
		var s: Array = specs[i]
		layout["lots"].append({"id": i + 1, "x": s[0], "z": s[1], "w": s[2], "h": s[3], "sector": [0, 0], "kind": s[4]})
		for dz in int(s[3]):
			for dx in int(s[2]):
				var c: Dictionary = layout["cells"][(int(s[1]) + dz) * int(layout["nx"]) + int(s[0]) + dx]
				c["lot_id"] = i + 1
				c["lot_kind"] = s[4]
				c["level"] = 1 if s[4] == "Block" else 0
				c["street"] = false
	return layout


## The drawn body's four corners in board inches (centre + rotated half extents).
func _corners(b: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var half: Vector2 = b["size"] * 0.5
	for sign in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:   # round the outline
		out.append(b["centre"] + (sign * half).rotated(-float(b["yaw"])))   # Basis(UP, yaw) turns x towards -z
	return out


func _lot_rect(layout: Dictionary, id: int) -> Rect2:
	var cell := float(layout["cell_in"])
	var lot: Dictionary = layout["lots"][id - 1]
	return Rect2((Vector2(lot["x"], lot["z"]) - Vector2(layout["nx"], layout["nz"]) * 0.5) * cell, Vector2(lot["w"], lot["h"]) * cell)


func test_only_the_intact_lots_get_a_drawn_body_and_a_ruined_tier_is_never_touched() -> void:
	var layout := _town()
	var bodies := BoardgenTownDressing.house_bodies(layout)
	assert_array(bodies.map(func(b: Dictionary) -> int: return b["lot"])).is_equal([1, 2, 3])
	for b in BoardgenGreybox.plan(layout):
		if b["kind"] == "tier1":
			assert_array([b["lo"].y, b["hi"].y]).is_equal([0.0, 3.0])   # the ruined Block is the box the core gave it


func test_a_drawn_body_stays_inside_its_cells_and_within_the_reach_of_the_collider() -> void:
	var layout := _town()
	for b in BoardgenTownDressing.house_bodies(layout):
		var rect := _lot_rect(layout, b["lot"])
		var corners := _corners(b)
		for p in corners:
			assert_bool(rect.grow(0.0001).has_point(p)).override_failure_message("lot %d: a corner leaves its cells: %s in %s" % [b["lot"], p, rect]).is_true()
		# the farthest the drawn outline gets from the collider's face (the rect's nearest side), over the corners and the middle of every drawn edge
		var gap := 0.0
		for i in 4:
			for p: Vector2 in [corners[i], (corners[i] + corners[(i + 1) % 4]) * 0.5]:
				gap = maxf(gap, minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y)))
		assert_float(gap).override_failure_message("lot %d: the drawn wall is %.3f in off the collider" % [b["lot"], gap]).is_less_equal(0.2001)
		assert_float(absf(b["yaw"])).is_less_equal(deg_to_rad(3.0) + 0.0001)


func test_eaves_plinth_and_inset_vary_per_house_and_the_roof_follows_its_body() -> void:
	var layout := _town()
	var bodies := BoardgenTownDressing.house_bodies(layout)
	var roofs := BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"])
	for i in bodies.size():
		assert_float(bodies[i]["top"]).is_between(2.2, 2.8)
		assert_float(bodies[i]["plinth"]).is_between(0.3, 0.6)
		assert_float(roofs[i]["eaves"]).is_equal(bodies[i]["top"])
		assert_float(absf(roofs[i]["yaw"] - bodies[i]["yaw"])).is_less_equal(deg_to_rad(2.0) + 0.0001)   # the roof's skew on top of its body's yaw
	# the two neighbours share no eaves line and no wall line (their drawn east / west faces differ)
	assert_float(absf(bodies[0]["top"] - bodies[1]["top"])).is_greater(0.01)
	assert_float(absf(bodies[0]["centre"].x + bodies[0]["size"].x * 0.5 - bodies[1]["centre"].x + bodies[1]["size"].x * 0.5)).is_greater(0.01)
	assert_array(BoardgenTownDressing.house_bodies(layout)).is_equal(bodies)   # deterministic


func test_the_greybox_keeps_the_collider_of_an_intact_house_and_draws_its_body_elsewhere() -> void:
	var layout := _town()
	var board: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(board)
	board.build(layout)
	var roofed := 0
	for b in BoardgenGreybox.plan(layout):
		assert_bool(BoardgenGreybox.draws_itself(b)).is_equal(b["kind"] != "roofed")   # nothing drawn by the greybox box of an intact house ...
		roofed += int(b["kind"] == "roofed")
	assert_int(roofed).is_greater(0)
	var heights := {}
	for shape in board.find_children("*", "CollisionShape3D", true, false):
		heights[snappedf((shape as CollisionShape3D).shape.size.y / BoardgenGreybox.INCHES_TO_METERS, 0.01)] = true
	assert_bool(heights.has(2.5)).override_failure_message("the 2.5 in solid collider of the intact houses is gone").is_true()   # ... the collider stays
	var houses := (board.find_child("TownDressing", false, false).find_child("Houses", false, false) as MultiMeshInstance3D).multimesh
	assert_int(houses.instance_count).is_equal(3)
