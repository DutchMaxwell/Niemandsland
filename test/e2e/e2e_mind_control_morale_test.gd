extends GdUnitTestSuite
## D16: Mind Control and Fatigue Debuff use the target's full morale test.

const Boot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _roots: Array


func before_test() -> void:
	Boot.arm_harness_mode()
	_roots = Boot.root_children(get_tree())
	_runner = scene_runner(Boot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)
	_main.solo_ai_slots = {2: true}
	_main._ensure_solo_controller()
	_main.opr_army_manager.game_phase = OPRArmyManager.GamePhase.PLAYING
	_main._solo_batch = true


func after_test() -> void:
	Boot.free_stray_root_nodes(get_tree(), _roots)
	_main = null
	_runner = null


func _pair(rule: String, faction: String = "jackals") -> Array:
	var bearer := Boot.make_unit(_main, 2, "Controller", [Vector3.ZERO])
	bearer.unit_properties["game_system"] = "gf"
	bearer.unit_properties["faction_folder"] = faction
	bearer.unit_properties["special_rules"] = [rule]
	var target := Boot.make_unit(_main, 1, "Victim", [Vector3(0.05, 0, 0)])
	_main.opr_army_manager.game_units[bearer.unit_id] = bearer
	_main.opr_army_manager.game_units[target.unit_id] = target
	return [bearer, target]


func _seed_for(first_below: int, second_at_least: int = 0) -> int:
	var rng := RandomNumberGenerator.new()
	for seed in range(100):
		rng.seed = seed
		var first := rng.randi_range(1, 6)
		var second := rng.randi_range(1, 6)
		if first < first_below and (second_at_least == 0 or second >= second_at_least):
			return seed
	return -1


func _log_text() -> String:
	var out := ""
	for entry in _main.battle_log.entries():
		out += str(entry["text"]) + "\n"
	return out


func test_shaken_target_auto_fails_mind_control_without_a_die() -> void:
	var pair := _pair("Mind Control")
	var target := pair[1] as GameUnit
	target.is_shaken = true
	_main.seed_tray_rng(3)
	var rng_before: int = _main._tray_rng.state
	await _main._solo_apply_mind_control(pair[0])
	assert_int(_main._tray_rng.state).is_equal(rng_before)
	assert_float((target.models[0] as ModelInstance).node.global_position.x).is_greater(0.05)
	assert_str(_log_text()).contains("Mind Control: Victim fails the morale test — Shaken")


func test_failed_mind_control_shakes_before_moving() -> void:
	var pair := _pair("Mind Control")
	var target := pair[1] as GameUnit
	target.unit_properties["quality"] = 6
	var seed := _seed_for(6)
	assert_int(seed).is_greater_equal(0)
	_main.seed_tray_rng(seed)
	await _main._solo_apply_mind_control(pair[0])
	assert_bool(target.is_shaken).is_true()
	assert_float((target.models[0] as ModelInstance).node.global_position.x).is_greater(0.05)
	assert_str(_log_text()).contains("Mind Control: Victim fails the morale test — Shaken, moved")


func test_fearless_recovery_prevents_mind_control_effect() -> void:
	var pair := _pair("Mind Control")
	var target := pair[1] as GameUnit
	target.unit_properties["quality"] = 6
	target.unit_properties["special_rules"] = ["Fearless"]
	var seed := _seed_for(6, 4)
	assert_int(seed).is_greater_equal(0)
	_main.seed_tray_rng(seed)
	await _main._solo_apply_mind_control(pair[0])
	assert_bool(target.is_shaken).is_false()
	assert_float((target.models[0] as ModelInstance).node.global_position.x).is_equal_approx(0.05, 0.0001)
	assert_str(_log_text()).contains("Fearless — recovery die")


func test_fatigue_debuff_failure_also_shakes_the_target() -> void:
	var pair := _pair("Fatigue Debuff", "wormhole_daemons_of_war")
	var target := pair[1] as GameUnit
	target.unit_properties["quality"] = 6
	_main.seed_tray_rng(_seed_for(6))
	await _main._solo_apply_mind_control(pair[0])
	assert_bool(target.is_shaken).is_true()
	assert_bool(target.is_fatigued).is_true()
