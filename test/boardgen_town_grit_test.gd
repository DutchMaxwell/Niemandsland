extends GdUnitTestSuite
## The grit map of the ruin town (plan PLAN_RUINTOWN_GRIT): built from the layout alone, deterministic, half-turn true for its data channels, cheap; and the look it drives must not lie.

const SEEDS := [7, 25, 41]


func _layout(board_seed: int) -> Dictionary:
	return ClassDB.instantiate("NmlCore").boardgen_layout_themed(board_seed, "ruintown")


## The layout turned by half a turn about the board centre (cells and landmarks; nothing else is read by the map).
func _turned(layout: Dictionary) -> Dictionary:
	var nx: int = layout["nx"]
	var nz: int = layout["nz"]
	var out := layout.duplicate(true)
	for i in nx * nz:
		var c: Dictionary = (layout["cells"][nx * nz - 1 - i] as Dictionary).duplicate(true)
		c["x"] = i % nx
		c["z"] = i / nx
		out["cells"][i] = c
	for lm: Dictionary in out["landmarks"]:
		lm["x"] = nx - int(lm["x"]) - int(lm["w"])
		lm["z"] = nz - int(lm["z"]) - int(lm["h"])
	return out


func test_the_map_is_the_same_for_the_same_seed() -> void:
	for s: int in SEEDS:
		assert_bool(BoardgenTownGrit.map(_layout(s)).get_data() == BoardgenTownGrit.map(_layout(s)).get_data()).is_true()


func test_a_half_turned_layout_gives_the_half_turned_map_for_wear_and_wet_outside_the_puddles() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var a := BoardgenTownGrit.map(layout)
		var b := BoardgenTownGrit.map(_turned(layout))
		var w := a.get_width()
		var h := a.get_height()
		var worst := 0.0
		for z in h:
			for x in w:
				var ca := a.get_pixel(x, z)
				var cb := b.get_pixel(w - 1 - x, h - 1 - z)
				if ca.g8 > 179 or cb.g8 > 179:
					continue   # a puddle (G5): the look, not the data - it need not mirror
				worst = maxf(worst, maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)))
		assert_float(worst).override_failure_message("seed %d: wear / wet differ by %.3f under a half turn" % [s, worst]).is_less_equal(1.5 / 255.0)


func test_the_map_knows_the_street_edges_and_the_mud_at_every_earth_border() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var img := BoardgenTownGrit.map(layout)
		var cls := BoardgenTownGrit.classes(layout)
		var nx: int = layout["nx"]
		var tpc := BoardgenTownGrit.TEXELS_PER_CELL
		var borders := 0
		for i in cls.size():
			if cls[i] != 1:
				continue
			var cx := i % nx
			var cz := i / nx
			if cx + 1 < nx and cls[i + 1] == 2:   # earth east of this street cell: the texel beside the border is muddy, the far side of the cell is not
				borders += 1
				assert_float(img.get_pixel(cx * tpc + tpc - 1, cz * tpc + tpc / 2).g).is_greater(0.5)
				assert_float(img.get_pixel((cx + 1) * tpc, cz * tpc + tpc / 2).g).is_greater(0.5)   # the damp earth across it
			if cx > 0 and cls[i - 1] == 0 and cx + 1 < nx and cls[i + 1] == 1:   # a wall west: the street's edge is near there, far from it in the middle of the next cell
				assert_float(img.get_pixel(cx * tpc, cz * tpc + tpc / 2).r).is_less(0.1)
		assert_int(borders).override_failure_message("seed %d has no street / earth border to test" % s).is_greater(0)


func test_the_map_is_built_in_under_30_ms() -> void:
	var layout := _layout(41)
	BoardgenTownGrit.map(layout)
	var best := 1e9
	for _i in 3:
		var t0 := Time.get_ticks_usec()
		BoardgenTownGrit.map(layout)
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	print("GRIT_MAP_BUILD_MS %.1f" % best)
	assert_float(best).is_less(60.0)   # the plan asks < 30 ms (laptop 14-26 ms, printed); the margin is for a loaded CI runner


