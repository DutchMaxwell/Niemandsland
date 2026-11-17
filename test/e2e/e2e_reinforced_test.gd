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


const CONTEXTS := [["gf", "custodian_brothers"], ["gf", "prime_brothers"],
	["aof", "eternal_wardens"], ["aof", "ossified_undead"]]


func test_reinforced_ev_obeys_distance_and_attack_gates() -> void:
	for context in CONTEXTS:
		var unit := _unit(["Reinforced"], context[0], context[1])
		unit.unit_properties["defense"] = 4
		for reach in [0, 24]:
			for distance in [-1.0, 9.0, 9.01]:
				var profile := {"range": reach, "attacks": 12, "ap": 2, "rules": []}
				var expected := 4.0 if distance > 9.0 else 5.0
				assert_float(AiEv.profile_ev(profile, {"quality": 4}, AiEv.ctx_for(unit), distance, reach == 0)) \
					.is_equal_approx(expected, 0.0001)


func test_reinforced_ev_requires_every_living_attached_member() -> void:
	var unit := _unit(["Reinforced"], "gf", "prime_brothers")
	unit.unit_properties["defense"] = 4
	var hero := _unit([], "gf", "prime_brothers")
	unit.unit_properties["attached_heroes"] = [hero]
	var profile := {"range": 24, "attacks": 12, "ap": 2, "rules": []}
	assert_float(AiEv.profile_ev(profile, {"quality": 4}, AiEv.ctx_for(unit), 12.0, false)) \
		.is_equal_approx(5.0, 0.0001)
	hero.unit_properties["special_rules"] = ["Reinforced"]
	assert_float(AiEv.profile_ev(profile, {"quality": 4}, AiEv.ctx_for(unit), 12.0, false)) \
		.is_equal_approx(4.0, 0.0001)


func test_reinforced_real_save_threshold_and_named_log() -> void:
	var unit := _unit([], "gf", "prime_brothers")
	var target := _unit(["Reinforced"], "gf", "prime_brothers")
	var profile := {"range": 24, "ap": 2, "rules": []}
	var start: int = _main.battle_log.entries().size()
	await _main._solo_resolve_saves(unit, target, "Rifle", [], 1, 4, profile, false, false, true, false, 9.0)
	var close_text := ""
	for entry in _main.battle_log.entries().slice(start):
		close_text += str(entry["text"]) + "\n"
	assert_str(close_text).not_contains("Reinforced:")
	start = _main.battle_log.entries().size()
	await _main._solo_resolve_saves(unit, target, "Rifle", [], 1, 4, profile, false, false, true, false, 9.01)
	var far_text := ""
	for entry in _main.battle_log.entries().slice(start):
		far_text += str(entry["text"]) + "\n"
	assert_str(far_text).contains("Reinforced:")
	assert_str(far_text).contains("saves on 5+")
