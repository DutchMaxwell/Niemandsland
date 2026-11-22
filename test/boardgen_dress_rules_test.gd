extends GdUnitTestSuite
## The honesty rules of the dressing (PLAN_RUINTOWN_DRESSING step 5): the grid helpers (5a) and, from 5b, R1 / R2 / R4 on placements: a hand-made CLEAN set (house panels, tier faces, parapets, ladders, litter, a lamp post,
## junk on terrain) on real town boards reports nothing; each planted break is reported. The numbers of the modules are the nominal K0 manifest numbers (inches); R3 and R5 follow in step 5c.

const SEEDS := [41, 25, 3]
const R := preload("res://scripts/boardgen_dress_rules.gd")


func _layout(seed: int) -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, "ruintown")


func _mod(family: String, role: String, len_in: float, lo: Array, hi: Array, proud: Array, tags: Array) -> Dictionary:
	return {"family": family, "role": role, "len_in": len_in, "aabb_in": [lo, hi], "proud_in": {"flat": proud[0], "low": proud[1], "high": proud[2]}, "tags": tags}


func _meta() -> Dictionary:
	return {"modules": {
		"dr_house_tb_plain_a": _mod("house_panel", "plain_a", 3.0, [0, 0, -0.3], [3, 2.5, 0.22], [0.22, 0.12, 0.08], ["single_band"]),
		"dr_ruin_face_foot_a": _mod("ruin_face", "foot", 3.0, [0, 0, -0.4], [3, 3, 0.12], [0.12, 0.08, 0.08], ["foot"]),
		"dr_ruin_face_plain_a": _mod("ruin_face", "plain", 3.0, [0, 0, -0.4], [3, 3, 0.08], [0.0, 0.08, 0.08], ["upper_band"]),
		"dr_ruin_face_window": _mod("ruin_face", "window", 3.0, [0, 0, -0.4], [3, 3, 0.08], [0.0, 0.08, 0.08], ["upper_band"]),
		"dr_parapet_stub_a": _mod("parapet", "parapet", 3.0, [0, 0, -0.4], [3, 0.7, 0], [0.0, 0.0, 0.0], ["top_edge", "R4_strip"]),
		"dr_ladder_3in": _mod("ladder", "ladder", 1.0, [-0.5, 0, 0], [0.5, 3, 0.3], [0.3, 0.3, 0.3], ["ladder", "R1_exception"]),
		"dr_ladder_top": _mod("ladder", "ladder_top", 1.0, [-0.5, 0, -0.3], [0.5, 3.5, 0.3], [0.3, 0.3, 0.3], ["ladder", "R1_exception"]),
		"dr_junk_barrels": _mod("junk", "junk", 1.4, [-0.7, 0, -0.7], [0.7, 0.7, 0.7], [0.0, 0.0, 0.0], ["bulky", "terrain_or_solid_only"]),
		"dr_litter_straw": _mod("litter", "litter", 2.0, [-1, 0, -1], [1, 0.03, 1], [0.0, 0.0, 0.0], ["flat"]),
		"dr_lamp_post": _mod("prop", "lamp", 0.2, [-0.1, 0, -0.1], [0.1, 2.9, 0.1], [0.1, 0.1, 0.1], ["cell_corner", "R1_exception"]),
		"dr_gable_tb_s3": _mod("gable", "gable", 3.0, [-0.15, -0.12, -0.3], [3.15, 2.0, 0.32], [0.0, 0.0, 0.32], ["span_3"]),
		"dr_ruin_gable_s3": _mod("ruin_gable", "gable", 3.0, [0, 0, -0.3], [3, 2.6, 0], [0.0, 0.0, 0.0], ["end_face", "R4_gable"])}}


