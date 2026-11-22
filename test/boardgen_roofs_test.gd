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
	assert_int(rooflines.size()).is_greater_equal(4)
	var core: Object = ClassDB.instantiate("NmlCore")   # (L1: this street's lots are all two cells deep, so its eaves-on roofs are twin gables; the kinds are counted on real boards:
	for s in range(1, 61):   # catslides need a roof one cell wide AND eaves-on: 8 of 518 main roofs on boards 1-60)
		for r: Dictionary in BoardgenTownDressing.roofs(core.boardgen_layout_themed(s, "ruintown")):
			types[r["type"]] = true
	assert_int(types.size()).is_equal(3)


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


## (L1, target C: steep roofs) Over town boards 1-60 every main roof strip is at least 48 degrees steep over its own half width (a two-cell-wide house is twin gables, not one shallow
## prism), and the drawn ridge brackets the core's 4.5 in (sight plan S4: mean eaves + height in 4.3-4.9 in, none under 3.5, none over RIDGE_MAX_IN). Red on the parent: 25-40 degrees.
func test_every_main_roof_is_at_least_48_degrees_steep_and_its_ridge_brackets_the_rule_height() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var ridges := PackedFloat64Array()
	var pitches := PackedFloat64Array()
	var twins := 0
	for s in range(1, 61):
		for r: Dictionary in BoardgenTownDressing.roofs(core.boardgen_layout_themed(s, "ruintown")):
			if r["annex"]:
				continue
			twins += int(r["ridges"] > 1)
			ridges.append(float(r["eaves"]) + float(r["height"]))
			for st: Dictionary in BoardgenTownDressing.ridge_strips(r):
				pitches.append(rad_to_deg(atan2(float(st["height"]), float(st["width"]) * 0.5)))
	var mean := 0.0
	for x in ridges:
		mean += x / ridges.size()
	var lo_p: float = Array(pitches).min()
	print("L1 PITCH %d strips, %.1f-%.1f deg; RIDGES %d roofs, mean %.2f in, %.2f-%.2f in; %d twin roofs" % [pitches.size(), lo_p, Array(pitches).max(), ridges.size(), mean, Array(ridges).min(), Array(ridges).max(), twins])
	assert_float(lo_p).is_greater_equal(48.0)
	assert_float(mean).is_between(4.3, 4.9)
	assert_float(Array(ridges).min()).is_greater_equal(3.5)
	assert_float(Array(ridges).max()).is_less_equal(BoardgenTownDressing.RIDGE_MAX_IN + 0.0001)
	assert_int(twins).is_greater(0)


## (L1) The strips of a twin roof lie side by side inside the roof's own width and keep its ridge line; hips only on a roof one ridge wide.
func test_a_twin_roof_is_two_one_cell_strips_side_by_side() -> void:
	var layout := _street_of_houses()
	var seen := 0
	for r: Dictionary in BoardgenTownDressing.roofs(layout):
		var strips := BoardgenTownDressing.ridge_strips(r)
		assert_int(strips.size()).is_equal(r["ridges"])
		if r["ridges"] == 1:
			continue
		seen += 1
		assert_str(r["type"]).is_equal("gable")
		var gap: Vector2 = strips[1]["centre"] - strips[0]["centre"]
		assert_float(gap.length()).is_equal_approx((float(r["width"]) - 2.0 * BoardgenTownDressing.OVERHANG_IN) / float(r["ridges"]), 0.001)
		assert_float(float(strips[0]["width"])).is_equal_approx(3.0 + 2.0 * BoardgenTownDressing.OVERHANG_IN, 0.001)
	assert_int(seen).is_greater(0)


## The 8 corners of a damage box (board inches), with the same basis the build gives it.
func _corners(b: Dictionary) -> Array[Vector3]:
	var basis := Basis(Vector3.UP, b["yaw"]) * Basis(Vector3.RIGHT, -float(b["pitch"]))
	var out: Array[Vector3] = []
	for i in 8:
		out.append(b["centre"] + basis * ((Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1) - Vector3.ONE * 0.5) * b["size"]))
	return out


