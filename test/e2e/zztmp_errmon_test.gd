extends GdUnitTestSuite
const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const OFFSET := Vector3(0.0, 0.0, 10.0)
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
	_main = null
	_runner = null

func test_ai_move_choreography_raises_no_engine_error(timeout := 120000) -> void:
	_main._solo_batch = true
	_main._solo_fast = true
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.position = OFFSET
	var u := E2EBoot.make_unit(_main, 2, "Nachtzehrer", [Vector3(-0.4, 0.0, -0.3)])
	var paths := [{"model": u.models[0], "path": [Vector3(-0.4, 0.0, -0.3), Vector3(-0.15, 0.0, -0.025), Vector3(0.1, 0.0, 0.25)], "radius_m": 0.0125}]
	await assert_error(func() -> void:
		await _main._solo_animate_move(paths)
	).is_success()