## The transform of face `k` (N E S W) of cell (cx, cz) with its origin at height `y`.
func _face(layout: Dictionary, cx: int, cz: int, k: int, y: float, inset: float, lean := 0.0) -> Transform3D:
	var c := float(layout["cell_in"])
	var x0 := (cx - int(layout["nx"]) * 0.5) * c
	var z0 := (cz - int(layout["nz"]) * 0.5) * c
	var start := [Vector3(x0 + c, y, z0), Vector3(x0 + c, y, z0 + c), Vector3(x0, y, z0 + c), Vector3(x0, y, z0)]
	var along := [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1)]
	var out := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	return R.face_xf(start[k], along[k], out[k], inset, lean)


func _centre(layout: Dictionary, cx: int, cz: int, y: float) -> Transform3D:
	var c := float(layout["cell_in"])
	return Transform3D(Basis(), Vector3((cx + 0.5 - int(layout["nx"]) * 0.5) * c, y, (cz + 0.5 - int(layout["nz"]) * 0.5) * c) * R.IN_M)


func _p(module: String, xf: Transform3D, cls := "test") -> Dictionary:
	return {"module": module, "xf": xf, "cls": cls}


## Cells of the board as [cx, cz, i].
func _cells(layout: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in (layout["cells"] as Array).size():
		out.append(Vector3i(i % int(layout["nx"]), floori(i / float(layout["nx"])), i))
	return out


func _in_board(layout: Dictionary, x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < int(layout["nx"]) and z < int(layout["nz"])


## A clean dressing: house panels on the open faces of the roofed houses, tier faces band by band (foot, then plain) with the inset the module's proud number asks for, parapet stubs in the edge strip of the
## other dropping edges, the kit ladders, straw on street cells, a lamp post at one cell corner, junk on terrain cells. Nothing near a ladder but ladders and plain faces.
func _clean(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kept := R.kept_clear(layout)
	var nx := int(layout["nx"])
	for cv in _cells(layout):
		var c: Dictionary = layout["cells"][cv.z]
		var top := R.top_in(layout, cv.x, cv.y)
		for k in 4:
			var nb: Vector2i = Vector2i(cv.x, cv.y) + R.DIRS[k]
			var nt := R.top_in(layout, nb.x, nb.y)
			var open := _in_board(layout, nb.x, nb.y) and R.walkable(layout, nb.y * nx + nb.x)
			if c["lot_kind"] == "Roofed" and open and nt <= 0.0:
				out.append(_p("dr_house_tb_plain_a", _face(layout, cv.x, cv.y, k, 0.0, 0.12), "houses"))
			elif R.walkable(layout, cv.z) and int(c["level"]) >= 1 and open and nt <= top - 3.0:
				for b in int((top - nt) / 3.0):
					out.append(_p("dr_ruin_face_foot_a" if b == 0 else "dr_ruin_face_plain_a", _face(layout, cv.x, cv.y, k, nt + 3.0 * b, 0.12), "tiers"))
			if R.walkable(layout, cv.z) and int(c["level"]) >= 1 and nt < top and not kept.has(cv.z):
				out.append(_p("dr_parapet_stub_a", _face(layout, cv.x, cv.y, k, top, 0.0), "tiers"))
		if R.walkable(layout, cv.z) and int(c["level"]) == 0 and not kept.has(cv.z):
			if c["street"]:
				out.append(_p("dr_litter_straw", _centre(layout, cv.x, cv.y, 0.04), "clutter"))
			elif c["lot_kind"] == "Rough":
				out.append(_p("dr_junk_barrels", _centre(layout, cv.x, cv.y, 0.0), "clutter"))
	var st := _street(layout)
	var corner := (_centre(layout, st.x, st.y, 0.0).origin / R.IN_M) - Vector3(float(layout["cell_in"]) * 0.5, 0.0, float(layout["cell_in"]) * 0.5)
	out.append(_p("dr_lamp_post", Transform3D(Basis(), corner * R.IN_M), "props"))   # a lamp post at a cell corner: the one R1 exception
	var plan := BoardgenGreybox.ladder_kit_plan(layout)
	for name: String in plan:
		for item: Dictionary in plan[name]:
			out.append(_p("dr_" + name, item["xf"], "ladders"))
	return out


## The first cell that is a street cell on the ground, walkable and not kept clear.
func _street(layout: Dictionary) -> Vector3i:
	var kept := R.kept_clear(layout)
	for cv in _cells(layout):
		if layout["cells"][cv.z]["street"] and int(layout["cells"][cv.z]["level"]) == 0 and not kept.has(cv.z):
			return cv
	return Vector3i(-1, -1, -1)


## [cell, k, neighbour top] of the first walkable tier cell (not a ladder cell) with a drop of 3 in or more to a walkable cell.
func _tier_edge(layout: Dictionary) -> Array:
	var kept := R.kept_clear(layout)
	for cv in _cells(layout):
		var top := R.top_in(layout, cv.x, cv.y)
		if not R.walkable(layout, cv.z) or int(layout["cells"][cv.z]["level"]) < 1 or kept.has(cv.z):
			continue
		for k in 4:
			var nb: Vector2i = Vector2i(cv.x, cv.y) + R.DIRS[k]
			if _in_board(layout, nb.x, nb.y) and R.walkable(layout, nb.y * int(layout["nx"]) + nb.x) and R.top_in(layout, nb.x, nb.y) <= top - 3.0:
				return [cv, k, R.top_in(layout, nb.x, nb.y)]
	return []


## [cell, k] of the first roofed house cell with an open ground cell beside it and nothing taller than the house along that face and across it (a gable's 0.15 in jetty spill then lands over open ground or the house).
func _house_edge(layout: Dictionary) -> Array:
	for cv in _cells(layout):
		if layout["cells"][cv.z]["lot_kind"] != "Roofed":
			continue
		for k in 4:
			var nb: Vector2i = Vector2i(cv.x, cv.y) + R.DIRS[k]
			var along: Vector2i = R.DIRS[(k + 1) % 4]
			var low := true
			for t in range(-1, 2):
				low = low and R.top_in(layout, cv.x + along.x * t, cv.y + along.y * t) <= BoardgenGreybox.SOLID_IN and R.top_in(layout, nb.x + along.x * t, nb.y + along.y * t) <= BoardgenGreybox.SOLID_IN
			if low and _in_board(layout, nb.x, nb.y) and R.walkable(layout, nb.y * int(layout["nx"]) + nb.x) and R.top_in(layout, nb.x, nb.y) <= 0.0:
				return [cv, k]
	return []


func _rules(lines: PackedStringArray) -> Array:
	var out := []
	for l in lines:
		if not out.has(l.substr(0, 2)):
			out.append(l.substr(0, 2))
	return out


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


func test_the_clean_dressing_reports_nothing_on_real_boards() -> void:
	for s in SEEDS:
		var layout := _layout(s)
		var clean := _clean(layout)
		print("DRESS_RULES seed %d: %d clean placements" % [s, clean.size()])
		assert_int(clean.size()).is_greater(100)
		assert_array(R.violations(layout, clean, _meta())).is_empty()


func test_a_panel_0_3_in_outside_its_cell_is_reported() -> void:
	var layout := _layout(41)
	var e := _tier_edge(layout)
	assert_array(e).is_not_empty()
	if e.is_empty():
		return
	var cv: Vector3i = e[0]
	var bad := _p("dr_ruin_face_foot_a", _face(layout, cv.x, cv.y, e[1], e[2], -0.3), "tiers")
	var alone := R.violations(layout, [bad], _meta())
	assert_array(_rules(alone)).contains_exactly(["R1"])   # it stands in the walkable cell (R3, the face outside the collider, joins in step 5c)
	var board: Array = _clean(layout)
	board.append(bad)
	assert_int(R.violations(layout, board, _meta()).size()).is_equal(alone.size())   # and a full board shows exactly that
	var control := _p("dr_ruin_face_foot_a", _face(layout, cv.x, cv.y, e[1], e[2], 0.12), "tiers")
	assert_array(R.violations(layout, [control], _meta())).is_empty()


func test_a_bulky_module_on_a_street_cell_is_reported_but_not_on_terrain() -> void:
	var layout := _layout(41)
	var st := _street(layout)
	var bad := _p("dr_junk_barrels", _centre(layout, st.x, st.y, 0.0), "clutter")
	assert_array(_rules(R.violations(layout, [bad], _meta()))).contains_exactly(["R1"])
	var plot := Vector3i(-1, -1, -1)
	for cv in _cells(layout):
		if layout["cells"][cv.z]["lot_kind"] == "Rough":
			plot = cv
			break
	assert_int(plot.x).is_greater(-1)   # the board has a garden plot to stand it on
	assert_array(R.violations(layout, [_p("dr_junk_barrels", _centre(layout, plot.x, plot.y, 0.0), "clutter")], _meta())).is_empty()


func test_a_parapet_1_in_high_is_reported_and_a_0_7_in_one_is_not() -> void:
	var layout := _layout(41)
	var e := _tier_edge(layout)
	assert_array(e).is_not_empty()
	if e.is_empty():
		return
	var cv: Vector3i = e[0]
	var top := R.top_in(layout, cv.x, cv.y)
	var xf := _face(layout, cv.x, cv.y, e[1], top, 0.0)
	assert_array(R.violations(layout, [_p("dr_parapet_stub_a", xf, "tiers")], _meta())).is_empty()
	var tall := Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, 1.0 / 0.7, 1.0)), xf.origin)
	assert_array(_rules(R.violations(layout, [_p("dr_parapet_stub_a", tall, "tiers")], _meta()))).contains_exactly(["R4"])
	var inward := _face(layout, cv.x, cv.y, e[1], top, -0.0)
	inward.origin -= xf.basis.z * 0.5 * R.IN_M   # 0.5 in in from the edge: outside the 0.4 in strip
	assert_array(_rules(R.violations(layout, [_p("dr_parapet_stub_a", inward, "tiers")], _meta()))).contains_exactly(["R4"])


