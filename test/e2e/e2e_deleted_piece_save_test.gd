extends GdUnitTestSuite
## Lead D15 (c): a deleted free terrain piece is left out of a FILE save (no undo survives a reload, so it would only
## come back as a hidden ghost node); a live piece is kept. The multiplayer full-state push is not a file save and
## keeps it (a later undo there must still find the piece on the other table).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SAVE := "user://e2e_deleted_piece_save.nml"

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


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_deleted_piece_is_left_out_of_a_file_save() -> void:
	var om: ObjectManager = _main.object_manager
	var gone: Node3D = om.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector3(0.3, 0, 0.1),
		false, 7801)
	om.spawn_sandbox_terrain("ruin_small_1f", ObjectManager.SandboxPropKind.RUIN, Vector3(-0.3, 0, -0.1), false, 7802)
	await _runner.simulate_frames(2)
	_main.radial_menu_controller.delete_objects([gone])
	var pushed: Array = _main.save_manager.serialize_game_state()["objects"]   # the peer push keeps the hidden piece
	assert_bool(pushed.any(func(o: Dictionary) -> bool: return int(o.get("network_id", -1)) == 7801)).is_true()
	assert_int(_main.save_manager.save_game(SAVE)).is_equal(OK)
	var saved: Array = JSON.parse_string(FileAccess.get_file_as_string(SAVE))["objects"]
	assert_bool(saved.any(func(o: Dictionary) -> bool: return int(o.get("network_id", -1)) == 7801)).is_false()
	assert_int(await _main.save_manager.load_game(SAVE)).is_equal(OK)
	await _runner.simulate_frames(4)
	assert_int(ObjectManager.sandbox_pieces(_main.get_tree()).size()).is_equal(1)   # the live ruin, no hidden ghost