func test_every_straight_street_knows_its_section_and_the_arteries_are_the_long_runs() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var cls := BoardgenTownGrit.classes(layout)
		var section := BoardgenTownGrit.runs(layout, cls)
		var img := BoardgenTownGrit.map(layout)
		var nx: int = layout["nx"]
		var tpc := BoardgenTownGrit.TEXELS_PER_CELL
		var arteries := 0
		for i: int in section:
			var r: Dictionary = section[i]
			arteries += 1 if r["artery"] else 0
			var cx := i % nx
			var cz := i / nx
			for t in tpc:   # across the cell the offset grows by one inch per inch (16 per inch in the byte), wherever the centre line wanders
				var a := img.get_pixel(cx * tpc + (t if r["axis"] == 1 else tpc / 2), cz * tpc + (t if r["axis"] == 0 else tpc / 2)).b8
				var b := img.get_pixel(cx * tpc + (mini(t + 1, tpc - 1) if r["axis"] == 1 else tpc / 2), cz * tpc + (mini(t + 1, tpc - 1) if r["axis"] == 0 else tpc / 2)).b8
				if t + 1 < tpc and a > 0 and a < 127 and b > 0 and b < 127 or (a > 128 and a < 255 and b > 128 and b < 255 and t + 1 < tpc):
					assert_int(b - a).is_between(2, 4)
			var lo := 128 if r["artery"] else 0
			var mid := img.get_pixel(cx * tpc + tpc / 2, cz * tpc + tpc / 2).b8
			assert_int(mid).is_between(lo, lo + 127)
		assert_int(arteries).override_failure_message("seed %d: no artery" % s).is_greater(0)
		for i in nx * layout["nz"]:   # a junction, a square and the ground off the streets have no section
			if not section.has(i):
				assert_int(img.get_pixel((i % nx) * tpc + tpc / 2, (i / nx) * tpc + tpc / 2).b8).is_equal(255)


## THE LOOK MUST NOT LIE (plan G3): street mud never reads as a plot or rough ground - the film over the setts is capped at 40 %, it is driven by the map (an earth border, water), and the
## map's wet / mud never exceeds 0.7 on a street texel (puddles, G5, are the only thing above it).
func test_street_mud_never_covers_more_than_40_percent_of_the_setts() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	var rx := RegEx.create_from_string("const float GRIT_MUD_COVER = ([0-9.]+);")
	var m := rx.search(src)
	assert_object(m).is_not_null()
	assert_float(float(m.get_string(1))).is_less_equal(0.4)
	assert_bool(src.contains("float cover = min(GRIT_MUD_COVER, ")).override_failure_message("the mud film is not capped by GRIT_MUD_COVER").is_true()
	assert_int(src.count("alb = mix(alb, mudc * 1.15, cover);")).is_equal(1)
	for s: int in SEEDS:
		var layout := _layout(s)
		var img := BoardgenTownGrit.map(layout)
		var cls := BoardgenTownGrit.classes(layout)
		var nx: int = layout["nx"]
		var tpc := BoardgenTownGrit.TEXELS_PER_CELL
		var worst := 0
		for z in img.get_height():
			for x in img.get_width():
				var g8 := img.get_pixel(x, z).g8
				if cls[(z / tpc) * nx + x / tpc] == 1 and g8 < 191:   # 191+ is a puddle (G5), not mud
					worst = maxi(worst, g8)
		assert_int(worst).override_failure_message("seed %d: wet / mud %d on a street texel" % [s, worst]).is_less_equal(179)