func test_an_overhang_of_0_5_in_at_2_5_in_is_reported_and_0_32_in_is_not() -> void:
	var layout := _layout(41)
	var e := _house_edge(layout)
	assert_array(e).is_not_empty()   # the board has a house with open ground beside it
	if e.is_empty():
		return
	var cv: Vector3i = e[0]
	assert_array(R.violations(layout, [_p("dr_gable_tb_s3", _face(layout, cv.x, cv.y, e[1], 2.5, 0.0), "houses")], _meta())).is_empty()   # a 0.32 in jetty
	var deep := _p("dr_gable_tb_s3", _face(layout, cv.x, cv.y, e[1], 2.5, -0.18), "houses")   # 0.18 further out: 0.5 in
	assert_array(_rules(R.violations(layout, [deep], _meta()))).contains_exactly(["R2"])


func test_a_ruin_gable_over_0_3_in_thick_is_reported_and_an_unknown_module_too() -> void:
	var layout := _layout(41)
	var e := _tier_edge(layout)
	assert_array(e).is_not_empty()
	if e.is_empty():
		return
	var cv: Vector3i = e[0]
	var top := R.top_in(layout, cv.x, cv.y)
	var xf := _face(layout, cv.x, cv.y, e[1], top, 0.0)
	assert_array(R.violations(layout, [_p("dr_ruin_gable_s3", xf, "tiers")], _meta())).is_empty()
	var thick := Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, 1.0, 2.0)), xf.origin)   # 0.6 in thick
	assert_array(_rules(R.violations(layout, [_p("dr_ruin_gable_s3", thick, "tiers")], _meta()))).contains_exactly(["R4"])
	assert_array(_rules(R.violations(layout, [_p("dr_nope", xf)], _meta()))).contains_exactly(["R0"])

