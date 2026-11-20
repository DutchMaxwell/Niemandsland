extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 4: the table's game system rides the game-state block of a save (and so the MP full-state
## push). Optional key, no SAVE_VERSION bump: a save without it - every save written before - loads as "never set" and
## resolves from its lists. Red proof: on main the round trip lost the value (nothing wrote or read the key).

const MainScript := preload("res://scripts/main.gd")


func _mgr() -> OPRArmyManager:
	var mgr := OPRArmyManager.new()
	add_child(mgr)
	return auto_free(mgr)


func _save_mgr(mgr: OPRArmyManager) -> SaveManager:
	var sm := SaveManager.new()
	add_child(sm)
	sm.army_manager = mgr
	return auto_free(sm)


func _wire(sm: SaveManager) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sm._serialize_game_state()))   # a save IS a JSON file


func test_the_system_survives_a_save_and_a_load() -> void:
	var mgr := _mgr()
	mgr.table_system = "aofs"
	var sm := _save_mgr(mgr)
	var wire := _wire(sm)
	assert_str(str(wire.get("game_system", "<missing>"))).is_equal("aofs")
	var other := _mgr()
	_save_mgr(other)._deserialize_game_state(wire)
	assert_str(other.table_system).is_equal("aofs")


func test_a_table_never_set_stays_never_set() -> void:
	var mgr := _mgr()
	var wire := _wire(_save_mgr(mgr))
	assert_str(str(wire.get("game_system", "<missing>"))).is_equal("")
	var other := _mgr()
	other.table_system = "gff"
	_save_mgr(other)._deserialize_game_state(wire)
	assert_str(other.table_system).is_equal("")


func test_an_older_save_without_the_key_resolves_from_its_list() -> void:
	# The game-state block as 1.7 wrote it: no "game_system". The load REPLACES the system (a previous table's value must
	# not leak in), and the table then answers from the list that came with the save.
	var mgr := _mgr()
	mgr.table_system = "gff"
	var army := OPRApiClient.OPRArmy.new()
	army.game_system_abbrev = "aof"
	mgr.armies[1] = army
	var old_block := {"current_round": 2, "game_phase": 1, "current_player": 1, "token_library": {}, "rule_state": {}, "rules_automation": 0}
	_save_mgr(mgr)._deserialize_game_state(old_block)
	assert_str(mgr.table_system).is_equal("")
	var m: Node = auto_free(MainScript.new())
	m.opr_army_manager = mgr
	assert_str(m._table_system()).is_equal("aof")


func test_a_value_that_is_no_system_loads_as_never_set() -> void:
	var mgr := _mgr()
	_save_mgr(mgr)._deserialize_game_state({"game_system": "fantasy"})
	assert_str(mgr.table_system).is_equal("")
