# gdUnit4 tests: the board builders strip rule-description and spell-effect text from a saved table
# before it is written, so a rebuilt tutorial board cannot bring the text back. Checked with the same
# detector the shipped-files guard uses. All text here is own synthetic wording.
extends GdUnitTestSuite

const TextStrip := preload("res://tools/tutorial_text_strip.gd")
const Guard := preload("res://test/tutorial_no_third_party_text_test.gd")


func _dirty_state() -> Dictionary:
	return {
		"version": "1.7",
		"rule_descriptions": {"Some Rule": "some words", "Other Rule": "more words"},
		"player_spells": {
			"1": [{"name": "Spell A", "threshold": 1, "effect": "words"}, {"name": "Spell B", "threshold": 2, "effect": "x"}],
			"2": [{"name": "Spell C", "threshold": 3, "effect": "yy"}],
		},
		"game_units": [
			{"unit_id": "u1", "unit_properties": {"name": "Unit", "rule_descriptions": {"Some Rule": "some words"}, "quality": 3}},
			{"unit_id": "u2", "unit_properties": {"name": "Unit 2", "quality": 4}},
		],
	}


func test_strip_state_removes_all_text_and_counts_it() -> void:
	var state := _dirty_state()
	assert_int(Guard.find_text(state).size()).is_equal(3)  # top-level map, spells, one unit's map
	var removed := TextStrip.strip_state(state)
	assert_array(Guard.find_text(state)).is_empty()
	# 10 + 10 ("some words", "more words") + 5 + 1 + 2 (spell effects) + 10 (unit map)
	assert_int(removed).is_equal(38)


func test_strip_state_keeps_everything_else() -> void:
	var state := _dirty_state()
	TextStrip.strip_state(state)
	assert_that(state["version"]).is_equal("1.7")
	assert_array(state["player_spells"]["1"]).has_size(2)
	assert_that(state["player_spells"]["1"][0]).is_equal({"name": "Spell A", "threshold": 1})
	assert_that(state["player_spells"]["2"][0]).is_equal({"name": "Spell C", "threshold": 3})
	assert_that(state["game_units"][0]["unit_properties"]["quality"]).is_equal(3)
	assert_that(state["game_units"][0]["unit_properties"]["name"]).is_equal("Unit")
	assert_that(state["rule_descriptions"]).is_equal({})
	assert_that(state["game_units"][1]["unit_properties"]).is_equal({"name": "Unit 2", "quality": 4})


func test_strip_state_is_idempotent_and_tolerates_empty_states() -> void:
	var state := _dirty_state()
	TextStrip.strip_state(state)
	assert_int(TextStrip.strip_state(state)).is_equal(0)
	assert_int(TextStrip.strip_state({})).is_equal(0)


func test_both_board_builders_strip_before_writing() -> void:
	# The builders are SceneTree scripts and cannot run inside a suite, so check the wiring itself:
	# each one preloads the helper and calls it on the state it writes.
	for path in ["res://tools/tutorial_board_builder.gd", "res://tools/lesson_table_builder.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_bool(src.contains("res://tools/tutorial_text_strip.gd")).is_true()
		assert_bool(src.contains(".strip_state(")).is_true()
