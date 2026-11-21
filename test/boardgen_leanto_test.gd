extends GdUnitTestSuite
## Lean-tos and sheds at the back and side of the houses (plan O6): they stand outside a house face on bare ground, flush with it, in the 0.75 in strip, never on the front, a street cell,
## a party wall or a ladder foot; and a board has some.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


## A street along x on row 7; ruined Block houses (3 in raised) on both sides, 2 cells deep, with a 1 cell gap between them and a bare yard behind.
func _street_of_blocks() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	layout["lots"] = []
	layout["connectors"] = []
	layout["landmarks"] = []
	for c: Dictionary in layout["cells"]:
		c["street"] = c["z"] == 7
		c["lot_id"] = 0
		c["lot_kind"] = "Street"
		c["level"] = 0
	var id := 0
	for side_z in [5, 8]:
		var x := 1
		while x < 14:
			var w: int = [2, 1, 3][id % 3]
			id += 1
			layout["lots"].append({"id": id, "x": x, "z": side_z, "w": w, "h": 2, "sector": [0, 0], "kind": "Block"})
			for dz in 2:
				for dx in w:
					var c: Dictionary = layout["cells"][(side_z + dz) * 16 + x + dx]
					c["lot_id"] = id
					c["lot_kind"] = "Block"
					c["level"] = 1
			x += w + 1
	return layout


func test_lean_tos_stand_flush_on_a_house_face_in_the_strip_and_never_on_its_front() -> void:
	var layout := _street_of_blocks()
	var tos := BoardgenTownDressing.lean_tos(layout)
	assert_int(tos.size()).is_greater(4)
	var cell := float(layout["cell_in"])
	var origin := Vector2(layout["nx"], layout["nz"]) * cell * -0.5
	var fronts := {}
	for f: Dictionary in BoardgenTownDressing.frontage(layout):
		fronts[f["lot"]] = f["front"]
	for b: Dictionary in tos:
		var lot: Dictionary = layout["lots"][int(b["lot"]) - 1]
		var rect := Rect2(origin + Vector2(lot["x"], lot["z"]) * cell, Vector2(lot["w"], lot["h"]) * cell)
		var lo := Vector2(b["lo"].x, b["lo"].z)
		var hi := Vector2(b["hi"].x, b["hi"].z)
		var size := hi - lo
		assert_str(b["face"]).is_not_equal(fronts[b["lot"]])   # never on the door side
		match b["face"]:
			"N": assert_float(hi.y).is_equal_approx(rect.position.y + 0.05, 0.1)
			"S": assert_float(lo.y).is_equal_approx(rect.end.y - 0.05, 0.1)
			"W": assert_float(hi.x).is_equal_approx(rect.position.x + 0.05, 0.1)
			"E": assert_float(lo.x).is_equal_approx(rect.end.x - 0.05, 0.1)
		# in the strip: at most 0.75 in off the face (the lid is a hair wider), at most 1.6 in high (+ the lid)
		assert_float(minf(size.x, size.y) if b["kind"] == "wood" else 0.0).is_less_equal(0.76)
		assert_float(b["hi"].y).is_less_equal(1.6 + 0.12 + 0.001)
		# on bare ground: the cell under the box centre is no street, lot or ladder foot
		var at := Vector2i(((lo + hi) * 0.5 - origin) / cell)
		var cd: Dictionary = layout["cells"][at.y * 16 + at.x]
		assert_bool(cd["street"] or cd["lot_id"] != 0).is_false()


func test_lean_tos_are_deterministic_and_do_not_depend_on_a_ruined_terrace() -> void:
	var layout := _street_of_blocks()
	assert_array(BoardgenTownDressing.lean_tos(layout)).is_equal(BoardgenTownDressing.lean_tos(layout))
	for lot: Dictionary in layout["lots"]:
		lot["kind"] = "Terrace"   # a Terrace's face may be a yard, not a wall: it carries none
	assert_array(BoardgenTownDressing.lean_tos(layout)).is_empty()
