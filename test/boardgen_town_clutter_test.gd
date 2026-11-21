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
		assert_vector(plan["lantern_post"][i]["xf"].origin + Vector3(0, BoardgenTownDressing.LANTERN_HEIGHT_IN * 0.0254, 0)).is_equal_approx(plan["lantern_glow"][i]["xf"].origin, Vector3.ONE * 0.00001)   # the glass at the head (at the foot it read as a white base)


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
			var own: Dictionary = layout["cells"][clampi(c.y, 0, 15) * 16 + clampi(c.x, 0, 15)]
			if own["lot_kind"] == "Terrace" and int(own["level"]) == 0 and not own["street"]:
				continue   # a story scene's piece in a yard (plan PLAN_RUINTOWN_GRIT S1: solid pieces stand in the strip OR in a yard)
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
	var scene_strip := 0   # plus the solid pieces of the story scenes (plan PLAN_RUINTOWN_GRIT S2), which stand on wall faces by the same rule
	var scene_items: Dictionary = BoardgenTownScenes.plan(layout)["items"]
	var fronts := BoardgenTownClutter.front_clusters(layout, BoardgenTownScenes.plan(layout)["reserved"])   # and the lived-in fronts (lane townC4), by the same rule
	for m: String in BoardgenTownClutter.STRIP:
		scene_strip += (scene_items.get(m, []) as Array).size() + (fronts.get(m, []) as Array).size()
	assert_int(pieces).is_equal(props.size() + scene_strip)   # one piece per prop box


func test_flat_pieces_are_flat_and_only_on_open_ground_and_the_outer_earth_has_more_of_them() -> void:
	var layout := _town()
	var plan := BoardgenTownClutter.plan(layout)
	var cell := float(layout["cell_in"])
	var origin := Vector2(16, 16) * cell * -0.5
	var inner := 0
	var outer := 0
	var scene_items: Dictionary = BoardgenTownScenes.plan(layout)["items"]   # (a story scene's flat spill may lie in a yard: test/boardgen_town_scenes_test.gd checks it)
	for m in BoardgenTownClutter.FLAT:
		for item: Dictionary in plan.get(m, []):
			if (scene_items.get(m, []) as Array).has(item):
				continue
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
	for m in ["fountain_basin_b", "fountain_column", "fountain_leaves"] + BoardgenTownClutter.STATUE_MODULES + ["pool_kerb", "well_ring", "well_frame"]:
		assert_bool(plan.has(m)).override_failure_message("no `%s` in the plan" % m).is_true()
	assert_int((plan["pool_kerb"] as Array).size()).is_equal(14)   # 2 x 2: two runs on each of the four edges; the 1 x 2 well: six runs
	var cell := 3.0
	var origin := Vector2(-24.0, -24.0)
	for item: Dictionary in plan["fountain_basin_b"]:
		var p := Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254
		assert_vector(p).is_equal_approx(Vector2(0.0, 0.0), Vector2.ONE * 0.001)   # the centre of the board
	for item: Dictionary in plan["pool_kerb"]:
		var p := Vector2(item["xf"].origin.x, item["xf"].origin.z) / 0.0254 - origin
		var pond := p.x >= 9 * cell - 0.001 and p.x <= 11 * cell + 0.001 and p.y >= 11 * cell - 0.001 and p.y <= 13 * cell + 0.001
		var well := p.x >= 13 * cell - 0.001 and p.x <= 14 * cell + 0.001 and p.y >= 2 * cell - 0.001 and p.y <= 4 * cell + 0.001
		assert_bool(pond or well).override_failure_message("a kerb run off its pool: %s" % p).is_true()
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


