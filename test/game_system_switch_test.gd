extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 6: Main.set_table_system is the one door that changes the table's game system. It works on
## an empty table, is refused (one battle-log line, nothing changed) while any list is on the table, and refuses an id that
## is no system. Red proof (test written first): "change with a loaded army" succeeded before the guard existed.

const MainScript := preload("res://scripts/main.gd")


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.battle_log = auto_free(BattleLog.new())
	return auto_free(m)


func _lines(m: Node, prefix: String) -> int:
	var n := 0
	for e in m.battle_log.entries():
		if str((e as Dictionary)["text"]).begins_with(prefix):
			n += 1
	return n


func _army(abbrev: String) -> OPRApiClient.OPRArmy:
	var a := OPRApiClient.OPRArmy.new()
	a.game_system_abbrev = abbrev
	return a


func test_an_empty_table_takes_the_system_and_logs_it_once() -> void:
	var m := _main()
	assert_bool(m.set_table_system("aofs", "P1")).is_true()
	assert_str(m.opr_army_manager.table_system).is_equal("aofs")
	assert_int(_lines(m, "Game system: Age of Fantasy: Skirmish")).is_equal(1)
	assert_bool(m.set_table_system("aofs", "P1")).is_true()   # already so: fine, and no second line
	assert_int(_lines(m, "Game system:")).is_equal(1)
	assert_bool(m.set_table_system("gff", "P1")).is_true()   # free while nothing is on the table
	assert_str(m.opr_army_manager.table_system).is_equal("gff")


func test_a_loaded_list_locks_the_system_with_a_reason_line() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "gf"
	m.opr_army_manager.armies[1] = _army("gf")
	assert_bool(m.set_table_system("aof", "P1")).is_false()
	assert_str(m.opr_army_manager.table_system).is_equal("gf")
	assert_int(_lines(m, "Game system unchanged: Game system is locked while a list is on the table")).is_equal(1)


func test_units_from_a_save_or_a_peer_lock_it_too() -> void:
	var m := _main()
	m.opr_army_manager.game_units["u1"] = GameUnit.new()   # no OPRArmy: a loaded save / a remote list carries none
	assert_bool(m.set_table_system("aof", "P1")).is_false()
	assert_str(m.opr_army_manager.table_system).is_equal("")
	m.opr_army_manager.game_units.clear()
	assert_bool(m.set_table_system("aof", "P1")).is_true()


func test_an_id_that_is_no_system_is_refused_and_says_so() -> void:
	var m := _main()
	assert_bool(m.set_table_system("fantasy", "P1")).is_false()
	assert_str(m.opr_army_manager.table_system).is_equal("")
	assert_int(_lines(m, "Game system unchanged: \"fantasy\" is not a game system")).is_equal(1)
