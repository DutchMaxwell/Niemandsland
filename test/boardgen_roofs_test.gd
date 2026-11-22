extends GdUnitTestSuite
## The roof grammar of the intact houses (plan O4): one main roof per intact lot, an annex only on a lot of two or more cells, the ridge parallels or points at the street,
## a catslide only on an eaves-on roof with its back away from the street, several kinds of roof on a board, and the three meshes are closed outward-facing shapes.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## A street along x on row 7 with intact houses along it on both sides (so each has a front): 12 lots of 2 x 2 / 1 x 2 / 3 x 2 cells.
func _street_of_houses() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["lots"] = []
	for c: Dictionary in layout["cells"]:
		c["street"] = c["z"] == 7
		c["lot_id"] = 0
		c["lot_kind"] = "Street"
		c["level"] = 0
	var id := 0
	for side in [[5, 2], [8, 1]]:   # north side: rows 5-6 (front S); south side: rows 8-9 (front N)
		var x := 0
		while x < 15:
			var w: int = [1, 1, 2, 1, 3, 2, 1][id % 7]
			if x + w > 16:
				break
			id += 1
			var z: int = side[0]
			layout["lots"].append({"id": id, "x": x, "z": z, "w": w, "h": 2, "sector": [0, 0], "kind": "Roofed"})
			for dz in 2:
				for dx in w:
					var c: Dictionary = layout["cells"][(z + dz) * 16 + x + dx]
					c["lot_id"] = id
					c["lot_kind"] = "Roofed"
			x += w + 1
	return layout


func test_one_main_roof_per_intact_lot_and_an_annex_only_on_a_lot_of_two_or_more_cells() -> void:
	var layout := _street_of_houses()
	var roofs := BoardgenTownDressing.roofs(layout)
	var mains := roofs.filter(func(r: Dictionary) -> bool: return not r["annex"])
	assert_int(mains.size()).is_equal(layout["lots"].size())
	var annexes := 0
	for r: Dictionary in roofs.filter(func(r: Dictionary) -> bool: return r["annex"]):
		annexes += 1
		var lot: Dictionary = layout["lots"][int(r["lot"]) - 1]
		assert_int(lot["w"] if r["along_x"] else lot["h"]).is_greater_equal(2)   # two cells along the ridge at least
		assert_float(r["height"]).is_less(mains.filter(func(m: Dictionary) -> bool: return m["lot"] == r["lot"]).front()["height"])   # lower than its main roof
	assert_int(annexes).is_greater(0)


func test_a_board_has_several_kinds_of_roof_and_a_catslide_hangs_towards_the_back() -> void:
	var layout := _street_of_houses()
	var types := {}
	var rooflines := {}
	for r: Dictionary in BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"]):
		types[r["type"]] = true
		rooflines["%s/%s/%.1f" % [r["type"], r["along_x"], r["height"]]] = true
		if r["type"] == "catslide":
			assert_bool(r["along_x"]).is_true()   # eaves-on along this street
			var lot: Dictionary = layout["lots"][int(r["lot"]) - 1]
			assert_int(r["back"]).is_equal(-1 if lot["z"] < 7 else 1)   # the north side's back is the north (-z), the south side's the south (+z) ... away from the street
	assert_int(types.size()).is_greater_equal(2)
	assert_int(rooflines.size()).is_greater_equal(4)


func test_the_ridge_follows_the_street_for_most_houses() -> void:
	var layout := _street_of_houses()
	var eaves_on := 0
	var mains := BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"])
	for r: Dictionary in mains:
		eaves_on += int(r["along_x"])   # the street runs along x
	assert_int(eaves_on).is_greater(mains.size() / 2)   # a planted "ridge always across the street" fails here
	assert_int(eaves_on).is_less(mains.size())   # and some roofs are gable-on


func test_the_hip_and_catslide_meshes_have_outward_normals_and_close_over_the_eaves() -> void:
	for mesh: ArrayMesh in [BoardgenTownDressing.hip_mesh(), BoardgenTownDressing.catslide_mesh()]:
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		assert_int(verts.size() % 3).is_equal(0)
		for t in verts.size() / 3:
			var centroid := (verts[3 * t] + verts[3 * t + 1] + verts[3 * t + 2]) / 3.0
			assert_float(normals[3 * t].dot(centroid - Vector3(0, 0.3, 0))).is_greater(0.0)   # facing out
			# winding agrees with the normal: clockwise seen from outside means the geometric normal of (a, b, c) points INTO the shape
			var geo := (verts[3 * t + 1] - verts[3 * t]).cross(verts[3 * t + 2] - verts[3 * t])
			assert_float(geo.dot(normals[3 * t])).is_less(0.0)


