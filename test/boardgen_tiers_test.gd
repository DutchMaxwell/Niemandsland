extends GdUnitTestSuite
## A ruined tier of two or three cells reads as a row of houses that lost their roofs (plan O7): the paint differs per part, short party-wall stubs stand at the ends of every boundary inside the
## edge strip, the middle of the top and the tier's boxes stay as the core gave them.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## Four ruined lots in a free layout: a 3 x 2 Block, a 2 x 2 Deck, a 1 x 2 Block and a 2 x 3 Block (long axis z), each raised one level.
func _tiers() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["lots"] = []
	layout["connectors"] = []
	layout["landmarks"] = []
	for c: Dictionary in layout["cells"]:
		c["street"] = false
		c["lot_id"] = 0
		c["lot_kind"] = "Street"
		c["level"] = 0
	var specs := [[1, 2, 3, 2, "Block"], [6, 2, 2, 2, "Deck"], [11, 2, 1, 2, "Block"], [1, 8, 2, 3, "Block"], [6, 9, 3, 2, "Block"]]
	for i in specs.size():
		var s: Array = specs[i]
		layout["lots"].append({"id": i + 1, "x": s[0], "z": s[1], "w": s[2], "h": s[3], "sector": [0, 0], "kind": s[4]})
		for dz in int(s[3]):
			for dx in int(s[2]):
				var c: Dictionary = layout["cells"][(int(s[1]) + dz) * 16 + int(s[0]) + dx]
				c["lot_id"] = i + 1
				c["lot_kind"] = s[4]
				c["level"] = 1
	return layout


func test_a_tier_two_cells_long_is_drawn_as_two_or_three_parts_cut_at_cell_boundaries() -> void:
	var layout := _tiers()
	var tiers := BoardgenTownDressing.tier_parts(layout)
	for lot: Dictionary in layout["lots"]:
		var n: int = maxi(lot["w"], lot["h"])
		var parts: int = tiers["parts"][lot["id"]]
		assert_int(parts).is_between(1 if n < 2 else 2, mini(n, 3))   # a lot of one cell along its length is one part; longer ones are split
		var seen := {}
		var last := -1
		for dz in lot["h"]:
			for dx in lot["w"]:
				var part: int = tiers["cells"][(lot["z"] + dz) * 16 + lot["x"] + dx]
				seen[part] = true
				var along: int = dx if tiers["axis_x"][lot["id"]] else dz
				if along == 0:
					assert_int(part).is_equal(0)
				last = maxi(last, part)
		assert_int(seen.size()).is_equal(parts)   # every part has cells
	assert_array(BoardgenTownDressing.tier_parts(layout)["cells"].keys()).is_equal(tiers["cells"].keys())   # deterministic


func test_party_stubs_stand_at_the_ends_of_each_boundary_inside_the_strip_and_stay_low() -> void:
	var layout := _tiers()
	var stubs := BoardgenTownDressing.party_stubs(layout)
	assert_int(stubs.size()).is_greater(2)
	var cell := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * cell * -0.5
	for b: Dictionary in stubs:
		var lot: Dictionary = layout["lots"][int(b["lot"]) - 1]
		assert_float(b["hi"].y - b["lo"].y).is_less_equal(0.5)   # <= 0.5 in, never promising cover
		assert_float(b["lo"].y).is_equal(3.0)   # on the tier top
		var rect := Rect2(origin + Vector2(lot["x"], lot["z"]) * cell, Vector2(lot["w"], lot["h"]) * cell)
		var c := Vector2((b["lo"].x + b["hi"].x) * 0.5, (b["lo"].z + b["hi"].z) * 0.5)
		assert_bool(rect.has_point(c)).is_true()
		var edge: float = minf(minf(c.x - rect.position.x, rect.end.x - c.x), minf(c.y - rect.position.y, rect.end.y - c.y))
		assert_float(edge).is_less_equal(0.75)   # inside the edge strip: the middle of the top is flat and free


func test_each_part_of_a_tier_carries_its_own_tone_in_the_ground_map_and_the_boxes_are_untouched() -> void:
	var layout := _tiers()
	var bytes := BoardgenGreybox.ground_map(layout, BoardgenTheme.TOWN_KINDS)
	var tiers := BoardgenTownDressing.tier_parts(layout)
	var tones := {}
	for i: int in tiers["cells"]:
		var g: int = bytes[i * 4 + 1]
		assert_int(g).is_between(1, 254)
		tones["%d/%d" % [layout["cells"][i]["lot_id"], tiers["cells"][i]]] = g
	assert_int(tones.size()).is_greater(5)   # the parts have their own tone bytes
	var tops := {}
	for b in BoardgenGreybox.plan(layout):
		if b["kind"] == "tier1" and not b.has("prop"):
			tops[b["hi"].y] = true
	assert_array(tops.keys()).is_equal([3.0])   # a tier is the same 3 in box as before