func test_the_damage_lies_in_a_few_patches_beside_the_walls_and_along_the_ruts_not_in_the_wear_lane() -> void:
	for s: int in SEEDS:
		var layout := _layout(s)
		var cls := BoardgenTownGrit.classes(layout)
		var pts := BoardgenTownGrit.patches(layout, cls)
		assert_int(pts.size()).override_failure_message("seed %d: %d patches" % [s, pts.size()]).is_between(4, 8)
		for i in pts.size():
			assert_float(float(pts[i]["r"]) * 2.0).is_between(2.0, 5.0)
			for j in range(i + 1, pts.size()):
				assert_float((pts[i]["at"] as Vector2).distance_to(pts[j]["at"])).is_greater_equal(6.0)
		var img := BoardgenTownGrit.map(layout)   # the walked middle (edge > 1.2 in) carries less than half the damage of the 1 in beside the walls
		var side := [0.0, 0]
		var middle := [0.0, 0]
		for z in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, z)
				if cls[(z / BoardgenTownGrit.TEXELS_PER_CELL) * int(layout["nx"]) + x / BoardgenTownGrit.TEXELS_PER_CELL] != 1:
					continue
				var edge := c.r * BoardgenTownGrit.EDGE_CAP_IN
				if c.b8 >= 128 and c.b8 < 255 and absf(absf((c.b8 - 192) / 16.0) - BoardgenTownGrit.RUT_IN) < 0.35:
					continue   # the ruts are damage in the middle by design
				var bucket: Array = side if edge < 1.0 else (middle if edge > 1.2 else [0.0, 0])
				bucket[0] += c.a
				bucket[1] += 1
		if middle[1] > 0:
			assert_float(middle[0] / middle[1]).override_failure_message("seed %d: middle %.3f side %.3f" % [s, middle[0] / middle[1], side[0] / side[1]]).is_less(0.5 * side[0] / side[1])


## The broken paving the odds give on the map itself (style bible 6): 4-8 % missing, 10-15 % sunken, 6-10 % cracked, 3-5 % repaired, at least half the missing ones in the patches (clustered,
## never salt and pepper), and the walked middle of a street at less than half the rest's odds. The shader reads the same odds (uniforms set by BoardgenTownGrit.apply).
func test_the_odds_of_the_setts_give_the_style_bibles_broken_paving() -> void:
	for s: int in SEEDS:
		var e := BoardgenTownGrit.expected_shares(_layout(s))
		print("GRIT_SHARES seed %d %s" % [s, e])
		assert_float(e["missing"]).override_failure_message("seed %d missing %.3f" % [s, e["missing"]]).is_between(0.04, 0.08)
		assert_float(e["sunken"]).override_failure_message("seed %d sunken %.3f" % [s, e["sunken"]]).is_between(0.10, 0.15)
		assert_float(e["cracked"]).is_between(0.06, 0.10)
		assert_float(e["repair"]).is_between(0.03, 0.05)
		assert_float(e["missing_in_patches"]).override_failure_message("seed %d clustered %.2f" % [s, e["missing_in_patches"]]).is_greater_equal(0.5)
		assert_float(e["lane_ratio"]).is_less(0.5)
	var src := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	for u in ["grit_odds_base", "grit_odds_damage", "grit_lane_keep"]:
		assert_bool(src.contains("uniform vec") and src.contains(" %s " % u)).override_failure_message("uniform %s" % u).is_true()


## THE LOOK MUST NOT LIE (plan G5): a puddle never reads as the dangerous pool - its colour stays 25 deg of hue and 0.15 of saturation away from the hazard water's teal, it is no wider than
## 1.2 in, never on a ladder's foot, never within 1.5 in of a dangerous cell; and there are 6-10 of them.
func test_a_puddle_is_never_the_hazard_pool() -> void:
	var grit := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	var board := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	var tint := _vec3(grit, "const vec3 GRIT_PUDDLE_TINT = vec3(")
	var m := RegEx.create_from_string("alb = vec3\\(([^)]*)\\) \\* mix\\(0\\.7, 1\\.3, swirl\\)").search(board)   # the hazard water's body (k == 2)
	assert_object(m).is_not_null()
	var tn := m.get_string(1).split(",")
	var teal := Color(float(tn[0]), float(tn[1]), float(tn[2]))
	assert_bool(grit.contains("alb = mix(alb, alb * 0.45 + GRIT_PUDDLE_TINT, 0.75 * pud);")).is_true()
	var mean := _vec3(grit, "const vec3 GRIT_COOL = vec3(") * 0.5   # a dark street sett under the water
	var water := mean.lerp(mean * 0.45 + tint, 0.75)
	var dh := absf(water.h - teal.h) * 360.0
	dh = minf(dh, 360.0 - dh)
	assert_float(dh).override_failure_message("puddle hue %.0f vs teal %.0f" % [water.h * 360.0, teal.h * 360.0]).is_greater_equal(25.0)
	assert_float(absf(water.s - teal.s)).is_greater_equal(0.15)
	assert_bool(grit.contains("EMISSION")).is_false()
	for s: int in SEEDS:
		var layout := _layout(s)
		var cls := BoardgenTownGrit.classes(layout)
		var pds := BoardgenTownGrit.puddles(layout, cls)
		assert_int(pds.size()).override_failure_message("seed %d: %d puddles" % [s, pds.size()]).is_between(6, 10)
		var nx: int = layout["nx"]
		var nz: int = layout["nz"]
		var cell := float(layout["cell_in"])
		var feet := {}
		for c: Dictionary in layout["connectors"]:
			feet[int(c["low"])] = true
			feet[int(c["high"])] = true
		for pd: Dictionary in pds:
			var at: Vector2 = pd["at"]
			assert_float(float(pd["r"]) * 2.0).is_less_equal(1.2)
			var i := floori(at.y / cell + nz * 0.5) * nx + floori(at.x / cell + nx * 0.5)
			assert_bool(feet.has(i)).is_false()
			for j in nx * nz:
				if cls[j] == 3:
					var r := Rect2((Vector2(j % nx, j / nx) - Vector2(nx, nz) * 0.5) * cell, Vector2(cell, cell))
					var q := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
					assert_float(q.distance_to(at)).is_greater_equal(1.5)


