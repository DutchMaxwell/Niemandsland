extends GdUnitTestSuite
## E2E — D76/W3-6 (a), PLAN_wave3_2026-09-27.md step 26: NML-1100. `_solo_tray_roll`'s headless
## (`_solo_batch`) path burned one die on a `count == 0` request (`for _di in maxi(1, count)`) — a
## UI guard that leaked into the rules-path RNG stream. From this fix the request is taken
## literally: zero dice draws nothing, so the tray's NEXT roll reads the stream's first faces
## instead of its second.

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
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_a_zero_die_roll_draws_nothing_and_the_next_roll_reads_the_streams_first_faces() -> void:
	_main.seed_tray_rng(27)
	var zero: Array = await _main._solo_tray_roll(0, 4, "AI (probe)")
	assert_array(zero) \
		.override_failure_message("D76 a: a zero-die request must draw nothing — got %s" % [zero]) \
		.is_empty()
	var next_roll: Array = await _main._solo_tray_roll(4, 4, "AI (probe)")

	_main.seed_tray_rng(27)
	var straight: Array = await _main._solo_tray_roll(4, 4, "AI (probe)")

	assert_array(next_roll) \
		.override_failure_message("the zero-die roll must not burn a stream position — got %s, want %s" % [next_roll, straight]) \
		.is_equal(straight)
