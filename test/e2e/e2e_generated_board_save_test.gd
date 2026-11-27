extends GdUnitTestSuite
## GEN-10: a generated board survives save and load on the real scenes/main.tscn - the save carries the board's record
## in the table block (the same block a joining peer gets), the load lays it again; a save without one takes a
## standing board away. Red before the step: the load left the table without its board.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const SAVE_PATH := "user://e2e_generated_board_save.nml"
const BOARD := {"id": "tiefwerk", "theme": "deepworks", "seed": 42, "version": 1, "digest": "cbcd64fada596527"}

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.table.setup_table(Vector2(4, 4))


func after_test() -> void:
	var look: Variant = _main.get("_board_look")
	if is_instance_valid(look):   # the board leaves while the table is alive
		(look as Node).queue_free()
		await get_tree().process_frame
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _drop_board() -> void:
	(_main.get("_board_look") as Node).queue_free()
	await get_tree().process_frame
	assert_dict(_main.generated_board()).is_empty()


@warning_ignore('unused_parameter')
func test_a_saved_board_is_on_the_table_after_the_load(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	assert_bool(_main.apply_generated_board(BOARD)).is_true()
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	await _drop_board()
	await _main.save_manager.load_game(SAVE_PATH)
	await get_tree().process_frame
	var board: Dictionary = _main.generated_board()
	assert_str(GeneratedBoard.code(board)).is_equal("TW-1-42")
	assert_str(str(board.get("digest", ""))).is_equal(BOARD["digest"])
	assert_bool(AiActRecorder.tiers_of_board(board).has("tiers")).override_failure_message("the core gets no ledges").is_true()


@warning_ignore('unused_parameter')
func test_a_save_without_a_board_loads_flat(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	assert_int(_main.save_manager.save_game(SAVE_PATH)).is_equal(OK)
	var table_block: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) as Dictionary).get("table", {})
	assert_bool(table_block.has("generated_board")).override_failure_message("a flat table wrote a board key").is_false()
	assert_bool(_main.apply_generated_board(BOARD)).is_true()
	await _main.save_manager.load_game(SAVE_PATH)
	await get_tree().process_frame
	assert_dict(_main.generated_board()).is_empty()
