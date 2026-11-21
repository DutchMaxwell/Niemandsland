extends GdUnitTestSuite
## Where the authored clutter modules stand (plans A2 / A2b / A6): lamp posts with their glass at every lantern, the pieces of the wall strip with their origin on a wall face inside the 0.75 in
## strip, FLAT pieces only on open ground (more outside the wall and in the bands), PLOT pieces on garden plots / RUINS yards, ivy on faces without a ladder. Pure data (no kit needed).

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## The recorded layout as a town with: a wall run, a ladder-less tier, garden plots, a yard, open ground.
func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["connectors"] = []
	layout["landmarks"] = []
	for c: Dictionary in layout["cells"]:
		c["street"] = false
		c["lot_id"] = 0
		c["lot_kind"] = "Street"
		c["level"] = 0
		c["deploy"] = 1 if c["z"] < 4 else (2 if c["z"] >= 12 else 0)
	var put := func(x: int, z: int, level: int, kind: String) -> void:
		var c: Dictionary = layout["cells"][z * 16 + x]
		c["level"] = level
		c["lot_kind"] = kind
	for z in range(4, 12):
		put.call(4, z, 2, "Wall")   # a wall column
	for x in range(9, 13):
		for z in range(5, 8):
			put.call(x, z, 1, "Block")   # a ruined block
	for spec in [[7, 5], [7, 6], [8, 9], [9, 9]]:
		put.call(spec[0], spec[1], 0, "Rough")   # garden plots
	put.call(7, 10, 0, "Terrace")   # a yard
	return layout


func test_every_lantern_gets_a_post_and_its_glass_at_the_same_spot() -> void:
	var plan := BoardgenTownClutter.plan(_town())
	assert_int((plan["lantern_post"] as Array).size()).is_equal(BoardgenTownDressing.lanterns(_town()).size())
	assert_int((plan["lantern_glow"] as Array).size()).is_equal((plan["lantern_post"] as Array).size())
	for i in (plan["lantern_post"] as Array).size():
		assert_vector(plan["lantern_post"][i]["xf"].origin).is_equal_approx(plan["lantern_glow"][i]["xf"].origin, Vector3.ONE * 0.00001)


func test_strip_pieces_stand_on_a_wall_face_facing_away_from_it_and_inside_their_cell_edge() -> void:
	var layout := _town()
	var pieces := 0
	var cell := float(layout["cell_in"])
	var origin := Vector2(16, 16) * cell * -0.5
	var props := BoardgenTownDressing.props(layout)
	assert_int(props.size()).is_greater(0)
	var plan := BoardgenTownClutter.plan(layout)
	for m: String in BoardgenTownClutter.STRIP:
		for item: Dictionary in plan.get(m, []):
			pieces += 1
			var xf: Transform3D = item["xf"]
			var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 - origin   # inches off the board's corner
			var c := Vector2i(at / cell)
			# the piece's origin is on the edge between its cell and a raised cell; +z points into its own cell
			var into := Vector2(xf.basis.z.x, xf.basis.z.z).round()
			var wall_cell := Vector2i(Vector2(at + into * 0.2 * -1.0) / cell) if false else c
			assert_float(absf(Vector2(xf.basis.z.x, xf.basis.z.z).length() - 1.0)).is_less(0.001)
			var behind := at - into * 0.3   # a hair behind the origin = inside the wall cell
			var bc := Vector2i(behind / cell)
			assert_int(int(layout["cells"][bc.y * 16 + bc.x]["level"])).is_greater(0)
			var ahead := at + into * 0.3
			var ac := Vector2i(ahead / cell)
			assert_int(int(layout["cells"][ac.y * 16 + ac.x]["level"])).is_equal(0)
	assert_int(pieces).is_equal(props.size())   # one piece per prop box


