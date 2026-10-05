extends GdUnitTestSuite
## A deleted free piece stays out of the rules after a real save and load on scenes/main.tscn (guards #1509 across a
## reload): the save keeps it hidden, the load restores the "deleted" mark and drops its collision, so its spot reads
## NONE, no sight volume remains and a model set down there stands on the table. The table theme hides the pieces it
## replaces the same way, so a saved themed table depends on this too.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SAVE := "user://e2e_deleted_piece_reload.nml"
const AT := Vector3(0.30, 0.0, 0.10)

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.object_manager.solid_models_library().apply_manifest_text("{}")
	_main.terrain_overlay.grid_cells.clear()


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_deleted_piece_stays_out_of_the_rules_after_a_reload() -> void:
	var solid: Node3D = _main.object_manager.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER,
		AT, false, 7701)
	await _runner.simulate_frames(2)
	_main.radial_menu_controller.delete_objects([solid])
	assert_int(_main.save_manager.save_game(SAVE)).is_equal(OK)
	assert_int(await _main.save_manager.load_game(SAVE)).is_equal(OK)
	await _runner.simulate_frames(6)
	assert_int(_main.terrain_overlay.get_terrain_at_world_position(AT)).is_equal(TerrainRules.TerrainType.NONE)
	assert_int((_main.terrain_overlay.los_volumes() as Array).size()).is_equal(0)
	assert_float(_main.object_manager._surface_y_under(AT)).is_less(0.005)
