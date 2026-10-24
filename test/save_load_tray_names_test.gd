extends GdUnitTestSuite
## Loading a save keeps every army tray's name. The save is JSON, so its player ids come back as the
## STRINGS "1"/"2"; the tray rebuild used to look them up with int keys and named every tray "Army".

const SAVE_PATH := "user://_test_tray_names.nml"
const OPRApiClientScript = preload("res://scripts/opr_api_client.gd")


func _table() -> Dictionary:
	var save_manager := SaveManager.new()
	var army_manager := OPRArmyManager.new()
	var object_manager := ObjectManager.new()
	add_child(object_manager)
	add_child(army_manager)
	add_child(save_manager)
	auto_free(object_manager)
	auto_free(army_manager)
	auto_free(save_manager)
	army_manager.object_manager = object_manager
	save_manager.army_manager = army_manager
	save_manager.object_manager = object_manager
	return {"save": save_manager, "army": army_manager}


func _unit(pid: int) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = "tray_unit_%d" % pid
	unit.source_type = "opr"
	unit.unit_properties = {"name": "Synthetic Unit", "size": 1, "player_id": pid, "special_rules": []}
	return unit


func _tray_name(table: Dictionary, pid: int) -> String:
	var tray = table["army"].army_trays.get(pid)
	return str(tray.get_meta("army_name", "<no tray>")) if tray != null else "<no tray>"


func test_loading_a_save_keeps_every_army_tray_name() -> void:
	var src := _table()
	for pid in [1, 2]:
		var army = OPRApiClientScript.OPRArmy.new()
		army.name = "Synthetic Host %d" % pid
		src["army"].armies[pid] = army
		var unit := _unit(pid)
		src["army"].game_units[unit.unit_id] = unit
	assert_int(src["save"].save_game(SAVE_PATH)).is_equal(OK)

	var dst := _table()
	assert_int(await dst["save"].load_game(SAVE_PATH)).is_equal(OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	assert_str(_tray_name(dst, 1)).is_equal("Synthetic Host 1")
	assert_str(_tray_name(dst, 2)).is_equal("Synthetic Host 2")


func test_int_keyed_names_still_work() -> void:
	var t := _table()
	var unit := _unit(1)
	t["save"]._loaded_game_units[unit.unit_id] = {"game_unit": unit}
	t["save"].restore_army_trays_after_load({1: "Live Sync Name"})
	assert_str(_tray_name(t, 1)).is_equal("Live Sync Name")
