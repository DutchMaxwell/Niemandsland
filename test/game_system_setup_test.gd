extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 3: the "system" key of the pending table setup reaches the army manager and writes ONE
## battle-log line; a setup without the key (harness, tutorial, scenario, old paths) leaves the table "never set".
## Red proof: on main a setup dict with system gff left table_system "" (nothing read the key).


func _manager() -> OPRArmyManager:
	return auto_free(OPRArmyManager.new())


func test_the_picked_system_is_applied_with_one_log_line() -> void:
	var mgr := _manager()
	var line := GameSystem.apply_table_setup({"size": Vector2(4, 4), "system": "gff"}, mgr)
	assert_str(mgr.table_system).is_equal("gff")
	assert_str(line).is_equal("Game system: Grimdark Future: Firefight")


func test_every_system_id_round_trips() -> void:
	for id in GameSystem.IDS:
		var mgr := _manager()
		assert_str(GameSystem.apply_table_setup({"system": id}, mgr)).is_equal("Game system: %s" % GameSystem.label(id))
		assert_str(mgr.table_system).is_equal(id)


func test_no_key_leaves_the_table_never_set() -> void:
	var mgr := _manager()
	assert_str(GameSystem.apply_table_setup({"size": Vector2(6, 4), "biome": "arid_desert"}, mgr)).is_equal("")
	assert_str(mgr.table_system).is_equal("")
	assert_str(GameSystem.apply_table_setup({}, mgr)).is_equal("")
	assert_str(GameSystem.apply_table_setup({"system": "aof"}, null)).is_equal("")


func test_a_value_that_is_no_system_changes_nothing_and_says_so() -> void:
	var mgr := _manager()
	mgr.table_system = "aof"
	var line := GameSystem.apply_table_setup({"system": "fantasy"}, mgr)
	assert_str(mgr.table_system).is_equal("aof")
	assert_str(line).contains("not a game system")
