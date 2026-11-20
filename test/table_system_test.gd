extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 2: the table has ONE game system. Main._table_system() = the value the table was set to,
## else the system of the first loaded list (lowest slot), else the default; _solo_rules_system() falls back to it when
## no human list is loaded. Red proof: on main a table set to aofs with no list answered gf (no resolver, no state).

const MainScript := preload("res://scripts/main.gd")


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	return auto_free(m)


func _army(abbrev: String) -> OPRApiClient.OPRArmy:
	var a := OPRApiClient.OPRArmy.new()
	a.game_system_abbrev = abbrev
	return a


func test_a_table_set_to_aofs_without_a_list_plays_aofs() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "aofs"
	assert_str(m._table_system()).is_equal("aofs")
	assert_str(m._solo_rules_system()).is_equal("aofs")


func test_a_table_never_set_and_empty_plays_the_default() -> void:
	var m := _main()
	assert_str(m.opr_army_manager.table_system).is_equal("")
	assert_str(m._table_system()).is_equal("gf")
	assert_str(m._solo_rules_system()).is_equal("gf")


func test_without_a_set_value_the_first_loaded_list_decides() -> void:
	var m := _main()
	m.opr_army_manager.armies[2] = _army("aof")
	assert_str(m._table_system()).is_equal("aof")
	m.opr_army_manager.armies[1] = _army("gff")   # lowest slot wins, whatever the insertion order
	assert_str(m._table_system()).is_equal("gff")
	m.opr_army_manager.armies[1] = null   # an empty slot is skipped
	assert_str(m._table_system()).is_equal("aof")


func test_the_set_value_wins_over_a_loaded_list() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "aofr"
	m.opr_army_manager.armies[1] = _army("gf")
	assert_str(m._table_system()).is_equal("aofr")
	# the human's own list still answers the rules system of its units
	assert_str(m._solo_rules_system()).is_equal("gf")


func test_a_stored_value_that_is_no_system_folds_to_the_default() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "nonsense"
	assert_str(m._table_system()).is_equal("gf")
