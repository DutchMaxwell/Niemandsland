extends GdUnitTestSuite

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


func _unit(rules: Array, system: String, faction: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "rule_%d" % rules.size()
	u.unit_properties = {"player_id": 2, "name": "Fixture", "quality": 4, "defense": 2,
		"special_rules": rules, "game_system": system, "faction_folder": faction}
	var model := ModelInstance.new()
	model.is_alive = true
	u.models.append(model)
	return u


func test_takedown_when_shooting_stamps_only_ranged_profiles() -> void:
	var unit := _unit(["Takedown when Shooting"], "aof", "saurians")
	for reach in [0, 24]:
		var profiles := AiEv.stamp_sergeant([
			{"range": reach, "attacks": 3, "count": 1, "rules": []}], unit)
		assert_int(profiles.size()).is_equal(1)
		assert_int(profiles[0]["attacks"]).is_equal(3)
		assert_bool(bool(profiles[0].get("takedown", false))).is_equal(reach > 0)
	assert_bool(RulesRegistry.has_primitive("aof", "saurians", "Takedown when Shooting")).is_true()


func test_takedown_when_shooting_never_creates_a_bonus_attack() -> void:
	var unit := _unit(["Takedown when Shooting"], "aof", "saurians")
	assert_array(_main._solo_takedown_bonus_groups(unit, false)).is_empty()
	assert_array(_main._solo_takedown_bonus_groups(unit, true)).is_empty()
	assert_bool(unit.unit_properties.has("takedown_bonus_used_Takedown when Shooting")).is_false()


func test_takedown_when_shooting_named_pick_keeps_wounds_on_one_model() -> void:
	var unit := _unit(["Takedown when Shooting"], "aof", "saurians")
	var target := Boot.make_unit(_main, 1, "Target", [Vector3.ZERO, Vector3(0.1, 0, 0)])
	for model in target.models:
		model.wounds_current = 1
	var start: int = _main.battle_log.entries().size()
	var pick: Dictionary = await _main._solo_takedown_pick(unit, target, "Rifle")
	assert_bool(pick.is_empty()).is_false()
	if pick.is_empty():
		return
	await _main._solo_land_takedown_wounds(target, "Rifle", pick, 0, 6)
	assert_int(target.get_alive_count()).is_equal(1)
	assert_bool((pick["model"] as ModelInstance).is_alive).is_false()
	var text := ""
	for entry in _main.battle_log.entries().slice(start):
		text += str(entry["text"]) + "\n"
	assert_str(text).contains("Takedown when Shooting")
