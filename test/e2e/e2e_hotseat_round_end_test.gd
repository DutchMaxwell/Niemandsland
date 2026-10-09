extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.6a "Automatic round end": on a hotseat Automatic table (two humans,
## no AI seat) the round ends by itself the moment neither side has an eligible unit left — the same
## end-of-round truth as solo: objectives are seized, mission VP is booked (with a mission picked) and
## the round advances (or the summary shows after SOLO_GAME_ROUNDS). The side that did NOT take the
## round's last activation opens the next round. The Next Round button is disabled while any unit still
## has to act. Manual tables stay free: no auto-advance, no disabled button.
##
## Real: scenes/main.tscn, the real radial _toggle_activation, the real _solo_auto_seize /
## _solo_book_mission_vp, the real advance_round, the real battle_log.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _scoring_before: String
var _vp_before: Array
var _markers_before: Array


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_scoring_before = SoloController.mission_scoring
	_vp_before = SoloController.mission_vp.duplicate()
	_markers_before = SoloController.mission_markers.duplicate(true)
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 1
	_main._solo_game_finished = false


func after_test() -> void:
	SoloController.mission_scoring = _scoring_before
	SoloController.mission_vp = _vp_before
	SoloController.mission_markers = _markers_before
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


func _has_line(needle: String) -> bool:
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			return true
	return false


func test_the_last_activation_ends_the_round_and_the_other_side_opens(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	_hotseat_automatic()
	await _activate(p1a)          # P1 opens
	assert_int(_main.opr_army_manager.current_round).override_failure_message(
		"step 2.6a — the round advanced before both sides were spent").is_equal(1)
	await _activate(p2)           # P2 answers; P1 still has Guards -> TAIL back to P1
	await _activate(p1b)          # P1's last unit -> the round is over
	assert_int(_main.opr_army_manager.current_round).override_failure_message(
		"step 2.6a — the round did not advance when both sides were spent").is_equal(2)
	assert_bool(_has_line("Round 2 begins")).override_failure_message(
		"step 2.6a — no round-start line was logged").is_true()
	assert_bool(p1b.is_activated).override_failure_message(
		"step 2.6a — the spent activations were not reset by the new round").is_false()
	# P1 took the round's last activation -> P2 opens round 2.
	assert_int(_main._hotseat_turn.side_on_turn).override_failure_message(
		"step 2.6a — the wrong side opens the new round").is_equal(2)
	await E2EBoot.settle(get_tree())


func test_a_mission_books_its_vp_at_the_hotseat_round_end(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	SoloController.mission_scoring = "round_vp"
	SoloController.mission_vp = [0, 0]
	await _activate(p1)
	await _activate(p2)           # both spent -> round end books the round's VP
	assert_bool(_has_line("Mission VP after round 1")).override_failure_message(
		"step 2.6a — the mission VP was not booked at the hotseat round end").is_true()
	await E2EBoot.settle(get_tree())


func test_the_next_round_button_is_disabled_while_a_unit_remains(timeout := 120000) -> void:
	_register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	_main._update_round_button()
	var btn: Button = _main.next_round_btn
	assert_bool(btn.disabled).override_failure_message(
		"step 2.6a — the Next Round button is live while units still have to act").is_true()
	assert_bool(str(btn.tooltip_text).find("the round ends when every unit has acted") != -1) \
		.override_failure_message("step 2.6a — the disabled button does not say why").is_true()
	await _activate(p1b)
	assert_bool(btn.disabled).override_failure_message(
		"step 2.6a — the button went live while a unit remained").is_true()
	await E2EBoot.settle(get_tree())


func test_manual_tables_do_not_auto_advance(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	await _activate(p1)
	await _activate(p2)
	assert_int(_main.opr_army_manager.current_round).override_failure_message(
		"step 2.6a — a Manual table advanced by itself").is_equal(1)
	assert_bool(p2.is_activated).override_failure_message(
		"step 2.6a — a Manual table was reset like an Automatic one").is_true()
	var btn: Button = _main.next_round_btn
	assert_bool(btn.disabled if btn != null else false).override_failure_message(
		"step 2.6a — a Manual table had its Next Round button disabled").is_false()
	await E2EBoot.settle(get_tree())
