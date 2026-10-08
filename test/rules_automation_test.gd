extends GdUnitTestSuite
## Rules-automation plan step 1.1 -- the Manual/Automatic level lives in the game state and the save.
## Nothing in gameplay reads it yet; this suite pins the pure helpers and the save round trip.


func _mgr() -> OPRArmyManager:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	return auto_free(mgr)


func _save_mgr(mgr: OPRArmyManager) -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	sm.army_manager = mgr
	return auto_free(sm)


func test_from_game_state_table() -> void:
	assert_int(RulesAutomation.from_game_state({})).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.from_game_state({"rules_automation": "x"})).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.from_game_state({"rules_automation": 7})).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.from_game_state({"rules_automation": -1})).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.from_game_state({"rules_automation": 0})).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.from_game_state({"rules_automation": 1})).is_equal(RulesAutomation.Level.AUTOMATIC)


func test_label() -> void:
	assert_str(RulesAutomation.label(RulesAutomation.Level.AUTOMATIC)).is_equal("Automatic")
	assert_str(RulesAutomation.label(RulesAutomation.Level.MANUAL)).is_equal("Manual")


func test_effective_table() -> void:
	assert_int(RulesAutomation.effective(RulesAutomation.Level.MANUAL, false)).is_equal(RulesAutomation.Level.MANUAL)
	assert_int(RulesAutomation.effective(RulesAutomation.Level.AUTOMATIC, false)).is_equal(RulesAutomation.Level.AUTOMATIC)
	assert_int(RulesAutomation.effective(RulesAutomation.Level.MANUAL, true)).is_equal(RulesAutomation.Level.AUTOMATIC)
	assert_int(RulesAutomation.effective(RulesAutomation.Level.AUTOMATIC, true)).is_equal(RulesAutomation.Level.AUTOMATIC)


func test_new_manager_defaults_to_manual() -> void:
	assert_int(_mgr().rules_automation).is_equal(RulesAutomation.Level.MANUAL)


func test_save_round_trip_keeps_automatic() -> void:
	var mgr := _mgr()
	mgr.rules_automation = RulesAutomation.Level.AUTOMATIC
	var state := _save_mgr(mgr)._serialize_game_state()
	assert_bool(state.has(RulesAutomation.SAVE_KEY)).is_true()
	var mgr2 := _mgr()
	_save_mgr(mgr2)._deserialize_game_state(state)
	assert_int(mgr2.rules_automation).is_equal(RulesAutomation.Level.AUTOMATIC)


func test_old_save_without_the_key_loads_manual() -> void:
	var mgr := _mgr()
	mgr.rules_automation = RulesAutomation.Level.AUTOMATIC
	_save_mgr(mgr)._deserialize_game_state({"current_round": 1, "game_phase": 1})
	assert_int(mgr.rules_automation).is_equal(RulesAutomation.Level.MANUAL)
