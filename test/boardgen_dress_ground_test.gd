extends GdUnitTestSuite
## The ground data of the ruin-town dressing (PLAN_RUINTOWN_DRESSING step 25): the class / height map `tops` (exact, R8), the weight map `mask` and the seeded street puddles.
## The test recomputes every cell's class from the layout fields itself, so a swapped class number in `tops` shows red.

const SEEDS := [41, 25]


func _layout(seed: int) -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore")
	return core.boardgen_layout_themed(seed, "ruintown")


func _feet(layout: Dictionary) -> Dictionary:
	var out := {}
	for conn: Dictionary in layout["connectors"]:
		out[int(conn["low_xz"][1]) * int(layout["nx"]) + int(conn["low_xz"][0])] = true
	return out


func _water(layout: Dictionary) -> Dictionary:
	var out := {}
	var nx: int = layout["nx"]
	for i in layout["cells"].size():
		var c: Dictionary = layout["cells"][i]
		if String(c["lot_kind"]) == "Hazard" and int(c["level"]) == 0:
			out[i] = true
	for lm: Dictionary in layout.get("landmarks", []):
		if String(lm["kind"]) != "Sump":
			continue
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				out[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	return out


func _solid(layout: Dictionary) -> Dictionary:
	var out := {}
	var nx: int = layout["nx"]
	for lm: Dictionary in layout.get("landmarks", []):
		if not lm.get("solid", false):
			continue
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				out[(int(lm["z"]) + dz) * nx + int(lm["x"]) + dx] = true
	return out


## The class table of "GROUND AND TOPS", first match wins, recomputed here from the layout fields (not from the script under test).
func _class(layout: Dictionary, i: int, water: Dictionary, solid: Dictionary) -> int:
	var c: Dictionary = layout["cells"][i]
	var kind := String(c["lot_kind"])
	var lvl := int(c["level"])
	if kind == "Roofed" or kind == "Tower":
		return 255
	if water.has(i) and lvl == 0:
		return 8
	if kind == "Wall":
		return 6 if lvl == 0 else 5
	if lvl >= 1:
		return 4 if kind == "Deck" else 3
	if kind == "Rough":
		return 7
	if kind == "Terrace" and not c["street"]:
		return 2
	if solid.has(i):
		return 2
	if c["street"]:
		return 1
	return 0


func _g(layout: Dictionary, c: Dictionary) -> int:
	var kind := String(c["lot_kind"])
	if kind == "Tower":
		return roundi(float(layout.get("tower_in", 12.0)) * 20.0)
	if kind == "Roofed":
		return roundi(2.5 * 20.0)
	return roundi(float(layout["level_in"][int(c["level"])]) * 20.0)


func _rect(layout: Dictionary, i: int) -> Rect2:
	var nx: int = layout["nx"]
	var cell := float(layout["cell_in"])
	var half := Vector2(layout["nx"], layout["nz"]) * cell * 0.5
	return Rect2((Vector2(i % nx, i / nx) - half) * cell, Vector2(cell, cell))


func _rect_dist(p: Vector2, r: Rect2) -> float:
	return p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y)))


func _cell_of(layout: Dictionary, p: Vector2) -> int:
	var cell := float(layout["cell_in"])
	var x := floori(p.x / cell + float(layout["nx"]) * 0.5)
	var z := floori(p.y / cell + float(layout["nz"]) * 0.5)
	return z * int(layout["nx"]) + x


