extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.T3 (hand-over): after an activation completes on a hotseat Automatic
## table the turn passes with one battle-log line ("P2 to activate"); when the other side has no
## eligible unit left the same side keeps activating and the line says so
## ("P2 has no units left — P1 keeps activating"); when both sides are spent there is no hand-over
## line (the round end is step 2.6a). The turn chip follows.
##
## Real: scenes/main.tscn, the real radial _toggle_activation, the real battle_log.

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
	_main.opr_army_manager.current_round = 1


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


func _count_lines(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


func test_the_turn_passes_with_one_line(timeout := 120000) -> void:
	var p1 := _register(1, "Alpha Squad", Vector3(-0.3, 0.0, 0.0))
	_register(2, "Bravo Squad", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(p1)
	assert_int(_count_lines("P2 to activate")) \
		.override_failure_message("step 2.T3 — the completed activation did not hand the turn to P2") \
		.is_equal(1)


func test_the_same_side_keeps_activating_when_the_other_is_empty(timeout := 120000) -> void:
	var p1a := _register(1, "Alpha Squad", Vector3(-0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	_hotseat_automatic()
	await _activate(p1a)
	assert_int(_count_lines("P2 has no units left — P1 keeps activating")) \
		.override_failure_message("step 2.T3 — an empty P2 did not TAIL back to P1 with the reason") \
		.is_equal(1)
	# TAIL: P1 keeps activating — the second unit is NOT refused.
	await _activate(p1b)
	assert_bool(p1b.is_activated) \
		.override_failure_message("step 2.T3 — TAIL did not keep P1 on turn") \
		.is_true()


func test_no_handover_line_when_both_sides_are_spent(timeout := 120000) -> void:
	var p1 := _register(1, "Alpha Squad", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Bravo Squad", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(p1)
	await _activate(p2)
	assert_int(_count_lines("to activate")) \
		.override_failure_message("step 2.T3 — a hand-over line was logged after the round was spent") \
		.is_equal(1)   # only the first hand-over (P1 -> P2); the round end is step 2.6a
	assert_int(_count_lines("keeps activating")).is_equal(0)
