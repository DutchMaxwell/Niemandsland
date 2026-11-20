extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 19: the gate PLAN_HEIGHTFIELD step 23 (the table chooser) asks for generated boards.
## GameSystem.generated_boards(system) = the boards on offer for that system: Tiefwerk for Firefight (gff) only, the ruined
## town for Skirmish (aofs) only and only once its row is flipped to available. gf, aof and aofr get no entry.
## Red proof: on main there is no gate - the chooser would have had to invent one.


func before_test() -> void:
	GameSystem.reset_cache()


func after_test() -> void:
	GameSystem.reset_cache()


func test_only_a_firefight_table_is_offered_tiefwerk() -> void:
	assert_array(GameSystem.generated_boards("gff")).is_equal(["tiefwerk"])
	for system in ["gf", "aof", "aofs", "aofr", ""]:
		assert_array(GameSystem.generated_boards(system)).override_failure_message("%s was offered a generated board" % system).is_empty()


func test_the_ruined_town_has_a_row_but_no_entry_until_it_ships() -> void:
	var rows: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameSystem.TERRAIN_PATH))["generated_board"]
	assert_bool(rows.has("ruined_town")).is_true()
	assert_bool(bool(rows["ruined_town"].get("available", true))).is_false()
	assert_bool(GameSystem.generated_boards("aofs").has("ruined_town")).is_false()
