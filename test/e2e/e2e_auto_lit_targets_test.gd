extends GdUnitTestSuite
## E2E — Automodus rework step 1.6: entering Charge / Advance & Shoot / Rush lights exactly the
## enemies player_intent accepts (one amber ring each), refuses to enter with no candidate, and frees
## the rings on cancel (boot pattern: e2e_auto_charge_test.gd).

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")
const INCH := 0.0254

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
	_main._solo_fast = true


func after_test() -> void:
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)
	_main = null
	_runner = null


func _unit(pid: int, unit_name: String, pos: Vector3) -> GameUnit:
	var u := E2EBoot.make_unit(_main, pid, unit_name, [pos])
	var opr := OPRApiClient.OPRUnit.new()
	var ccw := OPRApiClient.OPRWeapon.new()
	ccw.name = "CCW"
	ccw.range_value = 0
	ccw.attacks = 1
	opr.weapons = [ccw]
	u.source_type = "opr"
	u.source_data = opr
	_main.opr_army_manager.game_units[u.unit_id] = u
	return u


func _log_text() -> String:
	var text := ""
	for e in _main.battle_log.entries():
		text += str((e as Dictionary)["text"]) + "\n"
	return text


func test_charge_lights_only_chargeable_enemies(timeout := 60000) -> void:
	var attacker := _unit(1, "Chargers", Vector3.ZERO)
	var near := _unit(2, "Near", Vector3(8.0 * INCH, 0, 0))
	_unit(2, "Far", Vector3(20.0 * INCH, 0, 0))
	await _main.solo_begin_auto(attacker, AiDecision.Action.CHARGE)
	assert_bool(_main._solo_target_mode.has("auto_valid")) \
		.override_failure_message("auto_valid missing: no target was lit") \
		.is_true()
	assert_array(_main._solo_target_mode.get("auto_valid", [])).contains_exactly([near])
	assert_int((_main._solo_target_mode.get("cast_rings", []) as Array).size()).is_equal(1)
	assert_bool(_main._solo_target_mode.get("auto_previews", {"missing": true}).is_empty()).is_true()
	assert_str(_log_text()).contains("1 target(s) lit for Charge")
	_main._solo_end_targeting()


func test_advance_lights_every_enemy(timeout := 60000) -> void:
	var attacker := _unit(1, "Movers", Vector3.ZERO)
	_unit(2, "Near", Vector3(8.0 * INCH, 0, 0))
	_unit(2, "Far", Vector3(20.0 * INCH, 0, 0))
	await _main.solo_begin_auto(attacker, AiDecision.Action.ADVANCE)
	assert_int((_main._solo_target_mode.get("auto_valid", []) as Array).size()).is_equal(2)
	assert_int((_main._solo_target_mode.get("cast_rings", []) as Array).size()).is_equal(2)
	_main._solo_end_targeting()


func test_shaken_unit_gets_no_mode_and_a_reason(timeout := 60000) -> void:
	var attacker := _unit(1, "Shaky", Vector3.ZERO)
	attacker.is_shaken = true
	_unit(2, "Near", Vector3(8.0 * INCH, 0, 0))
	await _main.solo_begin_auto(attacker, AiDecision.Action.RUSH)
	assert_bool(_main._solo_target_mode.is_empty()).is_true()
	assert_str(_log_text()).contains("no valid target for Rush (Shaken")


func test_cancel_frees_the_rings(timeout := 60000) -> void:
	var attacker := _unit(1, "Movers", Vector3.ZERO)
	_unit(2, "Near", Vector3(8.0 * INCH, 0, 0))
	await _main.solo_begin_auto(attacker, AiDecision.Action.ADVANCE)
	var rings: Array = (_main._solo_target_mode.get("cast_rings", []) as Array).duplicate()
	assert_int(rings.size()).is_equal(1)
	_main._solo_end_targeting()
	await _runner.simulate_frames(2)
	for r in rings:
		assert_bool(is_instance_valid(r)).is_false()
