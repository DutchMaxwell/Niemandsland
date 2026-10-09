extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.6b "Round start: recovery for both sides": at the start of a hotseat
## Automatic round a Shaken unit with Battleborn/Steadfast rolls its recovery die on its OWN owner's
## tray (`_owner_roll`) and gets one result line ("recovers from Shaken (4+)" / "stays Shaken") —
## instead of the old human reminder line ("roll for X to recover from Shaken"). The AI's own branch is
## untouched. This deliberately changes the human side of solo too: its Shaken Battleborn units now roll
## and may clear Shaken automatically.
##
## Real: scenes/main.tscn, the real radial activation door, the real round start (_hotseat_start_round),
## the real _solo_battleborn_recovery / _owner_roll, the real battle_log. Harness dice (_solo_batch).

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


func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


func _lines_with(needle: String) -> int:
	var n := 0
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			n += 1
	return n


func test_a_shaken_battleborn_unit_rolls_at_the_hotseat_round_start(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Brothers", Vector3(0.3, 0.0, 0.0), ["Battleborn"])
	p2.is_shaken = true
	_hotseat_automatic()
	await _activate(p1)
	await _activate(p2)   # both spent -> round 2 begins; the round-start recovery runs
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("step 2.6b — the round did not advance").is_equal(2)
	var recovered := _lines_with("recovers from Shaken")
	var stayed := _lines_with("stays Shaken")
	assert_int(recovered + stayed) \
		.override_failure_message("step 2.6b — the human side's Battleborn unit did not roll a result line") \
		.is_equal(1)
	assert_int(_lines_with("roll for")) \
		.override_failure_message("step 2.6b — the old human reminder line is still logged") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())


func test_a_shaken_unit_without_a_recovery_rule_does_not_roll(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	p2.is_shaken = true
	_hotseat_automatic()
	await _activate(p1)
	await _activate(p2)
	assert_int(_main.opr_army_manager.current_round) \
		.override_failure_message("step 2.6b — the round did not advance").is_equal(2)
	assert_bool(p2.is_shaken) \
		.override_failure_message("step 2.6b — a plain Shaken unit must stay Shaken (no recovery rule)") \
		.is_true()
	assert_int(_lines_with("recovers from Shaken") + _lines_with("stays Shaken")) \
		.override_failure_message("step 2.6b — a unit without the rule rolled a recovery") \
		.is_equal(0)
	await E2EBoot.settle(get_tree())
