extends GdUnitTestSuite
## The grid helpers of the dressing's honesty rules (PLAN_RUINTOWN_DRESSING step 5a): what a cell's top is, where a model can stand, which cells stay clear, and the transform of a face module.
## The rules themselves (violations) follow in 5b and 5c with their planted-violation tests.

const SEEDS := [41, 25, 3]
const R := preload("res://scripts/boardgen_dress_rules.gd")


func _layout(seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")


func test_top_in_and_walkable_follow_the_grid() -> void:
	var seen := {}
	for s in SEEDS:
		var layout := _layout(s)
		for i in (layout["cells"] as Array).size():
			var c: Dictionary = layout["cells"][i]
			var x := i % int(layout["nx"])
			var z := floori(i / float(layout["nx"]))
			var want := 12.0 if c["lot_kind"] == "Tower" else 2.5 if c["lot_kind"] == "Roofed" else float(layout["level_in"][int(c["level"])])
			assert_float(R.top_in(layout, x, z)).is_equal(want)
			if c["lot_kind"] == "Roofed" or c["lot_kind"] == "Tower":
				assert_bool(R.walkable(layout, i)).is_false()
			seen[str(c["lot_kind"]) + str(int(c["level"]))] = true
		assert_float(R.top_in(layout, -1, 0)).is_equal(0.0)   # off the board
		assert_float(R.top_in(layout, 0, int(layout["nz"]))).is_equal(0.0)
		for lm: Dictionary in layout["landmarks"]:
			assert_bool(R.walkable(layout, int(lm["z"]) * int(layout["nx"]) + int(lm["x"]))).is_equal(not lm["solid"])
	assert_bool(seen.has("Roofed0") and seen.has("Tower0") and seen.has("Deck1") and seen.has("Block2") and seen.has("Wall0")).is_true()   # the loop saw every kind it claims to check


func test_a_solid_landmark_footprint_is_not_walkable_but_a_pool_is() -> void:
	var solid := 0
	var pools := 0
	for s in SEEDS:
		var layout := _layout(s)
		for lm: Dictionary in layout["landmarks"]:
			for dz in int(lm["h"]):
				for dx in int(lm["w"]):
					var i := (int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx
					assert_bool(R.walkable(layout, i)).is_equal(not lm["solid"])
			solid += 1 if lm["solid"] else 0
			pools += 1 if lm["kind"] == "Sump" else 0
	assert_bool(solid > 0 and pools > 0).is_true()   # both cases were exercised


func test_kept_clear_holds_both_ladder_cells_and_every_landmark_cell_and_no_street() -> void:
	var layout := _layout(41)
	var kept := R.kept_clear(layout)
	assert_int(layout["connectors"].size()).is_greater(10)
	for c: Dictionary in layout["connectors"]:
		assert_bool(kept.has(int(c["low"])) and kept.has(int(c["high"]))).is_true()
	var n := 0
	for lm: Dictionary in layout["landmarks"]:
		for dz in int(lm["h"]):
			for dx in int(lm["w"]):
				assert_bool(kept.has((int(lm["z"]) + dz) * int(layout["nx"]) + int(lm["x"]) + dx)).is_true()
				n += 1
	assert_int(n).is_greater(0)
	assert_bool(kept.size() < (layout["cells"] as Array).size()).is_true()   # not the whole board
	assert_bool(kept.get(int(layout["connectors"][0]["low"])) == "ladder").is_true()


func test_face_xf_puts_x_along_z_out_and_the_inset_into_the_mass() -> void:
	var xf := R.face_xf(Vector3(4, 0, -6), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.1, 0.0)   # the N face of a cell whose corner is (4, -6)
	assert_vector(xf.basis.x).is_equal_approx(Vector3(-1, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(xf.basis.z).is_equal_approx(Vector3(0, 0, -1), Vector3(0.0001, 0.0001, 0.0001))
	var p := xf * (Vector3(1.0, 2.0, 0.5) * R.IN_M) / R.IN_M   # 1 along, 2 up, 0.5 out of the mounting plane
	assert_vector(p).is_equal_approx(Vector3(3, 2, -6.4), Vector3(0.001, 0.001, 0.001))   # 0.5 out minus the 0.1 inset
	var leaned := R.face_xf(Vector3(4, 0, -6), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.0, 10.0)
	var top := leaned * (Vector3(0, 1, 0) * R.IN_M) / R.IN_M
	assert_float(top.z).is_equal_approx(-6.0 - sin(deg_to_rad(10.0)), 0.001)   # a positive lean tips the top OUT
	assert_float(top.y).is_equal_approx(cos(deg_to_rad(10.0)), 0.001)
	var inward := R.face_xf(Vector3(4, 0, -6), Vector3(-1, 0, 0), Vector3(0, 0, -1), 0.0, -10.0)
	assert_float((inward * (Vector3(0, 1, 0) * R.IN_M) / R.IN_M).z).is_equal_approx(-6.0 + sin(deg_to_rad(10.0)), 0.001)   # a negative lean tips it in


func test_the_constants_are_the_plans_numbers() -> void:
	assert_array([R.FLAT, R.CLEAR, R.OVERHANG, R.REACH, R.EDGE, R.PARAPET, R.LADDER_GAP, R.LEAN_MAX]).is_equal([0.08, 2.0, 0.35, 0.2, 0.4, 0.7, 0.9, 1.5])
