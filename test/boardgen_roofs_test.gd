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
