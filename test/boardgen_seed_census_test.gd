extends GdUnitTestSuite
## The seed census (tools/boardgen/seed_census.gd, LOOK5 Q1) can fail: a planted asymmetric cell turns ASYMMETRIC red, a second generation that
## differs turns NONDETERMINISTIC red, and an honest board is neither.

const CENSUS := preload("res://tools/boardgen/seed_census.gd")


func test_a_planted_asymmetric_cell_and_a_differing_second_generation_are_named() -> void:
	var core: Object = ClassDB.instantiate("NmlCore")
	var layout: Dictionary = core.boardgen_layout_themed(41, "ruintown")
	var honest: Dictionary = CENSUS.row(layout, layout.duplicate(true))
	assert_array(honest["fail"]).not_contains(["ASYMMETRIC", "NONDETERMINISTIC"])
	assert_int(honest["cells"]["wall_3"] + honest["cells"]["wall_6"] + honest["cells"]["wall_9"]).is_greater(0)
	var planted := layout.duplicate(true)
	var cell: Dictionary = planted["cells"].filter(func(c: Dictionary) -> bool: return int(c["level"]) == 0 and c["lot_kind"] == "Street")[0]
	cell["level"] = 1
	assert_array(CENSUS.row(planted, planted.duplicate(true))["fail"]).contains(["ASYMMETRIC"])
	assert_array(CENSUS.row(layout, planted)["fail"]).contains(["NONDETERMINISTIC"])