func test_flat_pieces_are_flat_and_only_on_open_ground_and_the_outer_earth_has_more_of_them() -> void:
	var layout := _town()
	var plan := BoardgenTownClutter.plan(layout)
	var cell := float(layout["cell_in"])
	var origin := Vector2(16, 16) * cell * -0.5
	var inner := 0
	var outer := 0
	for m in BoardgenTownClutter.FLAT:
		for item: Dictionary in plan.get(m, []):
			var xf: Transform3D = item["xf"]
			assert_float(xf.origin.y).is_equal(0.0)   # on the ground; the modules themselves are <= 0.08 in high
			var c := Vector2i((Vector2(xf.origin.x, xf.origin.z) / 0.0254 - origin) / cell)
			var cd: Dictionary = layout["cells"][c.y * 16 + c.x]
			assert_int(cd["level"]).is_equal(0)
			assert_bool(["Wall", "Roofed", "Hazard", "Block", "Deck", "Terrace", "Rough"].has(cd["lot_kind"])).is_false()
			if cd["deploy"] != 0 or c.x < 4:
				outer += 1
			else:
				inner += 1
	assert_int(outer + inner).is_greater(8)
	assert_int(outer).is_greater(inner)   # the bands and the strip outside the wall are the emptiest earth: they get the most


func test_plot_pieces_stand_on_garden_plots_and_yards_and_ivy_never_on_a_ladder_face() -> void:
	var layout := _town()
	var plan := BoardgenTownClutter.plan(layout)
	var cell := float(layout["cell_in"])
	var origin := Vector2(16, 16) * cell * -0.5
	var found := 0
	for m in BoardgenTownClutter.PLOT_TREES + BoardgenTownClutter.PLOT_BRAMBLES:
		for item: Dictionary in plan.get(m, []):
			found += 1
			var c := Vector2i((Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254 - origin) / cell)
			assert_bool(["Rough", "Terrace"].has(layout["cells"][c.y * 16 + c.x]["lot_kind"])).override_failure_message("a plot piece off its plot at %s" % c).is_true()
	assert_int(found).is_greater(0)
	# a ladder on the block's west face: no ivy there
	layout["connectors"] = [{"kind": "Ladder", "low": 5 * 16 + 8, "high": 5 * 16 + 9}]
	var with_ladder := BoardgenTownClutter.plan(layout)
	for k in ["ivy_strand_a", "ivy_strand_b"]:
		for item: Dictionary in with_ladder.get(k, []):
			var c := Vector2i((Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254 - origin) / cell)
			assert_bool(c.y * 16 + c.x == 5 * 16 + 8 or c.y * 16 + c.x == 5 * 16 + 9).is_false()
	assert_dict(BoardgenTownClutter.plan(_town())).is_equal(BoardgenTownClutter.plan(_town()))   # deterministic


