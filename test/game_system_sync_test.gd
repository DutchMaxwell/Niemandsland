extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 5: the table's game system is HOST-OWNED in multiplayer. sync_table_settings is an any_peer
## door (table configuration is collaborative), so a "game_system" key from a guest must be dropped there, while the host's
## own push reaches every peer and is applied (with one battle-log line). Frames are fed into _on_raw_command exactly as
## the relay delivers them, with the stamped sender id. Red proof: without the guard a guest's push reached the handler.

const NetworkManagerScript := preload("res://scripts/network_manager.gd")
const MainScript := preload("res://scripts/main.gd")
const HOST := 1
const GUEST := 2


func _net() -> Node:
	var nm: Node = auto_free(NetworkManagerScript.new())
	add_child(nm)
	return nm


func _frame(settings: Dictionary) -> PackedByteArray:
	return MPCommand.encode("rpc", 1, {"m": "sync_table_settings", "a": [settings]})


func test_a_guests_game_system_never_reaches_the_handler() -> void:
	var nm := _net()
	var seen: Array = []
	nm.remote_table_settings_changed.connect(func(s: Dictionary) -> void: seen.append(s))
	nm._on_raw_command(GUEST, _frame({"game_system": "aof", "biome": "arid_desert"}))
	assert_int(seen.size()).is_equal(1)
	assert_bool((seen[0] as Dictionary).has("game_system")).override_failure_message("a guest set the host-owned game system").is_false()
	assert_str(str((seen[0] as Dictionary).get("biome", ""))).is_equal("arid_desert")   # the collaborative keys still pass


func test_the_hosts_game_system_reaches_the_peer() -> void:
	var nm := _net()
	var seen: Array = []
	nm.remote_table_settings_changed.connect(func(s: Dictionary) -> void: seen.append(s))
	nm._on_raw_command(HOST, _frame({"game_system": "aofs"}))
	assert_int(seen.size()).is_equal(1)
	assert_str(str((seen[0] as Dictionary).get("game_system", ""))).is_equal("aofs")


func _main() -> Node:
	var m: Node = MainScript.new()
	m.opr_army_manager = auto_free(OPRArmyManager.new())
	m.battle_log = auto_free(BattleLog.new())
	return auto_free(m)


func _lines(m: Node, needle: String) -> int:
	var n := 0
	for e in m.battle_log.entries():
		if str((e as Dictionary)["text"]) == needle:
			n += 1
	return n


func test_a_peer_applies_the_hosts_system_once_and_logs_it() -> void:
	var m := _main()
	m._on_remote_table_settings_changed({"game_system": "gff"})
	assert_str(m.opr_army_manager.table_system).is_equal("gff")
	assert_int(_lines(m, "Game system: Grimdark Future: Firefight")).is_equal(1)
	m._on_remote_table_settings_changed({"game_system": "gff"})   # a repeat (late-joiner push after a push) logs nothing new
	assert_int(_lines(m, "Game system: Grimdark Future: Firefight")).is_equal(1)


func test_a_value_that_is_no_system_is_ignored() -> void:
	var m := _main()
	m.opr_army_manager.table_system = "aof"
	m._on_remote_table_settings_changed({"game_system": "fantasy"})
	assert_str(m.opr_army_manager.table_system).is_equal("aof")
