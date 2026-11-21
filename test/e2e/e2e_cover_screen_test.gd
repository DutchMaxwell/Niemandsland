extends GdUnitTestSuite
## E2E — PLAN_COVER_36 step 9b: the table reads cover from sight blockers through the volley latch (`_solo_screen_open`) from
## epoch 95. A gun line 2" up looks over a closed line of a third unit (models under 1" apart) at a squad 2" behind it: heads
## seen, feet hidden -> the dice reader `_solo_cover_defense` gives +1; at 94 it does not. The latch is keyed by target: a
## second unit equally behind the wall reads nothing from this volley's latch. RED: `_solo_cover_defense` without the screen
## half gives the squad no +1.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const IN := 0.0254

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_epoch_before = AiActRecorder.rules_epoch
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, xs: Array, z_in: float, y_m := 0.0) -> GameUnit:
	var pts: Array = []
	for x in xs:
		pts.append(Vector3(float(x) * IN, y_m, z_in * IN))
	var u := E2EBoot.make_unit(_main, pid, unit_name, pts)
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _board() -> Dictionary:
	return {"guns": _unit(2, "Gun Line", [0, 2, 4], 0.0, 0.05), "squad": _unit(1, "Squad", [0, 2, 4], 12.0),
		"wall": _unit(1, "Wall", [-2, -0.5, 1, 2.5, 4, 5.5], 10.0)}


func test_a_squad_behind_a_closed_unit_line_takes_cover_at_95_only() -> void:
	var b := _board()
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH
	_main._solo_screen_open(b["guns"], b["squad"])
	assert_bool(bool(_main._solo_screen.get("screened", false))).override_failure_message("heads over the wall, feet behind it").is_true()
	assert_int(_main._solo_cover_defense(b["squad"], 4)).is_equal(3)
	_main._solo_screen = {}
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH - 1
	_main._solo_screen_open(b["guns"], b["squad"])
	assert_bool(_main._solo_screen.is_empty()).override_failure_message("below 95 no latch opens").is_true()
	assert_int(_main._solo_cover_defense(b["squad"], 4)).is_equal(4)


func test_the_latch_answers_only_its_own_target_and_closes() -> void:
	var b := _board()
	var other := _unit(1, "Other Squad", [1, 3], 12.0)
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH
	_main._solo_screen_open(b["guns"], b["squad"])
	assert_bool(_main._solo_screened(other)).override_failure_message("a stale latch must not cover another target").is_false()
	assert_int(_main._solo_cover_defense(other, 4)).is_equal(4)
	_main._solo_screen = {}
	assert_bool(_main._solo_screened(b["squad"])).override_failure_message("a closed latch covers nobody").is_false()


func test_without_the_wall_nobody_is_behind_anything() -> void:
	var b := _board()
	for m in (b["wall"] as GameUnit).models:
		(m as ModelInstance).node.global_position.z = 40.0 * IN
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_95_PARITY_BATCH
	_main._solo_screen_open(b["guns"], b["squad"])
	assert_bool(bool(_main._solo_screen.get("screened", true))).is_false()
	assert_int(_main._solo_cover_defense(b["squad"], 4)).is_equal(4)
