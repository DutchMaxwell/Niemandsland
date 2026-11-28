extends GdUnitTestSuite
## GEN-1: the tier hand-over is live in a real game. A generated board stands on the table through the release door;
## the terrain line the table hands the core - built at the LIVE rules epoch, nothing set by the test - carries the
## board's ledges (`tiers`, `solid_cells`), the same the binding names for that board. Red while the live epoch is below
## the tier epoch (106): the line had no tiers although the board stood on the table.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

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
	_main.restore_generated_board({})   # the board leaves while the table is alive
	await get_tree().process_frame
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


@warning_ignore('unused_parameter')
func test_the_live_line_carries_the_boards_ledges(do_skip := not ClassDB.class_exists("NmlCore"),
		skip_reason := "NmlCore extension not loaded") -> void:
	var record := GeneratedBoard.resolve("tiefwerk", 42)
	assert_bool(_main.apply_generated_board(record)).override_failure_message("the board was not laid").is_true()
	var line: Variant = AiActRecorder._terrain_line(Callable(_main, "generated_board"))
	assert_bool(line is Dictionary).override_failure_message("no terrain line").is_true()
	if not line is Dictionary:
		return
	assert_bool((line as Dictionary).has("tiers")).override_failure_message(
		"live rules epoch %d: the line carries no tiers although the board stands" % AiActRecorder.rules_epoch).is_true()
	var want: Dictionary = (ClassDB.instantiate("NmlCore") as Object).call("boardgen_tiers", 42, "deepworks")
	assert_dict((line as Dictionary).get("tiers", {})).is_equal(want["tiers"])
	assert_array((line as Dictionary).get("solid_cells", [])).is_equal(want["solid_cells"])
	_main.restore_generated_board({})
	var flat: Variant = AiActRecorder._terrain_line(Callable(_main, "generated_board"))
	assert_bool((flat as Dictionary).has("tiers")).override_failure_message("a flat table carried tiers").is_false()
