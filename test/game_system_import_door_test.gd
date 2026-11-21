extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 7: the one import door (Main._on_opr_army_imported) refuses a list of another game system
## than the table's, BEFORE anything is stored or spawned, with one sentence naming both systems. A table nothing has named a
## system for yet takes the first list's system. A peer's list is never refused (it was vetted on its own machine), only noted.
## Red proof: on main an aof list imported onto a gff table was stored and spawned.

const MainScript := preload("res://scripts/main.gd")


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.battle_log = auto_free(BattleLog.new())
	return auto_free(m)


func _army(abbrev: String, army_name: String = "Test List") -> OPRApiClient.OPRArmy:
	var a := OPRApiClient.OPRArmy.new()
	a.name = army_name
	a.game_system_abbrev = abbrev
	return a


func _texts(m: Node) -> Array:
	return (m.battle_log.entries() as Array).map(func(e: Dictionary) -> String: return str(e["text"]))


func test_a_list_of_another_system_is_refused_before_anything_is_stored() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "gff"
	await m._on_opr_army_imported(_army("aof", "Ratmen"), 1)
	assert_int(m.opr_army_manager.armies.size()).is_equal(0)
	assert_int(m.opr_army_manager.game_units.size()).is_equal(0)
	assert_array(_texts(m)).is_equal(["Import refused: Ratmen is a list for Age of Fantasy, this table plays Grimdark Future: Firefight."])


func test_the_first_list_names_a_table_that_has_no_system() -> void:
	var m := _main()
	assert_bool(m._admit_list_system(_army("aofs", "Duelists"))).is_true()
	assert_str(m.opr_army_manager.table_system).is_equal("aofs")
	assert_array(_texts(m)).is_equal(["Game system: Age of Fantasy: Skirmish"])
	# from here on it is the table's system: the same system passes, another one is refused
	assert_bool(m._admit_list_system(_army("aofs"))).is_true()
	assert_bool(m._admit_list_system(_army("gf"))).is_false()
	assert_str(m.opr_army_manager.table_system).is_equal("aofs")


func test_a_list_already_on_the_table_names_the_system_too() -> void:
	# An old save / a peer's list: units but no set value. The table answers from them, so a gf list is refused here.
	var m := _main()
	var unit := GameUnit.new()
	unit.unit_properties = {"game_system": "aof"}
	m.opr_army_manager.game_units["u1"] = unit
	assert_str(m._table_system_or_empty()).is_equal("aof")
	assert_bool(m._admit_list_system(_army("gf"))).is_false()
	assert_bool(m._admit_list_system(_army("aof"))).is_true()
	assert_str(m.opr_army_manager.table_system).is_equal("")   # the set value is untouched: it resolves from the units


func test_a_peers_list_of_another_system_is_noted_never_refused() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "gff"
	var units := [{"unit_properties": {"game_system": "aof"}}]
	m._note_remote_list_system(units, "Peer Army")
	assert_array(_texts(m)).is_equal(["Peer Army is a list for Age of Fantasy, this table plays Grimdark Future: Firefight (a peer's list, kept)"])
	m._note_remote_list_system([{"unit_properties": {"game_system": "gff"}}], "Peer Army")   # same system: silent
	m._note_remote_list_system([], "Peer Army")
	assert_int(_texts(m).size()).is_equal(1)
	var empty := _main()
	empty._note_remote_list_system(units, "Peer Army")   # a table with no system yet has nothing to compare with
	assert_int(_texts(empty).size()).is_equal(0)
