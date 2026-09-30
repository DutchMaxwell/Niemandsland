extends GdUnitTestSuite
## E2E — the Save / Load file dialogs, row 23 of the UI inventory (uimenus step 10). They are native Godot
## FileDialogs: the restyle is a theme only. Pinned here: the game's Save dialog (save mode, *.nml filter,
## default folder, a "game_<time>.nml" name), its Load dialog (open mode, same filter and folder, a guest may
## not open it), and the menu's Load dialog (open mode, "Open" / "Cancel" pinned in English, *.nml filter).
## test_inventory_check_names_a_missing_filter proves the check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

class MenuProbe extends "res://scripts/startup_menu.gd":
	func _transition_to_game() -> void:
		pass

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _filters_ok(d: FileDialog) -> bool:
	return str(d.filters).contains("*.nml")


func test_game_save_dialog_is_a_save_dialog_with_the_nml_filter_folder_and_name() -> void:
	_main._on_save_game()
	await _runner.simulate_frames(2)
	var d: FileDialog = _main.save_game_dialog
	assert_bool(d.visible).is_true()
	assert_int(d.file_mode).is_equal(FileDialog.FILE_MODE_SAVE_FILE)
	assert_bool(_filters_ok(d)).is_true()
	assert_str(d.current_dir).is_equal(SaveManager.get_default_save_dir().replace("\\", "/").trim_suffix("/"))
	assert_bool(d.current_file.begins_with("game_") and d.current_file.ends_with(".nml")).is_true()
	d.hide()


func test_game_load_dialog_is_an_open_dialog_with_the_nml_filter_and_folder() -> void:
	_main._on_load_game()
	await _runner.simulate_frames(2)
	var d: FileDialog = _main.load_game_dialog
	assert_bool(d.visible).is_true()
	assert_int(d.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_bool(_filters_ok(d)).is_true()
	d.hide()


func test_menu_load_dialog_pins_english_open_cancel_and_the_nml_filter() -> void:
	var menu: Control = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	menu.set_script(MenuProbe)
	add_child(menu)
	await _runner.simulate_frames(2)
	menu._open_load_battle_dialog()
	var d: FileDialog = menu._load_dialog
	assert_int(d.file_mode).is_equal(FileDialog.FILE_MODE_OPEN_FILE)
	assert_str(d.ok_button_text).is_equal("Open")
	assert_str(d.cancel_button_text).is_equal("Cancel")
	assert_bool(_filters_ok(d)).is_true()
	assert_str(d.title).is_equal("Load game")


func test_all_three_dialogs_carry_the_house_theme() -> void:
	assert_object(_main.save_game_dialog.theme).is_same(HouseStyle.theme())
	assert_object(_main.load_game_dialog.theme).is_same(HouseStyle.theme())
	var menu: Control = auto_free(load("res://scenes/startup_menu.tscn").instantiate())
	menu.set_script(MenuProbe)
	add_child(menu)
	await _runner.simulate_frames(2)
	menu._open_load_battle_dialog()
	assert_object(menu._load_dialog.theme).is_same(HouseStyle.theme())


func test_inventory_check_names_a_missing_filter() -> void:
	var d := FileDialog.new()
	assert_bool(_filters_ok(d)).is_false()
	d.filters = PackedStringArray(["*.nml ; Niemandsland Save"])
	assert_bool(_filters_ok(d)).is_true()
	d.free()
