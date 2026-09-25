extends GdUnitTestSuite

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
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main.opr_army_manager.current_round = 2
	var holder := E2EBoot.make_unit(_main, 1, "Holder", [Vector3(0.03, 0, 0)])
	var arrival := E2EBoot.make_unit(_main, 2, "FreshAmbush", [Vector3(0.04, 0, 0)])
	arrival.unit_properties["ambush_arrived_round"] = 2
	_main.opr_army_manager.game_units[holder.unit_id] = holder
	_main.opr_army_manager.game_units[arrival.unit_id] = arrival


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str((entry as Dictionary)["text"]) + "\n"
	return out


func test_seize_line_explains_why_fresh_ambush_did_not_contest(timeout := 240000) -> void:
	_main.terrain_overlay.update_objectives([Vector3.ZERO], [0])
	_main._solo_auto_seize()
	assert_int(_main.terrain_overlay.get_objective_owner(0)).is_equal(1)
	assert_str(_log_text()).contains("Objective 1 seized by P1")
	assert_str(_log_text()).contains("FreshAmbush arrived from Ambush this round and cannot seize or contest")
	await E2EBoot.settle(get_tree())


func test_lock_is_logged_even_when_owner_does_not_change(timeout := 240000) -> void:
	_main.terrain_overlay.update_objectives([Vector3.ZERO], [1])
	_main._solo_auto_seize()
	assert_int(_main.terrain_overlay.get_objective_owner(0)).is_equal(1)
	assert_str(_log_text()).contains("FreshAmbush arrived from Ambush this round and cannot seize or contest")
	await E2EBoot.settle(get_tree())
