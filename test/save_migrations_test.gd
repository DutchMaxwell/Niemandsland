extends GdUnitTestSuite
## Goal 002: SaveMigrations — the versioned .nml chain. Current passes through; 1.4/1.5 (everything the
## alpha ever shipped) lift to current; pre-alpha and newer-build saves fail with a clear message.


func _fixture_1_5() -> Dictionary:
	# A representative real-world "1.5" file: pre-goal-002 saves may lack the post-1.5 no-bump fields
	# (rule_descriptions/player_spells/army_names) and objective owners.
	return {
		"version": "1.5",
		"saved_at": "2026-06-24T20:00:00",
		"table": {
			"size_feet": [4, 4],
			"biome": "grassland",
			"mission_objectives": [{"x": 24.0, "y": 24.0}],
		},
		"objects": [],
		"game_units": [],
		"game_state": {},
		"object_counter": 7,
	}


func test_current_version_passes_through_unchanged() -> void:
	var state := _fixture_1_5()
	state["version"] = SaveManager.SAVE_VERSION
	var res := SaveMigrations.migrate(state)
	assert_bool(bool(res["ok"])).is_true()
	assert_str(str(res["migrated_from"])).is_empty()


func test_1_5_migrates_to_current_and_normalises() -> void:
	var res := SaveMigrations.migrate(_fixture_1_5())
	assert_bool(bool(res["ok"])).is_true()
	assert_str(str(res["migrated_from"])).is_equal("1.5")
	var state: Dictionary = res["state"]
	assert_str(str(state["version"])).is_equal(SaveManager.SAVE_VERSION)
	# The checkpoint normalisation made the implicit defaults explicit.
	assert_bool(state.has("rule_descriptions")).is_true()
	assert_bool(state.has("army_names")).is_true()
	assert_int(int(state["table"]["mission_objectives"][0].get("owner", -1))).is_equal(0)


func _fixture_1_5_fully_populated() -> Dictionary:
	# The shape a REAL maintainer save carries: a "1.5" file written by a build that had already
	# shipped the post-1.5 additions WITHOUT a version bump — so every checkpoint field is already
	# present and objective owners are already stamped. The 1.5->1.6 step must be IDEMPOTENT here:
	# preserve populated fields and non-neutral owners, never clobber them. (Content anonymised — no
	# player names, per repo rule; mirrors the real 12-unit / 60-object / 2-army / 4-objective save.)
	return {
		"version": "1.5",
		"saved_at": "2026-07-08T06:51:48",
		"army_names": {"1": "Army Alpha", "2": "Army Bravo"},
		"player_spells": {"1": ["Spark", "Ward"]},
		"rule_descriptions": {"Shielded": "All-model rule: +1 defense vs non-spell hits."},
		"table": {
			"size_feet": [4, 4],
			"biome": "grassland",
			"deployment_type": "pitched",
			"grid_rotation": 0.0,
			"overlay_mode": 1,
			"grid_cells": [],
			"custom_zones": [],
			"placed_objects": [],
			"wall_segments": [],
			"mission_objectives": [
				{"x": 15.0, "y": 35.0, "owner": 0},
				{"x": 75.0, "y": 55.0, "owner": 2},  # already CONTESTED — must survive the lift
				{"x": 29.0, "y": 51.0, "owner": 1},
			],
		},
		"objects": [
			{"type": "opr_unit", "position": [0.15, 0.0, -0.3], "game_unit_id": 1},
			{"type": "opr_unit", "position": [0.45, 0.0, 0.6], "game_unit_id": 2},
		],
		"game_units": [{"unit_id": 1}, {"unit_id": 2}],
		"game_state": {"current_player": 1, "current_round": 1},
		"object_counter": 60,
	}


func test_real_shape_1_5_lifts_idempotently_and_preserves_content() -> void:
	var src := _fixture_1_5_fully_populated()
	var res := SaveMigrations.migrate(src)
	assert_bool(bool(res["ok"])).is_true()
	assert_str(str(res["migrated_from"])).is_equal("1.5")
	var state: Dictionary = res["state"]
	assert_str(str(state["version"])).is_equal(SaveManager.SAVE_VERSION)
	# Idempotent normalisation: already-populated fields are NOT clobbered.
	assert_int((state["army_names"] as Dictionary).size()).is_equal(2)
	assert_str(str(state["rule_descriptions"]["Shielded"])).contains("+1 defense")
	assert_bool((state["player_spells"] as Dictionary).has("1")).is_true()
	# The already-contested objective keeps its owner; the neutral ones stay neutral.
	var objectives: Array = state["table"]["mission_objectives"]
	assert_int(int(objectives[0]["owner"])).is_equal(0)
	assert_int(int(objectives[1]["owner"])).is_equal(2)
	assert_int(int(objectives[2]["owner"])).is_equal(1)
	# Content survives the lift: objects/units/positions intact.
	assert_int((state["objects"] as Array).size()).is_equal(2)
	assert_int((state["game_units"] as Array).size()).is_equal(2)
	assert_float(float(state["objects"][0]["position"][0])).is_equal_approx(0.15, 0.0001)
	assert_int(int(state["object_counter"])).is_equal(60)


func test_1_4_lifts_through_the_whole_chain() -> void:
	var state := _fixture_1_5()
	state["version"] = "1.4"   # regiments-era save: no sandbox terrain, none of the later fields
	var res := SaveMigrations.migrate(state)
	assert_bool(bool(res["ok"])).is_true()
	assert_str(str(res["migrated_from"])).is_equal("1.4")
	assert_str(str(res["state"]["version"])).is_equal(SaveManager.SAVE_VERSION)


func test_pre_alpha_format_fails_with_clear_message() -> void:
	var state := _fixture_1_5()
	state["version"] = "1.3"
	var res := SaveMigrations.migrate(state)
	assert_bool(bool(res["ok"])).is_false()
	assert_bool(str(res["error"]).contains("pre-alpha")).is_true()


func test_newer_build_save_fails_with_update_hint() -> void:
	var state := _fixture_1_5()
	state["version"] = "9.1"
	var res := SaveMigrations.migrate(state)
	assert_bool(bool(res["ok"])).is_false()
	assert_bool(str(res["error"]).contains("NEWER")).is_true()


func test_missing_or_garbage_version_fails() -> void:
	var state := _fixture_1_5()
	state["version"] = ""
	assert_bool(bool(SaveMigrations.migrate(state)["ok"])).is_false()
	state["version"] = "banana"
	assert_bool(bool(SaveMigrations.migrate(state)["ok"])).is_false()


func test_version_compare_is_numeric_not_lexicographic() -> void:
	# "1.10" must be NEWER than "1.9" — a lexicographic compare would get this wrong.
	assert_int(SaveMigrations._cmp("1.10", "1.9")).is_equal(1)
	assert_int(SaveMigrations._cmp("1.6", "1.6")).is_equal(0)
	assert_int(SaveMigrations._cmp("1.4", "1.6")).is_equal(-1)