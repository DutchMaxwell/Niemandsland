extends GdUnitTestSuite
## RULES_AUTOMATION_PLAN step 2.4 "Controller without an AI side": on a hotseat Automatic table the
## resolvers still need the SoloController for GEOMETRY (cover, LOS, sandbox terrain), so it is built
## even with no AI seat — but the alternation stays OFF: no NACHTMAHR turn may ever follow a human
## attack, and the round stays on the plain hotseat branch (the Next Round button advances it).
##
## Real: scenes/main.tscn, the real radial entry solo_begin_targeting, the real _solo_pump and
## _do_next_round.

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


func test_targeting_builds_a_geometry_controller_without_the_alternation(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	assert_bool(_main.solo_ai_slots.is_empty()) \
		.override_failure_message("fixture: plain local table, no designation").is_true()
	_hotseat_automatic()
	await _main.solo_begin_targeting(p1, false)   # the radial's Shoot entry
	assert_object(_main.solo_controller) \
		.override_failure_message("step 2.4 — no geometry controller was built for the hotseat table") \
		.is_not_null()
	assert_bool(_main._solo_alternation_active()) \
		.override_failure_message("step 2.4 — a controller without an AI seat armed the alternation") \
		.is_false()
	await E2EBoot.settle(get_tree())


func test_pump_never_plays_an_ai_turn_without_an_ai_seat(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	_main._ensure_solo_controller()
	assert_object(_main.solo_controller) \
		.override_failure_message("step 2.4 — _ensure_solo_controller bailed on a hotseat Automatic table") \
		.is_not_null()
	await _main._solo_pump()
	assert_bool(p2.is_activated) \
		.override_failure_message("step 2.4 — NACHTMAHR took a turn on a table with no AI seat") \
		.is_false()
	assert_bool(p1.is_activated).is_false()
	await E2EBoot.settle(get_tree())


func test_p2_may_enter_targeting_and_no_ai_turn_follows(timeout := 120000) -> void:
	var p1 := _register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	var p2 := _register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	await _main.solo_begin_targeting(p2, false)   # P2 shoots back
	assert_object(_main.solo_controller).is_not_null()
	assert_bool(_main._solo_alternation_active()).is_false()
	assert_bool(p1.is_activated) \
		.override_failure_message("step 2.4 — an AI turn followed P2's targeting entry") \
		.is_false()
	await E2EBoot.settle(get_tree())


func test_the_next_round_button_stays_on_the_hotseat_branch(timeout := 120000) -> void:
	_register(1, "Rifles", Vector3(-0.3, 0.0, 0.0))
	_register(2, "Raiders", Vector3(0.3, 0.0, 0.0))
	_hotseat_automatic()
	_main._ensure_solo_controller()
	var before: int = _main.opr_army_manager.current_round
	await _main._do_next_round()
	assert_int(_main.opr_army_manager.current_round).is_equal(before + 1)
	assert_bool(_main._solo_alternation_active()).is_false()
	await E2EBoot.settle(get_tree())
