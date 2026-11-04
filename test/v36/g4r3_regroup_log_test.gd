extends GdUnitTestSuite
## G4R3 F-T-REGROUP-LOG (PARITY_DIAG_1104 D6, gf_1000_net_022 R4 act 27): a unit the casualties tore
## out of coherency spends its activation on the Regroup rule. The table did it, but wrote no battle-log
## line (11 of 30 recorded Regroup activations left the unit without a single line), so a replay reads
## the activation as a unit the table never played. From EPOCH_73_V36 the activation writes one line
## naming the rule. Driven through the real activation entry (`_solo_activate_one_ai`) over main.tscn;
## below EPOCH_73_V36 the old silence stands, so the epoch-72 control must stay green.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _epoch_before: int


func before_test() -> void:
	_epoch_before = AiActRecorder.rules_epoch
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch_before
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


## The AI's unit and one far-away human unit (nothing to charge or shoot into). `gap_m` is the distance
## between the AI unit's two models: 0.10 m (~3.9") is past the 1" coherency link, 0.02 m is inside it.
func _board(gap_m: float) -> GameUnit:
	var human := E2EBoot.make_unit(_main, 1, "Foes", [Vector3(0.0, 0.0, 1.0)])
	_main.opr_army_manager.game_units[human.unit_id] = human
	var ai := E2EBoot.make_unit(_main, 2, "Cyborgs", [Vector3.ZERO, Vector3(gap_m, 0.0, 0.0)])
	_main.opr_army_manager.game_units[ai.unit_id] = ai
	return ai


func test_a_torn_units_activation_names_the_regroup_rule(timeout := 60000) -> void:
	var ai := _board(0.10)
	assert_bool(_main.solo_controller.unit_coherent_now(ai)).is_false()
	var done: GameUnit = await _main._solo_activate_one_ai()
	assert_object(done).is_equal(ai)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("a forced Regroup writes a line naming the rule (log: %s)" % text.strip_edges()) \
		.contains("Regroup: Cyborgs starts its activation out of coherency")
	await E2EBoot.settle(get_tree())


func test_a_coherent_units_activation_writes_no_regroup_line(timeout := 60000) -> void:
	var ai := _board(0.02)
	assert_bool(_main.solo_controller.unit_coherent_now(ai)).is_true()
	var done: GameUnit = await _main._solo_activate_one_ai()
	assert_object(done).is_equal(ai)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("a coherent unit does not regroup (log: %s)" % text.strip_edges()) \
		.not_contains("Regroup:")
	await E2EBoot.settle(get_tree())


func test_the_epoch_72_control_keeps_the_silent_regroup(timeout := 60000) -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_72_PLAYTEST_RULES
	var ai := _board(0.10)
	var done: GameUnit = await _main._solo_activate_one_ai()
	assert_object(done).is_equal(ai)
	var text := _log_text()
	assert_str(text) \
		.override_failure_message("below 73 the recorded corpus keeps the silent Regroup (log: %s)" % text.strip_edges()) \
		.not_contains("Regroup:")
	await E2EBoot.settle(get_tree())
