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


func test_a_half_turned_layout_gives_the_half_turned_map_for_wear_and_wet() -> void:
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
	assert_float(best).is_less(30.0)
