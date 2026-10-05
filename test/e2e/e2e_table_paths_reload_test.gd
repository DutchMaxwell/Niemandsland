extends GdUnitTestSuite
## The table's worn paths (lead D14 = a) survive a real save and load on scenes/main.tscn: written to a .nml file,
## cleared, loaded back, drawn again.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SAVE := "user://e2e_table_paths_reload.nml"
const PATH := [[[0.0, 0.0], [6.0, 0.0], [6.0, 8.0]]]

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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_paths_come_back_after_a_save_and_load() -> void:
	TablePaths.of(_main.table).set_paths(PATH)
	assert_int(_main.save_manager.save_game(SAVE)).is_equal(OK)
	TablePaths.of(_main.table).set_paths([])
	assert_int(await _main.save_manager.load_game(SAVE)).is_equal(OK)
	await _runner.simulate_frames(4)
	assert_array(TablePaths.of(_main.table).paths).is_equal(PATH)
	assert_int(TablePaths.of(_main.table).find_children("*", "Decal", false, false).size()).is_equal(2)


## The other table draws the paths it receives with the table settings (D14: sent via broadcast_table_settings).
func test_paths_received_with_the_table_settings_are_drawn() -> void:
	_main._on_remote_table_settings_changed({"paths": PATH})
	assert_array(TablePaths.of(_main.table).paths).is_equal(PATH)
	assert_int(TablePaths.of(_main.table).find_children("*", "Decal", false, false).size()).is_equal(2)
