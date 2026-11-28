extends GdUnitTestSuite
## GEN-3: a generated board as data - the record a table, a save and a peer share, its code and the silent re-roll.
## Red before the step: there is no res://scripts/generated_board.gd.

const SCRIPT := "res://scripts/generated_board.gd"


## A stand-in for NmlCore.boardgen_tiers: seeds in `bad` have a problem, every other seed is accepted.
class StubCore:
	extends RefCounted
	var bad: Array = []
	var asked: Array = []

	func boardgen_tiers(seed_value: int, theme: String) -> Dictionary:
		asked.append(seed_value)
		var problems: Array = ["unreachable"] if bad.has(seed_value) else []
		return {"tiers": {}, "solid_cells": [], "cells": [], "version": 1,
			"digest": "%016x" % (seed_value * 31 + theme.length()), "problems": problems}


func _gb() -> GDScript:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no generated board script").is_true()
	return load(SCRIPT) if ResourceLoader.exists(SCRIPT) else null


func test_a_code_round_trips() -> void:
	var gb := _gb()
	if gb == null:
		return
	var rec: Dictionary = gb.call("resolve", "tiefwerk", 1234, StubCore.new())
	assert_dict(rec).contains_key_value("seed", 1234).contains_key_value("theme", "deepworks") \
		.contains_key_value("id", "tiefwerk").contains_key_value("version", 1)
	var code: String = gb.call("code", rec)
	assert_str(code).is_equal("TW-1-1234")
	var back: Dictionary = gb.call("parse", code, 1)
	assert_dict(back).contains_key_value("id", "tiefwerk").contains_key_value("seed", 1234)
	assert_str(gb.call("code", gb.call("resolve", "ruined_town", 7, StubCore.new()))).is_equal("RT-1-7")


func test_a_foreign_version_is_refused_with_its_reason() -> void:
	var gb := _gb()
	if gb == null:
		return
	var back: Dictionary = gb.call("parse", "TW-2-1234", 1)
	assert_bool(back.has("seed")).is_false()
	assert_str(str(back.get("reason", ""))).contains("another version")
	assert_bool((gb.call("parse", "XX-1-5", 1) as Dictionary).has("seed")).is_false()
	assert_bool((gb.call("parse", "TW-1-abc", 1) as Dictionary).has("seed")).is_false()


func test_a_problem_seed_is_silently_rerolled_to_the_next() -> void:
	var gb := _gb()
	if gb == null:
		return
	var core := StubCore.new()
	core.bad = [500, 501]
	var rec: Dictionary = gb.call("resolve", "tiefwerk", 500, core)
	assert_int(int(rec.get("seed", -1))).is_equal(502)
	assert_array(core.asked).is_equal([500, 501, 502])
	core.bad = range(900, 950)
	assert_dict(gb.call("resolve", "tiefwerk", 900, core)).is_empty()
	assert_dict(gb.call("resolve", "castle", 1, StubCore.new())).is_empty()


## GEN-11: a stored record is checked against this build's board of the same seed - equal digest and version = "",
## else the reason names both board codes; a record without a digest (the dev door's) is not checked.
func test_a_stored_board_is_checked_against_this_builds() -> void:
	var gb := _gb()
	if gb == null:
		return
	var core := StubCore.new()
	var rec: Dictionary = gb.call("resolve", "tiefwerk", 77, core)
	assert_str(gb.call("verify", rec, core)).is_empty()
	var planted := rec.duplicate()
	planted["digest"] = "0000000000000000"
	assert_str(gb.call("verify", planted, core)).contains("TW-1-77").contains("does not match")
	var older := rec.duplicate()
	older["version"] = 0
	assert_str(gb.call("verify", older, core)).contains("board version 0").contains("this build makes version 1")
	assert_str(gb.call("verify", {"seed": 7, "theme": ""}, core)).is_empty()