## Jetties (plan O5): an intact house with a street at its door may carry an upper storey that overhangs the ground storey on the front face by 0.15-0.2 in - a recess inside its own cells.
func test_a_jetty_is_a_recess_of_at_most_a_fifth_of_an_inch_on_the_front_face_only() -> void:
	var layout := _street_of_houses()
	var jetties := 0
	for b in BoardgenTownDressing.house_bodies(layout):
		var parts := BoardgenTownDressing.house_parts(b)
		if b["jetty"] <= 0.0:
			assert_int(parts.size()).is_equal(1)
			continue
		jetties += 1
		assert_int(parts.size()).is_equal(2)
		assert_float(b["jetty"]).is_between(0.15, 0.2)
		assert_float(b["storey"]).is_between(1.5, 1.9)
		var lower: Dictionary = parts[0]
		var upper: Dictionary = parts[1]
		var shrink: Vector2 = (upper["size"] as Vector2) - (lower["size"] as Vector2)
		assert_float(shrink.x + shrink.y).is_equal_approx(b["jetty"], 0.0001)   # the ground storey is shorter by the jetty along ONE axis ...
		assert_bool(is_zero_approx(shrink.x) or is_zero_approx(shrink.y)).is_true()   # ... and only on the front side
		assert_float(lower["y1"]).is_equal(upper["y0"])
		assert_float(upper["y1"]).is_equal(b["top"])
		assert_str(b["front"]).is_not_empty()
	assert_int(jetties).is_greater(0)
	var fronts := {}
	for b in BoardgenTownDressing.house_bodies(layout):
		fronts[b["front"]] = true
	assert_bool(fronts.has("N") and fronts.has("S")).is_true()   # the houses on both sides of the street face it


## Roofs lane 22.11. (lead, K4 sheets: the tile roofs were the hottest thing on the board): every roof tone the town shader picks is a weathered slate / shingle / dull clay in the
## wall stone's value range - no channel above 0.32, saturation (max - min) / max at most 0.45 - and none is derived from the hot clay instance tint; the chimney brick is a dull
## brick-brown. Red before: roof_of mixed the clay tint (0.72, 0.36, 0.26) and the brick was (0.62, 0.34, 0.26).
func test_the_roof_tones_stay_in_the_wall_stones_range_and_never_orange() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	var at := src.find("vec3 roof_of(")
	var body := src.substr(at, src.find("\n}", at) - at)
	assert_bool(body.contains("clay *") or body.contains("mix(clay")).override_failure_message("a roof tone is derived from the hot clay tint").is_false()
	var tones := RegEx.create_from_string("vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)").search_all(body)
	assert_int(tones.size()).is_greater_equal(5)
	for m in tones:
		var c := Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
		var hi := maxf(c.x, maxf(c.y, c.z))
		assert_float(hi).override_failure_message("roof tone %s too bright" % c).is_less_equal(0.32)
		assert_float((hi - minf(c.x, minf(c.y, c.z))) / hi).override_failure_message("roof tone %s too saturated" % c).is_less_equal(0.45)
	var brick: Color = BoardgenTheme.TOWN_PALETTE[BoardgenTheme.TOWN_KINDS.find("brick")]
	assert_float(brick.s).override_failure_message("chimney brick %s too saturated" % brick).is_less_equal(0.45)
	assert_float(brick.v).is_less_equal(0.5)


## Roofs lane 22.11. (lead: on main WITH the staged kit the roofs still read rust - play board rust 6.4 % on seed 41): the kit's roof modules take the same weathered range as
## the shader's roofs. Untextured (TINT x instance colour) and textured (TEXTURED_TINT x instance colour, the factor on a warm terracotta texture) both lean cool: red never the
## strongest channel, and the untextured tone stays in the wall stone's range (no channel above 0.4). Red before: TINT roof_tiles (0.62, 0.30, 0.22), TEXTURED_TINT (1.35, 0.85, 0.7).
func test_the_kit_roofs_are_weathered_slate_not_terracotta() -> void:
	for inst: Color in [BoardgenTownKit.ROOF_SLATE, BoardgenTownKit.ROOF_CLAY]:
		var plain: Color = BoardgenTownKit.TINT["roof_tiles"] * inst
		var tex: Color = BoardgenTownKit.TEXTURED_TINT["roof_tiles"] * inst
		assert_float(maxf(plain.r, maxf(plain.g, plain.b))).override_failure_message("kit roof tone %s too bright" % plain).is_less_equal(0.4)
		assert_float(plain.s).override_failure_message("kit roof tone %s too saturated" % plain).is_less_equal(0.35)
		assert_bool(tex.r < maxf(tex.g, tex.b)).override_failure_message("the textured kit roof %s still pushes the terracotta red" % tex).is_true()
## Lead 22.11. (tower-stage play sheet): a square lamp at the eaves of an infill house lit its roof like a furnace. A lamp post within BESIDE_ROOF_IN of an intact house or a tall
## tower is found by beside_a_roof (it then burns at DIM_BESIDE_ROOF and has no fill); over town boards 1-40 some are, and a post in the open street is not.
func test_a_lamp_at_the_eaves_of_a_house_is_found_and_burns_low() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var beside := 0
	var lamps := 0
	for s in range(1, 41):
		var layout: Dictionary = core.boardgen_layout_themed(s, "ruintown")
		for lamp: Dictionary in BoardgenTownDressing.lanterns(layout):
			lamps += 1
			beside += 1 if BoardgenTownDressing.beside_a_roof(layout, lamp["at"]) else 0
	print("LAMPS beside a roof %d of %d" % [beside, lamps])
	assert_int(beside).is_greater(0)
	assert_int(beside).is_less(lamps)
	var open: Dictionary = core.boardgen_layout_themed(41, "ruintown").duplicate(true)
	for c: Dictionary in open["cells"]:
		c["lot_kind"] = "Street" if ["Roofed", "Tower"].has(c["lot_kind"]) else c["lot_kind"]
	assert_bool(BoardgenTownDressing.beside_a_roof(open, Vector2(5.5, 5.5))).override_failure_message("planted: no house on the board, no lamp beside one").is_false()
	assert_float(BoardgenTownDressing.DIM_BESIDE_ROOF).is_less(0.5)
