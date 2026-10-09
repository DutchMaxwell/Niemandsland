extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.6c "Round start: Ambush for two humans" (re-cut): on a hotseat Automatic
## table there is no AI seat to arrive its Ambushers, so BOTH human sides are asked to place their
## reserve units, ordered by the turn state — the opener's side first, then the other. Manual tables and
## the solo path are untouched.
##
## Real: scenes/main.tscn, the real SoloController reserve helpers, the real _solo_ambush_human_turn
## prompt (the "keep waiting" button), the real battle_log.

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _reserve_unit(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	u.unit_properties["ambush_reserve"] = true
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _line_index(needle: String) -> int:
	var entries: Array = _main.battle_log.entries()
	for i in range(entries.size()):
		if str((entries[i] as Dictionary)["text"]).find(needle) != -1:
			return i
	return -1


func _keep_waiting() -> void:
	_main._solo_deploy_ui_btn2.pressed.emit()


func test_the_opener_side_is_prompted_first(timeout := 120000) -> void:
	_reserve_unit(1, "P1Reserve", Vector3(-2.0, 0.0, 0.0))
	_reserve_unit(2, "P2Reserve", Vector3(-2.0, 0.0, 0.3))
	_hotseat_automatic()
	_main._ensure_solo_controller()
	# P2 opens the round (P1 took the last activation). The arrival step asks P2 first, then P1.
	_main._hotseat_ambush_arrivals(2, 2)
	await _runner.simulate_frames(4)
	_keep_waiting()
	await _runner.simulate_frames(4)
	_keep_waiting()
	await _runner.simulate_frames(6)

	var p2_i := _line_index("P2 Ambush")
	var p1_i := _line_index("P1 Ambush")
	assert_int(p2_i) \
		.override_failure_message("step 2.6c — the opener's side was not announced").is_greater_equal(0)
	assert_int(p1_i) \
		.override_failure_message("step 2.6c — the second side was not announced").is_greater_equal(0)
	assert_int(p2_i) \
		.override_failure_message("step 2.6c — the non-opener was prompted before the opener").is_less(p1_i)
	await E2EBoot.settle(get_tree())


func test_a_side_without_reserves_is_not_prompted(timeout := 120000) -> void:
	_reserve_unit(2, "P2Reserve", Vector3(-2.0, 0.0, 0.3))
	_hotseat_automatic()
	_main._ensure_solo_controller()
	_main._hotseat_ambush_arrivals(2, 2)
	await _runner.simulate_frames(4)
	# Only P2 has a reserve; after P2's prompt there is no P1 prompt to dismiss.
	_keep_waiting()
	await _runner.simulate_frames(6)
	assert_int(_line_index("P2 Ambush")) \
		.override_failure_message("step 2.6c — P2's reserve was not announced").is_greater_equal(0)
	assert_int(_line_index("P1 Ambush")) \
		.override_failure_message("step 2.6c — a side with no reserves was prompted").is_equal(-1)
	await E2EBoot.settle(get_tree())
