extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.7a "Mend human door": a HUMAN Mend bearer now heals the wounded Tough
## model within 3" (the same auto-pick the AI uses) and rolls its D3 on the owner's OWN tray
## (`_owner_roll`) with one result line ("Mend: … heals …"). The book's wording is a plain instruction
## (no "may"), so Mend is automatic — no prompt. On a Manual table nothing fires (the human applies it
## by hand). The AI's own path is untouched.
##
## Real: scenes/main.tscn, the real radial activation door (_toggle_activation -> _on_solo_human_activated),
## the real _solo_apply_mend / _solo_mend_pick / _owner_roll, the real battle_log. Harness dice (_solo_batch).

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
	_main._solo_game_finished = false
	_main._solo_batch = true   # instant, non-physics dice (the harness dice seam)


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _register(pid: int, unit_name: String, at: Vector3, rules: Array = []) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [at, at + Vector3(0.03, 0.0, 0.0)])
	if not rules.is_empty():
		u.unit_properties["special_rules"] = rules
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _hotseat_automatic() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.AUTOMATIC


func _manual() -> void:
	_main.opr_army_manager.rules_automation = RulesAutomation.Level.MANUAL


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(8)
	await E2EBoot.settle(get_tree())


func _lines_with(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


## A wounded Tough ally (wounds_max 3, wounded down to 1) within 3" of the bearer.
func _wounded_ally(pid: int, unit_name: String, at: Vector3) -> GameUnit:
	var u := _register(pid, unit_name, at)
	var m := u.models[0] as ModelInstance
	m.wounds_max = 3
	m.wounds_current = 1
	m.is_alive = true
	return u


func test_a_human_mend_bearer_heals_a_wounded_tough_ally(timeout := 120000) -> void:
	var healer := _register(1, "Healer", Vector3(-0.3, 0.0, 0.0), ["Mend"])
	var ally := _wounded_ally(1, "ToughAlly", Vector3(0.3, 0.0, 0.0))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.3))
	_hotseat_automatic()
	await _activate(healer)
	var m := ally.models[0] as ModelInstance
	assert_int(m.wounds_current) \
		.override_failure_message("step 2.7a — the human Mend bearer did not heal the wounded Tough ally") \
		.is_greater(1)
	assert_int(_lines_with("Mend:")) \
		.override_failure_message("step 2.7a — no Mend result line was logged for the human bearer") \
		.is_equal(1)
	await E2EBoot.settle(get_tree())


func test_mend_does_not_fire_on_a_manual_table(timeout := 120000) -> void:
	var healer := _register(1, "Healer", Vector3(-0.3, 0.0, 0.0), ["Mend"])
	var ally := _wounded_ally(1, "ToughAlly", Vector3(0.3, 0.0, 0.0))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.3))
	_manual()
	await _activate(healer)
	var m := ally.models[0] as ModelInstance
	assert_int(m.wounds_current) \
		.override_failure_message("step 2.7a — Mend must not fire on a Manual table (applied by hand)") \
		.is_equal(1)
	assert_int(_lines_with("Mend:")) \
		.override_failure_message("step 2.7a — a Manual table logged a Mend line") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())