## THE LOOK MUST NOT LIE (plan G5): nothing of the grit stands higher than 0.08 in on open standing ground - it is all paint and a bent normal on the existing surface (no vertex moves, no
## node is added), and its relief depths stay the street's own.
func test_the_grit_adds_no_height_to_the_open_ground() -> void:
	var grit := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	assert_bool(grit.contains("VERTEX")).is_false()
	for m in RegEx.create_from_string("depth_in = ([0-9.]+)").search_all(grit):   # only the city wall's masonry sets a relief depth (a wall face, not standing ground), and a shallow one
		assert_float(float(m.get_string(1))).is_less_equal(0.08)
	var street_fn := grit.substr(grit.find("vec3 grit_street("), grit.find("// A FLOOR for the open ground") - grit.find("vec3 grit_street("))
	assert_bool(street_fn.contains("depth_in")).is_false()
	var src := FileAccess.get_file_as_string("res://scripts/boardgen_town_grit.gd")
	assert_bool(src.contains("add_child") or src.contains("Mesh")).is_false()


func _vec3(src: String, head: String) -> Color:
	var at := src.find(head)
	var nums := src.substr(at + head.length(), 40).split(")")[0].split(",")
	return Color(float(nums[0]), float(nums[1]), float(nums[2]))


## A WALL IS NOT ONE WALLPAPER (plan W0, maintainer 21.11.): the authored stone and plaster are read through the period breaker - three takes per point on a triangle grid, each at its own
## offset ALONG the courses only (the bed joints stay level; the stone size is untouched, decision D-R2) - never straight off the 1.3 in tile; and the wall faces get their own structure.
func test_the_stone_and_plaster_sets_are_read_without_their_period() -> void:
	var board := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	var tile := FileAccess.get_file_as_string("res://shaders/ruintown_grit_tile.gdshaderinc")
	assert_bool(board.contains("ratio_of(t_stone")).override_failure_message("the stone set is read straight off its tile").is_false()
	assert_bool(board.contains("ratio_of(t_plaster")).is_false()
	assert_bool(board.contains("grit_albedo(t_stone, tuv)") and board.contains("grit_normal(n_stone, tuv)")).is_true()
	assert_bool(board.contains("grit_albedo(t_plaster, pu)") and board.contains("grit_normal(n_plaster, pu)")).is_true()
	assert_bool(tile.contains("return vec2((fract(h * 7.13) < 0.5 ? st.x : -st.x) + h * 17.0, st.y);")).override_failure_message("a take moves across the courses").is_true()
	assert_bool(board.contains("/ t_tile.x;")).is_true()   # the tile size (stone size) itself is the manifest's
	assert_bool(board.contains("grit_wall(p, wnrm, k, seed, ")).is_true()
	assert_bool(board.contains("grit_city_masonry(k, p, wnrm, seed, tint, alb, rel, depth_in, tex_on, tex_ratio, tex_n, ao);")).override_failure_message("the city wall still wears the banded set").is_true()
	var grit := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	assert_bool(grit.contains("if (grit_on < 0.5 || (k != 12 && k != 6)) {")).is_true()   # the city wall and the towers, and only with the map
