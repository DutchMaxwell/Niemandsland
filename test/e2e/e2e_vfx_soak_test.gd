extends GdUnitTestSuite
## E2E — combat effects leave nothing behind: 200 full bursts (a 10-tracer volley, 10 crosses, a hit/save
## strip, a seal that forms, dims and ends) through the production cue path never hold more nodes than the
## presenters' caps, and once the last tween ran out every presenter is empty and no seal is still tracked.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const BURSTS := 200

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	for fx in [_main.result_pips, _main.volley_cue, _main.spell_seal]:
		fx.force_for_tests = true
		fx.enabled = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func test_two_hundred_bursts_leave_no_nodes_behind(timeout := 240000) -> void:
	var pairs: Array = []
	for i in 10:
		pairs.append([Vector3(0.03 * i, 0.03, 0), Vector3(0.03 * i, 0.03, 0.3)])
	var peak := 0
	for b in BURSTS:
		var sid: int = _main._vfx_emit({"k": "seal", "at": Vector3.ZERO, "r": 0.3, "kind": "damage"})
		_main._vfx_emit({"k": "seal_dim", "sid": sid})
		_main._vfx_emit({"k": "volley", "f": 1, "pairs": pairs})
		_main._vfx_emit({"k": "pip", "t": 2, "at": Vector3(0, 0.05, 0.3), "n": 7})
		_main._vfx_emit({"k": "pip", "t": 3, "at": Vector3(0, 0.07, 0.3), "n": 3})
		for i in 10:
			_main._vfx_emit({"k": "pip", "t": 1, "at": Vector3(0.03 * i, 0.03, 0.3), "n": 1})
		_main._vfx_emit({"k": "seal_end", "sid": sid, "o": b % 2})
		peak = maxi(peak, _main.result_pips.get_child_count() + _main.volley_cue.get_child_count())
		await get_tree().process_frame
	assert_int(_main.result_pips.get_child_count()).is_less_equal(ResultPips.MAX_LIVE)
	assert_int(_main.volley_cue.get_child_count()).is_less_equal(VolleyCue.MAX_LIVE)
	assert_int(peak).is_less_equal(ResultPips.MAX_LIVE + VolleyCue.MAX_LIVE)
	await get_tree().create_timer(ResultPips.LIFE_S + 1.0).timeout
	assert_int(_main.result_pips.get_child_count() + _main.volley_cue.get_child_count()
		+ _main.spell_seal.get_child_count()).override_failure_message("a cue outlived its tween").is_equal(0)
	assert_int((_main._vfx_seals as Dictionary).size()).is_equal(0)
	assert_int((_main._vfx_seen as Dictionary).size()).is_less_equal(513)