## (L2, target C: 9 of 17 roofs broken) Over town boards 1-40: a third to a half of the main roofs are broken per board on average (each board 20-67 %: at most half, bar the two every board has), every board half has
## one, exactly one per board is collapsed to its rafters, and no two roofs whose lots touch show the same damage (holed / sagged / collapsed). Deterministic. Red on the parent: no damage.
func test_broken_roofs_one_in_two_to_three_one_collapsed_never_the_same_beside_each_other() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var shares := PackedFloat64Array()
	for s in range(1, 41):
		var layout: Dictionary = core.boardgen_layout_themed(s, "ruintown")
		var mains := BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return not r["annex"])
		var broken := mains.filter(func(r: Dictionary) -> bool: return r.get("damage", "whole") != "whole")
		shares.append(float(broken.size()) / mains.size())
		assert_float(shares[-1]).override_failure_message("seed %d: %d of %d roofs broken" % [s, broken.size(), mains.size()]).is_between(0.2, 0.67)
		assert_int(mains.filter(func(r: Dictionary) -> bool: return r["damage"] == "collapsed").size()).is_equal(1)
		for half in 2:
			assert_bool(broken.any(func(r: Dictionary) -> bool: return r["half"] == half)).override_failure_message("seed %d half %d: no broken roof" % [s, half]).is_true()
		for r: Dictionary in broken:
			assert_str(r["type"]).is_equal("gable")
			for q: Dictionary in broken:
				if q != r and (q["rect"] as Rect2i).grow(1).intersects(r["rect"]):
					assert_str(q["damage"]).override_failure_message("seed %d: lots %d and %d touch and are both %s" % [s, r["lot"], q["lot"], r["damage"]]).is_not_equal(r["damage"])
		assert_array(BoardgenTownDressing.roofs(layout)).is_equal(BoardgenTownDressing.roofs(layout))
	var mean := 0.0
	for x in shares:
		mean += x / shares.size()
	print("L2 BROKEN share mean %.3f, boards %.2f-%.2f" % [mean, Array(shares).min(), Array(shares).max()])
	assert_float(mean).is_between(0.33, 0.5)


## (L2, D-R3) Nothing of a broken roof is over standing room: every timber box (rafter, ridge beam, batten) lies with all 8 corners over a cell of its own lot, an intact house
## (Roofed = solid, nobody stands in or on it); every tile piece lies within the roof's own overhang. A holed roof shows 3+ rafters, a sagged one two pieces. Town boards 1-40.
func test_no_part_of_a_broken_roof_leaves_the_solid_cells_of_its_house() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var counts := {}
	for s in range(1, 41):
		var layout: Dictionary = core.boardgen_layout_themed(s, "ruintown")
		var nx: int = layout["nx"]
		var cell_in := float(layout["cell_in"])
		var half_board := Vector2(nx, layout["nz"]) * cell_in * 0.5
		for r: Dictionary in BoardgenTownDressing.roofs(layout):
			for st: Dictionary in BoardgenTownDressing.ridge_strips(r):
				var parts := BoardgenTownDressing.roof_parts(st)
				var state: String = st.get("damage", "whole") if st["strip"] == 0 else "whole"
				counts[state] = int(counts.get(state, 0)) + 1
				var rect := Rect2(Vector2(r["rect"].position) * cell_in - half_board, Vector2(r["rect"].size) * cell_in)
				for b: Dictionary in parts[1]:
					for c: Vector3 in _corners(b):
						var at := Vector2(c.x, c.z)
						if b["kind"] == "roof":
							assert_bool(rect.grow(BoardgenTownDressing.OVERHANG_IN + 0.45).has_point(at)).override_failure_message("seed %d lot %d: a tile piece at %s" % [s, r["lot"], at]).is_true()
							continue
						var cell := Vector2i(((at + half_board) / cell_in).floor())
						var cd: Dictionary = layout["cells"][cell.y * nx + cell.x]
						assert_bool(cd["lot_id"] == r["lot"] and cd["lot_kind"] == "Roofed" and rect.grow(-0.2).has_point(at)).override_failure_message("seed %d lot %d: %s box corner %s over cell %s (%s)" % [s, r["lot"], state, at, cell, cd["lot_kind"]]).is_true()
				if state in ["holed", "collapsed"]:
					assert_int(parts[1].filter(func(b: Dictionary) -> bool: return b["kind"] == "wood").size()).is_greater_equal(3 + 1 + 2)
				elif state == "sagged":
					assert_int(parts[0].size()).is_equal(2)
				else:
					assert_array(parts[0]).is_equal([st])
	print("L2 STRIPS %s" % counts)
	assert_int(counts.get("collapsed", 0)).is_equal(40)
