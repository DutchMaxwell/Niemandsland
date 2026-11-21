extends GdUnitTestSuite
## The frontage table of the ruin town's house lots (plan O1): every house with a street beside it has a front, front and back are opposite faces, corner lots are
## flagged, the table is deterministic and not a constant, and a tie goes toward the square.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


func _layouts() -> Array[Dictionary]:
	var out: Array[Dictionary] = [str_to_var(FileAccess.get_file_as_string(FIXTURE))]
	if ClassDB.class_exists("NmlCore") and ClassDB.instantiate("NmlCore").has_method("boardgen_layout_themed"):
		for board_seed in [3, 7, 25]:
			out.append(ClassDB.instantiate("NmlCore").boardgen_layout_themed(board_seed, "ruintown"))
	return out


func test_every_house_with_a_street_beside_it_has_a_front_with_the_most_street_cells_and_the_back_is_opposite() -> void:
	var opposite := {"N": "S", "E": "W", "S": "N", "W": "E"}
	var houses := 0
	for layout in _layouts():
		for f: Dictionary in BoardgenTownDressing.frontage(layout):
			var total := 0
			for face: String in f["streets"]:
				total += int(f["streets"][face])
			if total == 0:
				assert_str(f["front"]).is_empty()   # a backyard house has no front
				continue
			houses += 1
			assert_str(f["front"]).is_not_empty()
			assert_int(f["streets"][f["front"]]).is_equal((f["streets"].values() as Array).max())
			assert_str(f["back"]).is_equal(opposite[f["front"]])
			assert_array(f["sides"]).has_size(2)
			assert_bool(f["sides"].has(f["front"]) or f["sides"].has(f["back"])).is_false()
	assert_int(houses).is_greater(5)


func test_a_corner_lot_has_street_beside_two_adjacent_faces() -> void:
	for layout in _layouts():
		for f: Dictionary in BoardgenTownDressing.frontage(layout):
			var s: Dictionary = f["streets"]
			assert_bool(f["corner"]).is_equal((s["N"] > 0 or s["S"] > 0) and (s["E"] > 0 or s["W"] > 0))


func test_the_table_is_deterministic_and_the_front_is_not_one_constant_face() -> void:
	var fronts := {}
	for layout in _layouts():
		assert_array(BoardgenTownDressing.frontage(layout)).is_equal(BoardgenTownDressing.frontage(layout))
		for f: Dictionary in BoardgenTownDressing.frontage(layout):
			fronts[f["front"]] = true
	assert_int(fronts.size()).is_greater_equal(3)   # a planted "front = north always" fails here


func test_a_tie_goes_toward_the_square() -> void:
	# a 1 x 1 house at (2, 7) with street on its north and its south side (one cell each): the board centre lies south-east of it, so the front is S ... and its half-turn twin
	# at (13, 8) has the centre north-west of it, so its front is N
	var layout := {"nx": 16, "nz": 16, "cells": [], "lots": []}
	for i in 256:
		layout["cells"].append({"x": i % 16, "z": i / 16, "street": false, "lot_id": 0, "lot_kind": "Street", "level": 0})
	for spec in [[2, 7, 1], [13, 8, 2]]:
		layout["lots"].append({"id": spec[2], "x": spec[0], "z": spec[1], "w": 1, "h": 1, "kind": "Block"})
		layout["cells"][spec[1] * 16 + spec[0]]["lot_id"] = spec[2]
		layout["cells"][spec[1] * 16 + spec[0]]["lot_kind"] = "Block"
		layout["cells"][(spec[1] - 1) * 16 + spec[0]]["street"] = true
		layout["cells"][(spec[1] + 1) * 16 + spec[0]]["street"] = true
	var table := BoardgenTownDressing.frontage(layout)
	assert_str(table[0]["front"]).is_equal("S")   # lot (2, 7): the board centre lies below and right of it
	assert_str(table[1]["front"]).is_equal("N")
