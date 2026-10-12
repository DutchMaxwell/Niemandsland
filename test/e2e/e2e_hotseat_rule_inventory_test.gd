extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.9 "Engine inventory for both armies": at game start in a hotseat
## Automatic table (two humans, no AI seat), the rule inventory is logged for EACH human army, headed
## "Rules the engine applies (Px)" with an "apply by hand" tail — so each player sees what the engine
## will run and what they must run themselves. A Manual table logs nothing. The AI-seat handoff line
## ("AI rule inventory") is unchanged and never appears on a hotseat table.
##
## Real: scenes/main.tscn, the real game_phase_changed seam (_on_game_phase_changed), the real
## opr_army_manager.start_game(), the real _solo_log_rule_inventory, the real battle_log.

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
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.DEPLOYMENT
	_main.opr_army_manager.current_round = 1
	_main._solo_game_finished = false
	_main._solo_batch = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [Vector3(0.0, 0.0, 0.0)])
	if not rules.is_empty():
		u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _lines_with(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


func test_hotseat_automatic_logs_inventory_for_each_human_army(timeout := 120000) -> void:
	_register(1, "P1 Squad", ["Breath Attack"])
	_register(2, "P2 Squad", ["Hit & Run"])
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC
	_main.opr_army_manager.start_game()
	await _runner.simulate_frames(2)
	assert_int(_lines_with("Rules the engine applies (P1)")) \
		.override_failure_message("step 2.9 — no inventory line for the P1 human army") \
		.is_equal(1)
	assert_int(_lines_with("Rules the engine applies (P2)")) \
		.override_failure_message("step 2.9 — no inventory line for the P2 human army") \
		.is_equal(1)
	assert_int(_lines_with("apply by hand")) \
		.override_failure_message("step 2.9 — the human inventory line is missing its 'apply by hand' tail") \
		.is_equal(2)
	assert_int(_lines_with("AI rule inventory")) \
		.override_failure_message("step 2.9 — the AI-seat inventory line leaked onto a hotseat table") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_manual_table_logs_no_inventory(timeout := 120000) -> void:
	_register(1, "P1 Squad", ["Breath Attack"])
	_register(2, "P2 Squad", ["Hit & Run"])
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL
	_main.opr_army_manager.start_game()
	await _runner.simulate_frames(2)
	assert_int(_lines_with("Rules the engine applies")) \
		.override_failure_message("step 2.9 — a Manual table logged the engine inventory") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