## The landmarks: a fountain and a statue and the pools stand inside their footprints; the solid boxes keep their colliders (the greybox draws them zero-size when the kit draws them).
func test_the_landmark_modules_stand_inside_their_footprints() -> void:
	var layout := _town()
	layout["landmarks"] = [
		{"kind": "TankCluster", "x": 7, "z": 7, "w": 2, "h": 2, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Crane", "x": 2, "z": 5, "w": 1, "h": 1, "turn": 1, "terrain": 2, "solid": true},
		{"kind": "Sump", "x": 9, "z": 11, "w": 2, "h": 2, "turn": 0, "terrain": 1, "solid": false},
		{"kind": "Sump", "x": 13, "z": 2, "w": 1, "h": 2, "turn": 0, "terrain": 1, "solid": false}]
	var plan := BoardgenTownClutter.plan(layout)
	for m in BoardgenTownClutter.FOUNTAIN_MODULES + BoardgenTownClutter.STATUE_MODULES + ["pool_kerb", "well_ring", "well_frame"]:
		assert_bool(plan.has(m)).override_failure_message("no `%s` in the plan" % m).is_true()
	assert_int((plan["pool_kerb"] as Array).size()).is_equal(8)   # 2 x 2: two runs on each of the four edges
	var cell := 3.0
	var origin := Vector2(-24.0, -24.0)
	for item: Dictionary in plan["fountain_basin"]:
		var p := Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254
		assert_vector(p).is_equal_approx(Vector2(0.0, 0.0), Vector2.ONE * 0.001)   # the centre of the board
	for item: Dictionary in plan["pool_kerb"]:
		var p := Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254 - origin
		assert_bool(p.x >= 9 * cell - 0.001 and p.x <= 11 * cell + 0.001 and p.y >= 11 * cell - 0.001 and p.y <= 13 * cell + 0.001).override_failure_message("a kerb run off its pool: %s" % p).is_true()
	assert_float(plan["statue_stump"][0]["xf"].origin.y).is_equal_approx(1.57 * 0.0254, 0.0001)   # on top of the plinth


## The pond kerb is tinted down through the kit's own per-module instance colour (not a shader hack): a pale run read as a dashed white line round the water from above.
func test_the_pool_kerb_is_a_weathered_stone_tint_not_a_white_run() -> void:
	var tint: Color = BoardgenTownKit.MODULE_TINT["pool_kerb"]
	assert_float(tint.get_luminance()).is_less(0.65)
	assert_float(tint.get_luminance()).is_greater(0.3)   # darker, not black


func _edge_between(layout: Dictionary, item: Dictionary, wall_ok: Callable) -> bool:
	var cell := float(layout["cell_in"])
	var origin := Vector2(16, 16) * cell * -0.5
	var xf: Transform3D = item["xf"]
	var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 - origin
	var into := Vector2(xf.basis.z.x, xf.basis.z.z).round()
	var behind := Vector2i((at - into * 0.3) / cell)
	var ahead := Vector2i((at + into * 0.3) / cell)
	return wall_ok.call(layout["cells"][behind.y * 16 + behind.x], layout["cells"][ahead.y * 16 + ahead.x])


## The hall, the towers, the square and the yards (second batch of A2 / A2b / A3).
func test_hall_towers_square_walls_and_yards_follow_the_strip_rules() -> void:
	var layout := _town()
	var put := func(x: int, z: int, level: int, kind: String, street := false) -> void:
		var c: Dictionary = layout["cells"][z * 16 + x]
		c["level"] = level
		c["lot_kind"] = kind
		c["street"] = street
	for x in range(6, 10):   # the market square
		for z in range(5, 11):
			put.call(x, z, 0, "Street", true)
	for z in range(5, 11):   # a house row on its west side
		put.call(5, z, 2, "Block")
	for x in [13, 14]:   # three towers
		for z in [2, 3]:
			put.call(x, z, 3, "Block")
	for x in [1, 2]:
		for z in [12, 13]:
			put.call(x, z, 3, "Block")
	for x in [1, 2]:
		for z in [1, 2]:
			put.call(x, z, 3, "Block")
	for spec in [[1, 9], [2, 9], [1, 10], [2, 10], [3, 9], [3, 10], [1, 11], [2, 11]]:
		put.call(spec[0], spec[1], 0, "Terrace")   # yard cells
	layout["landmarks"] = [{"kind": "PumpHouse", "x": 10, "z": 5, "w": 2, "h": 2, "turn": 0, "terrain": 0, "solid": false}]
	var plan := BoardgenTownClutter.plan(layout)
	assert_int((plan.get("hall_column_a", []) as Array).size() + (plan.get("hall_column_b", []) as Array).size()).is_equal(4)
	assert_int((plan["hall_pediment"] as Array).size()).is_equal(1)
	for m in ["hall_column_a", "hall_column_b", "hall_pediment"]:
		for item: Dictionary in plan.get(m, []):
			assert_float(item["xf"].origin.y).is_equal_approx(3.0 * 0.0254, 0.0001)   # on the hall block's top
	var towers := (plan.get("tower_turret", []) as Array).size() + (plan.get("tower_cap_burnt", []) as Array).size()
	assert_int(towers).is_greater(0)
	for item: Dictionary in plan.get("tower_turret", []):
		var xf: Transform3D = item["xf"]
		var corner := Vector2(xf.origin.x, xf.origin.z) / 0.0254 + Vector2(24, 24)   # inches off the board's corner
		var inward := Vector2(xf.basis.x.x + xf.basis.z.x, xf.basis.x.z + xf.basis.z.z)   # +x and +z of the module: the quadrant it fills
		var mid := corner + inward * 0.4
		var c := Vector2i(mid / 3.0)
		assert_int(int(layout["cells"][c.y * 16 + c.x]["level"])).override_failure_message("a turret points off its tower: %s" % corner).is_equal(3)
	for m in ["stall_frame", "stall_frame_ruined", "stall_awning", "stall_awning_ruined", "brazier", "brazier_coals", "sign_bracket", "sign_board_loaf", "sign_board_boot"]:
		for item: Dictionary in plan.get(m, []):
			assert_bool(_edge_between(layout, item, func(behind: Dictionary, ahead: Dictionary) -> bool: return behind["level"] >= 1 and ahead["level"] == 0 and ahead["street"])).override_failure_message("`%s` is not on a house face of the square" % m).is_true()
	var square_pieces := 0
	for m in ["stall_frame", "stall_frame_ruined", "brazier", "sign_bracket"]:
		square_pieces += (plan.get(m, []) as Array).size()
	assert_int(square_pieces).is_greater(0)
	assert_int((plan.get("laundry_line", []) as Array).size()).is_less_equal(2)
	for item: Dictionary in plan.get("rubble_heap_a", []) + plan.get("rubble_heap_b", []):
		var c := Vector2i((Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254 + Vector2(24, 24)) / 3.0)
		assert_str(layout["cells"][c.y * 16 + c.x]["lot_kind"]).is_equal("Terrace")   # only on a RUINS yard


func test_every_tower_corner_turret_fills_its_tower_not_the_air() -> void:
	# corners NW, NE, SE, SW of a tower top; the module fills local +x / +z, so after the yaw that quadrant must point into the tower
	var inward := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for corner in 4:
		var quad := Basis(Vector3.UP, BoardgenTownClutter.TURRET_YAW[corner]) * Vector3(1, 0, 1)
		assert_vector(Vector2(quad.x, quad.z).round()).override_failure_message("corner %d turns its turret off the tower" % corner).is_equal(inward[corner])


## The kit ladder replaces the box ladder only if the walkable / ladder data stays identical (lead's condition): the kit plan IS BoardgenGreybox.ladder_kit_plan renamed - one segment per 3 in of every
## connector's rise at the same edge point - and the box ladders it replaces are not solid, so no collider disappears.
func test_the_kit_ladder_carries_exactly_the_ladder_data_of_the_box_ladder() -> void:
	var layout := _town()
	layout["level_in"] = [0, 3, 6, 9]
	layout["connectors"] = [{"kind": "Ladder", "low": 5 * 16 + 8, "high": 5 * 16 + 9, "low_xz": [8, 5], "high_xz": [9, 5], "edge_in": [27.0, 16.5]}]
	layout["cells"][5 * 16 + 9]["level"] = 1   # the core only joins cells one level apart: a 3 in rise
	var box_plan := BoardgenGreybox.plan(layout)
	var ladders := box_plan.filter(func(b: Dictionary) -> bool: return b["kind"] == "ladder" and not b.get("lantern", false))
	assert_int(ladders.size()).is_greater(0)
	for b: Dictionary in ladders:
		assert_bool(b["solid"]).override_failure_message("a solid ladder box: its collider would disappear with the kit ladder").is_false()
	var kit_plan := BoardgenGreybox.ladder_kit_plan(layout)
	var segments := 0
	for key: String in kit_plan:
		segments += (kit_plan[key] as Array).size()
	assert_int(segments).is_equal(1)   # a 3 in rise is one segment: the top one
	assert_int((kit_plan["ladder_top"] as Array).size()).is_equal(1)
	# the town kit's ladder items are those very transforms
	var town := BoardgenTownKit.new()
	var from_kit := BoardgenTownKit.plan(layout)
	assert_array(from_kit["timber_ladder_top"]).is_equal(kit_plan["ladder_top"])
	town.free()


## Lead 21.11.: burnt cap frames are rare (they read as scaffolding when a third of the towers had one).
func test_burnt_cap_frames_are_rare() -> void:
	assert_float(BoardgenTownClutter.BURNT_CAP_SHARE).is_less_equal(0.15)
	assert_float(BoardgenTownClutter.BURNT_CAP_SHARE).is_greater(0.0)   # but they exist
