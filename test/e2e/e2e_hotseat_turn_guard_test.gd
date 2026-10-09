extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.T2a "refuse off-turn verbs, show the turn chip": on a hotseat
## Automatic table (two humans at the board, no AI seat) the pure TwoHumanTurn state enforces one
## side per activation. A unit whose side is not on turn cannot Activate (the radial toggle) or
## Shoot/Fight/Cast/Pass — the refusal names the side on turn ("It is P2's turn"). A turn chip sits
## beside the rules chip and reads "Turn: P1" / "Turn: P2". Manual tables are untouched.
##
## Real: scenes/main.tscn, the real radial _toggle_activation, the real solo_begin_targeting, the
## real battle_log, the real _update_rules_chip.

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


## The real Activate door: the radial's manual activation toggle, then let its coroutine settle.
func _activate(unit: GameUnit) -> void:
	await _main.radial_menu_controller._toggle_activation({"game_unit": unit})
	await _runner.simulate_frames(4)
	await E2EBoot.settle(get_tree())


func _has_line(needle: String) -> bool:
	for e in _main.battle_log.entries():
		if str((e as Dictionary)["text"]).find(needle) != -1:
			return true
	return false


func test_p1_activates_then_p1_second_unit_is_refused(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(p1a)
	assert_bool(p1a.is_activated).override_failure_message("P1's first activation was not applied").is_true()
	# P1's SECOND unit belongs to the side that just acted — off-turn now.
	await _activate(p1b)
	assert_bool(p1b.is_activated) \
		.override_failure_message("step 2.T2a — P1 activated a second unit while off-turn") \
		.is_false()
	assert_bool(_has_line("It is P2's turn")) \
		.override_failure_message("step 2.T2a — the off-turn refusal did not name the side on turn") \
		.is_true()
	await E2EBoot.settle(get_tree())


func test_p2_may_activate_on_its_turn(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(p1a)
	await _activate(p2)
	assert_bool(p2.is_activated) \
		.override_failure_message("step 2.T2a — P2 was wrongly refused on its own turn") \
		.is_true()
	await E2EBoot.settle(get_tree())


func test_off_turn_shoot_is_refused(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _activate(p1a)
	await _main.solo_begin_targeting(p1b, false)   # the radial's Shoot entry, off-turn
	assert_bool(_main._solo_target_mode.is_empty()) \
		.override_failure_message("step 2.T2a — an off-turn Shoot opened targeting") \
		.is_true()
	assert_bool(_has_line("It is P2's turn")).is_true()
	await E2EBoot.settle(get_tree())


func test_the_turn_chip_follows_the_side_on_turn(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	_main._update_rules_chip()
	var chip = _main.get("_turn_chip")
	assert_object(chip) \
		.override_failure_message("step 2.T2a — no turn chip was built beside the rules chip") \
		.is_not_null()
	if chip == null:
		return   # base has no chip yet; fail cleanly instead of dereferencing null
	assert_str((chip as Label).text) \
		.override_failure_message("the turn chip must open on P1") \
		.is_equal("Turn: P1")
	await _activate(p1a)
	assert_str((chip as Label).text) \
		.override_failure_message("the turn chip must follow the side on turn (P2 after P1)") \
		.is_equal("Turn: P2")
	await E2EBoot.settle(get_tree())


func test_manual_tables_are_untouched(timeout := 120000) -> void:
	var p1a := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p1b := _register(1, "Guards", Vector3(0.0, 0.0, -0.3))
	# Default MANUAL: no turn guard, no chip.
	await _activate(p1b)   # would be off-turn only if the guard applied
	assert_bool(p1b.is_activated) \
		.override_failure_message("step 2.T2a — a Manual table was turn-guarded") \
		.is_true()
	var chip = _main.get("_turn_chip")
	var chip_visible := chip != null and (chip as Label).visible
	assert_bool(chip_visible) \
		.override_failure_message("the turn chip must not show on a Manual table") \
		.is_false()
	await E2EBoot.settle(get_tree())