func test_every_cell_class_and_height_matches_the_table_on_seeds_41_and_25() -> void:
	for seed: int in SEEDS:
		var layout := _layout(seed)
		var img := BoardgenDressGround.tops(layout)
		assert_int(img.get_width()).is_equal(int(layout["nx"]))
		assert_int(img.get_height()).is_equal(int(layout["nz"]))
		var water := _water(layout)
		var solid := _solid(layout)
		var classes := {}
		for i in layout["cells"].size():
			var x: int = i % int(layout["nx"])
			var z: int = i / int(layout["nx"])
			var col := img.get_pixel(x, z)
			var want := _class(layout, i, water, solid)
			assert_int(roundi(col.r * 255.0)).is_equal(want)
			assert_int(roundi(col.g * 255.0)).is_equal(_g(layout, layout["cells"][i]))
			assert_int(roundi(col.b * 255.0)).is_equal(BoardgenDressStory.pick(int(layout["cells"][i]["lot_id"]), 0, 256))
			classes[want] = true
		assert_int(classes.size()).is_greater_equal(4)   # the check is not empty: every seed shows at least four top classes


func test_ladder_feet_are_alpha_255_and_every_other_cell_is_0() -> void:
	var seen := 0
	for seed: int in SEEDS:
		var layout := _layout(seed)
		var feet := _feet(layout)
		var img := BoardgenDressGround.tops(layout)
		for i in layout["cells"].size():
			var a := roundi(img.get_pixel(i % int(layout["nx"]), i / int(layout["nx"])).a * 255.0)
			assert_int(a).is_equal(255 if feet.has(i) else 0)
		seen += feet.size()
	assert_int(seen).is_greater(0)   # without a ladder foot the alpha check would pass with zero rows


func test_tops_keeps_exact_class_borders() -> void:
	for seed: int in SEEDS:
		var layout := _layout(seed)
		var img := BoardgenDressGround.tops(layout)
		var water := _water(layout)
		var solid := _solid(layout)
		var nx: int = layout["nx"]
		for i in layout["cells"].size():
			var r := roundi(img.get_pixel(i % nx, i / nx).r * 255.0)
			assert_int(r).is_equal(_class(layout, i, water, solid))
			if i % nx + 1 < nx:   # a class change between neighbours is two exact values, never a blend
				var right := roundi(img.get_pixel(i % nx + 1, i / nx).r * 255.0)
				assert_int(right).is_equal(_class(layout, i + 1, water, solid))


func test_puddles_are_seeded_off_water_and_off_ladder_feet() -> void:
	for seed: int in SEEDS:
		var layout := _layout(seed)
		var ps := BoardgenDressGround.puddles(layout)
		assert_int(ps.size()).is_between(6, 10)
		assert_that(ps).is_equal(BoardgenDressGround.puddles(layout))
		var feet := _feet(layout)
		var water := _water(layout)
		assert_int(water.size()).is_greater(0)   # otherwise the distance check below is vacuous
		for p: Dictionary in ps:
			var centre: Vector2 = p["centre"]
			assert_float(float(p["radius"])).is_greater(0.0)
			assert_bool(feet.has(_cell_of(layout, centre))).is_false()
			for i: int in water:
				assert_float(_rect_dist(centre, _rect(layout, i))).is_greater_equal(1.5 - 0.001)


func test_mask_is_384_square_deterministic_and_paints_in_under_50_ms() -> void:
	for seed: int in SEEDS:
		var layout := _layout(seed)
		var t0 := Time.get_ticks_usec()
		var m := BoardgenDressGround.mask(layout)
		var dt := Time.get_ticks_usec() - t0
		print("DRESS_GROUND mask seed %d: %d us" % [seed, dt])
		assert_int(m.get_width()).is_equal(384)
		assert_int(m.get_height()).is_equal(384)
		assert_int(dt).is_less(50000)
		assert_that(m.get_data()).is_equal(BoardgenDressGround.mask(layout).get_data())
		var painted := false
		for y in range(0, 384, 16):
			for x in range(0, 384, 16):
				var c := m.get_pixel(x, y)
				painted = painted or c.r > 0.0 or c.g > 0.0 or c.b > 0.0 or c.a > 0.0
		assert_bool(painted).is_true()


func test_tops_is_deterministic() -> void:
	for seed: int in SEEDS:
		var layout := _layout(seed)
		assert_that(BoardgenDressGround.tops(layout).get_data()).is_equal(BoardgenDressGround.tops(layout).get_data())
