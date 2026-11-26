extends GdUnitTestSuite
## The green map of the ruin town (LOOK4 G2): where the cover grows, baked once from the layout. Half-turn symmetric, nothing on a street, a pool or a kept-clear cell,
## and a rough, not a carpet, on the open earth.


func _layout(s: int) -> Dictionary:
	return ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")


func _cell_of(layout: Dictionary, tx: int, tz: int) -> int:
	var cell := float(layout["cell_in"])
	var per_cell := cell * BoardgenTownGreen.TEXELS_PER_IN
	return int(floor(tz / per_cell)) * int(layout["nx"]) + int(floor(tx / per_cell))


func test_the_map_is_half_turn_symmetric_and_four_texels_per_inch() -> void:
	for s in [41, 25, 7]:
		var layout := _layout(s)
		var img := BoardgenTownGreen.map(layout)
		assert_int(img.get_width()).is_equal(int(layout["nx"]) * int(layout["cell_in"]) * 4)
		assert_int(img.get_format()).is_equal(Image.FORMAT_RGB8)   # (LOOK5 S3 / S5) R cover, G wear, B verge
		var w := img.get_width()
		var h := img.get_height()
		var off := 0
		for tz in h:
			for tx in w:
				off += int(absf(img.get_pixel(tx, tz).r - img.get_pixel(w - 1 - tx, h - 1 - tz).r) > 0.003)
		assert_int(off).override_failure_message("seed %d: %d texels differ from their half-turn twin" % [s, off]).is_equal(0)


func test_nothing_grows_on_a_street_a_pool_or_a_kept_clear_cell() -> void:
	for s in [41, 25, 3]:
		var layout := _layout(s)
		var img := BoardgenTownGreen.map(layout)
		var clear := BoardgenDressRules.kept_clear(layout)
		var grown := 0
		for tz in img.get_height():
			for tx in img.get_width():
				var i := _cell_of(layout, tx, tz)
				var kind := BoardgenGreybox._cell_kind(layout["cells"][i], true)
				var v := img.get_pixel(tx, tz).r
				grown += int(v > 0.0)
				if kind in ["street", "hazard"] or clear.has(i):
					assert_float(v).override_failure_message("seed %d: cover %.2f on a %s texel (%d, %d)" % [s, v, "kept-clear" if clear.has(i) else kind, tx, tz]).is_equal(0.0)
		assert_int(grown).is_greater(0)


func test_the_open_earth_is_rough_not_a_carpet() -> void:
	var total := 0.0
	var n := 0
	for s in range(1, 21):
		var layout := _layout(s)
		var img := BoardgenTownGreen.map(layout)
		for tz in img.get_height():
			for tx in img.get_width():
				if BoardgenGreybox._cell_kind(layout["cells"][_cell_of(layout, tx, tz)], true) == "ground":
					total += img.get_pixel(tx, tz).r
					n += 1
	var mean := total / n
	print("GREEN mean cover on earth %.3f over %d texels" % [mean, n])
	assert_float(mean).is_between(0.35, 0.6)


## LOOK5 S3: G is the WEAR where feet went - half-turn symmetric, 0 off the open earth, a worn lane on every board with a backyard house, and the cover gives way
## to it (R + G <= 1).
func test_the_wear_channel_is_symmetric_on_earth_only_and_the_cover_gives_way() -> void:
	var boards := 0
	for s in range(1, 21):
		var layout := _layout(s)
		var img := BoardgenTownGreen.map(layout)
		var w := img.get_width()
		var h := img.get_height()
		var best := 0.0
		for tz in h:
			for tx in w:
				var c := img.get_pixel(tx, tz)
				var kind := BoardgenGreybox._cell_kind(layout["cells"][_cell_of(layout, tx, tz)], true)
				assert_float(absf(c.g - img.get_pixel(w - 1 - tx, h - 1 - tz).g)).override_failure_message("seed %d: wear not symmetric at (%d, %d)" % [s, tx, tz]).is_less(0.003)
				if kind not in ["ground", "rough"]:
					assert_float(c.g).override_failure_message("seed %d: wear %.2f on a %s texel" % [s, c.g, kind]).is_equal(0.0)
				assert_float(c.r + c.g).is_less_equal(1.0 + 1.0 / 255.0)
				best = maxf(best, c.g)
		if BoardgenTownDressing.frontage(layout).any(func(f: Dictionary) -> bool: return f["front"] == ""):
			boards += 1
			assert_float(best).override_failure_message("seed %d: a backyard house and no worn lane" % s).is_greater(0.5)
	assert_int(boards).is_greater(0)


## LOOK5 S5: B is the VERGE - half-turn symmetric, high on an earth texel beside a street (the nearest texel centre is 0.125 in off the cell edge: 1 - 0.125 / 0.5),
## 0 from 0.5 in on and on every texel that is not open earth.
func test_the_verge_channel_is_symmetric_and_lies_only_at_a_streets_edge() -> void:
	var near_street := 0
	for s in range(1, 21):
		var layout := _layout(s)
		var img := BoardgenTownGreen.map(layout)
		var w := img.get_width()
		var h := img.get_height()
		var per := int(float(layout["cell_in"]) * BoardgenTownGreen.TEXELS_PER_IN)
		for tz in h:
			for tx in w:
				var b := img.get_pixel(tx, tz).b
				assert_float(absf(b - img.get_pixel(w - 1 - tx, h - 1 - tz).b)).is_less(0.003)
				var i := _cell_of(layout, tx, tz)
				var kind := BoardgenGreybox._cell_kind(layout["cells"][i], true)
				if kind not in ["ground", "rough"]:
					assert_float(b).override_failure_message("seed %d: verge %.2f on a %s texel" % [s, b, kind]).is_equal(0.0)
					continue
				var inner := mini(mini(tx % per, per - 1 - tx % per), mini(tz % per, per - 1 - tz % per))   # texels to the cell's nearest edge
				if inner >= 2:
					assert_float(b).override_failure_message("seed %d: verge %.2f at >= 0.5 in from a cell edge" % [s, b]).is_equal(0.0)
				elif b >= 0.7:
					near_street += 1
	assert_int(near_street).is_greater(100)
