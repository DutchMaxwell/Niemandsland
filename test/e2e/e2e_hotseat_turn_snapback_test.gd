extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.T2b (Q7 = snap back): on a hotseat Automatic table during the PLAYING
## phase, a DRAG of a unit whose side is not on turn returns every dragged model to its pre-drag
## position on release (the same restore the drop refusal uses) with one line naming the side on turn
## ("Bravo Squad is not on turn — moved back"). No wound, marker or activation changes; an on-turn drag
## and a Manual table are untouched; the deployment phase stays free.
##
## Real: scenes/main.tscn, the real ObjectManager._stop_dragging release path, the real battle_log.

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


func _level(level: int) -> void:
	_main.opr_army_manager.rules_automation = level


## Drive the real release seam: the object manager has the drag state a pickup would have set, then
## `_stop_dragging()` runs the ordinary drop (commit) or the step 2.T2b snap-back.
func _drag(u: GameUnit, from: Vector3, to: Vector3) -> Node3D:
	var om: ObjectManager = _main.object_manager
	var node: Node3D = u.models[0].node
	om._selected_objects = [node]
	om._drag_start_positions[node] = from
	om._drag_start_rotations[node] = node.rotation.y
	om._drag_anchor_object = node
	om._drag_anchor_position = from
	om._drag_path_points = PackedVector2Array([Vector2(from.x, from.z), Vector2(to.x, to.z)])
	om._is_dragging = true
	node.global_position = to
	om._stop_dragging()
	await E2EBoot.settle(get_tree())
	return node


func _has_line(needle: String) -> bool:
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			return true
	return false


func test_off_turn_drag_snaps_back_with_one_line(timeout := 120000) -> void:
	var p1 := _register(1, "Alpha Squad", Vector3(-0.5, 0.0, 0.0))
	var p2 := _register(2, "Bravo Squad", Vector3(0.5, 0.0, 0.5))
	_level(RulesAutomation.Level.AUTOMATIC)
	var from := Vector3(0.5, 0.0, 0.5)
	var to := Vector3(0.9, 0.0, 0.9)
	var node := await _drag(p2, from, to)   # P2 is off-turn while P1 opens the round
	assert_vector(node.global_position) \
		.override_failure_message("step 2.T2b — an off-turn drag did not snap back to its pre-drag position") \
		.is_equal_approx(from, Vector3.ONE * 0.0001)
	assert_bool(_has_line("Bravo Squad is not on turn — moved back")) \
		.override_failure_message("step 2.T2b — the snap-back did not name the unit and the turn") \
		.is_true()
	assert_bool(p2.is_activated) \
		.override_failure_message("step 2.T2b — the refused drag changed the activation state") \
		.is_false()
	assert_bool(p1.is_activated).is_false()


func test_on_turn_drag_is_unchanged(timeout := 120000) -> void:
	var p1 := _register(1, "Alpha Squad", Vector3(-0.5, 0.0, 0.0))
	_register(2, "Bravo Squad", Vector3(0.5, 0.0, 0.5))
	_level(RulesAutomation.Level.AUTOMATIC)
	var from := Vector3(-0.5, 0.0, 0.0)
	var to := Vector3(-0.9, 0.0, -0.2)
	var node := await _drag(p1, from, to)   # P1 opens the round: on turn
	assert_float(node.global_position.x) \
		.override_failure_message("step 2.T2b — an on-turn drag was wrongly snapped back") \
		.is_equal_approx(to.x, 0.001)
	assert_float(node.global_position.z).is_equal_approx(to.z, 0.001)
	assert_bool(_has_line("is not on turn — moved back")) \
		.override_failure_message("step 2.T2b — an on-turn drag produced a snap-back line") \
		.is_false()


func test_manual_table_drag_is_unchanged(timeout := 120000) -> void:
	_register(1, "Alpha Squad", Vector3(-0.5, 0.0, 0.0))
	var p2 := _register(2, "Bravo Squad", Vector3(0.5, 0.0, 0.5))
	_level(RulesAutomation.Level.MANUAL)
	var from := Vector3(0.5, 0.0, 0.5)
	var to := Vector3(0.9, 0.0, 0.9)
	var node := await _drag(p2, from, to)   # Manual: no guard, P2 may move
	assert_float(node.global_position.x) \
		.override_failure_message("step 2.T2b — a Manual table was turn-guarded") \
		.is_equal_approx(to.x, 0.001)
	assert_float(node.global_position.z).is_equal_approx(to.z, 0.001)
	assert_bool(_has_line("is not on turn — moved back")).is_false()


func test_deployment_drag_is_free(timeout := 120000) -> void:
	_register(1, "Alpha Squad", Vector3(-0.5, 0.0, 0.0))
	var p2 := _register(2, "Bravo Squad", Vector3(0.5, 0.0, 0.5))
	_level(RulesAutomation.Level.AUTOMATIC)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	var from := Vector3(0.5, 0.0, 0.5)
	var to := Vector3(0.9, 0.0, 0.9)
	var node := await _drag(p2, from, to)   # deployment stays free in Automatic
	assert_float(node.global_position.x) \
		.override_failure_message("step 2.T2b — an Automatic deployment drag was turn-guarded") \
		.is_equal_approx(to.x, 0.001)
	assert_float(node.global_position.z).is_equal_approx(to.z, 0.001)
	assert_bool(_has_line("is not on turn — moved back")).is_false()