## Fences round the garden plots (kit batch A7, PLOT-EDGE): every piece inside a plot cell on an edge that looks at open level-0 ground, +z (a corner: both arms) into the plot, never on a
## street cell; every plot keeps a way in (a broken run or an open edge).
func test_fences_ring_the_garden_plots_from_inside_with_a_gap() -> void:
	var boards: Array = [_town()]
	for s: int in [7, 11, 13, 25, 41]:
		boards.append(ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown"))
	var total := 0
	for layout: Dictionary in boards:
		var nx: int = layout["nx"]
		var plan := BoardgenTownClutter.plan(layout)
		var origin := Vector2(nx, int(layout["nz"])) * 3.0 * -0.5
		var plot_cells := {}
		for cd: Dictionary in layout["cells"]:
			if cd["lot_kind"] == "Rough" and int(cd["level"]) == 0 and not cd["street"]:
				plot_cells[int(cd["z"]) * nx + int(cd["x"])] = true
		var straight := 0
		var gaps := 0
		for style: Array in BoardgenTownClutter.FENCE_STYLES:
			for k in 3:
				for it: Dictionary in plan.get(style[k], []):
					total += 1
					var xf: Transform3D = it["xf"]
					var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 - origin
					var probes: Array[Vector2] = []
					if k == 2:   # a corner: a point along each arm, 0.4 in in
						probes = [at + Vector2(xf.basis.x.x, xf.basis.x.z) * 1.5 + Vector2(xf.basis.z.x, xf.basis.z.z) * 0.4, at + Vector2(xf.basis.z.x, xf.basis.z.z) * 1.5 + Vector2(xf.basis.x.x, xf.basis.x.z) * 0.4]
					else:
						probes = [at + Vector2(xf.basis.z.x, xf.basis.z.z) * 0.4]
						assert_float(minf(fposmod(at.x, 3.0), fposmod(at.y, 3.0))).is_less(0.01)   # on a cell edge
						straight += 1 if k == 0 else 0
						gaps += 1 if k == 1 else 0
					for p: Vector2 in probes:
						var c := Vector2i(p / 3.0)
						assert_bool(plot_cells.has(c.y * nx + c.x)).override_failure_message("a fence at %s leans out of its plot" % at).is_true()
		var edges := 0
		for i: int in plot_cells:
			for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var n := Vector2i(i % nx, i / nx) + d
				if n.x >= 0 and n.y >= 0 and n.x < nx and n.y < int(layout["nz"]) and not plot_cells.has(n.y * nx + n.x) and int(layout["cells"][n.y * nx + n.x]["level"]) == 0 and layout["cells"][n.y * nx + n.x]["lot_kind"] != "Hazard":
					edges += 1
		var corners := 0
		for style: Array in BoardgenTownClutter.FENCE_STYLES:
			corners += (plan.get(style[2], []) as Array).size()
		if edges > 0:   # a way in: fewer closed runs than plot edges
			assert_int(straight + 2 * corners).override_failure_message("a plot fenced shut").is_less(edges)
	assert_int(total).is_greater(0)


## The feet and faces of the city wall (kit batch A7): rubble spills at the open feet of the wall cells beside a breach, buttresses on the FIELD face of long runs, ivy clusters on the shade
## (east / west) faces - every piece with its origin on a wall face, +z out onto open level-0 ground that is no ladder end.
func test_wall_spills_buttresses_and_ivy_clusters_stand_on_the_right_faces() -> void:
	var counts := {"wall_rubble_spill": 0, "wall_buttress_a": 0, "wall_buttress_b": 0, "ivy_cluster_large": 0, "ivy_cluster_small": 0}
	var shade_ivy := 0
	var lit_ivy := 0
	for s: int in [7, 11, 13, 17, 19, 23, 25, 29, 41, 43]:
		var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")
		var nx: int = layout["nx"]
		var clear := BoardgenTownClutter._kept_clear(layout)
		var plan := BoardgenTownClutter.plan(layout)
		for m: String in counts:
			for it: Dictionary in plan.get(m, []):
				counts[m] += 1
				var xf: Transform3D = it["xf"]
				var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 + Vector2(24, 24)
				var into := Vector2(xf.basis.z.x, xf.basis.z.z).round()
				var wall := Vector2i((at - into * 0.3) / 3.0)
				var foot := Vector2i((at + into * 0.3) / 3.0)
				var wc: Dictionary = layout["cells"][wall.y * nx + wall.x]
				var fc: Dictionary = layout["cells"][foot.y * nx + foot.x]
				assert_int(int(wc["level"])).override_failure_message("seed %d: %s not on a raised face" % [s, m]).is_greater(0)
				assert_int(int(fc["level"])).is_equal(0)
				assert_bool(clear.has(foot.y * nx + foot.x)).override_failure_message("seed %d: %s on a ladder face" % [s, m]).is_false()
				if m.begins_with("wall_buttress"):
					assert_str(wc["lot_kind"]).is_equal("Wall")
					assert_float(into.x).is_equal(-1.0 if wall.x * 2 < nx else 1.0)   # the field side
				if m.begins_with("ivy_cluster"):
					if absf(into.x) == 1.0:
						shade_ivy += 1   # a shade face (train 2: every face may carry ivy, the shade faces most)
					else:
						lit_ivy += 1
				if m == "wall_rubble_spill":
					var beside := false
					for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
						var b := wall + d
						beside = beside or (b.x >= 0 and b.y >= 0 and b.x < nx and b.y < 16 and layout["cells"][b.y * nx + b.x]["lot_kind"] == "Wall" and int(layout["cells"][b.y * nx + b.x]["level"]) == 0)
					assert_bool(beside).override_failure_message("seed %d: a spill away from any breach" % s).is_true()
	print("WALL PIECES ", counts)
	for m: String in counts:
		assert_int(counts[m]).override_failure_message("no %s on ten boards" % m).is_greater(0)
	assert_int(shade_ivy).override_failure_message("the shade faces must carry most of the ivy").is_greater(lit_ivy)
	assert_int(lit_ivy).override_failure_message("ivy on the lit faces too (train 2)").is_greater(0)


## Large hanging signs (kit batch A8): on a raised house face (not the wall, not an intact house) that looks at a street off the square, +z over the street, at most three a half.
func test_large_signs_hang_on_street_fronts_off_the_square() -> void:
	var total := 0
	for s: int in [7, 11, 13, 17, 19, 23, 25, 29, 41, 43]:
		var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")
		var nx: int = layout["nx"]
		var plan := BoardgenTownClutter.plan(layout)
		var irons: Array = plan.get("sign_large_iron", [])
		var boards := 0
		for m: String in BoardgenTownClutter.SIGN_BOARDS:
			boards += (plan.get(m, []) as Array).size()
		assert_int(boards).is_equal(irons.size())
		var per_half := [0, 0]
		for it: Dictionary in irons:
			total += 1
			var xf: Transform3D = it["xf"]
			var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 + Vector2(24, 24)
			var into := Vector2(xf.basis.z.x, xf.basis.z.z).round()
			var house := Vector2i((at - into * 0.3) / 3.0)
			var street := Vector2i((at + into * 0.3) / 3.0)
			var hc: Dictionary = layout["cells"][house.y * nx + house.x]
			var sc: Dictionary = layout["cells"][street.y * nx + street.x]
			assert_int(int(hc["level"])).is_greater(0)
			assert_bool(["Wall", "Roofed"].has(hc["lot_kind"])).is_false()
			assert_bool(sc["street"] and int(sc["level"]) == 0).override_failure_message("seed %d: a sign over no street" % s).is_true()
			per_half[1 if at.y >= 24.0 else 0] += 1
		assert_int(per_half.max()).is_less_equal(BoardgenTownClutter.SIGNS_PER_HALF)
	assert_int(total).is_greater(5)


## Green feet (plan TARGET C, train 2, V1): every weed clump stands with its origin on a raised face, +z out onto open level-0 ground that is no ladder end, its 1.03 in inside the
## 3 in edge, never on a face that carries a strip prop; the shade (east / west) faces carry more of them; every board has some.
func test_weed_clumps_stand_at_open_wall_feet_inside_their_edge_and_never_on_a_ladder_or_a_prop() -> void:
	var shade := 0
	var lit := 0
	for s: int in [7, 11, 13, 17, 19, 23, 25, 29, 41, 43]:
		var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")
		var nx: int = layout["nx"]
		var clear := BoardgenTownClutter._kept_clear(layout)
		var plan := BoardgenTownClutter.plan(layout)
		var props := {}
		for b: Dictionary in BoardgenTownDressing.props(layout):
			if typeof(b.get("face")) == TYPE_VECTOR2I:
				props["%d/%d" % [int(b["at"].x), int(b["at"].y)]] = b["face"]
		var n := 0
		for m: String in ["weeds_a", "weeds_b"]:
			for it: Dictionary in plan.get(m, []):
				n += 1
				var xf: Transform3D = it["xf"]
				var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 + Vector2(24, 24)
				var into := Vector2(xf.basis.z.x, xf.basis.z.z).round()
				var wall := Vector2i((at - into * 0.3) / 3.0)
				var foot := Vector2i((at + into * 0.3) / 3.0)
				assert_int(int(layout["cells"][wall.y * nx + wall.x]["level"])).override_failure_message("seed %d: a weed clump not at a raised face" % s).is_greater(0)
				assert_int(int(layout["cells"][foot.y * nx + foot.x]["level"])).is_equal(0)
				assert_bool(clear.has(foot.y * nx + foot.x)).override_failure_message("seed %d: a weed clump on a ladder end" % s).is_false()
				var along := absf(at.x - float(foot.x) * 3.0 - 1.5) if into.x == 0.0 else absf(at.y - float(foot.y) * 3.0 - 1.5)
				assert_float(along).override_failure_message("seed %d: a weed clump over its cell edge" % s).is_less_equal(1.5 - 0.52)
				var key := "%d/%d" % [foot.x, foot.y]
				assert_bool(props.has(key) and props[key] == Vector2i(-into)).override_failure_message("seed %d: a weed clump on a prop's face" % s).is_false()
				if into.x != 0.0:
					shade += 1
				else:
					lit += 1
		assert_int(n).override_failure_message("seed %d: no green feet" % s).is_greater(0)
	assert_int(shade).is_greater(lit)


func test_front_clusters_stand_in_the_strip_of_open_fronts_never_on_a_ladder_a_lamp_a_scene_or_the_deployment_earth() -> void:
	var total := 0
	for s: int in [7, 11, 13, 17, 19, 23, 25, 29, 41, 43]:
		var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")
		var nx: int = layout["nx"]
		var clear := BoardgenTownClutter._kept_clear(layout)
		var reserved: Dictionary = BoardgenTownScenes.plan(layout)["reserved"]
		var lamps := BoardgenTownDressing.lanterns(layout)
		var fronts := BoardgenTownClutter.front_clusters(layout, reserved)
		for m: String in fronts:
			for it: Dictionary in fronts[m]:
				total += 1
				var xf: Transform3D = it["xf"]
				var at := Vector2(xf.origin.x, xf.origin.z) / 0.0254 + Vector2(24, 24)
				var into := Vector2(xf.basis.z.x, xf.basis.z.z).normalized().round()
				var wall := Vector2i((at - into * 0.3) / 3.0)
				var foot := Vector2i((at + into * 0.3) / 3.0)
				var behind := foot + Vector2i(into)
				var fc: Dictionary = layout["cells"][foot.y * nx + foot.x]
				assert_int(int(layout["cells"][wall.y * nx + wall.x]["level"])).override_failure_message("seed %d: `%s` not at a raised face" % [s, m]).is_greater(0)
				assert_int(int(fc["level"])).is_equal(0)
				assert_bool(clear.has(foot.y * nx + foot.x) or reserved.has(foot.y * nx + foot.x)).override_failure_message("seed %d: `%s` on a ladder end or a scene" % [s, m]).is_false()
				assert_int(int(fc.get("deploy", 0))).override_failure_message("seed %d: `%s` on the deployment earth" % [s, m]).is_equal(0)
				assert_int(int(layout["cells"][behind.y * nx + behind.x]["level"])).override_failure_message("seed %d: `%s` in a one-cell lane" % [s, m]).is_equal(0)
				for l: Dictionary in lamps:
					assert_float((l["at"] as Vector2 + Vector2(24, 24)).distance_to(at)).override_failure_message("seed %d: `%s` on a lamp's foot" % [s, m]).is_greater(BoardgenTownClutter.LAMP_FREE_IN)
	assert_int(total).is_greater(100)
